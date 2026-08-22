# WebContent crash recovery — 2026-08-22

## Source-supported

- WebKit treats `webViewWebContentProcessDidTerminate(_:)` as the public host notification for a dead WebContent helper.
- There is no public per-view memory quota or public process-kill API.
- `WKProcessPool` is deprecated and cannot establish a hard one-view/one-process isolation boundary.
- No public web-agent benchmark reports recovery success after forced WebContent termination.

## NotebookLM counter-audit

- A test-only private kill selector does not model GPU/network helper death, App Nap, real memory pressure, or unknown server commit after a write.
- WebKit may share helpers; a process kill must not be assumed to affect exactly one view outside the controlled test.
- Recovery must invalidate node/observation handles and must never replay an indeterminate write.
- Metadata-only checkpoints and per-write recovery state are promising, but the notebook's broader systems claims were not adopted without primary verification.
- A follow-up found no public numeric WKWebView session-recovery or cookie-survival result. Its claim that cookies survive because storage is out of the WebContent process was treated as a hypothesis to measure.
- The opportunity notebook proposed generic task ledgers, zombie harvesting, and prompt-cache preservation. Those are not evidence for WebKit cookie fidelity and were not added to this slice.
- A post-implementation audit correctly warned that cookie-only recovery does not establish SPA state. Its uncited assertion that `sessionStorage` is necessarily erased by a WebContent crash was contradicted by the local forced-crash measurement below.

## Local design

- Use `_killWebContentProcessAndResetState` only inside a serialized test; never link or call private SPI in production code.
- Record a bounded native termination event and immediately invalidate the current observation address space.
- During a human handoff recovery, reload the last HTTP(S) URL in the same `WKWebsiteDataStore`, return a fresh observation, and never dispatch an action.
- Label the result as a WebContent-only forced crash probe, not full resource-pressure recovery.

## Local measurement

- The private selector is present on this macOS 27 runtime and is invoked only by the test target.
- A real forced helper termination fires the public delegate, records the prior document/observation IDs, and makes the old locator fail as stale.
- The first probe exposed that `_killWebContentProcessAndResetState` may clear `WKWebView.url`; recovery initially failed closed with `webContentProcessTerminated`.
- Moving the last observed HTTP(S) URL into host-owned state fixed the failure. The same non-persistent data store reloaded and returned a different document ID and observation ID in 0.874 seconds for the targeted test.
- No action was replayed. This does not resolve an in-flight server write, volatile SPA heap loss, GPU/network helper death, or background App Nap.
- Ten independent targeted test invocations all passed: median 0.762 s, p95/max 1.009 s, min 0.694 s. These durations include fixture startup, navigation, kill, reload, and fresh observation; they are not pure reload latency.
- A second fixture sets an `HttpOnly; SameSite=Lax` authentication cookie, proves an authenticated account page, kills WebContent, reloads the host-owned account URL in the same non-persistent data store, and proves the account page remains authenticated without reading or serializing the cookie.
- Cookie survival passed 10/10 independent runs: min 0.628 s, median 0.6495 s, interpolated p95 0.66055 s, max 0.661 s. Durations again include fixture startup and both pre-crash navigations, so they are end-to-end test times rather than reload-only latency.
- The fixture was then expanded to require the `HttpOnly` cookie, `localStorage`, and `sessionStorage` after recovery. All three survived 10/10 independent forced WebContent crashes: min 0.620 s, median 0.645 s, interpolated p95 0.68505 s, max 0.708 s.
- This measures one local HTTP origin in the same WKWebView/data-store lifetime. It does not prove in-memory JavaScript heap restoration (which is lost), OAuth refresh, partitioned cookies, IndexedDB, service workers, Keychain/passkeys, network-process death, or a host-process restart.
