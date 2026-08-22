# WKJSHandle probe

## Scope

`wkjs-handle-probe` is a macOS 27 executable that checks the public WebKit
object-result bridge without making `WKJSHandle` part of durable addressing.

It attempts handle creation through:

- isolated-world `evaluateJavaScript`;
- isolated-world `callAsyncJavaScript`;
- an object container returned by `evaluateJavaScript`;
- page-world `evaluateJavaScript` after navigation preferences explicitly
  enable handle creation.

It also probes the correctly named `WKDOMNodeSnapshot` API.

## Local measurement — 2026-08-21

Environment:

- arm64;
- macOS 27.0, build `26A5416b`;
- Xcode 27.0, build `27A5237l`;
- Swift compiler `6.4 (swiftlang-6.4.0.30.4)`.

Observed:

- both isolated and page worlds expose `window.webkit.createJSHandle` as a
  JavaScript function;
- `WKContentWorld.Configuration.jsHandleCreationEnabled` reads back as `true`;
- all four handle-return paths fail with `WKErrorDomain Code=5`,
  “JavaScript execution returned a result of an unsupported type”;
- `createNodeSnapshot` fails at the same native result boundary with Code 5;
- the final measured handle attempts took approximately 0.23–2.44 ms before
  returning the error. These are failure latencies, not performance results.

An explicit symbol-graph extraction also exposed a beta-component mismatch:
the SDK Swift interface reports `.31.1`, while the active compiler reports
`.30.4`. This is a plausible environmental cause, not a proven diagnosis.

## Decision

- The current beta runtime is **not usable** for native JS handles on this host.
- Keep the probe and rerun it after an OS/Xcode update.
- Availability checks alone are insufficient; the runtime needs a successful
  creation-and-dereference capability probe.
- `WKJSHandle` remains an optional short-lived optimization only.
- Ephemeral IDs backed by fresh locator recipes remain the canonical addressing
  design.
