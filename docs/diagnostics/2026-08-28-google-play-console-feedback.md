# Google Play Console actuation feedback — 2026-08-28

## Scope and external boundary

The report came from persistent native profile `default`, Google Play developer
`6316651857418272089`, app `4973846706155879193`. This remediation made no
Google Play request and did not replay any mutation. The reported external state
remains evidence supplied by the operator, not fresh provider verification.

## Confirmed causes

- Native confirmation and browser dispatch were conflated. Click dispatch still
  used `HTMLElement.click()`, so its DOM event correctly reported
  `trustedUserGesture: false`.
- Click verification supported only exact URL and newly appearing exact semantic
  text. It could not prove control state such as `checked` or `aria-checked`.
- There was no bounded keyboard/blur operation.
- Element scrolling described only the root document after `scrollIntoView`, not
  the nearest scrollable dialog or list ancestor.
- Observation accepted only a numerical limit, so callers could not reduce the
  payload before serialization by role or accessible name.
- Session status omitted the handoff control state.

## Local remediation in this checkout

- Observations now expose `checked`, `selected`, the visible selected option, and
  a small allowlist of UI-state attributes (`aria-checked`, `aria-selected`,
  `aria-disabled`, `aria-expanded`, `data-state`, and `open`). Sensitive or
  arbitrary attributes are not added.
- CSS-hidden checkbox/radio inputs remain semantically addressed by their native
  identity and state, while observation geometry, hit testing, and scrolling use
  the associated rendered label. This avoids targeting a zero-area Material input.
- Transactional click postconditions now include `checked_equals`,
  `selected_equals`, `enabled_equals`, `value_equals`, `attribute_equals`,
  `dialog_appears`, and `option_selected`. They retain the existing
  pre-dispatch-already-satisfied rejection and idempotency ledger.
- `semantic_text_contains` tolerates explanatory prefixes/suffixes while retaining
  digest-only transaction storage: a rolling hash selects byte windows and SHA-256
  confirms the exact expected substring.
- `press_key` accepts only Enter, Tab, or Escape. `blur` and `commit_input` are
  explicit operations. Under native approval, click/submit/key dispatch uses
  AppKit; MCP approval, fill, blur, and commit remain labeled untrusted JavaScript.
- Element scrolling now returns the dimensions and position of the nearest
  scrollable ancestor after centering the target.
- `browser_observe` accepts bounded server-side `roles` and `name_contains`
  filters. Other hidden elements remain excluded before serialization.
- `browser_session(operation="status")` now includes `control_state`.
- `handoff_start` returns immediately with an opaque session-bound resume token;
  `handoff_status` polls; `handoff_resume` retains local confirmation and consumes
  the token before returning a fresh observation.

## Trusted native actuation result

The implementation uses the public AppKit event constructors documented by
[Apple](https://developer.apple.com/documentation/appkit/nsevent/mouseevent%28with%3Alocation%3Amodifierflags%3Atimestamp%3Awindownumber%3Acontext%3Aeventnumber%3Aclickcount%3Apressure%3A%29).
It routes the event directly through `WKWebView` after the second stable semantic
resolution. Before dispatch, an isolated-world listener is armed with a random
token and expected physical identity. The receipt reports `trusted` only when the
matching DOM click, keydown, or Tab-induced blur reports `event.isTrusted == true`.

This follows WebKit's documented constraint that activation-triggering events are
limited to trusted input events ([WebKit User Activation API](https://webkit.org/blog/13862/the-user-activation-api/)).
It deliberately does not use WebKit's 2026 AutoFill-only trusted-bindings path:
that upstream change explicitly leaves the engine-level event untrusted
([WebKit commit 310673](https://commits.webkit.org/310673@main)).

Local fixtures that reject untrusted click and Enter events now pass. Confirmation
mode, dispatch mode, and measured trust are separate receipt fields. A missing or
mismatched native receipt fails without replay.

## Remaining external gates

- The changed source is not installed and the active Aqua broker was not restarted.
- Google Play Console has not been exercised against this build.
- A real Play control known to reject `HTMLElement.click()` must prove the installed
  AppKit path and provider-side postcondition before the issue is closed externally.

## Validation boundary

`swift test` completed successfully on 2026-08-28: 142 tests passed across the
server, runtime, transaction, authority, provenance, addressing, proxy, and
credential-boundary suites. Local compile and synthetic WebKit tests cover state
serialization, trusted AppKit click/key/blur receipts, confirmation/dispatch
separation, non-blocking tokenized handoff, nested scroll reporting, observation
filters, checked-state transaction verification, and anti-replay. They do not
prove installed-binary, Google Play, or provider-side behavior.
