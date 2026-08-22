import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile, mkdir } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { ControllerLease } from "../src/lease.js";

test("controller lease excludes a second owner and releases cleanly", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "webkitui-lease-"));
  const lock = path.join(root, "controller.lock");
  try {
    const first = new ControllerLease(lock);
    const second = new ControllerLease(lock);
    await first.acquire();
    await assert.rejects(second.acquire(), /another Linux browser controller/);
    await first.release();
    await second.acquire();
    await second.release();
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("controller lease reclaims a dead owner record", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "webkitui-lease-"));
  const lock = path.join(root, "controller.lock");
  try {
    await mkdir(lock, { mode: 0o700 });
    await writeFile(
      path.join(lock, "owner.json"),
      JSON.stringify({ pid: 2_147_483_647, processStart: null, token: "dead" }),
    );
    const lease = new ControllerLease(lock);
    await lease.acquire();
    await lease.release();
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
