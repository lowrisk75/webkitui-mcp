#!/usr/bin/env node
// Standalone MCP-client smoke test — spawns dist/index.js over stdio (exactly
// how Claude Code would) and drives it through a real session. Useful both as
// a CI-less sanity check and as a way to validate a fix before wiring the
// server into a live Claude Code session.
//
// Env vars:
//   SMOKE_URL                  URL to navigate to (default: https://example.com)
//   SMOKE_EXTENSION_PATH       unpacked MV3 extension dir to load (optional)
//   SMOKE_EVAL                 JS expression to run via webkitui_evaluate (optional)
//   SMOKE_POST_EXTENSION_CMD   shell command run once the extension id is known,
//                              with the id appended as the last argument
//                              (e.g. a native-messaging-host installer script)
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const serverEntry = path.join(here, "..", "dist", "index.js");

const url = process.env.SMOKE_URL ?? "https://example.com";
const extensionPath = process.env.SMOKE_EXTENSION_PATH ?? null;
const evalScript = process.env.SMOKE_EVAL ?? null;
const postExtensionCmd = process.env.SMOKE_POST_EXTENSION_CMD ?? null;

function section(title) {
  console.log(`\n=== ${title} ===`);
}

async function callTool(client, name, args = {}) {
  const res = await client.callTool({ name, arguments: args });
  const text = res.content?.[0]?.text ?? "";
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = text;
  }
  console.log(`${name}(${JSON.stringify(args)}) ->`, res.isError ? "ERROR" : "ok");
  console.log(JSON.stringify(parsed, null, 2));
  if (res.isError) throw new Error(`${name} failed: ${text}`);
  return parsed;
}

async function main() {
  const transport = new StdioClientTransport({ command: "node", args: [serverEntry] });
  const client = new Client({ name: "webkitui-mcp-smoke-test", version: "0.1.0" }, { capabilities: {} });

  section("connect");
  await client.connect(transport);
  const { tools } = await client.listTools();
  console.log(`${tools.length} tools:`, tools.map((t) => t.name).join(", "));

  section("webkitui_launch");
  await callTool(client, "webkitui_launch", extensionPath ? { loadExtensionPath: extensionPath } : {});

  if (extensionPath) {
    section("webkitui_extension_id");
    const { extensionId } = await callTool(client, "webkitui_extension_id", {});
    if (!extensionId) {
      console.warn("WARNING: no extension id resolved — service worker never registered.");
    } else if (postExtensionCmd) {
      section(`post-extension command: ${postExtensionCmd} ${extensionId}`);
      const out = execFileSync(postExtensionCmd, [extensionId], { encoding: "utf8" });
      console.log(out);
    }
  }

  section("webkitui_navigate");
  await callTool(client, "webkitui_navigate", { url });

  if (evalScript) {
    section("webkitui_evaluate");
    await callTool(client, "webkitui_evaluate", { script: evalScript });
  }

  section("webkitui_console_logs");
  await callTool(client, "webkitui_console_logs", {});

  section("webkitui_network_requests");
  await callTool(client, "webkitui_network_requests", {});

  section("webkitui_close");
  await callTool(client, "webkitui_close", {});

  await client.close();
  process.exit(0);
}

main().catch((err) => {
  console.error("SMOKE TEST FAILED:", err);
  process.exit(1);
});
