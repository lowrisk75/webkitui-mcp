#!/usr/bin/env node

import assert from "node:assert/strict";
import net from "node:net";

const socketPath = process.argv[2];
const expectedVersion = process.argv[3] ?? "0.6.0";
const timeoutMilliseconds = 10_000;

if (!socketPath) {
  throw new Error("usage: verify-installed-native.mjs <socket-path> [expected-version]");
}

const metadata = {
  "io.modelcontextprotocol/protocolVersion": "2026-07-28",
  "io.modelcontextprotocol/clientInfo": {
    name: "webkitui-installed-verifier",
    version: "1",
  },
  "io.modelcontextprotocol/clientCapabilities": { elicitation: {} },
};

function connect() {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(socketPath);
    const connectionTimeout = setTimeout(() => {
      socket.destroy();
      reject(new Error(`timed out connecting to ${socketPath}`));
    }, timeoutMilliseconds);
    let nextID = 1;
    let buffered = "";
    const pending = new Map();

    socket.setEncoding("utf8");
    socket.once("error", (error) => {
      clearTimeout(connectionTimeout);
      reject(error);
    });
    socket.once("connect", () => {
      clearTimeout(connectionTimeout);
      socket.removeAllListeners("error");
      socket.on("error", (error) => {
        for (const entry of pending.values()) entry.reject(error);
        pending.clear();
      });
      socket.on("data", (chunk) => {
        buffered += chunk;
        while (buffered.includes("\n")) {
          const boundary = buffered.indexOf("\n");
          const line = buffered.slice(0, boundary);
          buffered = buffered.slice(boundary + 1);
          if (!line.trim()) continue;
          const response = JSON.parse(line);
          const entry = pending.get(response.id);
          if (!entry) continue;
          pending.delete(response.id);
          if (response.error) entry.reject(new Error(JSON.stringify(response.error)));
          else entry.resolve(response.result);
        }
      });

      resolve({
        call(method, params = {}) {
          const id = nextID++;
          const request = {
            jsonrpc: "2.0",
            id,
            method,
            params: { ...params, _meta: metadata },
          };
          return new Promise((resolveCall, rejectCall) => {
            const callTimeout = setTimeout(() => {
              pending.delete(id);
              rejectCall(new Error(`${method} timed out after ${timeoutMilliseconds} ms`));
            }, timeoutMilliseconds);
            pending.set(id, {
              resolve(value) {
                clearTimeout(callTimeout);
                resolveCall(value);
              },
              reject(error) {
                clearTimeout(callTimeout);
                rejectCall(error);
              },
            });
            socket.write(`${JSON.stringify(request)}\n`);
          });
        },
        close() {
          socket.end();
        },
      });
    });
  });
}

async function tool(client, name, args) {
  const result = await client.call("tools/call", { name, arguments: args });
  assert.equal(result.resultType, "complete");
  return result.structuredContent;
}

const first = await connect();
const second = await connect();

try {
  const [firstDiscovery, secondDiscovery] = await Promise.all([
    first.call("server/discover"),
    second.call("server/discover"),
  ]);
  assert.equal(firstDiscovery._meta["io.modelcontextprotocol/serverInfo"].version, expectedVersion);
  assert.equal(secondDiscovery._meta["io.modelcontextprotocol/serverInfo"].version, expectedVersion);

  const expectedTools = [
    "browser_act",
    "browser_capture",
    "browser_fill_siliconpass",
    "browser_rotate_siliconpass_password",
    "browser_navigate",
    "browser_observe",
    "browser_read_text",
    "browser_scroll",
    "element_scroll_into_view",
    "browser_session",
    "browser_transaction",
  ];
  const [firstTools, secondTools] = await Promise.all([
    first.call("tools/list"),
    second.call("tools/list"),
  ]);
  assert.deepEqual(firstTools.tools.map(({ name }) => name), expectedTools);
  assert.deepEqual(secondTools.tools.map(({ name }) => name), expectedTools);

  const [firstProfiles, secondProfiles] = await Promise.all([
    tool(first, "browser_session", { operation: "profiles" }),
    tool(second, "browser_session", { operation: "profiles" }),
  ]);
  assert.deepEqual(firstProfiles.profiles, ["default"]);
  assert.deepEqual(secondProfiles.profiles, ["default"]);
  assert.equal(firstProfiles.contains_credentials, false);
  assert.equal(secondProfiles.contains_credentials, false);

  const firstSession = await tool(first, "browser_session", {
    operation: "open",
    profile_id: "default",
  });
  const secondSession = await tool(second, "browser_session", {
    operation: "open",
    profile_id: "default",
  });
  assert.equal(firstSession.session_id, secondSession.session_id);
  assert.equal(firstSession.profile_id, "default");
  assert.equal(secondSession.profile_id, "default");

  console.log(JSON.stringify({
    status: "verified",
    version: expectedVersion,
    clients: 2,
    tools: expectedTools.length,
    profile: "default",
    sharedSession: true,
  }, null, 2));
} finally {
  first.close();
  second.close();
}
