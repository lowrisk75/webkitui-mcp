import fs from "node:fs/promises";

const documents = await Promise.all(process.argv.slice(2).map(async (path) => ({
  path,
  value: JSON.parse(await fs.readFile(path, "utf8")),
})));
if (documents.length === 0) throw new Error("usage: node summarize.mjs RESULT_JSON...");

const metricNames = [
  "contextInitializationNanoseconds",
  "readinessNanoseconds",
  "observationNanoseconds",
  "captureNanoseconds",
  "observationBytes",
  "pngBytes",
];
function percentile(values, fraction) {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * fraction) - 1)];
}
const summary = documents.map(({ path, value }) => ({
  path,
  engine: value.engine,
  mode: value.mode,
  browserLaunchMilliseconds: value.browserLaunchNanoseconds == null
    ? null : value.browserLaunchNanoseconds / 1e6,
  sampleCount: value.samples.length,
  pixelSize: [value.samples[0].pixelWidth, value.samples[0].pixelHeight],
  elementCount: value.samples[0].elementCount,
  metrics: Object.fromEntries(metricNames.map((name) => {
    const values = value.samples.map((sample) => sample[name]);
    const divisor = name.endsWith("Nanoseconds") ? 1e6 : 1;
    return [name.replace("Nanoseconds", "Milliseconds"), {
      median: percentile(values, 0.5) / divisor,
      p95: percentile(values, 0.95) / divisor,
      minimum: Math.min(...values) / divisor,
      maximum: Math.max(...values) / divisor,
    }];
  })),
}));
console.log(JSON.stringify(summary, null, 2));
