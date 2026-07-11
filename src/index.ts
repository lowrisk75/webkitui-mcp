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
      .describe('Browser channel, e.g. "chrome", "chrome-beta". Default "chrome" (real installed Chrome, not bundled Chromium).'),
  })
  .strict();

const NavigateInput = z
  .object({
    url: z.string().min(1).describe("URL to navigate the active page to."),
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
      .describe("JS expression or IIFE evaluated in the page's MAIN world via page.evaluate."),
    timeoutMs: z.number().int().positive().optional().describe("Default 30000."),
  })
  .strict();

const NetworkRequestsInput = z
  .object({
    urlContains: z.string().optional().describe("Substring filter on request URL."),
  })
  .strict();

const ExtensionIdInput = z
  .object({
    timeoutMs: z.number().int().positive().optional().describe("Wait for the service worker to register. Default 5000."),
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
      "requires headless=false (Chrome refuses unpacked extensions headless, no exceptions). " +
      "Re-launching closes any existing session first. Attaches console/network listeners to " +
      "the first page immediately.",
    annotations: { destructiveHint: true },
    inputSchema: toInputSchema(LaunchInput),
  },
  {
    name: "webkitui_navigate",
    description:
      "Navigate the active page to a URL. Clears the console-log and network-request buffers " +
      "on every navigate, so webkitui_console_logs / webkitui_network_requests always reflect " +
      "'since last navigate'.",
    annotations: { readOnlyHint: false },
    inputSchema: toInputSchema(NavigateInput),
  },
  {
    name: "webkitui_click",
    description: "Click the first element matching a Playwright locator string (CSS or text=).",
    annotations: { destructiveHint: true },
    inputSchema: toInputSchema(SelectorInput),
  },
  {
    name: "webkitui_type",
    description: "Fill text into the first element matching a Playwright locator string.",
    annotations: { destructiveHint: true },
    inputSchema: toInputSchema(TypeInput),
  },
  {
    name: "webkitui_screenshot",
    description: "Screenshot the active page. Returns a file path if outPath is given, else base64 PNG.",
    annotations: { readOnlyHint: true },
    inputSchema: toInputSchema(ScreenshotInput),
  },
  {
    name: "webkitui_evaluate",
    description:
      "Run page.evaluate(script) in the active page's MAIN world and return the JSON-serializable " +
      "result. For multi-statement scripts wrap in an IIFE, e.g. \"(() => { ...; return x; })()\". " +
      "Times out after timeoutMs (default 30000) so a hung script can't block the MCP server itself " +
      "— but the script keeps running in the page after that (Playwright/CDP has no true mid-eval " +
      "cancellation), which can still wedge later calls on the same page. If a call times out, " +
      "prefer webkitui_navigate or webkitui_close+webkitui_launch to get a clean page.",
    annotations: { readOnlyHint: false },
    inputSchema: toInputSchema(EvaluateInput),
  },
  {
    name: "webkitui_console_logs",
    description: "Return console.log/warn/error/pageerror messages captured since the last webkitui_navigate.",
    annotations: { readOnlyHint: true },
    inputSchema: toInputSchema(z.object({}).strict()),
  },
  {
    name: "webkitui_network_requests",
    description:
      "Return network requests captured since the last webkitui_navigate, with method/status/ok/failure. " +
      "Optionally filter by a URL substring.",
    annotations: { readOnlyHint: true },
    inputSchema: toInputSchema(NetworkRequestsInput),
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
    name: "webkitui_close",
    description: "Close the browser context/session cleanly. Safe to call even if nothing is launched.",
    annotations: { destructiveHint: true },
    inputSchema: toInputSchema(z.object({}).strict()),
  },
];

// ---------------------------------------------------------------------------
// Server wiring
// ---------------------------------------------------------------------------

const server = new Server({ name: "webkitui-mcp", version: "0.1.0" }, { capabilities: { tools: {} } });

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

      case "webkitui_screenshot": {
        const input = ScreenshotInput.parse(args);
        return ok(await session.screenshot(input.outPath, input.fullPage));
      }

      case "webkitui_evaluate": {
        const input = EvaluateInput.parse(args);
        return ok(await session.evaluate(input.script, input.timeoutMs));
      }

      case "webkitui_console_logs":
        return ok(session.getConsoleLogs());

      case "webkitui_network_requests":
        return ok(session.getNetworkRequests(NetworkRequestsInput.parse(args).urlContains));

      case "webkitui_extension_id":
        return ok(await session.getExtensionId(ExtensionIdInput.parse(args).timeoutMs));

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
