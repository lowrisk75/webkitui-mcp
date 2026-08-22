# Native actuation

## Safety boundary

`browser_act` supports `click`, `submit`, and bounded `fill`. Click and submit are intentionally described as **untrusted JavaScript gestures**. They cannot satisfy browser features that require trusted physical user activation. Fill accepts only non-password input/textarea controls, rejects input newlines, labels its bytes `MODEL_GENERATED`, and verifies the exact value through a semantic identity stable across observation leases.

The model supplies an observation ID, ephemeral element ID, idempotency key, and exact expected URL. None grants authority.

## Multi-round authorization

1. The server verifies the session, latest observation, target, operation, and post-condition shape.
2. It stores an opaque random `requestState` bound to the exact arguments and a 60-second expiry.
3. It returns MCP `input_required` with one `elicitation/create` confirmation.
4. The confirmation message labels the page-derived target label as untrusted data.
5. A retry must carry the unchanged arguments, exact state, and an accepted `confirm: true` response.
6. The state is removed before dispatch, including on decline. Replays fail.
7. Only then does the private authority issue a 15-second, origin- and action-scoped capability, revoked after the attempt.

Legacy MCP clients cannot actuate because they cannot complete the 2026-07-28 multi-round contract.

## Dispatch and verification

The locator recipe is resolved fresh, checked for uniqueness/actionability, stabilized with host monotonic time, then resolved again. The transaction ledger records preparation before dispatch and verifies the exact page URL afterward. It returns `verified` or `indeterminate`; it never infers success from the UI appearance alone.

`browser_transaction` reads a receipt or re-observes an indeterminate transaction. Reconciliation may prove a late post-condition but never dispatches or retries.

## Deliberate limits

- No arbitrary JavaScript execution.
- No coordinate retry.
- Fill dispatches `input` and `change`; arbitrary site handlers may autosave or submit. Human confirmation authorizes that risk, but the runtime cannot prove absence of a server-side effect.
- Submit is limited to native form submit controls. Custom JavaScript buttons remain ordinary clicks.
- No same-page target-field post-condition yet; ephemeral element IDs are not stable semantic keys.
- No exactly-once or rollback claim for uncooperative web servers.

## Local human handoff

`browser_session(operation: "handoff")` transfers the actual persistent `WKWebView` into a visible local window and returns MCP `input_required`. While control is human, navigation, observation, capture, locator resolution, transaction reconciliation, and actuation from the agent fail closed.

The user performs login, MFA, CAPTCHA, or sensitive entry directly in WebKit. A decline leaves human control active. An accepted, exact-state-bound response hides the window, invalidates all prior element symbols, and returns a new full observation. If WebKit's content process terminated during handoff, the runtime reloads the host-owned last HTTP(S) URL from the persistent data store before re-observing. A test-only WebKit process-kill selector now exercises the real public termination callback, verifies that no action is replayed, and preserves an authenticated `HttpOnly` cookie, `localStorage`, and `sessionStorage` across 10/10 local fixture runs in the same view/data-store lifetime. JavaScript heap state, GPU/network-process failure, host-process restart, richer storage, and in-flight server writes remain separate unmeasured cases.

The local audit contains only state transitions, document/observation identifiers, and monotonic timestamps. It never serializes page text or input values.
