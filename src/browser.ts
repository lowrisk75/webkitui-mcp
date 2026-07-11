import { chromium } from "playwright";
import type { BrowserContext, Page, Request } from "playwright";
import * as os from "node:os";
import * as path from "node:path";
import * as fs from "node:fs";

export interface ConsoleEntry {
  type: string;
  text: string;
  location?: string;
  timestamp: number;
}

export interface NetworkEntry {
  url: string;
  method: string;
  resourceType: string;
  status: number | null;
  statusText: string | null;
  ok: boolean | null;
  failure: string | null;
  postDataPreview: string | null;
  startedAt: number;
  finishedAt: number | null;
}

export interface LaunchOptions {
  userDataDir?: string;
  loadExtensionPath?: string;
  headless?: boolean;
  channel?: string;
}

const DEFAULT_PROFILE_DIR = path.join(os.homedir(), ".webkitui-mcp", "chrome-profile");
const MAX_LOG_ENTRIES = 2000;
const DEFAULT_EVALUATE_TIMEOUT_MS = 30_000;

/** Serializes calls through the singleton session so overlapping tool calls
 * (e.g. two launches, or navigate racing close) can't interleave state. */
class Mutex {
  private tail: Promise<unknown> = Promise.resolve();

  run<T>(fn: () => Promise<T>): Promise<T> {
    const result = this.tail.then(fn, fn);
    this.tail = result.then(
      () => undefined,
      () => undefined,
    );
    return result;
  }
}

class WebkitSession {
  private context: BrowserContext | null = null;
  private page: Page | null = null;
  private consoleLogs: ConsoleEntry[] = [];
  private networkEntries: NetworkEntry[] = [];
  private networkByRequest = new Map<Request, NetworkEntry>();
  private mutex = new Mutex();

  isLaunched(): boolean {
    return this.context !== null && this.page !== null;
  }

  private requireContext(): BrowserContext {
    if (!this.context) throw new Error("No browser session — call webkitui_launch first.");
    return this.context;
  }

  private requirePage(): Page {
    if (!this.page) throw new Error("No browser session — call webkitui_launch first.");
    return this.page;
  }

  launch(opts: LaunchOptions) {
    return this.mutex.run(async () => {
      if (this.context) {
        await this.closeInternal();
      }

      const userDataDir = opts.userDataDir ? untildify(opts.userDataDir) : DEFAULT_PROFILE_DIR;
      fs.mkdirSync(userDataDir, { recursive: true });

      const extensionPath = opts.loadExtensionPath ? untildify(opts.loadExtensionPath) : null;
      if (extensionPath && !fs.existsSync(extensionPath)) {
        throw new Error(`loadExtensionPath does not exist: ${extensionPath}`);
      }

      // Chrome refuses to load unpacked extensions in headless mode — full stop,
      // regardless of channel. Silently forcing this is safer than a launch that
      // "succeeds" with the extension quietly absent.
      const headless = opts.headless ?? false;
      if (extensionPath && headless) {
        throw new Error(
          "headless cannot be true when loadExtensionPath is set — Chrome does not load unpacked extensions headless.",
        );
      }

      const args: string[] = ["--no-first-run", "--no-default-browser-check"];
      if (extensionPath) {
        args.push(`--disable-extensions-except=${extensionPath}`, `--load-extension=${extensionPath}`);
      }

      // Google removed the --load-extension CLI flag from branded Chrome/Edge
      // builds in Chrome 137 (June 2025) to stop malware from side-loading
      // unpacked extensions — it's silently ignored there, no error, the
      // extension just never appears. It still works in Playwright's bundled
      // Chromium (Chrome for Testing), so extension loads are pinned to that
      // regardless of any requested channel.
      const requestedChannel = opts.channel;
      const channelOverridden = Boolean(extensionPath && requestedChannel);
      const channel = extensionPath ? undefined : requestedChannel ?? "chrome";

      const context = await chromium.launchPersistentContext(userDataDir, {
        headless,
        channel,
        args,
      });

      try {
        const page = context.pages()[0] ?? (await context.newPage());
        this.attachPageListeners(page);
        this.context = context;
        this.page = page;
      } catch (e) {
        // Context launched but page setup failed — don't leak an orphaned
        // Chrome process holding the profile-dir lock.
        await context.close().catch(() => {});
        throw e;
      }

      return {
        userDataDir,
        headless,
        channel: channel ?? "chromium (bundled, Chrome for Testing)",
        loadedExtension: extensionPath,
        ...(channelOverridden
          ? {
              warning: `requested channel "${requestedChannel}" ignored — branded Chrome/Edge silently drop --load-extension since Chrome 137, so extension loads always use bundled Chromium.`,
            }
          : {}),
      };
    });
  }

  private attachPageListeners(page: Page) {
    page.on("console", (msg) => {
      this.pushConsole({
        type: msg.type(),
        text: msg.text(),
        location: formatLocation(msg.location()),
        timestamp: Date.now(),
      });
    });
    page.on("pageerror", (err) => {
      this.pushConsole({ type: "pageerror", text: err.message, timestamp: Date.now() });
    });
    page.on("request", (req) => {
      const entry: NetworkEntry = {
        url: req.url(),
        method: req.method(),
        resourceType: req.resourceType(),
        status: null,
        statusText: null,
        ok: null,
        failure: null,
        postDataPreview: previewPostData(req),
        startedAt: Date.now(),
        finishedAt: null,
      };
      this.networkByRequest.set(req, entry);
      this.pushNetwork(entry);
    });
    page.on("requestfinished", async (req) => {
      const entry = this.networkByRequest.get(req);
      if (!entry) return;
      const resp = await req.response();
      entry.status = resp?.status() ?? null;
      entry.statusText = resp?.statusText() ?? null;
      entry.ok = resp?.ok() ?? null;
      entry.finishedAt = Date.now();
    });
    page.on("requestfailed", (req) => {
      const entry = this.networkByRequest.get(req);
      if (!entry) return;
      entry.failure = req.failure()?.errorText ?? "unknown failure";
      entry.finishedAt = Date.now();
    });
  }

  private pushConsole(entry: ConsoleEntry) {
    this.consoleLogs.push(entry);
    if (this.consoleLogs.length > MAX_LOG_ENTRIES) this.consoleLogs.shift();
  }

  private pushNetwork(entry: NetworkEntry) {
    this.networkEntries.push(entry);
    if (this.networkEntries.length > MAX_LOG_ENTRIES) this.networkEntries.shift();
  }

  navigate(url: string, waitUntil?: "load" | "domcontentloaded" | "networkidle") {
    return this.mutex.run(async () => {
      const page = this.requirePage();
      this.consoleLogs = [];
      this.networkEntries = [];
      this.networkByRequest.clear();
      const response = await page.goto(url, { waitUntil: waitUntil ?? "load" });
      return {
        url: page.url(),
        status: response?.status() ?? null,
        ok: response?.ok() ?? null,
      };
    });
  }

  click(selector: string, timeoutMs?: number) {
    return this.mutex.run(async () => {
      const page = this.requirePage();
      await page.locator(selector).first().click({ timeout: timeoutMs });
      return { clicked: selector };
    });
  }

  type(selector: string, text: string, timeoutMs?: number) {
    return this.mutex.run(async () => {
      const page = this.requirePage();
      await page.locator(selector).first().fill(text, { timeout: timeoutMs });
      return { typed: selector };
    });
  }

  screenshot(outPath?: string, fullPage?: boolean) {
    return this.mutex.run(async () => {
      const page = this.requirePage();
      if (outPath) {
        const resolved = untildify(outPath);
        fs.mkdirSync(path.dirname(resolved), { recursive: true });
        await page.screenshot({ path: resolved, fullPage: fullPage ?? false });
        return { path: resolved };
      }
      const buffer = await page.screenshot({ fullPage: fullPage ?? false });
      return { base64: buffer.toString("base64") };
    });
  }

  evaluate(script: string, timeoutMs?: number) {
    return this.mutex.run(async () => {
      const page = this.requirePage();
      const timeout = timeoutMs ?? DEFAULT_EVALUATE_TIMEOUT_MS;
      const result = await Promise.race([
        page.evaluate(script),
        new Promise((_, reject) =>
          setTimeout(() => reject(new Error(`webkitui_evaluate timed out after ${timeout}ms`)), timeout),
        ),
      ]);
      return { result };
    });
  }

  getConsoleLogs(): ConsoleEntry[] {
    return this.consoleLogs;
  }

  getNetworkRequests(urlContains?: string): NetworkEntry[] {
    if (!urlContains) return this.networkEntries;
    return this.networkEntries.filter((e) => e.url.includes(urlContains));
  }

  getExtensionId(timeoutMs = 5000) {
    return this.mutex.run(async () => {
      const context = this.requireContext();
      const findFrom = (workers: readonly { url(): string }[]) =>
        workers.find((w) => w.url().startsWith("chrome-extension://")) ?? null;

      let worker = findFrom(context.serviceWorkers());
      if (!worker) {
        worker = await context.waitForEvent("serviceworker", { timeout: timeoutMs }).catch(() => null);
      }
      if (!worker) return { extensionId: null, url: null };

      const url = worker.url();
      const extensionId = url.split("/")[2] ?? null;
      return { extensionId, url };
    });
  }

  close() {
    return this.mutex.run(() => this.closeInternal());
  }

  private async closeInternal() {
    if (this.context) {
      await this.context.close().catch(() => {});
    }
    this.context = null;
    this.page = null;
    this.consoleLogs = [];
    this.networkEntries = [];
    this.networkByRequest.clear();
    return { closed: true };
  }
}

function untildify(p: string): string {
  // Only "~" or "~/..." is a home-dir reference — "~foo" is a literal
  // relative path (a user named "foo" is a different, unsupported case).
  const isHomeRef = p === "~" || p.startsWith("~/");
  return isHomeRef ? path.join(os.homedir(), p.slice(1)) : path.resolve(p);
}

function formatLocation(loc: { url: string; lineNumber: number; columnNumber: number }): string {
  return `${loc.url}:${loc.lineNumber}:${loc.columnNumber}`;
}

function previewPostData(req: Request): string | null {
  const data = req.postData();
  if (!data) return null;
  return data.length > 500 ? `${data.slice(0, 500)}…(truncated)` : data;
}

export const session = new WebkitSession();
