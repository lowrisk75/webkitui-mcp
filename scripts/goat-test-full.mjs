// Comprehensive coverage pass: exercises every tool at least once (click,
// type, screenshot were never tested before), wait_for's url mode, error
// paths (before-launch, invalid tabId, closing the last tab, real
// evaluate/wait_for timeouts, headless+extension), per-tab console/network
// isolation, cdp_send Browser.close triggering a clean context reset,
// concurrent-call mutex correctness, and a custom userDataDir.
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const serverEntry = "/Users/kevinnadjarian/GitHub/webkitui-mcp/dist/index.js";
let pass = 0;
let fail = 0;

function assert(cond, msg) {
  if (cond) {
    pass++;
    console.log(`  OK: ${msg}`);
  } else {
    fail++;
    console.error(`  FAIL: ${msg}`);
  }
}

async function callTool(client, name, args = {}) {
  const res = await client.callTool({ name, arguments: args });
  const text = res.content?.[0]?.text ?? "";
  let parsed;
  try { parsed = JSON.parse(text); } catch { parsed = text; }
  return { isError: Boolean(res.isError), text, parsed };
}

function connect() {
  const transport = new StdioClientTransport({ command: "node", args: [serverEntry] });
  const client = new Client({ name: "goat-full-test", version: "0.1.0" }, { capabilities: {} });
  return { transport, client };
}

const TEST_HTML = `<html><body>
<input id="txt" type="text" />
<button id="btn" onclick="document.getElementById('result').innerText='clicked'">Click me</button>
<div id="result">not clicked</div>
<a id="hashlink" href="javascript:void(0)" onclick="location.hash='jumped'">Jump</a>
</body></html>`;
const TEST_URL = `data:text/html,${encodeURIComponent(TEST_HTML)}`;

async function section1_clickTypeScreenshot() {
  console.log("\n=== 1. click / type / screenshot (never tested before) ===");
  const { transport, client } = connect();
  await client.connect(transport);
  await callTool(client, "webkitui_launch", {});
  await callTool(client, "webkitui_navigate", { url: TEST_URL });

  const typeRes = await callTool(client, "webkitui_type", { selector: "#txt", text: "hello goat" });
  assert(!typeRes.isError, "type into #txt succeeded");
  const typedVal = await callTool(client, "webkitui_evaluate", { script: "document.getElementById('txt').value" });
  assert(typedVal.parsed?.result === "hello goat", `typed value round-trips (got ${JSON.stringify(typedVal.parsed)})`);

  const clickRes = await callTool(client, "webkitui_click", { selector: "#btn" });
  assert(!clickRes.isError, "click #btn succeeded");
  const resultText = await callTool(client, "webkitui_evaluate", { script: "document.getElementById('result').innerText" });
  assert(resultText.parsed?.result === "clicked", `click actually fired the handler (got ${JSON.stringify(resultText.parsed)})`);

  const shotFile = path.join(os.tmpdir(), `goat-screenshot-${Date.now()}.png`);
  const fileShot = await callTool(client, "webkitui_screenshot", { outPath: shotFile });
  assert(!fileShot.isError && fs.existsSync(shotFile) && fs.statSync(shotFile).size > 500, "screenshot to file wrote a real PNG");
  fs.rmSync(shotFile, { force: true });

  const b64Shot = await callTool(client, "webkitui_screenshot", {});
  assert(!b64Shot.isError && typeof b64Shot.parsed?.base64 === "string" && b64Shot.parsed.base64.length > 500, "screenshot to base64 returned real data");

  await callTool(client, "webkitui_close", {});
  await client.close();
}

async function section2_waitForUrl() {
  console.log("\n=== 2. wait_for url mode ===");
  const { transport, client } = connect();
  await client.connect(transport);
  await callTool(client, "webkitui_launch", {});

  // Real http(s) URL, not data: — Playwright's URL-glob matcher (and
  // waitForURL's underlying navigation-wait semantics) are built around
  // real page navigations; a data: URL's own huge encoded-HTML "path"
  // plus a same-document hash change is an unrepresentative edge case.
  await callTool(client, "webkitui_navigate", { url: "https://example.com" });
  await callTool(client, "webkitui_evaluate", { script: "location.hash = 'jumped'" });
  const waited = await callTool(client, "webkitui_wait_for", { url: "**#jumped", timeoutMs: 3000 });
  assert(!waited.isError, `wait_for url mode resolved after hash change (${JSON.stringify(waited.isError ? waited.text : waited.parsed)})`);

  await callTool(client, "webkitui_close", {});
  await client.close();
}

async function section3_errorPaths() {
  console.log("\n=== 3. error paths ===");
  const { transport, client } = connect();
  await client.connect(transport);

  const beforeLaunch = await callTool(client, "webkitui_navigate", { url: TEST_URL });
  assert(beforeLaunch.isError && beforeLaunch.text.includes("No browser session"), "navigate before launch gives clean error");

  await callTool(client, "webkitui_launch", {});

  const badTab = await callTool(client, "webkitui_switch_tab", { tabId: "tab-999" });
  assert(badTab.isError && badTab.text.includes("Unknown tabId"), "switch_tab with bogus id gives clean error");

  const badHeadless = await callTool(client, "webkitui_launch", {
    loadExtensionPath: "/Users/kevinnadjarian/GitHub/RGPD/dlp-endpoint/extension",
    headless: true,
  });
  assert(badHeadless.isError && badHeadless.text.includes("headless"), "headless=true + extension throws clean error");
  // that failed launch must not have clobbered the working session from before it
  const stillWorks = await callTool(client, "webkitui_list_tabs", {});
  assert(
    !stillWorks.isError && Array.isArray(stillWorks.parsed) && stillWorks.parsed.length > 0,
    `session survives a failed re-launch attempt (got ${JSON.stringify(stillWorks.parsed)})`,
  );

  await callTool(client, "webkitui_navigate", { url: TEST_URL });
  const evalTimeout = await callTool(client, "webkitui_evaluate", {
    script: "new Promise(() => {})", // never resolves
    timeoutMs: 500,
  });
  assert(evalTimeout.isError && evalTimeout.text.includes("timed out"), "evaluate real timeout fires and reports cleanly");
  if (!evalTimeout.isError || !evalTimeout.text.includes("timed out")) console.log("    DEBUG evalTimeout:", JSON.stringify(evalTimeout));

  const waitTimeout = await callTool(client, "webkitui_wait_for", { selector: "#does-not-exist", timeoutMs: 500 });
  assert(waitTimeout.isError, "wait_for real timeout on a selector that never appears fires cleanly");

  const tabsAfterHang = await callTool(client, "webkitui_list_tabs", {});
  console.log("    DEBUG list_tabs after eval-timeout:", JSON.stringify(tabsAfterHang));
  if (!Array.isArray(tabsAfterHang.parsed) || tabsAfterHang.parsed.length === 0) {
    console.error("  FAIL: list_tabs returned no tabs after the eval-timeout — mutex/state got wedged");
    fail++;
    await client.close();
    return;
  }
  const tabs = tabsAfterHang;
  const onlyTabId = tabs.parsed[0].tabId;
  const closedLast = await callTool(client, "webkitui_close_tab", { tabId: onlyTabId });
  assert(!closedLast.isError, "closing the last tab doesn't crash the server");
  const afterLastClose = await callTool(client, "webkitui_navigate", { url: TEST_URL });
  assert(afterLastClose.isError, "navigate after closing the last tab gives a clean error, not a hang");

  await callTool(client, "webkitui_close", {});
  await client.close();
}

async function section4_tabIsolation() {
  console.log("\n=== 4. console/network isolation across tabs ===");
  const { transport, client } = connect();
  await client.connect(transport);
  await callTool(client, "webkitui_launch", {});

  const urlA = `data:text/html,${encodeURIComponent("<script>console.log('MARKER_A')</script>")}`;
  const urlB = `data:text/html,${encodeURIComponent("<script>console.log('MARKER_B')</script>")}`;

  await callTool(client, "webkitui_navigate", { url: urlA });
  const tab1 = (await callTool(client, "webkitui_list_tabs", {})).parsed[0].tabId;
  const tabB = await callTool(client, "webkitui_new_tab", { url: urlB });

  const logsTab1 = await callTool(client, "webkitui_console_logs", { tabId: tab1 });
  const logsTabB = await callTool(client, "webkitui_console_logs", { tabId: tabB.parsed.tabId });
  const tab1HasA = logsTab1.parsed.some((e) => e.text.includes("MARKER_A"));
  const tab1HasB = logsTab1.parsed.some((e) => e.text.includes("MARKER_B"));
  const tabBHasB = logsTabB.parsed.some((e) => e.text.includes("MARKER_B"));
  const tabBHasA = logsTabB.parsed.some((e) => e.text.includes("MARKER_A"));
  assert(tab1HasA && !tab1HasB, "tab1's console_logs has only its own marker");
  assert(tabBHasB && !tabBHasA, "tabB's console_logs has only its own marker, not tab1's");

  await callTool(client, "webkitui_close", {});
  await client.close();
}

async function section5_cdpBrowserClose() {
  console.log("\n=== 5. cdp_send Browser.close triggers clean reset ===");
  const { transport, client } = connect();
  await client.connect(transport);
  await callTool(client, "webkitui_launch", {});
  await callTool(client, "webkitui_navigate", { url: TEST_URL });

  await callTool(client, "webkitui_cdp_send", { method: "Browser.close" });
  await new Promise((r) => setTimeout(r, 500));

  const afterClose = await callTool(client, "webkitui_navigate", { url: TEST_URL });
  assert(
    afterClose.isError && afterClose.text.includes("No browser session"),
    `post-Browser.close call gives the clean "no session" error, not a raw Playwright error (got: ${afterClose.text.slice(0, 100)})`,
  );

  await client.close();
}

async function section6_concurrency() {
  console.log("\n=== 6. concurrent-call mutex correctness ===");
  const { transport, client } = connect();
  await client.connect(transport);
  await callTool(client, "webkitui_launch", {});
  await callTool(client, "webkitui_navigate", { url: TEST_URL });

  const results = await Promise.all(
    Array.from({ length: 8 }, (_, i) => callTool(client, "webkitui_evaluate", { script: `${i} * 2` })),
  );
  const allOk = results.every((r) => !r.isError);
  const values = results.map((r) => r.parsed?.result).sort((a, b) => a - b);
  const expected = Array.from({ length: 8 }, (_, i) => i * 2).sort((a, b) => a - b);
  assert(allOk, "8 concurrent evaluate calls all succeeded (no mutex deadlock/crash)");
  assert(JSON.stringify(values) === JSON.stringify(expected), `each call got its own correct result, no cross-talk (got ${JSON.stringify(values)})`);

  await callTool(client, "webkitui_close", {});
  await client.close();
}

async function section7_customUserDataDir() {
  console.log("\n=== 7. custom userDataDir ===");
  const customDir = path.join(os.tmpdir(), `goat-custom-profile-${Date.now()}`);
  const { transport, client } = connect();
  await client.connect(transport);
  const launched = await callTool(client, "webkitui_launch", { userDataDir: customDir });
  assert(!launched.isError && launched.parsed.userDataDir === customDir, "launch returns the exact custom userDataDir");
  assert(fs.existsSync(customDir), "custom userDataDir was actually created on disk");
  await callTool(client, "webkitui_close", {});
  await client.close();
  fs.rmSync(customDir, { recursive: true, force: true });
}

async function main() {
  await section1_clickTypeScreenshot();
  await section2_waitForUrl();
  await section3_errorPaths();
  await section4_tabIsolation();
  await section5_cdpBrowserClose();
  await section6_concurrency();
  await section7_customUserDataDir();

  console.log(`\n${"=".repeat(50)}`);
  console.log(`RESULT: ${pass} passed, ${fail} failed`);
  process.exitCode = fail > 0 ? 1 : 0;
}

main().catch((e) => {
  console.error("SUITE CRASHED:", e);
  process.exitCode = 1;
});
