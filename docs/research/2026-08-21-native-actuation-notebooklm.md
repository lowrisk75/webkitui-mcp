# Native actuation research — 2026-08-21

## Scope

Native WebKit actuation, stale-address recovery, transactional verification, and MCP human authorization.

## NotebookLM queries

- Main private notebook: requested published measurements, implementation blind spots, and missed opportunities. One long blind-spot query was privacy-blocked; a short English reformulation succeeded.
- Private opportunity notebook: requested unbuilt, measurable opportunities. Its answer supplied no citations, so it is retained only as conjectural brainstorming.

## Source-verified

- Playwright re-resolves a locator before every action and checks uniqueness, visibility, stability, event reception, enabled state, and editability where applicable. Sources: [locators](https://playwright.dev/docs/locators), [actionability](https://playwright.dev/docs/actionability).
- Web-exposed user activation is tied to trusted input events; a JavaScript-generated event is not equivalent to physical user activation. Source: [WebKit User Activation API](https://webkit.org/blog/13862/the-user-activation-api/).
- MCP 2026-07-28 multi-round tool results represent missing human input with `resultType: input_required`, `inputRequests`, opaque `requestState`, and keyed `inputResponses`. Source: [official schema](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/schema/2026-07-28/schema.ts).
- The installed macOS 27 SDK compiles `WKDOMNodeSnapshot`; the Safari 27 release notes use the name `WKSerializedNode`. The installed SDK is the implementation authority for this machine; the naming disagreement remains documented, not normalized away.

## Locally measured

- Runtime action suite: 12 tests passed in 1.354 s before this slice, including click, fill, ambiguity abort, and stale-observation rejection.
- Transaction coordinator: 2 tests passed in 0.681 s; a click is not reported verified until its post-condition is observed, and an already-satisfied post-condition is rejected.
- A locally dispatched click and fill both reported `event.isTrusted == false`.
- Two indistinguishable `Save` buttons abort before dispatch and incremented `address_now_ambiguous` exactly once in the fixture.
- MCP server suite after MRTR integration: 6 tests passed in 0.589 s, including decline and replay rejection for a single-use confirmation state.
- A representative `input_required` tool response validated as `CallToolResultResponse` against the downloaded official 2026-07-28 JSON Schema with Ajv 8.20.0. Ajv ignored only undeclared format implementations such as `uri` and `byte`.

## Conjectural / not yet measured

- Public benchmarks still do not isolate stale-reference failures into the five addressing counters implemented here.
- No published controlled measurement found for `WKJSHandle` improving action reliability or latency.
- A compiler from model intent to explicit preconditions/post-conditions may improve write reliability, but no causal ablation was found.
- Semantic post-conditions bound to locator recipes could safely cover same-page toggles. The current MCP write surface deliberately supports only exact page-URL post-conditions until that design is measured.
- The second notebook suggested hybrid visual/semantic recovery and transaction compilation, but provided no primary evidence.

## Resulting constraints

- Re-resolve twice around a host-monotonic stability interval; never use two `requestAnimationFrame` callbacks.
- Abort ambiguity, replacement, stale observation, geometry drift, or failed hit testing before dispatch.
- Describe WebKit actions as untrusted JavaScript gestures, never native physical input.
- A model cannot mint a capability. Modern MCP clients must complete a bound human elicitation; legacy clients fail closed.
- Confirmation state is private, opaque, 60-second, exact-argument-bound, and consumed before execution.
- Every click has an idempotency key and an exact post-condition. Unknown dispatch is indeterminate and never automatically replayed.
