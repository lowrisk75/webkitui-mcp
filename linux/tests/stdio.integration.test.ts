import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { createInterface } from "node:readline";
import test from "node:test";

const enabled = process.env.WEBKITUI_RUN_BROWSER_TESTS === "1";

test(
  "stdio MCP performs confirmed Chromium open, navigate, observe, and close",
  { skip: !enabled, timeout: 60_000 },
  async () => {
    const child = spawn(process.execPath, [new URL("../src/index.js", import.meta.url).pathname], {
      stdio: ["pipe", "pipe", "pipe"],
    });
    const lines = createInterface({ input: child.stdout, crlfDelay: Infinity });
    const iterator = lines[Symbol.asyncIterator]();
    const send = (request: unknown) => child.stdin.write(`${JSON.stringify(request)}\n`);
    try {
      send(call(1, "browser_session", { operation: "open", engine: "chromium" }));
      const opened = await nextResponse(iterator);
      const sessionID = structured(opened).session_id as string;
      assert.ok(sessionID);

      const navigationArguments = { session_id: sessionID, url: "https://example.com" };
      send(call(2, "browser_navigate", navigationArguments));
      const requested = await nextResponse(iterator);
      const requestState = (requested.result as { requestState: string }).requestState;
      assert.ok(requestState);

      send({
        ...call(3, "browser_navigate", navigationArguments),
        params: {
          ...(call(3, "browser_navigate", navigationArguments).params as Record<string, unknown>),
          requestState,
          inputResponses: {
            confirmation: { action: "accept", content: { confirm: true } },
          },
        },
      });
      const navigated = await nextResponse(iterator);
      const observation = structured(navigated).observation as { title: { text: string } };
      assert.match(observation.title.text, /Example Domain/);

      send(call(4, "browser_observe", { session_id: sessionID }));
      const observed = await nextResponse(iterator);
      assert.ok((structured(observed).observation as { observation_id: string }).observation_id);

      send(call(5, "browser_session", { operation: "close", session_id: sessionID }));
      const closed = await nextResponse(iterator);
      assert.equal(structured(closed).state, "closed");
      child.stdin.end();
      const [exitCode] = (await once(child, "exit")) as [number | null];
      assert.equal(exitCode, 0);
    } finally {
      if (child.exitCode === null) child.kill();
    }
  },
);

function call(id: number, name: string, arguments_: Record<string, unknown>) {
  return {
    jsonrpc: "2.0",
    id,
    method: "tools/call",
    params: {
      name,
      arguments: arguments_,
      _meta: {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientInfo": { name: "stdio-tests", version: "1" },
        "io.modelcontextprotocol/clientCapabilities": { elicitation: {} },
      },
    },
  };
}

async function nextResponse(
  iterator: AsyncIterator<string>,
): Promise<Record<string, unknown>> {
  const next = await iterator.next();
  if (next.done) throw new Error("stdio server closed before responding");
  return JSON.parse(next.value) as Record<string, unknown>;
}

function structured(response: Record<string, unknown>): Record<string, unknown> {
  const result = response.result as { structuredContent?: Record<string, unknown> };
  if (result.structuredContent === undefined) throw new Error("missing structuredContent");
  return result.structuredContent;
}
