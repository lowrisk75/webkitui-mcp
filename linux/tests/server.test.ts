import assert from "node:assert/strict";
import test from "node:test";
import { LinuxMCPServer } from "../src/server.js";
import type { LinuxBrowserRuntime, LinuxRuntimeOptions } from "../src/runtime.js";

class FakeRuntime {
  readonly sessionID = "00000000-0000-4000-8000-000000000001";
  readonly allowWrites = false;
  navigateCalls = 0;
  opened = false;

  async open() {
    this.opened = true;
  }

  async close() {
    this.opened = false;
  }

  status() {
    return { session_id: this.sessionID, state: this.opened ? "open" : "closed" };
  }

  async navigate(url: string) {
    this.navigateCalls += 1;
    return { observation_id: "observation-1", url };
  }

  async observe() {
    return { observation_id: "observation-2" };
  }

  async capture() {
    return { mime_type: "image/png" as const, base64: "AA==" };
  }

  async act() {
    throw new Error("disabled");
  }

  transaction() {
    throw new Error("unknown receipt_id");
  }
}

test("publishes exactly the six bounded tools and no raw evaluator", async () => {
  const server = new LinuxMCPServer();
  const response = await request(server, 1, "tools/list", {}, false);
  const tools = (response.result as { tools: Array<{ name: string }> }).tools;
  assert.deepEqual(
    tools.map((tool) => tool.name),
    [
      "browser_session",
      "browser_navigate",
      "browser_observe",
      "browser_capture",
      "browser_act",
      "browser_transaction",
    ],
  );
  assert.equal(JSON.stringify(tools).includes("evaluate"), false);
});

test("legacy navigation fails closed without dispatch", async () => {
  const fake = new FakeRuntime();
  const server = serverWith(fake);
  await open(server, false);
  const response = await request(
    server,
    2,
    "tools/call",
    {
      name: "browser_navigate",
      arguments: { session_id: fake.sessionID, url: "https://example.com" },
    },
    false,
  );
  assert.equal((response.result as { isError: boolean }).isError, true);
  assert.equal(fake.navigateCalls, 0);
});

test("modern confirmation is exact, single-use, and dispatches once", async () => {
  const fake = new FakeRuntime();
  const server = serverWith(fake);
  await open(server, true);
  const arguments_ = { session_id: fake.sessionID, url: "https://example.com" };
  const requested = await request(
    server,
    2,
    "tools/call",
    { name: "browser_navigate", arguments: arguments_ },
    true,
  );
  const pending = requested.result as { resultType: string; requestState: string };
  assert.equal(pending.resultType, "input_required");
  assert.equal(fake.navigateCalls, 0);

  const changed = await request(
    server,
    3,
    "tools/call",
    {
      name: "browser_navigate",
      arguments: { ...arguments_, url: "https://attacker.example" },
      requestState: pending.requestState,
      inputResponses: confirmation(),
    },
    true,
  );
  assert.equal((changed.error as { code: number }).code, -32602);
  assert.equal(fake.navigateCalls, 0);

  const requestedAgain = await request(
    server,
    4,
    "tools/call",
    { name: "browser_navigate", arguments: arguments_ },
    true,
  );
  const state = (requestedAgain.result as { requestState: string }).requestState;
  const accepted = await request(
    server,
    5,
    "tools/call",
    {
      name: "browser_navigate",
      arguments: arguments_,
      requestState: state,
      inputResponses: confirmation(),
    },
    true,
  );
  assert.equal((accepted.result as { isError?: boolean }).isError, undefined);
  assert.equal(fake.navigateCalls, 1);

  const replay = await request(
    server,
    6,
    "tools/call",
    {
      name: "browser_navigate",
      arguments: arguments_,
      requestState: state,
      inputResponses: confirmation(),
    },
    true,
  );
  assert.equal((replay.error as { code: number }).code, -32602);
  assert.equal(fake.navigateCalls, 1);
});

test("read-only worker rejects act before creating a confirmation", async () => {
  const fake = new FakeRuntime();
  const server = serverWith(fake);
  await open(server, true);
  const response = await request(
    server,
    2,
    "tools/call",
    {
      name: "browser_act",
      arguments: {
        session_id: fake.sessionID,
        kind: "fill",
        observation_id: "o1",
        element_id: "e1",
        text: "safe",
      },
    },
    true,
  );
  assert.equal((response.result as { isError: boolean }).isError, true);
  assert.match(JSON.stringify(response.result), /read-only/);
});

function serverWith(fake: FakeRuntime): LinuxMCPServer {
  return new LinuxMCPServer((_options: LinuxRuntimeOptions) => fake as unknown as LinuxBrowserRuntime);
}

async function open(server: LinuxMCPServer, modern: boolean): Promise<void> {
  const response = await request(
    server,
    1,
    "tools/call",
    { name: "browser_session", arguments: { operation: "open" } },
    modern,
  );
  assert.equal((response.result as { isError?: boolean }).isError, undefined);
}

function confirmation() {
  return { confirmation: { action: "accept", content: { confirm: true } } };
}

async function request(
  server: LinuxMCPServer,
  id: number,
  method: string,
  params: Record<string, unknown>,
  modern: boolean,
): Promise<Record<string, unknown>> {
  const requestParams = { ...params };
  if (modern) {
    requestParams._meta = {
      "io.modelcontextprotocol/protocolVersion": "2026-07-28",
      "io.modelcontextprotocol/clientInfo": { name: "tests", version: "1" },
      "io.modelcontextprotocol/clientCapabilities": { elicitation: {} },
    };
  }
  const line = await server.handleLine(
    JSON.stringify({ jsonrpc: "2.0", id, method, params: requestParams }),
  );
  assert.notEqual(line, null);
  return JSON.parse(line as string) as Record<string, unknown>;
}
