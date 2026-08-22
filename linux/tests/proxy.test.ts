import assert from "node:assert/strict";
import net from "node:net";
import test from "node:test";
import { PinnedHTTPProxy } from "../src/proxy.js";
import { NetworkPolicy } from "../src/security.js";

test("local proxy requires authentication and blocks private CONNECT targets", async () => {
  const policy = new NetworkPolicy({
    resolver: { resolve4: async () => ["1.1.1.1"], resolve6: async () => [] },
  });
  const proxy = new PinnedHTTPProxy(policy, () => "https://127.0.0.1");
  const endpoint = await proxy.start();
  try {
    const port = Number(new URL(endpoint.server).port);
    const unauthenticated = await rawProxyRequest(
      port,
      "CONNECT 127.0.0.1:443 HTTP/1.1\r\nHost: 127.0.0.1:443\r\n\r\n",
    );
    assert.match(unauthenticated, /^HTTP\/1\.1 407/);

    const authorization = Buffer.from(`${endpoint.username}:${endpoint.password}`).toString("base64");
    const privateTarget = await rawProxyRequest(
      port,
      `CONNECT 127.0.0.1:443 HTTP/1.1\r\nHost: 127.0.0.1:443\r\nProxy-Authorization: Basic ${authorization}\r\n\r\n`,
    );
    assert.match(privateTarget, /^HTTP\/1\.1 403/);
  } finally {
    await proxy.close();
  }
});

test("authenticated proxy blocks public authorities outside the session capability", async () => {
  const policy = new NetworkPolicy({
    resolver: { resolve4: async () => ["1.1.1.1"], resolve6: async () => [] },
  });
  const proxy = new PinnedHTTPProxy(policy, () => "https://example.com");
  const endpoint = await proxy.start();
  try {
    const port = Number(new URL(endpoint.server).port);
    const authorization = Buffer.from(`${endpoint.username}:${endpoint.password}`).toString("base64");
    const response = await rawProxyRequest(
      port,
      `CONNECT attacker.example:443 HTTP/1.1\r\nHost: attacker.example:443\r\nProxy-Authorization: Basic ${authorization}\r\n\r\n`,
    );
    assert.match(response, /^HTTP\/1\.1 403/);
  } finally {
    await proxy.close();
  }
});

async function rawProxyRequest(port: number, request: string): Promise<string> {
  return await new Promise((resolve, reject) => {
    const socket = net.connect({ host: "127.0.0.1", port });
    let response = "";
    socket.setEncoding("utf8");
    socket.once("error", reject);
    socket.on("data", (chunk) => {
      response += chunk;
      if (response.includes("\r\n\r\n")) {
        socket.destroy();
        resolve(response);
      }
    });
    socket.once("connect", () => socket.write(request));
  });
}
