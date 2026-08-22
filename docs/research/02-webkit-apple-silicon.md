# Deep Research 2 — WebKit on Apple Silicon as an agent runtime

Paste into Perplexity Pro / Deep Research. Answer in English; end with a raw URL
list, one per line, no markdown.

---

**Role.** You are a macOS systems engineer. You are building a headless-ish
browser automation service on Apple Silicon, native WebKit, no Chromium, no
Node-based driver. It runs alongside heavy local workloads on a 16 GB machine, so
memory discipline matters more than peak throughput.

**Question.** What is the state of the art for driving WebKit programmatically on
macOS in 2026, and where are the real limits?

Cover:

1. **The available control surfaces.** WKWebView + `evaluateJavaScript`,
   `callAsyncJavaScript`, WKUserScript injection timing, the Safari/WebKit remote
   inspector protocol, `WKWebView.inspectable`, WebDriver via `safaridriver`,
   `WKWebExtension` (macOS 15+), and Playwright's WebKit build. For each: what it
   can and cannot do, and whether it survives across macOS releases.

2. **Running without a window.** Can WKWebView render, lay out and screenshot
   reliably off-screen or in a background app? What actually breaks — timers
   throttled, rAF suspended, IntersectionObserver never firing, media blocked?
   Cite the known workarounds and their cost.

3. **Process and memory.** WebKit's multi-process model, `WKProcessPool` sharing,
   `WKWebViewConfiguration` reuse, jetsam behaviour on a memory-pressured Mac, and
   how to bound a runaway page. Measured RSS per tab where anyone has published it.
   How does this compare with a Chromium/Playwright process tree for the same page?

4. **Apple Silicon specifics.** Anything measurably better on ARM64 than the
   Intel path: unified memory effects, `NSImage`/`CGImage` capture costs,
   ScreenCaptureKit vs `takeSnapshot(with:)`, VideoToolbox for encoding captures,
   and whether GPU-accelerated compositing is available off-screen.

5. **Accessibility as an API.** Getting a usable accessibility tree out of
   WKWebView on macOS: what is exposed via AX APIs versus what needs injected
   JavaScript. Fidelity, cost, and whether ARIA semantics survive.

6. **Determinism.** Waiting for a page to be *ready* rather than *loaded*:
   network-idle heuristics, mutation-observer quiescence, and what the reliable
   signals are on real sites.

**Constraints.** Apple documentation, WebKit source and bug reports, WWDC
sessions, and engineering write-ups only. Distinguish what is documented from what
is folklore. Flag anything that changed in macOS 26/27.

**Output.** A technical report, then a raw list of every source URL, one per line,
no markdown, for direct import into NotebookLM.
