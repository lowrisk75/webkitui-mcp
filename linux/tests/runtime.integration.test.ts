import assert from "node:assert/strict";
import test from "node:test";
import type { Page } from "playwright";
import { LinuxBrowserRuntime } from "../src/runtime.js";

const enabled = process.env.WEBKITUI_RUN_BROWSER_TESTS === "1";

for (const engine of ["chromium", "webkit"] as const) {
  test(
    `${engine} opens, navigates, observes, captures, and closes`,
    { skip: !enabled, timeout: 60_000 },
    async () => {
      const runtime = new LinuxBrowserRuntime({ engine });
      await runtime.open();
      try {
        const observation = await runtime.navigate("https://example.com", 30_000);
        assert.equal(observation.backend, `linux-playwright-${engine}`);
        assert.equal(observation.url.text, "https://example.com/");
        assert.match(observation.title.text, /Example Domain/);
        assert.ok(observation.elements.some((element) => element.role.text === "link"));
        const capture = await runtime.capture(false);
        assert.equal(capture.mime_type, "image/png");
        assert.ok(capture.base64.length > 1_000);
        await assert.rejects(runtime.navigate("http://127.0.0.1", 1_000));
      } finally {
        await runtime.close();
      }
      assert.equal(runtime.status().state, "closed");
    },
  );
}

test(
  "transactional fill rejects implicit submit and click recovers a replaced semantic node",
  { skip: !enabled, timeout: 30_000 },
  async () => {
    const runtime = new LinuxBrowserRuntime({ engine: "chromium", allowWrites: true });
    await runtime.open();
    try {
      const page = runtimePage(runtime);
      await page.setContent(`
        <label for="email">Email</label><input id="email" />
        <button data-testid="save" onclick="document.querySelector('#result').textContent='Saved'">Save</button>
        <p id="result"></p>
      `);
      const first = await runtime.observe();
      const email = first.elements.find((element) => element.name.text === "Email");
      assert.ok(email);
      await assert.rejects(
        runtime.act({
          kind: "fill",
          observation_id: first.observation_id,
          element_id: email.element_id,
          text: "unsafe@example.com\n",
        }),
        /line breaks/,
      );

      const second = await runtime.observe();
      const secondEmail = second.elements.find((element) => element.name.text === "Email");
      assert.ok(secondEmail);
      const fillReceipt = await runtime.act({
        kind: "fill",
        observation_id: second.observation_id,
        element_id: secondEmail.element_id,
        text: "safe@example.com",
      });
      assert.equal(fillReceipt.status, "succeeded");
      assert.equal(runtime.transaction(fillReceipt.receipt_id), fillReceipt);

      const third = await runtime.observe();
      const save = third.elements.find((element) => element.name.text === "Save");
      assert.ok(save);
      await page.evaluate(() => {
        const old = document.querySelector("button");
        if (old === null) throw new Error("fixture button missing");
        const replacement = old.cloneNode(true) as HTMLElement;
        replacement.style.marginTop = "20px";
        old.replaceWith(replacement);
      });
      const clickReceipt = await runtime.act({
        kind: "click",
        observation_id: third.observation_id,
        element_id: save.element_id,
        expected_text: "Saved",
      });
      assert.equal(clickReceipt.status, "succeeded");
      const addressing = runtime.status().addressing as Record<string, number>;
      assert.equal(addressing.node_replaced_but_semantic_locator_recovered, 1);
      assert.equal(addressing.coordinate_invalidated_by_layout_change, 1);
    } finally {
      await runtime.close();
    }
  },
);

test(
  "action fails closed when a fresh semantic locator becomes ambiguous",
  { skip: !enabled, timeout: 30_000 },
  async () => {
    const runtime = new LinuxBrowserRuntime({ engine: "chromium", allowWrites: true });
    await runtime.open();
    try {
      const page = runtimePage(runtime);
      await page.setContent("<button>Save</button>");
      const observation = await runtime.observe();
      const save = observation.elements.find((element) => element.name.text === "Save");
      assert.ok(save);
      await page.evaluate(() => {
        const button = document.querySelector("button");
        if (button === null) throw new Error("fixture button missing");
        button.after(button.cloneNode(true));
      });
      await assert.rejects(
        runtime.act({
          kind: "click",
          observation_id: observation.observation_id,
          element_id: save.element_id,
          expected_text: "Saved",
        }),
        /ambiguous/,
      );
      const addressing = runtime.status().addressing as Record<string, number>;
      assert.equal(addressing.address_now_ambiguous, 1);
    } finally {
      await runtime.close();
    }
  },
);

function runtimePage(runtime: LinuxBrowserRuntime): Page {
  const page = (runtime as unknown as { page: Page | null }).page;
  if (page === null) throw new Error("runtime fixture page is unavailable");
  return page;
}
