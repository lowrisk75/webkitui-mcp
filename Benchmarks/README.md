# Same-Mac browser benchmark

This first lane compares local runtime costs on one Apple Silicon Mac without an LLM or network. It is a controlled fixture benchmark, not a browser quality ranking.

## Controlled dimensions

- Same deterministic HTML and JavaScript fixture.
- 30 fresh non-persistent contexts per engine.
- 1280×800 CSS points, device scale 2, measured output 2560×1600.
- 500 interactive elements returned.
- 300 ms post-mutation quiet interval.
- Sequential execution on the same machine and date.

## Known non-equivalences

- WKWebView uses the production WebkitUIMCP observation containing provenance and locator recipes. The Playwright lane returns a smaller comparison DOM object. Observation byte size is therefore **not an engine comparison**.
- WKWebView is offscreen and subject to WebKit inactivity policy; Chrome is headless.
- The installed Playwright 1.61.1 Chromium bundle was absent. The measured lane uses installed Google Chrome 151 stable through Playwright's `channel: "chrome"`.
- Chrome launch is measured directly. WebKit helper launch is lazy and not yet isolated from readiness, so cold-start numbers are not equivalent.
- No process-tree RSS, energy, GPU, crash, or authenticated-session measurement is included yet.

## Reproduce

```bash
swift run -c release --arch arm64 webkitui-benchmark \
  Benchmarks/fixture.html 30 Benchmarks/results-wkwebview-2026-08-21.json

node Benchmarks/playwright-runner.mjs \
  Benchmarks/fixture.html 30 Benchmarks/results-playwright-chrome-2026-08-21.json

node Benchmarks/summarize.mjs \
  Benchmarks/results-wkwebview-2026-08-21.json \
  Benchmarks/results-playwright-chrome-2026-08-21.json
```

## Result — 2026-08-21

All times are milliseconds. `n = 30` per engine.

| Metric | WKWebView median / p95 | Playwright + Chrome median / p95 |
|---|---:|---:|
| Context initialization | 2.38 / 5.75 | 114.57 / 167.89 |
| Readiness | 384.55 / 457.39 | 335.86 / 343.77 |
| Observation extraction | 20.11 / 20.92 | 42.86 / 54.20 |
| PNG capture | 38.18 / 41.71 | 64.04 / 90.72 |

Chrome browser launch was 630.58 ms. No equivalent WebKit browser-helper cold-start value was produced, so it must not be compared to WK context initialization.

Raw immutable run artifacts:

- `results-wkwebview-2026-08-21.json`
- `results-playwright-chrome-2026-08-21.json`

## Next gates

1. Install the Playwright-pinned Chromium only with explicit authorization and add a separate lane.
2. Aggregate complete process-tree RSS/PSS rather than parent-process RSS.
3. Add presented-window lanes for both engines to expose background throttling.
4. Add repeated navigation/decay and process-termination experiments.
5. Keep representation/task-success evaluation separate from runtime latency.
