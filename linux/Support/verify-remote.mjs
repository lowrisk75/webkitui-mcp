#!/usr/bin/env node
import { spawn } from "node:child_process";
import { once } from "node:events";
import { createInterface } from "node:readline";
import { performance } from "node:perf_hooks";

const command = process.argv.slice(2);
if (command.length === 0) throw new Error("usage: verify-remote.mjs COMMAND [ARG ...]");
const engine = process.env.WEBKITUI_VERIFY_ENGINE ?? "chromium";
if (engine !== "chromium" && engine !== "webkit") throw new Error("invalid engine");

const child = spawn(command[0], command.slice(1), { stdio: ["pipe", "pipe", "inherit"] });
const iterator = createInterface({ input: child.stdout, crlfDelay: Infinity })[Symbol.asyncIterator]();
let id = 0;
const timings = {};

async function request(name, arguments_, extras = {}) {
  const started = performance.now();
  child.stdin.write(`${JSON.stringify({
    jsonrpc: "2.0",
    id: ++id,
    method: "tools/call",
    params: {
      name,
      arguments: arguments_,
      _meta: {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": { elicitation: {} },
      },
      ...extras,
    },
  })}\n`);
  let timer;
  const line = await Promise.race([
    iterator.next(),
    new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error("response timeout")), 60_000);
    }),
  ]).finally(() => clearTimeout(timer));
  if (line.done) throw new Error("remote closed before responding");
  const response = JSON.parse(line.value);
  if (response.error) throw new Error(response.error.message);
  timings[`${name}_${id}`] = Math.round(performance.now() - started);
  return response.result;
}

try {
  const opened = await request("browser_session", { operation: "open", engine });
  const sessionID = opened.structuredContent.session_id;
  const privateNavigation = { session_id: sessionID, url: "http://127.0.0.1" };
  const privatePending = await request("browser_navigate", privateNavigation);
  const privateDenied = await request("browser_navigate", privateNavigation, {
    requestState: privatePending.requestState,
    inputResponses: { confirmation: { action: "accept", content: { confirm: true } } },
  });
  if (privateDenied.isError !== true) throw new Error("private navigation was not denied");
  const navigation = { session_id: sessionID, url: "https://example.com" };
  const pending = await request("browser_navigate", navigation);
  const navigated = await request("browser_navigate", navigation, {
    requestState: pending.requestState,
    inputResponses: { confirmation: { action: "accept", content: { confirm: true } } },
  });
  const observed = await request("browser_observe", { session_id: sessionID });
  const capture = await request("browser_capture", { session_id: sessionID, full_page: false });
  await request("browser_session", { operation: "close", session_id: sessionID });
  child.stdin.end();
  const [exitCode] = await once(child, "exit");
  if (exitCode !== 0) throw new Error(`remote exited ${exitCode}`);
  const observation = observed.structuredContent.observation;
  console.log(JSON.stringify({
    engine,
    title: navigated.structuredContent.observation.title.text,
    observation_id_present: typeof observation.observation_id === "string",
    private_navigation_denied: true,
    capture_bytes: Math.floor(capture.structuredContent.capture.base64.length * 0.75),
    addressing: observation.addressing,
    timings_ms: timings,
  }));
} finally {
  if (child.exitCode === null) child.kill();
}
