import assert from "node:assert/strict";
import test from "node:test";
import { NetworkPolicy, isPublicAddress, parseOriginSet } from "../src/security.js";

test("public-address policy blocks local, private, documentation, and mapped ranges", () => {
  for (const address of [
    "0.0.0.0",
    "10.0.0.1",
    "100.64.0.1",
    "127.0.0.1",
    "169.254.1.1",
    "172.16.0.1",
    "192.168.1.1",
    "192.0.2.1",
    "198.51.100.1",
    "203.0.113.1",
    "224.0.0.1",
    "::1",
    "fd00::1",
    "fe80::1",
    "ff02::1",
    "::ffff:127.0.0.1",
    "::ffff:7f00:1",
    "64:ff9b::7f00:1",
    "100::1",
    "2001::1",
    "2001:db8::1",
    "2002:7f00:1::",
  ]) {
    assert.equal(isPublicAddress(address), false, address);
  }
  assert.equal(isPublicAddress("1.1.1.1"), true);
  assert.equal(isPublicAddress("2606:4700:4700::1111"), true);
});

test("navigation parser rejects credentials, local names, and non-web schemes", () => {
  const policy = new NetworkPolicy({
    resolver: { resolve4: async () => ["1.1.1.1"], resolve6: async () => [] },
  });
  assert.throws(() => policy.parseNavigationURL("file:///etc/passwd"));
  assert.throws(() => policy.parseNavigationURL("http://localhost/"));
  assert.throws(() => policy.parseNavigationURL("https://user:secret@example.com/"));
  assert.equal(policy.parseNavigationURL("https://example.com/path").origin, "https://example.com");
});

test("DNS answers fail closed if any resolved address is private", async () => {
  const policy = new NetworkPolicy({
    resolver: {
      resolve4: async () => ["1.1.1.1"],
      resolve6: async () => ["::1"],
    },
  });
  await assert.rejects(policy.assertPublicURL(new URL("https://example.com")));
});

test("request capability is same-origin plus explicit subresource origins", async () => {
  const policy = new NetworkPolicy({
    allowedSubresourceOrigins: new Set(["https://static.example.net"]),
    resolver: { resolve4: async () => ["1.1.1.1"], resolve6: async () => [] },
  });
  await policy.authorizeRequest("https://example.com/app", "https://example.com", true);
  await policy.authorizeRequest(
    "https://static.example.net/app.js",
    "https://example.com",
    false,
  );
  await assert.rejects(
    policy.authorizeRequest("https://attacker.example/leak", "https://example.com", false),
  );
  await assert.rejects(
    policy.authorizeRequest("https://static.example.net/redirect", "https://example.com", true),
  );
  await policy.authorizeProxyURL(
    new URL("https://static.example.net/app.js"),
    "https://example.com",
  );
  await assert.rejects(
    policy.authorizeProxyURL(new URL("https://attacker.example/leak"), "https://example.com"),
  );
});

test("operator subresource allowlist accepts bare origins only", () => {
  assert.deepEqual(
    [...parseOriginSet("https://cdn.example,https://images.example:8443")],
    ["https://cdn.example", "https://images.example:8443"],
  );
  assert.throws(() => parseOriginSet("https://cdn.example/path"));
});
