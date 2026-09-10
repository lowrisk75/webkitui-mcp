# Reach gaps — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the product able to finish ordinary tasks on ordinary sites. Today it refuses little and reaches less: a `confirm()` is answered "cancel" without telling anyone, a country dropdown cannot be set, a keyboard has three keys, and an invoice link opens nothing.

**Architecture:** Every gap here is closed with public API the product already has access to, in the files it already owns. Nothing here weakens the approval gate: each new operation is confirmed exactly as click and fill are, reports its own `trusted_gesture_state` honestly, and fails closed when it cannot be verified. Where the honest answer is an untrusted gesture, it is dispatched as one and labelled as one, which is what `fill` already does.

**Tech Stack:** Swift 6, Swift Package Manager, Swift Testing, WebKit / AppKit, macOS 15+ on Apple silicon.

**Spec:** `docs/research/2026-09-09-tool-surface-gap-matrix.md` is the evidence for every gap, with its ranking and its classification of what is refusable, what is blocked, and what is merely absent. `docs/2026-08-29-full-sota-product-plan.md` remains the parent product spec.

## How this plan is written, and why differently

The previous plan, `2026-09-09-sota-delta-after-safari-mcp.md`, specified exact code. Seventeen of those specifications were wrong against the real tree — one would have shipped a privacy regression, one built on an API the repository had already measured as never firing, and one published two features the same document listed as deferred. The implementers caught all seventeen by reading the code.

So this plan states **contracts, anchors and constraints**, and names the tests that must exist. It does not paste implementations. An implementer reads the surrounding code and writes what fits it. Where a decision is genuinely mine to make, it is stated as a decision with its reason, not as a snippet.

## Global Constraints

- `swift-tools-version: 6.0`; floor `.macOS(.v15)`; every build and test command passes `--arch arm64`.
- macOS 27 API only inside `if #available(macOS 27, *)`. The build and the suite must stay valid at the macOS 15 floor.
- `xcrun swift-format lint --strict --recursive Sources Tests Package.swift` must exit 0 before any commit.
- Swift Testing (`import Testing`) in `WebKitUIMCPCoreTests`, `WebKitUIMCPRuntimeTests`, `WebKitUIMCPServerTests`, `WebKitUIMCPLicensingTests`. XCTest only in `WebKitUIMCPConfirmPolicyTests`. A runtime suite touching `WebKitRuntime` needs `@MainActor`.
- Run serially: `swift test --arch arm64 --no-parallel --skip hostExclusiveSession`. Four Swift Testing bundles must each print one `Test run with` summary, plus the XCTest bundle. A bundle with no summary did not finish, whatever the exit status says.
- **Never call `performClick` in a test.** It runs a nested AppKit event loop; a `CFRunLoopStop` posted for it reaches the main run loop and Swift Testing's async entry calls `exit(0)`, so the bundle stops mid-run silently with status 0.
- Every new operation on `browser_act` must be confirmed through the same `rateLimitedConfirmation` funnel as the existing ones. There are eleven presenter call sites and one funnel; do not add a twelfth site.
- Any new application-authored phrase shown in the confirmation must be added to the `keys` array in `Sources/WebKitUIMCPConfirm/main.swift` and to both `Support/AquaApp/{en,fr}.lproj/Localizable.strings`, then verified with `--verify-localization en` and `--verify-localization fr` (the `.lproj` bundles must sit beside the binary; `scripts/package-preview.sh` shows how it stages them). A phrase carrying a number cannot be a whole-string key — use a labelled `Label:\nvalue` section, as `Confirmations asked for in the last minute:` does.
- Licence is BUSL-1.1. Never MIT. Nothing is pushed.
- Commit trailers, exactly:
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_019VwrQsCEcmT25v1DJUfJMw
  ```

## The decision this plan makes, once, for all of it

Several gaps can only be closed with a JavaScript-dispatched gesture, because WebKit gives an embedder no trusted route: hover has no forwarded `NSEventTypeMouseMoved`, and a `<select>` popup is an `NSMenu` running its own event loop that synthetic events do not reach.

**They are implemented as untrusted gestures, dispatched through JavaScript, reported as `trusted_gesture_state: untrusted`, and confirmed exactly like every other action.** This is not a new policy. `fill`, `blur` and `commit_input` are already JavaScript-dispatched and already reported untrusted; the product's promise has never been that every gesture is trusted, only that it says which are. A refusal here would not make the product safer — it would make it unable to tick a checkbox on a page that uses a custom control, while telling the operator nothing.

What must not happen: a new operation that reports `trusted` without a measured receipt, or that is dispatched without confirmation.

---

## Task 1: Answer a JavaScript dialog instead of silently cancelling it

`WebKitRuntime` declares `WKUIDelegate` conformance and implements none of the three panel methods. Measured on 2026-09-09: `confirm()` returns `false` and `prompt()` returns `null` on every page, silently, because WebKit treats an unimplemented panel as dismissed. A site that guards a delete or a save behind `confirm()` therefore always receives Cancel, the action never happens, and the failure surfaces as an unverified postcondition rather than as a dialog nobody answered.

The postcondition `dialog_appears` resolves an in-page modal, not a JavaScript dialog, so such a dialog cannot currently even be observed.

**Contract:**
- The runtime implements `runJavaScriptAlertPanel`, `runJavaScriptConfirmPanel` and `runJavaScriptTextInputPanel` (all public, `WKUIDelegate.h`).
- A pending dialog is **observable**: its kind (`alert`, `confirm`, `prompt`), its message and its default text appear in the observation, labelled untrusted site content like every other page string.
- A pending dialog **blocks acting on the page** — nothing else can be dispatched while one is open, and attempting it returns a specific outcome naming the dialog rather than a generic failure.
- `browser_act` gains operations to answer one: accept, dismiss, and for a prompt, accept with an exact value. Each is confirmed natively, showing the dialog's own message as untrusted site text and the exact value being supplied.
- Answering is single-use and bound to the specific pending dialog, exactly as a confirmed click is bound to a re-resolved target. A stale answer fails closed.
- No dialog is ever answered automatically. An unanswered dialog times out into an explicit indeterminate outcome; it must never hang the server, and it must never silently resolve as Cancel again.
- `beforeunload` is out of scope: no `BeforeUnload` symbol exists in the public macOS 27 SDK headers. Say so in the code comment.

**Files:** `Sources/WebKitUIMCPRuntime/WebKitRuntime.swift`, `Sources/WebKitUIMCPServer/MCPServer.swift`, `Sources/WebKitUIMCPConfirm/main.swift`, both `.lproj` catalogues, `Tests/WebKitUIMCPRuntimeTests/WebKitRuntimeTests.swift`, `Tests/WebKitUIMCPServerTests/MCPServerTests.swift`.

**Tests that must exist and must have been seen to fail first:**
- [ ] A page calling `confirm()` reports a pending confirm dialog in its observation, with the message as untrusted content.
- [ ] Acting on any other element while a dialog is pending fails with the dialog named.
- [ ] A confirmed accept makes `confirm()` return `true`, proven by the page's own recorded result.
- [ ] A confirmed dismiss makes it return `false`.
- [ ] A confirmed prompt accept supplies the exact value, and the page reads that exact string.
- [ ] A declined confirmation leaves the dialog pending and dispatches nothing.
- [ ] An unanswered dialog resolves indeterminate within its timeout and the runtime stays usable afterwards.

- [ ] **Commit.** One commit, message written by the implementer, both trailers.

---

## Task 2: A keyboard with more than three keys

`dispatchNativeKey` accepts `Enter`, `Tab` and `Escape` and throws `targetNotActionable` for everything else. The gap matrix ranks this second overall and cheapest to close: the ARIA combobox that replaced `<select>` on modern checkouts is driven by arrow keys, and a page that filters a list as you type needs printable characters.

**Contract:**
- Native `NSEvent` dispatch, with a measured trusted DOM receipt, for: the existing three, the four arrow keys, `Home`, `End`, `PageUp`, `PageDown`, `Delete`, `Backspace`, and single printable characters.
- Modifiers are supported as an explicit set (`command`, `shift`, `option`, `control`) rather than a chord string, so the confirmation can state them and nothing has to parse user text.
- The confirmation names the exact key and modifiers. A key press is not a free action: `command`+a printable character is a menu command on many pages.
- A key whose `keyCode` cannot be determined is refused before dispatch, not sent as an approximation.
- The trusted receipt requirement is unchanged: a missing or mismatched DOM receipt fails indeterminate, and no trust flag is synthesised.
- The existing `press_key` enum in the MCP schema is extended, not replaced; a client sending `Enter` must behave exactly as before.

**Files:** `Sources/WebKitUIMCPRuntime/WebKitRuntime.swift` (`dispatchNativeKey` and the operation enum), `Sources/WebKitUIMCPServer/MCPServer.swift` (schema, confirmation summary), the confirm helper and both catalogues if a new phrase appears, plus both test bundles.

**Tests that must exist and must have been seen to fail first:**
- [ ] `ArrowDown` on a listbox moves the active option, proven by the page's own state.
- [ ] A printable character reaches an input and its value contains it, with a measured trusted receipt.
- [ ] A modifier is reported in the confirmation text and reaches the page as a modified event.
- [ ] An unmappable key is refused before anything is dispatched.
- [ ] `Enter`, `Tab` and `Escape` still behave exactly as the existing tests assert.

- [ ] **Commit.**

---

## Task 3: Stop swallowing a new window

`grep -c createWebViewWith` returns 0. WebKit's default when the delegate does not implement it is to cancel the navigation and return nil, so `window.open()` and `target="_blank"` do nothing at all and report nothing at all. The gap matrix ranks this third: invoice, statement and report links on billing portals are overwhelmingly `target="_blank"`.

**Decision:** the product's refusal of multiple tabs stands. One session holds one exclusive host lease, and that is what lets an approval refer to an unambiguous page. This task does not add tabs. It stops the silence.

**Contract:**
- `createWebViewWithConfiguration:for:windowFeatures:` is implemented and returns nil — the refusal is unchanged — but the request is **recorded** with its target URL, sanitised to an origin and path with query values redacted exactly as `sanitizedHref` does.
- The action result that caused it reports a named outcome, `new_window_suppressed`, carrying that destination, so the agent learns what happened instead of seeing a click that did nothing.
- The observation reports whether a suppressed new-window request is outstanding.
- `browser_navigate` remains the way to follow it: the agent reads the destination and asks for it explicitly, which puts the navigation back under the normal exact-destination confirmation.
- Nothing is followed automatically. A suppressed window must never turn into a navigation without its own approval.

**Files:** `Sources/WebKitUIMCPRuntime/WebKitRuntime.swift`, `Sources/WebKitUIMCPServer/MCPServer.swift`, both test bundles.

**Tests that must exist and must have been seen to fail first:**
- [ ] A click on `target="_blank"` reports `new_window_suppressed` with the destination origin.
- [ ] The destination's query values are redacted in that report.
- [ ] No navigation happens without a separate approved `browser_navigate`.
- [ ] `window.open()` from page script is recorded the same way.

- [ ] **Commit.**

---

## Task 4: Set a `<select>`, and hover

Both are untrusted by necessity, per the decision above. A `<select>` popup is an `NSMenu` with its own event loop; hover has no forwarded mouse-moved event.

**Contract:**
- `browser_act` gains `select_option`, addressing the option by its exact visible label, not by index. An index is a structural fact and the resolver already refuses to let structure be identity.
- The confirmation states the control, the exact option label being chosen, and the label currently selected, so an operator sees the change rather than the intent.
- After dispatch the runtime verifies the freshly re-resolved control's `selectedOption` equals the requested label, and fails indeterminate otherwise. `change` and `input` events are dispatched as a real selection would.
- An option label that matches more than one option, or none, is refused before dispatch with the count reported.
- `browser_act` gains `hover`, dispatching `mouseover`, `mouseenter` and `mousemove` to the re-resolved target.
- Both report `trusted_gesture_state: untrusted` and `dispatch_mode: javascript`. Neither may ever report trusted.
- Hover has no postcondition of its own by default: what it reveals is discovered by the next observation. Where a caller supplies a postcondition, it is verified as for any other action.

**Files:** `Sources/WebKitUIMCPRuntime/WebKitRuntime.swift`, `Sources/WebKitUIMCPServer/MCPServer.swift`, the confirm helper and both catalogues, both test bundles.

**Tests that must exist and must have been seen to fail first:**
- [ ] Choosing an option by label changes the selection, and the page's `change` handler observed it.
- [ ] The result reports untrusted and JavaScript dispatch.
- [ ] An ambiguous option label is refused with its count, and the selection is unchanged.
- [ ] A hover reveals a menu that was absent from the previous observation and present in the next.
- [ ] The confirmation text names both the option being chosen and the one currently selected.

- [ ] **Commit.**

---

## Task 5: Viewport size, and getting back

Two small absences that stop recovery. The viewport is fixed at 1280×800 in two places and no tool changes it, so a breakpoint-hidden control is unreachable. There is no back, forward or reload, so a wrong turn cannot be undone — made worse because the observation redacts query values, so the agent may not hold the URL it would need to return to.

**Contract:**
- A tool sets the viewport in CSS pixels, bounded to sane limits, and the change is reported so an agent knows the page it observed next is a different layout.
- Device and mobile emulation are **not** implemented: no `ContentMode` symbol exists in the public macOS SDK. Say so where a reader would look for it.
- `set_emulated_media` is deliberately not implemented — it is a web-development convenience with no bearing on acting on someone else's site.
- Back, forward and reload are added to `browser_session` or `browser_navigate`, each confirmed natively with the exact destination it would reach, taken from `WKWebView.backForwardList` rather than from the page.
- Back and forward are refused when the entry they would reach is absent, rather than doing nothing.
- Reload on a page that resulted from a form submission is refused: re-submitting is exactly the replay this product exists to prevent. That refusal is explicit and named.
- Changing the viewport, or moving in history, invalidates the current observation like any other navigation.

**Files:** `Sources/WebKitUIMCPRuntime/WebKitRuntime.swift`, `Sources/WebKitUIMCPServer/MCPServer.swift`, the confirm helper and both catalogues, both test bundles.

**Tests that must exist and must have been seen to fail first:**
- [ ] A viewport change alters what a media query reports, and invalidates the prior observation.
- [ ] Going back reaches the previous entry and requires a confirmation naming it.
- [ ] Back with no previous entry is refused, not silently ignored.
- [ ] Reload after a form submission is refused with its reason named.

- [ ] **Commit.**

---

## Task 6: Refuse a permission out loud

Media capture and geolocation permission requests reach unimplemented public delegate methods, so they are denied by default and nothing says so. A page waiting on a camera permission looks, to the agent, like a page that is simply not working.

**Contract:**
- `requestMediaCapturePermissionFor:` and `requestGeolocationPermissionFor:` are implemented and **deny** — the refusal is the right answer for an agent-driven browser and does not change.
- Each denial is recorded with the origin that asked and what it asked for, and appears in the observation.
- Nothing here grants a permission. There is no tool to grant one, and adding one is out of scope for this plan.

**Files:** `Sources/WebKitUIMCPRuntime/WebKitRuntime.swift`, `Sources/WebKitUIMCPServer/MCPServer.swift`, both test bundles.

**Tests that must exist and must have been seen to fail first:**
- [ ] A page requesting geolocation is denied and the denial appears in the observation with its origin.
- [ ] A page requesting camera access is denied and recorded.
- [ ] No code path grants either.

- [ ] **Commit.**

---

## Task 7: Say how to get control back

Reported from a real session on 2026-09-10, and the report's own diagnosis was wrong
in a way that proves the defect. A user was sent to `idmsa.apple.com`, correctly
received `authentication_origin_requires_human_handoff`, logged in by hand, and the
native window said "Ready — Waiting for Agent". Every subsequent call then returned the
bare string `humanControlActive`, forever, and the agent concluded the login was
unrecoverable and would have to be redone.

**The way back exists.** `browser_session { operation: "handoff" }` called a second time
from `human_step_completed` reaches `requestAgentResume()` — the same operation both
hands control over and takes it back. What does not exist is any way for a caller to
learn that. The three token-based operations (`handoff_start`, `handoff_status`,
`handoff_resume`) all demand a `resume_token` that this path never issues, so an agent
reading the schema concludes, reasonably, that there is no route home.

`humanControlActive` is thrown as a bare runtime enum case and never mapped to a
structured error. Fourteen other errors in this server carry a `remediation`. This one
governs a state a human has to be talked out of, and it carries nothing.

**Contract:**
- `humanControlActive` reaches the client as a structured error naming the current
  control state and the exact operation that reclaims control, including the session id
  to pass. It says whether a confirmation will be shown.
- The message distinguishes the two states behind that one error: a human is still
  working (`human_controlled`), versus a human has finished and the agent has simply not
  asked for control back (`human_step_completed`). Only the second is the caller's move,
  and the caller must be told which it is facing.
- `browser_session operation=status` says the same thing in the same words, since that is
  where an agent looks next. `handoff_active: false` while control is human-held is
  itself misleading and must be reconciled or explained.
- The tool description for `handoff` says it both hands over and reclaims. Today it reads
  as one-way.
- Nothing here resumes automatically. The human's completed step is still returned only
  when the agent asks and the confirmation is accepted, exactly as now.

**Files:** `Sources/WebKitUIMCPServer/MCPServer.swift`, its tool descriptions, and
`Tests/WebKitUIMCPServerTests/MCPServerTests.swift`.

**Tests that must exist and must have been seen to fail first:**
- [ ] Acting while a human is in control returns a structured error naming
  `operation: "handoff"` and the session id, not a bare string.
- [ ] The error distinguishes `human_controlled` from `human_step_completed`.
- [ ] The remediation the error names actually works: following it from
  `human_step_completed` returns control and a fresh observation.
- [ ] `status` and the error agree about what the caller should do.

- [ ] **Commit.**

---

## Task 8: Let an agent see the options it is allowed to choose

`select_option` shipped in Task 4 and addresses an option by its exact visible label,
deliberately, because an index is structure and this product refuses to let structure be
identity. But the observation publishes only `selectedOption`. An agent therefore has to
guess the available labels from surrounding page text, and a guess that misses is refused
— correctly, and uselessly.

Reported by the implementer of Task 4 against their own work.

**Contract:**
- A `<select>` in the observation carries its selectable option labels, as untrusted site
  content like every other page string.
- The list is bounded, and says when it was truncated. A country list is 250 entries; a
  list of every timezone is more, and neither may spend a client's whole context.
- A disabled option is marked, not omitted: an agent that cannot see it will keep asking
  for it.
- A sensitive `<select>` publishes no options, matching the rule `fill` and
  `select_option` already apply.
- Options are not published for a control the observation is not otherwise reporting.

**Files:** `Sources/WebKitUIMCPRuntime/WebKitRuntime.swift` (the observation source and
`WebKitObservedElement`), `Sources/WebKitUIMCPServer/MCPServer.swift` if the payload needs
it, both test bundles.

**Tests that must exist and must have been seen to fail first:**
- [ ] A three-option select reports all three labels, and the selected one is still
  identifiable.
- [ ] A list longer than the bound is truncated and says so.
- [ ] A disabled option is present and marked disabled.
- [ ] A sensitive select publishes no options at all.
- [ ] An option label chosen from what the observation published is accepted by
  `select_option` — the two halves agree.

- [ ] **Commit.**

---

## Not in this plan

**Cross-origin iframe content — the largest gap, and it needs its own plan.** The gap matrix ranks it first: hosted payment fields, CAPTCHAs and embedded SSO widgets are counted and never read, which removes a checkout — the flagship task — from what the product can do.

It is **not blocked**. The instrumentation script is already injected into every frame (`forMainFrameOnly: false`, `WebKitRuntime.swift:500`), so the code already runs inside those documents. What is missing is the plumbing: capture `WKFrameInfo` from each frame's own script message, then address that frame with `callAsyncJavaScript(in:)` instead of always the main frame.

It gets its own plan because it is an architecture change, not a feature. Element identity, observation generations, the `framePath` locator clause, the origin lock, provenance labelling and the network boundary all currently assume one document. A rushed version would produce addresses that silently mean the wrong element in the wrong origin, which is worse than the honest blindness the product has now.

Also deferred, from the previous plan and unchanged: main-frame HTTP status on the navigation result; the console and uncaught-error journal; contacted and refused hosts on the proxy metrics. The gap matrix argues the network-observation work outranks everything in this plan if the goal is the strongest product rather than the most tasks completed, because `browser_transaction reconcile` currently reconciles an indeterminate write against another observation of the interface — while the product correctly says the interface never proves a server commit.

And unchanged from the parent spec: the provider proof matrix, physical-Mac authentication tests, adversarial benchmarking, commercial and legal truth, and an independent review of the gesture and credential boundary.
