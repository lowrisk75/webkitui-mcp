# Native actuation

## Safety boundary

`browser_act` supports `click`, `submit`, bounded `fill`, Enter/Tab/Escape, blur, and input commit. `approval_mode=native` routes click/submit/key actions through public AppKit `NSEvent` handling after exact local confirmation. `approval_mode=mcp`, fill, blur, and commit remain untrusted JavaScript gestures. Fill accepts only non-password input/textarea controls, rejects input newlines, labels its bytes `MODEL_GENERATED`, and verifies the exact value through a semantic identity stable across observation leases.

The model supplies an observation ID, ephemeral element ID, idempotency key, and exact expected URL. None grants authority.

## Multi-round authorization

1. The server verifies the session, latest observation, target, operation, and post-condition shape.
2. It stores an opaque random `requestState` bound to the exact arguments and a 60-second expiry.
3. It returns MCP `input_required` with one `elicitation/create` confirmation.
4. The confirmation message labels the page-derived target label as untrusted data.
5. A retry must carry the unchanged arguments, exact state, and an accepted `confirm: true` response.
6. The state is removed before dispatch, including on decline. Replays fail.
7. Only then does the private authority issue a 15-second, origin- and action-scoped capability, revoked after the attempt.

Legacy MCP clients use a server-owned native exact-action confirmation; they cannot forge approval through tool arguments.

Confirmation and dispatch are separate receipt fields. Native dispatch arms a
random-token listener in the isolated instrumentation world, re-resolves and
stabilizes the target, delivers the AppKit event directly to `WKWebView`, and
accepts trust only when the matching physical identity and DOM event type report
`event.isTrusted == true`. A missing receipt is an unknown dispatch outcome and
is never replayed automatically.

## Dispatch and verification

The locator recipe is resolved fresh, checked for uniqueness/actionability, stabilized with host monotonic time, then resolved again. The transaction ledger records preparation before dispatch and verifies an exact URL, new semantic text, target control state/value, bounded state attribute, dialog name, or visible selected-option label afterward. Target state uses the freshly re-observed unique semantic identity rather than an expired element ID. It returns `verified` or `indeterminate`; it never infers success from the dispatch receipt alone.

`browser_transaction` reads a receipt or re-observes an indeterminate transaction. Reconciliation may prove a late post-condition but never dispatches or retries.
If it remains indeterminate, the result now states `real_world_state_unknown`
and directs the caller to independent provider/backend evidence before retrying.

## Deliberate limits

- No arbitrary JavaScript execution.
- No coordinate retry.
- Fill dispatches `input` and `change`; arbitrary site handlers may autosave or submit. Human confirmation authorizes that risk, but the runtime cannot prove absence of a server-side effect.
- Submit is limited to native form submit controls. Custom JavaScript buttons remain ordinary clicks.
- Synthetic keyboard events and OAuth controls requiring trusted physical user activation are not misrepresented as native trust; use human handoff when the site rejects them.
- No exactly-once or rollback claim for uncooperative web servers.

## Local human handoff

`browser_session(operation: "handoff_start")` transfers the persistent `WKWebView` into a visible local window and immediately returns a random session-bound token. `handoff_status` polls without blocking or changing control. `handoff_resume` still requires local native confirmation, consumes the token before requesting agent control, invalidates old addresses, and returns a fresh observation. The older multi-round `handoff` remains for compatibility. While control is human, navigation, observation, capture, locator resolution, transaction reconciliation, and actuation from the agent fail closed.

The user performs login, MFA, CAPTCHA, or sensitive entry directly in WebKit. A decline leaves human control active. An accepted, exact-state-bound response hides the window, invalidates all prior element symbols, and returns a new full observation. If WebKit's content process terminated during handoff, the runtime reloads the host-owned last HTTP(S) URL from the persistent data store before re-observing. A test-only WebKit process-kill selector now exercises the real public termination callback, verifies that no action is replayed, and preserves an authenticated `HttpOnly` cookie, `localStorage`, and `sessionStorage` across 10/10 local fixture runs in the same view/data-store lifetime. JavaScript heap state, GPU/network-process failure, host-process restart, richer storage, and in-flight server writes remain separate unmeasured cases.

Restricted authentication origins cannot be returned to agent control. Resume
fails closed while the live URL remains restricted; the window stays human
controlled. Status and error results expose only the canonical origin and a
bounded classification such as `auth_ui_not_ready`.

The local audit contains only state transitions, document/observation identifiers, and monotonic timestamps. It never serializes page text or input values.
