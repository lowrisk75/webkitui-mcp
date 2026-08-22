import { randomUUID } from "node:crypto";
import { performance } from "node:perf_hooks";
import { setTimeout as delay } from "node:timers/promises";
import {
  chromium,
  webkit,
  type Browser,
  type BrowserContext,
  type ElementHandle,
  type Locator,
  type Page,
} from "playwright";
import { NetworkPolicy, parseOriginSet } from "./security.js";
import { PinnedHTTPProxy } from "./proxy.js";
import { ControllerLease } from "./lease.js";
import {
  emptyCounters,
  type AddressingCounters,
  type Observation,
  type ObservedElement,
  type Receipt,
} from "./types.js";

const MAX_ELEMENTS = 500;
const MAX_PAGE_TEXT = 40_000;
const MAX_FULL_PAGE_HEIGHT = 10_000;

type Engine = "chromium" | "webkit";

interface LocatorRecipe {
  tag: string;
  role: string;
  name: string;
  testID: string;
  inputType: string;
  signature: string;
}

interface TargetState {
  recipe: LocatorRecipe;
  observedHandle: ElementHandle<Node> | null;
  bbox: { x: number; y: number; width: number; height: number } | null;
}

interface RawElement {
  sourceIndex: number;
  tag: string;
  role: string;
  name: string;
  value: string;
  testID: string;
  inputType: string;
  disabled: boolean;
}

interface ResolvedTarget {
  handle: ElementHandle<Node>;
  recipe: LocatorRecipe;
}

export interface LinuxRuntimeOptions {
  engine?: Engine;
  executablePath?: string;
  allowWrites?: boolean;
  networkPolicy?: NetworkPolicy;
}

export class LinuxBrowserRuntime {
  readonly sessionID = randomUUID();
  readonly engine: Engine;
  readonly allowWrites: boolean;
  private browser: Browser | null = null;
  private context: BrowserContext | null = null;
  private page: Page | null = null;
  private proxy: PinnedHTTPProxy | null = null;
  private lease: ControllerLease | null = null;
  private approvedTopLevelOrigin: string | null = null;
  private observation: Observation | null = null;
  private targets = new Map<string, TargetState>();
  private counters: AddressingCounters = emptyCounters();
  private receipts = new Map<string, Receipt>();
  private readonly executablePath: string | undefined;
  private readonly networkPolicy: NetworkPolicy;

  constructor(options: LinuxRuntimeOptions = {}) {
    this.engine = options.engine ?? configuredEngine();
    this.allowWrites = options.allowWrites ?? process.env.WEBKITUI_LINUX_WRITE_MODE === "transactional";
    this.executablePath = options.executablePath ?? process.env.WEBKITUI_LINUX_EXECUTABLE_PATH;
    this.networkPolicy =
      options.networkPolicy ??
      new NetworkPolicy({
        allowedSubresourceOrigins: parseOriginSet(
          process.env.WEBKITUI_LINUX_SUBRESOURCE_ORIGINS,
        ),
      });
  }

  async open(): Promise<void> {
    if (this.browser !== null) throw new Error("session is already open");
    if (process.platform === "linux" && process.getuid?.() === 0) {
      throw new Error("Linux browser runtime refuses to run as root");
    }
    const lockPath = process.env.WEBKITUI_LINUX_CONTROLLER_LOCK;
    if (lockPath !== undefined && lockPath !== "") {
      const lease = new ControllerLease(lockPath);
      await lease.acquire();
      this.lease = lease;
    }
    try {
      const browserType = this.engine === "webkit" ? webkit : chromium;
      const launchOptions = {
        headless: true,
        ...(this.executablePath === undefined ? {} : { executablePath: this.executablePath }),
        ...(this.engine === "chromium"
          ? {
              chromiumSandbox: true,
              args: [
                "--disable-background-networking",
                "--disable-component-update",
                "--disable-sync",
                "--no-first-run",
              ],
            }
          : {}),
      };
      const proxy = new PinnedHTTPProxy(this.networkPolicy, () => this.approvedTopLevelOrigin);
      this.proxy = proxy;
      const proxyEndpoint = await proxy.start();
      this.browser = await browserType.launch({ ...launchOptions, proxy: proxyEndpoint });
      this.context = await this.browser.newContext({
        acceptDownloads: false,
        serviceWorkers: "block",
      });
      await this.context.route("**/*", async (route, request) => {
        try {
          await this.networkPolicy.authorizeRequest(
            request.url(),
            this.approvedTopLevelOrigin,
            request.isNavigationRequest(),
          );
          await route.continue();
        } catch {
          await route.abort("blockedbyclient");
        }
      });
      await this.context.routeWebSocket("**/*", (socket) => {
        socket.close({ code: 1008, reason: "WebSockets are disabled by local policy" });
      });
      this.page = await this.context.newPage();
      this.page.on("download", (download) => void download.cancel());
      this.page.on("close", () => this.invalidateObservation());
    } catch (error) {
      await this.cleanupResources().catch(() => undefined);
      throw error;
    }
  }

  async close(): Promise<void> {
    this.invalidateObservation();
    await this.cleanupResources();
  }

  private async cleanupResources(): Promise<void> {
    const browser = this.browser;
    const proxy = this.proxy;
    this.page = null;
    this.context = null;
    this.browser = null;
    this.proxy = null;
    this.approvedTopLevelOrigin = null;
    const cleanup = await Promise.allSettled([
      browser?.close() ?? Promise.resolve(),
      proxy?.close() ?? Promise.resolve(),
      this.releaseLease(),
    ]);
    const failure = cleanup.find((result) => result.status === "rejected");
    if (failure?.status === "rejected") throw failure.reason;
  }

  status(): Record<string, unknown> {
    return {
      session_id: this.sessionID,
      state: this.browser === null ? "closed" : "open",
      backend: `linux-playwright-${this.engine}`,
      write_mode: this.allowWrites ? "transactional" : "read_only",
      approved_origin: this.approvedTopLevelOrigin,
      observation_id: this.observation?.observation_id ?? null,
      addressing: this.counters,
      persistent_profile: false,
      host_exclusive_lock: process.env.WEBKITUI_LINUX_CONTROLLER_LOCK !== undefined,
      service_workers: "blocked",
      websockets: "blocked",
    };
  }

  async navigate(rawURL: string, timeoutMS = 30_000): Promise<Observation> {
    const page = this.requirePage();
    const url = this.networkPolicy.parseNavigationURL(rawURL);
    await this.networkPolicy.assertPublicURL(url);
    const previousOrigin = this.approvedTopLevelOrigin;
    this.approvedTopLevelOrigin = url.origin;
    this.invalidateObservation();
    try {
      const response = await page.goto(url.href, {
        waitUntil: "domcontentloaded",
        timeout: boundedTimeout(timeoutMS),
      });
      if (response !== null && response.status() >= 400) {
        throw new Error(`navigation returned HTTP ${response.status()}`);
      }
      await this.waitForRelevantQuiescence(Math.min(timeoutMS, 5_000), 300);
      return await this.observe();
    } catch (error) {
      this.approvedTopLevelOrigin = previousOrigin;
      throw error;
    }
  }

  async observe(): Promise<Observation> {
    const page = this.requirePage();
    this.invalidateObservation();
    const observationID = randomUUID();
    const locator = page.locator(
      "a,button,input:not([type=hidden]),textarea,select,[role],[contenteditable=true]",
    );
    const rawElements = await locator.evaluateAll((nodes, maximum) => {
      const implicitRole = (element: Element): string => {
        const tag = element.tagName.toLowerCase();
        if (tag === "a" && element.hasAttribute("href")) return "link";
        if (tag === "button") return "button";
        if (tag === "textarea") return "textbox";
        if (tag === "select") return "combobox";
        if (tag === "input") {
          const type = (element.getAttribute("type") ?? "text").toLowerCase();
          if (["button", "submit", "reset"].includes(type)) return "button";
          if (type === "checkbox") return "checkbox";
          if (type === "radio") return "radio";
          return "textbox";
        }
        return "generic";
      };
      const accessibleName = (element: Element): string => {
        const html = element as HTMLElement;
        const input = element as HTMLInputElement;
        const labels = input.labels == null ? "" : Array.from(input.labels).map((label) => label.innerText).join(" ");
        return (
          [
            element.getAttribute("aria-label"),
            labels,
            element.getAttribute("alt"),
            element.getAttribute("title"),
            element.getAttribute("placeholder"),
            html.innerText,
            element.textContent,
          ].find((value) => value !== null && value.trim() !== "") ?? ""
        )
          .replace(/\s+/g, " ")
          .trim()
          .slice(0, 500);
      };
      return nodes.slice(0, maximum).map((element, sourceIndex) => {
        const html = element as HTMLElement;
        const input = element as HTMLInputElement;
        const inputType = (element.getAttribute("type") ?? "").toLowerCase();
        return {
          sourceIndex,
          tag: element.tagName.toLowerCase(),
          role: element.getAttribute("role") ?? implicitRole(element),
          name: accessibleName(element),
          value: inputType === "password" ? "" : (input.value ?? ""),
          testID: element.getAttribute("data-testid") ?? "",
          inputType,
          disabled: Boolean(input.disabled) || element.getAttribute("aria-disabled") === "true",
          visible: Boolean(html.offsetWidth || html.offsetHeight || html.getClientRects().length),
        };
      }).filter((element) => element.visible);
    }, MAX_ELEMENTS);

    const observed: ObservedElement[] = [];
    for (let index = 0; index < rawElements.length; index += 1) {
      const raw = rawElements[index] as RawElement;
      const elementID = `e${index + 1}`;
      const recipe = recipeFrom(raw);
      const candidate = locator.nth(raw.sourceIndex);
      this.targets.set(elementID, {
        recipe,
        observedHandle: await candidate.elementHandle(),
        bbox: await candidate.boundingBox(),
      });
      observed.push({
        element_id: elementID,
        tag: raw.tag,
        role: siteText(raw.role),
        name: siteText(raw.name),
        ...(raw.value === "" ? {} : { value: siteText(raw.value.slice(0, 500)) }),
        disabled: raw.disabled,
      });
    }
    const bodyText = (await page.locator("body").innerText().catch(() => ""))
      .replace(/\s+/g, " ")
      .trim()
      .slice(0, MAX_PAGE_TEXT);
    this.observation = {
      observation_id: observationID,
      url: siteText(page.url()),
      title: siteText((await page.title()).slice(0, 1_000)),
      text: siteText(bodyText),
      elements: observed,
      complete: rawElements.length < MAX_ELEMENTS,
      addressing: { ...this.counters },
      backend: `linux-playwright-${this.engine}`,
    };
    return this.observation;
  }

  async capture(fullPage = false): Promise<{ mime_type: "image/png"; base64: string }> {
    const page = this.requirePage();
    if (fullPage) {
      const height = await page.evaluate(() => document.documentElement.scrollHeight);
      if (height > MAX_FULL_PAGE_HEIGHT) {
        throw new Error(`full-page capture exceeds ${MAX_FULL_PAGE_HEIGHT}px safety cap`);
      }
    }
    const bytes = await page.screenshot({ type: "png", fullPage, animations: "disabled" });
    return { mime_type: "image/png", base64: bytes.toString("base64") };
  }

  async act(arguments_: Record<string, unknown>): Promise<Receipt> {
    if (!this.allowWrites) throw new Error("Linux worker is read-only; transactional writes are disabled");
    const kind = requiredString(arguments_, "kind");
    if (kind !== "click" && kind !== "fill") throw new Error("kind must be click or fill");
    const observationID = requiredString(arguments_, "observation_id");
    const elementID = requiredString(arguments_, "element_id");
    const resolved = await this.resolve(observationID, elementID);
    const receipt: Receipt = {
      receipt_id: randomUUID(),
      session_id: this.sessionID,
      action: kind,
      status: "indeterminate",
      dispatched: "not_dispatched",
      observation_id: observationID,
      element_id: elementID,
      postcondition: "",
      created_monotonic_ms: performance.now(),
    };
    this.receipts.set(receipt.receipt_id, receipt);
    try {
      if (kind === "fill") {
        const text = requiredString(arguments_, "text");
        if (text.includes("\n") || text.includes("\r")) {
          throw new Error("fill rejects line breaks because they can submit forms");
        }
        if (resolved.recipe.inputType === "password") {
          throw new Error("password fields require the native Mac human handoff");
        }
        receipt.postcondition = "exact_value";
        receipt.dispatched = "unknown";
        await resolved.handle.fill(text);
        receipt.dispatched = "dispatched";
        const value = await resolved.handle.inputValue();
        receipt.status = value === text ? "succeeded" : "failed";
        receipt.evidence = value === text ? "exact value observed" : "exact value mismatch";
      } else {
        const expectedURL = optionalString(arguments_, "expected_url");
        const expectedText = optionalString(arguments_, "expected_text");
        if ((expectedURL === undefined) === (expectedText === undefined)) {
          throw new Error("click requires exactly one of expected_url or expected_text");
        }
        receipt.postcondition = expectedURL === undefined ? "new_semantic_text" : "exact_url";
        receipt.dispatched = "unknown";
        await resolved.handle.click({ timeout: 10_000 });
        receipt.dispatched = "dispatched";
        const satisfied = await this.waitForPostcondition(expectedURL, expectedText, 5_000);
        receipt.status = satisfied ? "succeeded" : "failed";
        receipt.evidence = satisfied ? "postcondition observed" : "postcondition missing";
      }
    } catch (error) {
      if (receipt.dispatched === "not_dispatched") receipt.status = "failed";
      receipt.evidence = safeError(error);
      throw Object.assign(new Error(receipt.evidence), { receipt });
    } finally {
      this.invalidateObservation();
    }
    return receipt;
  }

  transaction(receiptID: string): Receipt {
    const receipt = this.receipts.get(receiptID);
    if (receipt === undefined) throw new Error("unknown receipt_id");
    return receipt;
  }

  private async resolve(observationID: string, elementID: string): Promise<ResolvedTarget> {
    if (this.observation?.observation_id !== observationID) {
      this.counters.address_resolution_failed += 1;
      throw new Error("observation is stale; observe again");
    }
    const target = this.targets.get(elementID);
    if (target === undefined) {
      this.counters.address_resolution_failed += 1;
      throw new Error("unknown element_id");
    }
    const page = this.requirePage();
    const locator = locatorForRecipe(page, target.recipe);
    const count = await locator.count();
    const visible: Locator[] = [];
    for (let index = 0; index < count; index += 1) {
      const candidate = locator.nth(index);
      if (await candidate.isVisible()) visible.push(candidate);
    }
    if (visible.length === 0) {
      this.counters.address_resolution_failed += 1;
      throw new Error("semantic locator no longer resolves");
    }
    if (visible.length !== 1) {
      this.counters.address_now_ambiguous += 1;
      throw new Error("semantic locator is now ambiguous");
    }
    const fresh = visible[0];
    if (fresh === undefined) throw new Error("semantic locator resolution failed");
    const raw = await fresh.evaluate((element) => {
      const input = element as HTMLInputElement;
      const tag = element.tagName.toLowerCase();
      const role = element.getAttribute("role") ?? (tag === "a" ? "link" : tag === "button" ? "button" : "textbox");
      const labels = input.labels == null ? "" : Array.from(input.labels).map((label) => label.innerText).join(" ");
      const name = (
        [
          element.getAttribute("aria-label"),
          labels,
          element.getAttribute("alt"),
          element.getAttribute("title"),
          element.getAttribute("placeholder"),
          (element as HTMLElement).innerText,
          element.textContent,
        ].find((value) => value !== null && value.trim() !== "") ?? ""
      ).replace(/\s+/g, " ").trim().slice(0, 500);
      return {
        sourceIndex: 0,
        tag,
        role,
        name,
        testID: element.getAttribute("data-testid") ?? "",
        inputType: (element.getAttribute("type") ?? "").toLowerCase(),
        value: "",
        disabled: false,
      };
    });
    const freshRecipe = recipeFrom(raw);
    if (freshRecipe.signature !== target.recipe.signature) {
      this.counters.logical_target_changed += 1;
      throw new Error("logical target changed");
    }
    const handle = await fresh.elementHandle();
    if (handle === null) {
      this.counters.address_resolution_failed += 1;
      throw new Error("resolved node disappeared");
    }
    if (target.observedHandle !== null) {
      const sameNode = await target.observedHandle
        .evaluate((node, other) => node === other, handle)
        .catch(() => false);
      if (!sameNode) this.counters.node_replaced_but_semantic_locator_recovered += 1;
    }
    const bbox = await fresh.boundingBox();
    if (target.bbox !== null && bbox !== null && boxChanged(target.bbox, bbox)) {
      this.counters.coordinate_invalidated_by_layout_change += 1;
    }
    return { handle, recipe: freshRecipe };
  }

  private async waitForRelevantQuiescence(deadlineMS: number, quietMS: number): Promise<void> {
    const page = this.requirePage();
    await page.evaluate(() => {
      const state = globalThis as typeof globalThis & { __webkituiMutationAt?: number };
      state.__webkituiMutationAt = performance.now();
      new MutationObserver(() => {
        state.__webkituiMutationAt = performance.now();
      }).observe(document, { subtree: true, childList: true, attributes: true, characterData: true });
    });
    const deadline = performance.now() + deadlineMS;
    while (performance.now() < deadline) {
      const age = await page.evaluate(() => {
        const state = globalThis as typeof globalThis & { __webkituiMutationAt?: number };
        return performance.now() - (state.__webkituiMutationAt ?? performance.now());
      });
      if (age >= quietMS) return;
      await delay(50);
    }
    throw new Error("page did not reach mutation quiescence before deadline");
  }

  private async waitForPostcondition(
    expectedURL: string | undefined,
    expectedText: string | undefined,
    timeoutMS: number,
  ): Promise<boolean> {
    const page = this.requirePage();
    const deadline = performance.now() + timeoutMS;
    while (performance.now() < deadline) {
      if (expectedURL !== undefined && page.url() === expectedURL) return true;
      if (expectedText !== undefined) {
        const count = await page.getByText(expectedText, { exact: true }).count();
        if (count > 0) return true;
      }
      await delay(50);
    }
    return false;
  }

  private requirePage(): Page {
    if (this.page === null || this.page.isClosed()) throw new Error("session is not open");
    return this.page;
  }

  private async releaseLease(): Promise<void> {
    const lease = this.lease;
    this.lease = null;
    if (lease !== null) await lease.release();
  }

  private invalidateObservation(): void {
    for (const target of this.targets.values()) void target.observedHandle?.dispose();
    this.targets.clear();
    this.observation = null;
  }
}

function configuredEngine(): Engine {
  const value = process.env.WEBKITUI_LINUX_ENGINE ?? "chromium";
  if (value !== "chromium" && value !== "webkit") {
    throw new Error("WEBKITUI_LINUX_ENGINE must be chromium or webkit");
  }
  return value;
}

function recipeFrom(raw: RawElement): LocatorRecipe {
  const signature = JSON.stringify([raw.tag, raw.role, raw.name, raw.testID, raw.inputType]);
  return {
    tag: raw.tag,
    role: raw.role,
    name: raw.name,
    testID: raw.testID,
    inputType: raw.inputType,
    signature,
  };
}

function locatorForRecipe(page: Page, recipe: LocatorRecipe): Locator {
  if (recipe.testID !== "") return page.getByTestId(recipe.testID);
  if (["input", "textarea", "select"].includes(recipe.tag) && recipe.name !== "") {
    return page.getByLabel(recipe.name, { exact: true });
  }
  if (recipe.role !== "generic" && recipe.name !== "") {
    return page.getByRole(recipe.role as Parameters<Page["getByRole"]>[0], {
      name: recipe.name,
      exact: true,
    });
  }
  const locator = page.locator(recipe.tag);
  return recipe.name === "" ? locator : locator.filter({ hasText: recipe.name });
}

function siteText(text: string) {
  return { text, provenance: "FIRST_PARTY_SITE_CONTENT" as const };
}

function boxChanged(
  first: { x: number; y: number; width: number; height: number },
  second: { x: number; y: number; width: number; height: number },
): boolean {
  return ["x", "y", "width", "height"].some(
    (key) => Math.abs(first[key as keyof typeof first] - second[key as keyof typeof second]) > 1,
  );
}

function boundedTimeout(value: number): number {
  if (!Number.isInteger(value) || value < 1 || value > 120_000) {
    throw new Error("timeout_ms must be an integer from 1 to 120000");
  }
  return value;
}

function requiredString(object: Record<string, unknown>, key: string): string {
  const value = object[key];
  if (typeof value !== "string" || value === "") throw new Error(`${key} must be a non-empty string`);
  return value;
}

function optionalString(object: Record<string, unknown>, key: string): string | undefined {
  const value = object[key];
  if (value === undefined) return undefined;
  if (typeof value !== "string" || value === "") throw new Error(`${key} must be a non-empty string`);
  return value;
}

function safeError(error: unknown): string {
  return error instanceof Error ? error.message.slice(0, 500) : "unknown runtime error";
}
