# `willSubmitForm` instrumentation — 2026-08-22

## Primary SDK evidence

- macOS 27's `WKNavigationDelegate.webView(_:willSubmitForm:submissionHandler:)` runs after navigation policy allows a form submission and before it continues.
- `WKFormInfo` exposes transient `sourceFrame`, `targetFrame`, `submissionURL`, `httpMethod`, and all `formValues`; Apple explicitly says it does not uniquely identify a form across calls.
- The callback can delay continuation but provides no documented cancellation value.

## NotebookLM

- No published agent benchmark or recovery-rate measurement was returned for this API.
- The review correctly flags alternate exfiltration paths, frames, WebContent termination after dispatch, SPA fetch/XHR bypass, and the sensitivity of raw form values.
- The missed-opportunity query timed out and produced no usable answer.

## Implementation consequence

- Instrument standard navigational submissions as hash-only audit events.
- HMAC the full method, destination, and sorted form payload with a process-random key; never serialize field names or values.
- Record frame/origin shape, count, and monotonic time, then call the submission handler exactly once.
- Do not claim this observes `fetch`, XHR, WebSocket, beacon, or server commit.

## Local beta measurement

- Environment: macOS 27.0 build `26A5416b`, arm64, macOS 27 SDK.
- The runtime responds to Objective-C selector `webView:willSubmitForm:submissionHandler:`.
- A real local HTTP form submitted with page-world `requestSubmit()` reached `/submitted`, but the delegate produced zero events.
- Therefore the API does **not** cover WebkitUIMCP's current untrusted/programmatic actuation path in this beta measurement. The hash-only callback remains a probe for trusted/native submission paths, not a recovery guarantee.
