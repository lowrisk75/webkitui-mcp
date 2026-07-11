// Validates webkitui_worker_console_logs against the real DLP extension.
//
// The DLP extension's background.js only console.error()s when its native
// messaging port disconnects (see extension/background.js) — there's no log
// on the success path. To get a deterministic real log line, this launches
// normally (native host connects fine, worker tracker attaches), THEN kills
// the running dlp-native-host process — background.js's port.onDisconnect
// fires for real, logging "[dlp] native host disconnected: ...", AFTER our
// tracker is already listening. (Hiding the manifest before launch instead
// races the service worker's eager top-level connect() against our tracker's
// async CDP attach chain — confirmed empirically to lose that race.)
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { execSync } from "node:child_process";

const serverEntry = "/Users/kevinnadjarian/GitHub/webkitui-mcp/dist/index.js";
const extensionPath = "/Users/kevinnadjarian/GitHub/RGPD/dlp-endpoint/extension";

async function callTool(client, name, args = {}) {
  const res = await client.callTool({ name, arguments: args });
  const text = res.content?.[0]?.text ?? "";
  let parsed;
  try { parsed = JSON.parse(text); } catch { parsed = text; }
  console.log(`${name}(${JSON.stringify(args)}) -> ${res.isError ? "ERROR" : "ok"}`);
  if (res.isError) { console.log(text); throw new Error(`${name} failed`); }
  return parsed;
}

async function main() {
  const transport = new StdioClientTransport({ command: "node", args: [serverEntry] });
  const client = new Client({ name: "goat-worker-test", version: "0.1.0" }, { capabilities: {} });

  await client.connect(transport);
  await callTool(client, "webkitui_launch", { loadExtensionPath: extensionPath });
  const { extensionId } = await callTool(client, "webkitui_extension_id", {});
  console.log("extensionId:", extensionId);

  // Let background.js's initial connect() settle (successfully, native host
  // is present) before we yank the process out from under it.
  await new Promise((r) => setTimeout(r, 1000));

  try {
    execSync("pkill -f dlp-native-host");
    console.log("killed dlp-native-host process(es)");
  } catch {
    console.log("no dlp-native-host process found to kill (port may not have connected yet)");
  }
  await new Promise((r) => setTimeout(r, 1000));

  console.log("\n--- worker console logs (after killing native host mid-session) ---");
  const logs = await callTool(client, "webkitui_worker_console_logs", {});
  console.log(JSON.stringify(logs, null, 2));

  await callTool(client, "webkitui_close", {});
  await client.close();

  // background.js's own console.error() text is the ideal signal, but Chrome
  // doesn't reliably surface console.* calls made from inside chrome.* API
  // event callbacks over CDP (see WorkerConsoleTracker's doc comment) — its
  // own internal "Unchecked runtime.lastError" diagnostic for the same event
  // (delivered via the Log domain) is the reliable fallback signal.
  const ownLog = logs.find((e) => e.workerUrl.includes(extensionId) && e.text.includes("native host disconnected"));
  const chromeLog = logs.find(
    (e) => e.workerUrl.includes(extensionId) && /native host|lastError/i.test(e.text),
  );
  if (ownLog) {
    console.log("\nPASS (best case): captured background.js's own console.error via webkitui_worker_console_logs.");
  } else if (chromeLog) {
    console.log(
      `\nPASS (fallback): background.js's own console.error wasn't captured (known Chrome limitation), ` +
        `but Chrome's own diagnostic was: "${chromeLog.text}" — the disconnect is still observable.`,
    );
  } else {
    console.error("\nFAIL: captured nothing about the native-host disconnect, via any channel.");
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error("TEST FAILED:", e);
  process.exitCode = 1;
});
