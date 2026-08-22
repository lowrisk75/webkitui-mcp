# Same-Mac WKWebView versus Playwright benchmark — 2026-08-21

## NotebookLM queries

The required WebKITUI MPC notebook was asked for published measurements/fair protocol, bugs/confounders, and unique missed metrics. One missed-opportunity answer failed; a shorter English reformulation succeeded.

## Source-supported before measurement

- No credible published same-page, same-Mac Apple Silicon comparison of active WKWebView and Playwright Chromium was found in the supplied corpus.
- Parent PID RSS is invalid for both multiprocess engines; full process-tree aggregation is required.
- Viewport and device scale must match because pixel buffers affect unified memory.
- Offscreen WKWebView and headless Chromium are not equivalent power-management states.
- `WKProcessPool` must not be used for benchmark isolation.

## Locally measured

Machine/date lane: current Apple Silicon Mac, 2026-08-21. Release arm64. Deterministic local fixture. No network or LLM. `n = 30` fresh contexts per engine. Both returned 500 elements and 2560×1600 PNGs.

| Metric | WKWebView median / p95 | Playwright 1.61.1 + Chrome 151 median / p95 |
|---|---:|---:|
| Context initialization | 2.38 / 5.75 ms | 114.57 / 167.89 ms |
| Readiness | 384.55 / 457.39 ms | 335.86 / 343.77 ms |
| Observation | 20.11 / 20.92 ms | 42.86 / 54.20 ms |
| PNG capture | 38.18 / 41.71 ms | 64.04 / 90.72 ms |

Chrome launch measured 630.58 ms. WebKit helper cold start was not separately observable in this harness and is **unknown**.

WebkitUIMCP observation JSON was 993,627 bytes; the simplified Playwright comparison object was 106,981 bytes. This reflects different schemas and must not be presented as engine overhead or token efficiency. PNG sizes also differ because encoder/render output differs.

## Conjectural / not established

- These results do not prove WKWebView is globally faster: only context creation, this semantic extraction implementation, and this screenshot path were lower in this offscreen fixture.
- Chrome's lower readiness time may come from engine/page-load differences, instrumentation overhead, or WebKit background policy; the harness does not causally separate them.
- Memory, energy, GPU cost, long-run decay, crash recovery, visible-window behavior, and authenticated-session success remain unmeasured.
- The Playwright-pinned Chromium binary was absent. Installed Chrome stable is a valid Chromium-family comparison lane, but not the exact originally requested binary.

## Artifacts

- `Benchmarks/fixture.html`
- `Benchmarks/results-wkwebview-2026-08-21.json`
- `Benchmarks/results-playwright-chrome-2026-08-21.json`
- `Benchmarks/README.md`
