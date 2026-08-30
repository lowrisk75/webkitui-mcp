import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import path from "node:path";

const serverEntry = "/Users/kevinnadjarian/GitHub/webkitui-mcp/dist/index.js";

async function callTool(client, name, args = {}) {
  const res = await client.callTool({ name, arguments: args });
  const text = res.content?.[0]?.text ?? "";
  let parsed;
  try { parsed = JSON.parse(text); } catch { parsed = text; }
  console.log(`${name}(${JSON.stringify(args)}) -> ${res.isError ? "ERROR" : "ok"}`);
  console.log(JSON.stringify(parsed, null, 2));
  if (res.isError) throw new Error(`${name} failed: ${text}`);
  return parsed;
}

async function main() {
  const transport = new StdioClientTransport({ command: "node", args: [serverEntry] });
  const client = new Client({ name: "goat-test", version: "0.1.0" }, { capabilities: {} });
  await client.connect(transport);

  await callTool(client, "webkitui_launch", {});
  await callTool(client, "webkitui_navigate", { url: "https://example.com" });
  await callTool(client, "webkitui_get_page_text", {});
  await callTool(client, "webkitui_wait_for", { selector: "h1", state: "visible" });

  const tab1 = await callTool(client, "webkitui_list_tabs", {});
  const newTab = await callTool(client, "webkitui_new_tab", { url: "https://example.org" });
  await callTool(client, "webkitui_list_tabs", {});
  await callTool(client, "webkitui_switch_tab", { tabId: tab1[0].tabId });
  await callTool(client, "webkitui_console_logs", {});
  await callTool(client, "webkitui_close_tab", { tabId: newTab.tabId });
  await callTool(client, "webkitui_list_tabs", {});

  await callTool(client, "webkitui_press_key", { selector: "body", key: "Tab" });
  await callTool(client, "webkitui_cdp_send", { method: "Browser.getVersion" });

  await callTool(client, "webkitui_close", {});
  await client.close();
  console.log("\nALL GOAT-TIER TOOLS OK");
  process.exit(0);
}

main().catch((e) => {
  console.error("TEST FAILED:", e);
  process.exit(1);
});
