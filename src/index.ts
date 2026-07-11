#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  type Tool,
} from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";
import { zodToJsonSchema } from "zod-to-json-schema";
import { session } from "./browser.js";

// ---------------------------------------------------------------------------
// Input schemas (zod) — single source of truth for validation.
// ---------------------------------------------------------------------------

const LaunchInput = z
  .object({
    userDataDir: z
      .string()
      .optional()
      .describe("Persistent profile dir (~ expanded). Default: ~/.webkitui-mcp/chrome-profile."),
    loadExtensionPath: z
      .string()
      .optional()
      .describe("Path to an unpacked MV3 extension dir to load (~ expanded). Forces headless=false."),
    headless: z
      .boolean()
      .optional()
      .describe("Default false. Must be false (or omitted) when loadExtensionPath is set."),
    channel: z
      .string()
      .optional()
      .describe('Browser channel, e.g. "chrome", "chrome-beta". Default "chrome" (real installed Chrome, not bundled Chromium). Ignored when loadExtensionPath is set.'),
  })
  .strict();

const TabIdInput = z
  .object({
    tabId: z.string().min(1).describe('Tab id from webkitui_list_tabs, e.g. "tab-2".'),
  })
  .strict();

const NewTabInput = z
  .object({
    url: z.string().optional().describe("Navigate the new tab here immediately. Omit for a blank tab."),
  })
  .strict();

const NavigateInput = z
  .object({
    url: z.string().min(1).describe("URL to navigate the active tab to."),
    waitUntil: z.enum(["load", "domcontentloaded", "networkidle"]).optional(),
  })
  .strict();

const SelectorInput = z
  .object({
    selector: z
      .string()
      .min(1)
      .describe('Playwright locator string — CSS ("button.submit"), text ("text=Sign in"), or other Playwright engine syntax.'),
    timeoutMs: z.number().int().positive().optional(),
  })
  .strict();

const TypeInput = SelectorInput.extend({
  text: z.string().describe("Text to fill into the matched element."),
});

const PressKeyInput = z
  .object({
    key: z.string().min(1).describe('Key or chord, e.g. "Enter", "Control+A", "Escape".'),
    selector: z.string().optional().describe("Focus this element first (Playwright locator string). Omit to send to whatever currently has focus."),
    timeoutMs: z.number().int().positive().optional(),
  })
  .strict();

const WaitForInput = z
  .object({
    selector: z.string().optional().describe("Wait for this Playwright locator to reach `state`."),
    state: z.enum(["attached", "visible", "hidden", "detached"]).optional().describe('Default "visible". Only used with selector.'),
    url: z.string().optional().describe("Wait for the active tab's URL to match this string/glob instead of a selector."),
    timeoutMs: z.number().int().positive().optional().describe("Default 30000."),
  })
  .strict()
  .refine((v) => Boolean(v.selector) !== Boolean(v.url), {
    message: "Provide exactly one of selector or url.",
  });

const ScreenshotInput = z
  .object({
    outPath: z.string().optional().describe("Where to write the PNG (~ expanded). Omit to get base64 back."),
    fullPage: z.boolean().optional(),
  })
  .strict();

const EvaluateInput = z
  .object({
    script: z
      .string()
      .min(1)
      .describe("JS expression or IIFE evaluated in the active tab's MAIN world via page.evaluate."),
    timeoutMs: z.number().int().positive().optional().describe("Default 30000."),
  })
  .strict();

const ConsoleLogsInput = z
  .object({
    tabId: z.string().optional().describe("Defaults to the active tab."),
  })
  .strict();

const NetworkRequestsInput = z
  .object({
    urlContains: z.string().optional().describe("Substring filter on request URL."),
    tabId: z.string().optional().describe("Defaults to the active tab."),
  })
  .strict();

const WorkerConsoleLogsInput = z
  .object({
    workerUrlContains: z.string().optional().describe('Substring filter on worker URL, e.g. an extension id.'),
  })
  .strict();

const ExtensionIdInput = z
  .object({
    timeoutMs: z.number().int().positive().optional().describe("Wait for the service worker to register. Default 5000."),
  })
  .strict();

const CdpSendInput = z
  .object({
    method: z.string().min(1).describe('Raw CDP method, e.g. "Emulation.setGeolocationOverride", "Network.setCacheDisabled".'),
    params: z.record(z.unknown()).optional().describe("Method params, per the CDP spec for `method`."),
  })
  .strict();

// ---------------------------------------------------------------------------
// JSON-Schema for each tool — derived from the zod schemas above, so the
// two can never drift apart the way hand-written duplicates would.
// ---------------------------------------------------------------------------

function toInputSchema(schema: z.ZodTypeAny): Tool["inputSchema"] {
  const json = zodToJsonSchema(schema, { target: "jsonSchema7", $refStrategy: "none" });
  delete (json as { $schema?: unknown }).$schema;
  return json as Tool["inputSchema"];
}

const tools: Tool[] = [
  {
    name: "webkitui_launch",
    description:
      "Launch a real Chrome (via Playwright/CDP, launchPersistentContext) with a persistent " +
      "user-data dir. Optionally load an unpacked MV3 extension via loadExtensionPath — this " +
      "requires headless=false (Chrome refuses unpacked extensions headless, no exceptions) and " +
      "always uses Playwright's bundled Chromium regardless of `channel` (branded Chrome/Edge " +
      "dropped --load-extension in Chrome 137). Re-launching closes any existing session first. " +
      "Attaches console/network listeners to the first tab and starts service-worker console " +
      "tracking immediately.",
    annotations: { destructiveHint: true },
    inputSchema: toInputSchema(LaunchInput),
  },
  {
    name: "webkitui_list_tabs",
    description: "List all open tabs (id, url, title, which one is active).",
    annotations: { readOnlyHint: true },
    inputSchema: toInputSchema(z.object({}).strict()),
  },
  {
    name: "webkitui_new_tab",
    description: "Open a new tab, make it active, and optionally navigate it.",
    annotations: { destructiveHint: true },
    inputSchema: toInputSchema(NewTabInput),
  },
  {
    name: "webkitui_switch_tab",
    description: "Make an existing tab active (subsequent navigate/click/evaluate/etc. target it) and bring it to front.",
    annotations: { readOnlyHint: false },
    inputSchema: toInputSchema(TabIdInput),
  },
  {
    name: "webkitui_close_tab",
    description: "Close a tab. If it was active, another open tab (if any) becomes active.",
    annotations: { destructiveHint: true },
    inputSchema: toInputSchema(TabIdInput),
  },
  {
    name: "webkitui_navigate",
    description:
      "Navigate the active tab to a URL. Clears that tab's console-log and network-request " +
      "buffers, so webkitui_console_logs / webkitui_network_requests always reflect 'since last navigate'.",
    annotations: { readOnlyHint: false },
    inputSchema: toInputSchema(NavigateInput),
  },
  {
    name: "webkitui_click",
    description: "Click the first element matching a Playwright locator string (CSS or text=) in the active tab.",
    annotations: { destructiveHint: true },
    inputSchema: toInputSchema(SelectorInput),
  },
  {
    name: "webkitui_type",
    description: "Fill text into the first element matching a Playwright locator string in the active tab.",
    annotations: { destructiveHint: true },
    inputSchema: toInputSchema(TypeInput),
  },
  {
    name: "webkitui_press_key",
    description:
      'Press a key or chord (e.g. "Enter", "Control+A") in the active tab — optionally focusing a ' +
      "selector first. Useful for shortcuts, form submission, and dismissing UI that click/type can't reach.",
    annotations: { destructiveHint: true },
    inputSchema: toInputSchema(PressKeyInput),
  },
  {
    name: "webkitui_wait_for",
    description:
      "Block until a condition is true on the active tab: either a locator reaches a state " +
      '(default "visible") or the URL matches a string/glob. Use before click/type/evaluate on ' +
      "content that loads asynchronously instead of guessing a fixed delay.",
    annotations: { readOnlyHint: true },
    inputSchema: toInputSchema(WaitForInput),
  },
  {
    name: "webkitui_screenshot",
    description: "Screenshot the active tab. Returns a file path if outPath is given, else base64 PNG.",
    annotations: { readOnlyHint: true },
    inputSchema: toInputSchema(ScreenshotInput),
  },
  {
    name: "webkitui_get_page_text",
    description: "Return the active tab's visible body text (document.body.innerText) — cheaper than a screenshot when you just need the content.",
    annotations: { readOnlyHint: true },
    inputSchema: toInputSchema(z.object({}).strict()),
  },
  {
    name: "webkitui_evaluate",
    description:
      "Run page.evaluate(script) in the active tab's MAIN world and return the JSON-serializable " +
      "result. For multi-statement scripts wrap in an IIFE, e.g. \"(() => { ...; return x; })()\". " +
      "Times out after timeoutMs (default 30000) so a hung script can't block the MCP server itself " +
      "— but the script keeps running in the page after that (Playwright/CDP has no true mid-eval " +
      "cancellation), which can still wedge later calls on the same tab. If a call times out, " +
      "prefer webkitui_navigate or webkitui_close_tab+webkitui_new_tab to get a clean tab.",
    annotations: { readOnlyHint: false },
    inputSchema: toInputSchema(EvaluateInput),
  },
  {
    name: "webkitui_console_logs",
    description: "Return console.log/warn/error/pageerror messages captured since the last webkitui_navigate, for a tab (default: active).",
    annotations: { readOnlyHint: true },
    inputSchema: toInputSchema(ConsoleLogsInput),
  },
  {
    name: "webkitui_network_requests",
    description:
      "Return network requests captured since the last webkitui_navigate for a tab (default: active), " +
      "with method/status/ok/failure/postDataPreview. Optionally filter by a URL substring.",
    annotations: { readOnlyHint: true },
    inputSchema: toInputSchema(NetworkRequestsInput),
  },
  {
    name: "webkitui_worker_console_logs",
    description:
      "Return console output captured from service/shared workers (e.g. an extension's MV3 " +
      "background.js) since launch — Playwright has no built-in API for this; it's captured via a " +
      "raw CDP Target.attachToTarget session set up at webkitui_launch. This is the only way to see " +
      "what an extension's background script logged; page-scoped webkitui_console_logs cannot see it. " +
      "Optionally filter by a substring of the worker's chrome-extension://<id>/... URL.",
    annotations: { readOnlyHint: true },
    inputSchema: toInputSchema(WorkerConsoleLogsInput),
  },
  {
    name: "webkitui_extension_id",
    description:
      "Return the chrome-extension:// id generated for the unpacked extension loaded at launch, " +
      "found via the context's registered service worker. Waits up to timeoutMs if the service " +
      "worker hasn't registered yet.",
    annotations: { readOnlyHint: true },
    inputSchema: toInputSchema(ExtensionIdInput),
  },
  {
    name: "webkitui_cdp_send",
    description:
      "Send a raw Chrome DevTools Protocol command against the active tab and return its result — " +
      "an escape hatch for anything not covered by the other tools (network throttling, geolocation " +
      "override, permission overrides, precise input events, etc.). See " +
      "https://chromedevtools.github.io/devtools-protocol/ for method/param reference. Opens a fresh " +
      "CDP session per call and detaches it afterward.",
    annotations: { destructiveHint: true },
    inputSchema: toInputSchema(CdpSendInput),
  },
  {
    name: "webkitui_close",
    description: "Close the browser context and all tabs cleanly. Safe to call even if nothing is launched.",
    annotations: { destructiveHint: true },
    inputSchema: toInputSchema(z.object({}).strict()),
  },
];

// ---------------------------------------------------------------------------
// Server wiring
// ---------------------------------------------------------------------------

const server = new Server({ name: "webkitui-mcp", version: "0.2.0" }, { capabilities: { tools: {} } });

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools }));

function ok(payload: unknown) {
  return { content: [{ type: "text" as const, text: JSON.stringify(payload, null, 2) }] };
}

function fail(message: string) {
  return { isError: true as const, content: [{ type: "text" as const, text: message }] };
}

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: rawArgs } = request.params;
  const args = rawArgs ?? {};
  try {
    switch (name) {
      case "webkitui_launch":
        return ok(await session.launch(LaunchInput.parse(args)));

      case "webkitui_list_tabs":
        return ok(await session.listTabs());

      case "webkitui_new_tab":
        return ok(await session.newTab(NewTabInput.parse(args).url));

      case "webkitui_switch_tab":
        return ok(await session.switchTab(TabIdInput.parse(args).tabId));

      case "webkitui_close_tab":
        return ok(await session.closeTab(TabIdInput.parse(args).tabId));

      case "webkitui_navigate": {
        const input = NavigateInput.parse(args);
        return ok(await session.navigate(input.url, input.waitUntil));
      }

      case "webkitui_click": {
        const input = SelectorInput.parse(args);
        return ok(await session.click(input.selector, input.timeoutMs));
      }

      case "webkitui_type": {
        const input = TypeInput.parse(args);
        return ok(await session.type(input.selector, input.text, input.timeoutMs));
      }

      case "webkitui_press_key": {
        const input = PressKeyInput.parse(args);
        return ok(await session.pressKey(input.key, input.selector, input.timeoutMs));
      }

      case "webkitui_wait_for":
        return ok(await session.waitFor(WaitForInput.parse(args)));

      case "webkitui_screenshot": {
        const input = ScreenshotInput.parse(args);
        return ok(await session.screenshot(input.outPath, input.fullPage));
      }

      case "webkitui_get_page_text":
        return ok(await session.getPageText());

      case "webkitui_evaluate": {
        const input = EvaluateInput.parse(args);
        return ok(await session.evaluate(input.script, input.timeoutMs));
      }

      case "webkitui_console_logs":
        return ok(session.getConsoleLogs(ConsoleLogsInput.parse(args).tabId));

      case "webkitui_network_requests": {
        const input = NetworkRequestsInput.parse(args);
        return ok(session.getNetworkRequests(input.urlContains, input.tabId));
      }

      case "webkitui_worker_console_logs":
        return ok(session.getWorkerConsoleLogs(WorkerConsoleLogsInput.parse(args).workerUrlContains));

      case "webkitui_extension_id":
        return ok(await session.extensionId(ExtensionIdInput.parse(args).timeoutMs));

      case "webkitui_cdp_send": {
        const input = CdpSendInput.parse(args);
        return ok(await session.cdpSend(input.method, input.params));
      }

      case "webkitui_close":
        return ok(await session.close());

      default:
        return fail(`Unknown tool: ${name}`);
    }
  } catch (e) {
    if (e instanceof z.ZodError) {
      return fail(`Invalid arguments for ${name}: ${JSON.stringify(e.issues, null, 2)}`);
    }
    const message = e instanceof Error ? e.message : String(e);
    return fail(`${name} failed: ${message}`);
  }
});

// L1 — never let one stray async error kill the long-lived server. Log to stderr
// (stdout is the MCP channel and must stay clean) and keep serving.
process.on("unhandledRejection", (reason) => {
  console.error("[webkitui-mcp] unhandledRejection:", reason);
});
process.on("uncaughtException", (err) => {
  console.error("[webkitui-mcp] uncaughtException:", err);
});

async function shutdown() {
  await session.close().catch(() => {});
  process.exit(0);
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("webkitui-mcp running on stdio");
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
