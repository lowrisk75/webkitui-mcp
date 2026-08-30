import { chromium } from "playwright";
import type { BrowserContext, CDPSession, Page, Request } from "playwright";
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

export interface WorkerConsoleEntry {
  workerUrl: string;
  type: string;
  text: string;
  timestamp: number;
}

export interface TabInfo {
  tabId: string;
  url: string;
  title: string;
  active: boolean;
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
const DEFAULT_WAIT_TIMEOUT_MS = 30_000;

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

interface TabState {
  page: Page;
  consoleLogs: ConsoleEntry[];
  networkEntries: NetworkEntry[];
  networkByRequest: Map<Request, NetworkEntry>;
}

/**
 * Captures console output from service workers (extension background
 * scripts, PWA workers) — Playwright's Worker class has no 'console' event,
 * so this attaches a raw CDP session to the page, discovers worker-type
 * targets, and attaches to each with the legacy (non-flat) Target protocol:
 * Target.attachToTarget -> sessionId, then Target.sendMessageToTarget to
 * enable Runtime, then Target.receivedMessageFromTarget carries the child
 * session's Runtime.consoleAPICalled/exceptionThrown events tagged with that
 * sessionId. Flat-mode attach isn't usable here — Playwright's CDPSession
 * wrapper has no way to address a specific flat sub-session per send() call.
 *
 * Both Runtime.enable AND Log.enable are sent on attach — Runtime alone was
 * empirically unreliable for console.* calls made from INSIDE a chrome.*
 * extension API event callback (chrome.runtime.onMessage, a Port's
 * onDisconnect, etc.): the callback demonstrably ran (state it set was
 * observable via a follow-up Runtime.evaluate) but produced no
 * Runtime.consoleAPICalled event, repeatably, across dozens of manual runs.
 * Also enabling Log fixed it — Runtime.consoleAPICalled then arrived
 * reliably for the exact same code path (confirmed 3/3 clean runs). Chrome's
 * own internal diagnostics for these events (e.g. "Unchecked
 * runtime.lastError: ...") additionally surface via Log.entryAdded, captured
 * here too as a bonus signal even when a console.* call doesn't fire at all.
 */
class WorkerConsoleTracker {
  private entries: WorkerConsoleEntry[] = [];
  private targetUrlBySession = new Map<string, string>();
  private attachedTargetIds = new Set<string>();
  private nextMsgId = 1;

  private constructor(private cdp: CDPSession) {}

  static async attach(context: BrowserContext, page: Page): Promise<WorkerConsoleTracker> {
    const cdp = await context.newCDPSession(page);
    const tracker = new WorkerConsoleTracker(cdp);
    await tracker.init();
    return tracker;
  }

  private async init() {
    this.cdp.on("Target.receivedMessageFromTarget", ({ sessionId, message }) => {
      if (!this.targetUrlBySession.has(sessionId)) return;
      let msg: { method?: string; params?: Record<string, unknown> };
      try {
        msg = JSON.parse(message);
      } catch {
        return;
      }
      if (msg.method === "Runtime.consoleAPICalled") {
        const p = msg.params as { type?: string; args?: Array<{ value?: unknown; description?: string }> };
        const text = (p.args ?? [])
          .map((a) => (a.value !== undefined ? String(a.value) : (a.description ?? "")))
          .join(" ");
        this.push(sessionId, p.type ?? "log", text);
      } else if (msg.method === "Runtime.exceptionThrown") {
        const p = msg.params as { exceptionDetails?: { exception?: { description?: string }; text?: string } };
        const text = p.exceptionDetails?.exception?.description ?? p.exceptionDetails?.text ?? "unknown exception";
        this.push(sessionId, "exception", text);
      } else if (msg.method === "Log.entryAdded") {
        const p = msg.params as { entry?: { level?: string; text?: string; source?: string } };
        if (p.entry?.text) this.push(sessionId, `log:${p.entry.level ?? p.entry.source ?? "other"}`, p.entry.text);
      }
    });

    this.cdp.on("Target.targetCreated", ({ targetInfo }) => {
      if (isWorkerTargetType(targetInfo.type)) {
        this.attachToTarget(targetInfo.targetId, targetInfo.url).catch(() => {});
      }
    });

    await this.cdp.send("Target.setDiscoverTargets", { discover: true });
    const { targetInfos } = await this.cdp.send("Target.getTargets", {});
    await Promise.all(
      targetInfos
        .filter((info) => isWorkerTargetType(info.type))
        .map((info) => this.attachToTarget(info.targetId, info.url).catch(() => {})),
    );
  }

  private async attachToTarget(targetId: string, url: string) {
    // Target.setDiscoverTargets retroactively fires targetCreated for every
    // target that already existed, not just future ones — without this
    // guard, a target found via the initial getTargets() enumeration gets a
    // SECOND targetCreated event and a second, redundant debugger session.
    if (this.attachedTargetIds.has(targetId)) return;
    this.attachedTargetIds.add(targetId);
    const { sessionId } = await this.cdp.send("Target.attachToTarget", { targetId, flatten: false });
    this.targetUrlBySession.set(sessionId, url);
    await this.sendToTarget(sessionId, "Runtime.enable", {});
    await this.sendToTarget(sessionId, "Log.enable", {});
  }

  private async sendToTarget(sessionId: string, method: string, params: unknown) {
    const id = this.nextMsgId++;
    await this.cdp.send("Target.sendMessageToTarget", {
      sessionId,
      message: JSON.stringify({ id, method, params }),
    });
  }

  private push(sessionId: string, type: string, text: string) {
    const workerUrl = this.targetUrlBySession.get(sessionId) ?? "(unknown worker)";
    this.entries.push({ workerUrl, type, text, timestamp: Date.now() });
    if (this.entries.length > MAX_LOG_ENTRIES) this.entries.shift();
  }

  getEntries(workerUrlContains?: string): WorkerConsoleEntry[] {
    if (!workerUrlContains) return this.entries;
    return this.entries.filter((e) => e.workerUrl.includes(workerUrlContains));
  }
}

function isWorkerTargetType(type: string): boolean {
  return type === "service_worker" || type === "worker" || type === "shared_worker";
}

class WebkitSession {
  private context: BrowserContext | null = null;
  private tabs = new Map<string, TabState>();
  private activeTabId: string | null = null;
  private nextTabSeq = 1;
  private workerTracker: WorkerConsoleTracker | null = null;
  // Pages the session opens for its own bookkeeping (currently just the
  // worker tracker's anchor page) — excluded from webkitui_list_tabs and
  // from the auto-registration `context.on('page', ...)` handler below.
  private internalPages = new Set<Page>();
  private mutex = new Mutex();

  isLaunched(): boolean {
    return this.context !== null && this.activeTabId !== null;
  }

  private requireContext(): BrowserContext {
    if (!this.context) throw new Error("No browser session — call webkitui_launch first.");
    return this.context;
  }

  private activeTab(): TabState {
    if (!this.activeTabId) throw new Error("No browser session — call webkitui_launch first.");
    const tab = this.tabs.get(this.activeTabId);
    if (!tab) throw new Error(`Active tab "${this.activeTabId}" no longer exists.`);
    return tab;
  }

  private tabOrActive(tabId?: string): TabState {
    if (!tabId) return this.activeTab();
    const tab = this.tabs.get(tabId);
    if (!tab) throw new Error(`Unknown tabId: ${tabId}`);
    return tab;
  }

  launch(opts: LaunchOptions) {
    return this.mutex.run(async () => {
      // Validate BEFORE tearing down any existing session — a bad launch
      // call (typo'd path, headless+extension conflict) must be a no-op on
      // a working session, not destroy it before finding out the new one
      // can't start either.
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

      if (this.context) {
        await this.closeInternal();
      }

      const userDataDir = opts.userDataDir ? untildify(opts.userDataDir) : DEFAULT_PROFILE_DIR;
      fs.mkdirSync(userDataDir, { recursive: true });

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
      const channel = extensionPath ? undefined : (requestedChannel ?? "chrome");

      const context = await chromium.launchPersistentContext(userDataDir, {
        headless,
        channel,
        args,
      });

      try {
        const page = context.pages()[0] ?? (await context.newPage());
        this.context = context;
        this.registerTab(page, { activate: true });

        // The worker tracker's CDP session is tied to the page it's created
        // on — if that page's tab closes, the session (and all worker
        // console capture) dies silently with it. A dedicated page that's
        // never exposed as a user tab means tracking survives any tab the
        // caller opens and closes. Created (and added to internalPages)
        // BEFORE the general 'page' listener below is attached, so its own
        // 'page' event — which can fire before the awaited newPage() call
        // here even returns — has no listener yet to wrongly register it
        // as a visible tab.
        const trackerPage = await context.newPage();
        this.internalPages.add(trackerPage);
        this.workerTracker = await WorkerConsoleTracker.attach(context, trackerPage).catch((e) => {
          console.error("[webkitui-mcp] worker console tracking unavailable:", e);
          return null;
        });

        // Covers pages this session didn't open itself (window.open,
        // target=_blank, extension popups). Pages WE open via
        // webkitui_new_tab also fire this event — registerTab is
        // idempotent, so that's safe.
        context.on("page", (p) => {
          if (!this.internalPages.has(p)) this.registerTab(p, { activate: false });
        });
        // External death (Chrome crashes, or webkitui_cdp_send sends
        // Browser.close) should reset to a clean "no session" state instead
        // of leaving stale tabs/context around that fail every subsequent
        // call with a confusing Playwright "Target closed" error.
        context.on("close", () => this.resetState());
      } catch (e) {
        // Context launched but page setup failed — don't leak an orphaned
        // Chrome process holding the profile-dir lock.
        await context.close().catch(() => {});
        this.resetState();
        throw e;
      }

      return {
        userDataDir,
        headless,
        channel: channel ?? "chromium (bundled, Chrome for Testing)",
        loadedExtension: extensionPath,
        tabId: this.activeTabId,
        ...(channelOverridden
          ? {
              warning: `requested channel "${requestedChannel}" ignored — branded Chrome/Edge silently drop --load-extension since Chrome 137, so extension loads always use bundled Chromium.`,
            }
          : {}),
      };
    });
  }

  private registerTab(page: Page, opts: { activate: boolean }): string {
    const existing = [...this.tabs.entries()].find(([, t]) => t.page === page);
    if (existing) {
      const [tabId] = existing;
      if (opts.activate) this.activeTabId = tabId;
      return tabId;
    }

    const tabId = `tab-${this.nextTabSeq++}`;
    const state: TabState = { page, consoleLogs: [], networkEntries: [], networkByRequest: new Map() };
    this.tabs.set(tabId, state);
    this.attachPageListeners(state);
    page.on("close", () => {
      this.tabs.delete(tabId);
      if (this.activeTabId === tabId) {
        this.activeTabId = this.tabs.size > 0 ? [...this.tabs.keys()][0] : null;
      }
    });
    if (opts.activate || !this.activeTabId) this.activeTabId = tabId;
    return tabId;
  }

  private attachPageListeners(state: TabState) {
    const { page } = state;
    page.on("console", (msg) => {
      state.consoleLogs.push({
        type: msg.type(),
        text: msg.text(),
        location: formatLocation(msg.location()),
        timestamp: Date.now(),
      });
      if (state.consoleLogs.length > MAX_LOG_ENTRIES) state.consoleLogs.shift();
    });
    page.on("pageerror", (err) => {
      state.consoleLogs.push({ type: "pageerror", text: err.message, timestamp: Date.now() });
      if (state.consoleLogs.length > MAX_LOG_ENTRIES) state.consoleLogs.shift();
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
      state.networkByRequest.set(req, entry);
      state.networkEntries.push(entry);
      if (state.networkEntries.length > MAX_LOG_ENTRIES) state.networkEntries.shift();
    });
    page.on("requestfinished", async (req) => {
      const entry = state.networkByRequest.get(req);
      if (!entry) return;
      const resp = await req.response();
      entry.status = resp?.status() ?? null;
      entry.statusText = resp?.statusText() ?? null;
      entry.ok = resp?.ok() ?? null;
      entry.finishedAt = Date.now();
    });
    page.on("requestfailed", (req) => {
      const entry = state.networkByRequest.get(req);
      if (!entry) return;
      entry.failure = req.failure()?.errorText ?? "unknown failure";
      entry.finishedAt = Date.now();
    });
  }

  navigate(url: string, waitUntil?: "load" | "domcontentloaded" | "networkidle") {
    return this.mutex.run(async () => {
      const tab = this.activeTab();
      tab.consoleLogs = [];
      tab.networkEntries = [];
      tab.networkByRequest.clear();
      const response = await tab.page.goto(url, { waitUntil: waitUntil ?? "load" });
      return {
        url: tab.page.url(),
        status: response?.status() ?? null,
        ok: response?.ok() ?? null,
      };
    });
  }

  click(selector: string, timeoutMs?: number) {
    return this.mutex.run(async () => {
      const tab = this.activeTab();
      await tab.page.locator(selector).first().click({ timeout: timeoutMs });
      return { clicked: selector };
    });
  }

  type(selector: string, text: string, timeoutMs?: number) {
    return this.mutex.run(async () => {
      const tab = this.activeTab();
      await tab.page.locator(selector).first().fill(text, { timeout: timeoutMs });
      return { typed: selector };
    });
  }

  pressKey(key: string, selector?: string, timeoutMs?: number) {
    return this.mutex.run(async () => {
      const tab = this.activeTab();
      if (selector) {
        await tab.page.locator(selector).first().press(key, { timeout: timeoutMs });
      } else {
        await tab.page.keyboard.press(key);
      }
      return { pressed: key };
    });
  }

  waitFor(opts: {
    selector?: string;
    state?: "attached" | "visible" | "hidden" | "detached";
    url?: string;
    timeoutMs?: number;
  }) {
    return this.mutex.run(async () => {
      const tab = this.activeTab();
      const timeout = opts.timeoutMs ?? DEFAULT_WAIT_TIMEOUT_MS;
      if (opts.selector) {
        await tab.page.locator(opts.selector).first().waitFor({ state: opts.state ?? "visible", timeout });
        return { waited: "selector", selector: opts.selector, state: opts.state ?? "visible" };
      }
      if (opts.url) {
        await tab.page.waitForURL(opts.url, { timeout });
        return { waited: "url", url: tab.page.url() };
      }
      throw new Error("waitFor requires either selector or url.");
    });
  }

  screenshot(outPath?: string, fullPage?: boolean) {
    return this.mutex.run(async () => {
      const tab = this.activeTab();
      if (outPath) {
        const resolved = untildify(outPath);
        fs.mkdirSync(path.dirname(resolved), { recursive: true });
        await tab.page.screenshot({ path: resolved, fullPage: fullPage ?? false });
        return { path: resolved };
      }
      const buffer = await tab.page.screenshot({ fullPage: fullPage ?? false });
      return { base64: buffer.toString("base64") };
    });
  }

  evaluate(script: string, timeoutMs?: number) {
    return this.mutex.run(async () => {
      const tab = this.activeTab();
      const timeout = timeoutMs ?? DEFAULT_EVALUATE_TIMEOUT_MS;
      let timer: NodeJS.Timeout;
      const timeoutPromise = new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(`webkitui_evaluate timed out after ${timeout}ms`)), timeout);
      });
      try {
        const result = await Promise.race([tab.page.evaluate(script), timeoutPromise]);
        return { result };
      } finally {
        clearTimeout(timer!);
      }
    });
  }

  getPageText() {
    return this.mutex.run(async () => {
      const tab = this.activeTab();
      // String form (not a typed arrow fn) so this file doesn't need "dom"
      // in tsconfig lib just for one DOM-typed callback.
      const text = await tab.page.evaluate("document.body ? document.body.innerText : ''");
      return { text };
    });
  }

  cdpSend(method: string, params?: Record<string, unknown>) {
    return this.mutex.run(async () => {
      const tab = this.activeTab();
      const context = this.requireContext();
      const cdp = await context.newCDPSession(tab.page);
      try {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const result = await (cdp.send as any)(method, params ?? {});
        return { result };
      } finally {
        await cdp.detach().catch(() => {});
      }
    });
  }

  getConsoleLogs(tabId?: string): ConsoleEntry[] {
    return this.tabOrActive(tabId).consoleLogs;
  }

  getNetworkRequests(urlContains?: string, tabId?: string): NetworkEntry[] {
    const entries = this.tabOrActive(tabId).networkEntries;
    if (!urlContains) return entries;
    return entries.filter((e) => e.url.includes(urlContains));
  }

  getWorkerConsoleLogs(workerUrlContains?: string): WorkerConsoleEntry[] {
    if (!this.workerTracker) {
      throw new Error(
        "Worker console tracking is not active (failed during launch — check server stderr for details).",
      );
    }
    return this.workerTracker.getEntries(workerUrlContains);
  }

  async listTabs(): Promise<TabInfo[]> {
    return this.mutex.run(async () => {
      const infos: TabInfo[] = [];
      for (const [tabId, tab] of this.tabs) {
        infos.push({
          tabId,
          url: tab.page.url(),
          title: await tab.page.title().catch(() => ""),
          active: tabId === this.activeTabId,
        });
      }
      return infos;
    });
  }

  newTab(url?: string) {
    return this.mutex.run(async () => {
      const context = this.requireContext();
      const page = await context.newPage();
      const tabId = this.registerTab(page, { activate: true });
      if (url) await page.goto(url);
      return { tabId, url: page.url() };
    });
  }

  switchTab(tabId: string) {
    return this.mutex.run(async () => {
      const tab = this.tabs.get(tabId);
      if (!tab) throw new Error(`Unknown tabId: ${tabId}`);
      this.activeTabId = tabId;
      await tab.page.bringToFront();
      return { tabId };
    });
  }

  closeTab(tabId: string) {
    return this.mutex.run(async () => {
      const tab = this.tabs.get(tabId);
      if (!tab) throw new Error(`Unknown tabId: ${tabId}`);
      await tab.page.close();
      return { closed: tabId };
    });
  }

  extensionId(timeoutMs = 5000) {
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
    this.resetState();
    return { closed: true };
  }

  private resetState() {
    this.context = null;
    this.tabs.clear();
    this.activeTabId = null;
    this.workerTracker = null;
    this.internalPages.clear();
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
