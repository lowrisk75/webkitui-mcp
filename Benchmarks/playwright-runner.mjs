import fs from "node:fs/promises";
import { chromium } from "playwright";

const fixturePath = process.argv[2];
const iterations = Number(process.argv[3] ?? 5);
if (!fixturePath || !Number.isInteger(iterations) || iterations < 1 || iterations > 100) {
  throw new Error("usage: node playwright-runner.mjs FIXTURE [ITERATIONS 1...100]");
}
const html = await fs.readFile(fixturePath, "utf8");
const samples = [];

const initializationStart = process.hrtime.bigint();
const browser = await chromium.launch({ channel: "chrome", headless: true });
const initializationEnd = process.hrtime.bigint();

for (let index = 0; index < iterations; index += 1) {
  const contextInitializationStart = process.hrtime.bigint();
  const context = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    deviceScaleFactor: 2,
  });
  const page = await context.newPage();
  const contextInitializationEnd = process.hrtime.bigint();
  const readinessStart = process.hrtime.bigint();
  await page.setContent(html, { waitUntil: "load" });
  await page.waitForFunction(() => window.__benchmarkReady === true);
  await page.waitForTimeout(300);
  const readinessEnd = process.hrtime.bigint();

  const observationStart = process.hrtime.bigint();
  const observation = await page.evaluate(() => {
    const selector = "a[href],button,input,select,textarea,[role],[contenteditable='true']";
    return [...document.querySelectorAll(selector)].slice(0, 500).map((element, offset) => {
      const box = element.getBoundingClientRect();
      return {
        elementID: `e${offset + 1}`,
        tag: element.tagName.toLowerCase(),
        role: element.getAttribute("role"),
        accessibleName: element.getAttribute("aria-label") ?? "",
        label: element.labels?.[0]?.innerText ?? "",
        text: element.innerText ?? "",
        value: element.type === "password" ? null : (element.value ?? null),
        disabled: Boolean(element.disabled),
        visible: box.width > 0 && box.height > 0,
        boundingBox: { x: box.x, y: box.y, width: box.width, height: box.height },
      };
    });
  });
  const observationEnd = process.hrtime.bigint();
  const observationBytes = Buffer.byteLength(JSON.stringify(observation));

  const captureStart = process.hrtime.bigint();
  const png = await page.screenshot({ type: "png" });
  const captureEnd = process.hrtime.bigint();
  const imageSize = await page.evaluate(() => [innerWidth, innerHeight, devicePixelRatio]);
  samples.push({
    contextInitializationNanoseconds: Number(contextInitializationEnd - contextInitializationStart),
    readinessNanoseconds: Number(readinessEnd - readinessStart),
    observationNanoseconds: Number(observationEnd - observationStart),
    captureNanoseconds: Number(captureEnd - captureStart),
    observationBytes,
    elementCount: observation.length,
    pngBytes: png.length,
    pixelWidth: imageSize[0] * imageSize[2],
    pixelHeight: imageSize[1] * imageSize[2],
  });
  await context.close();
}
await browser.close();
const result = JSON.stringify({
  engine: "Playwright 1.61.1 + Google Chrome 151 stable",
  mode: "headless-incognito",
  viewportPoints: [1280, 800],
  browserLaunchNanoseconds: Number(initializationEnd - initializationStart),
  samples,
}, null, 2);
if (process.argv[4]) await fs.writeFile(process.argv[4], result + "\n");
else console.log(result);
