# Goal Delegation and reliable browser addressing — SOTA decision packet

Date: 2026-09-01
Project: WebKitUI MCP
Status: research and architecture decision; not implementation or release proof

## Executive decision

Proceed, but split the work into two safety layers:

1. First remove avoidable friction without changing authority: contextual
   element identities, locator-quality diagnostics, compact observations,
   bounded inspection, and an explicit human-completion handoff state.
2. Introduce Goal Delegation only as a structured, runtime-enforced grant. A
   natural-language goal is context, never authority. Start in shadow mode,
   then permit only explicitly bounded navigation classes. Consequential
   actions, secret/token management, permissions, payments, communication,
   deletion, upload, publication, and unknown cases remain exact-confirmation
   gates.

Verdict: **GO WITH CAVEATS** for an implementation prototype. **NO-GO** for a
generic “accept everything for this goal” mode or coordinate-click fallback.

Confidence: high for the architecture and MVP ordering; medium for the exact
utility/security trade-off until measured on hostile and real provider pages.

## Requested outcomes

- Stop repetitive native navigation prompts when a user has deliberately
  delegated a narrow browsing goal.
- Disambiguate unnamed or repeated links and controls before actuation.
- Offer a non-sensitive inspection path without arbitrary JavaScript.
- Keep geometric recovery bounded and non-authoritative.
- Reduce observation token volume.
- Distinguish “handoff is active” from “the human has finished”.

Out of scope for this packet: source changes, provider account mutations,
signing, packaging, release, publication, or a claim that prompt injection is
solved.

## Current project baseline

### VERIFIED — locator primitives exist but are underused

`LocatorFact` already defines `contextAnchor` and `stableAttribute`, and the
resolver already rejects ambiguity instead of selecting from corroborating
facts (`Sources/WebKitUIMCPCore/LocatorRecipe.swift:4-20,74-124,141-234`). The
runtime currently builds recipes from role, accessible name, label, and a tag
fallback; visible text is only corroborating
(`Sources/WebKitUIMCPRuntime/WebKitRuntime.swift:1814-1871`). Context anchors
and stable attributes other than tag are therefore modeled but not populated.

### VERIFIED — observations omit the attributes needed by the feedback

`WebKitObservedElement` includes semantics, state, bounding box, and recipe,
but no sanitized `href`, `id`, `name`, `title`, test identifier, context chain,
or locator-quality result (`Sources/WebKitUIMCPRuntime/WebKitRuntime.swift:93-127`).
The instrumentation reads `name` and `id` only for sensitivity classification
and does not serialize them (`Sources/WebKitUIMCPRuntime/WebKitRuntime.swift:2050-2133`).

### VERIFIED — oversized results are duplicated by design today

Every structured tool result is JSON-serialized into `content[].text` and also
returned as `structuredContent` (`Sources/WebKitUIMCPServer/MCPServer.swift:2020-2027`).
The MCP 2025-06-18 specification says servers returning structured content
*should* also return serialized JSON for backward compatibility; this is not a
protocol *must*. A negotiated modern compact response is therefore possible,
but legacy behavior must be preserved or versioned.

### VERIFIED — handoff readiness does not mean human completion

`ready_for_resume_request` currently means only that the token is active and
the runtime remains `human_controlled`
(`Sources/WebKitUIMCPServer/MCPServer.swift:1301-1329`). Resume then triggers a
second native confirmation (`Sources/WebKitUIMCPServer/MCPServer.swift:1332-1393`).
There is no `human_step_completed` state or native completion button.

### VERIFIED — no goal-scoped grant exists

The current private capability is short-lived and exact-action-bound. Source
and documentation expose no goal grant, approval budget, or automatic approval
policy. Existing exact confirmation and transaction controls must remain the
downstream authority boundary.

## Current primary evidence

| Label | Evidence | Project consequence | Limitation |
| --- | --- | --- | --- |
| VERIFIED | W3C accessible-name guidance gives `aria-labelledby` highest precedence, supports associated `label`, and names `fieldset` through `legend`. It also warns that `aria-labelledby` references do not chain. | Reuse the standards-computed accessible name. Treat surrounding headings, legends, regions, and siblings as separately typed context, not invented accessible names. | Author markup can still be wrong, duplicated, hidden, or adversarial. |
| VERIFIED | Playwright re-resolves locators for every action, recommends user-facing semantics and explicit contracts, and treats multi-match actuation as a strictness error. | Preserve fresh re-resolution and ambiguity failure. Add context and stable facts before considering geometry. | Playwright is test automation, not a security authority. |
| VERIFIED | Playwright defines geometric stability as the same bounding box over at least two consecutive animation frames. | A geometric recovery experiment needs at least two samples; the current hard-coded `geometryStable: true` is insufficient proof. | Two frames do not prove semantic identity or defeat hostile overlays. |
| VERIFIED | WebDriver BiDi provides bounded node location (`maxNodeCount`, contextual start nodes), accessibility locators, and node attributes/rects. | A bounded non-sensitive inspect tool is consistent with current browser-control protocol design. | BiDi exposes general primitives; WebKitUI must retain a smaller security surface. |
| VERIFIED | MCP permits `structuredContent`; duplicating it in text is backward-compatibility guidance, not a mandatory representation for every negotiated client. | Add a modern compact result profile while keeping a legacy-compatible lane. | Client behavior must be measured before removing duplicate JSON. |
| VERIFIED | RFC 9396 standardizes structured fine-grained authorization details rather than relying on a single coarse scope string. | Model Goal Delegation as structured details with typed constraints, expiry, and audience, not a prose permission. | OAuth RAR is an analogy, not a browser-agent authorization standard. |
| VERIFIED | CaMeL separates trusted control flow from untrusted data and enforces capabilities outside the model. | Page text and the model cannot broaden a goal grant. Runtime policy alone decides. | CaMeL does not directly validate WebKitUI’s policy language or UI. |
| VERIFIED | Current computer-use safety guidance retains confirmations for consequential state-changing actions and watch mode on sensitive sites. | Delegation must preserve hard gates and active supervision classes. | Vendor system cards report their own systems, not independent WebKitUI results. |

Primary references:

- [W3C: Providing Accessible Names and Descriptions](https://www.w3.org/WAI/ARIA/apg/practices/names-and-descriptions/)
- [W3C: Understanding Label in Name](https://www.w3.org/WAI/WCAG22/Understanding/label-in-name.html)
- [Playwright: Locators](https://playwright.dev/docs/locators)
- [Playwright: Actionability](https://playwright.dev/docs/actionability)
- [Playwright: ARIA snapshots](https://playwright.dev/docs/aria-snapshots)
- [W3C: WebDriver BiDi](https://www.w3.org/TR/webdriver-bidi/)
- [Model Context Protocol: Tools](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)
- [RFC 9396: OAuth 2.0 Rich Authorization Requests](https://www.rfc-editor.org/rfc/rfc9396.html)
- [CaMeL: Defeating Prompt Injections by Design](https://arxiv.org/abs/2503.18813)
- [OpenAI: ChatGPT agent user confirmations and watch mode](https://deploymentsafety.openai.com/chatgpt-agent/user-confirmations)

## Capability and constraint matrix

| Area | Decision | Priority | Security rule |
| --- | --- | --- | --- |
| Context anchors | Adopt typed anchors: standards-computed label/name, nearest labelled region/section, fieldset legend, nearest preceding heading in the same structural container, and bounded previous-sibling visible text. | P0 | Preserve source kind and page provenance. Never present inferred context as the accessible name. |
| `aria-labelledby` | Keep standards-compliant direct computation; do not recursively follow an indirect chain that the standard ignores. | P0 | Bound referenced nodes and text; sensitive-content filter still applies. |
| Stable attributes | Add sanitized `href`, `id`, `name`, `title`, `data-testid`, and a configurable explicit attribute allowlist. | P0 | Every value passes sensitivity/opacity checks. Raw classes are excluded by default. |
| `href` | Expose canonical scheme/host/path. Strip user info and fragment. Redact query values by default; allow exact query keys or values only through a reviewed allowlist. | P0 | URL data can carry secrets and exfiltration payloads; destination evidence is not authority. |
| Locator quality | Emit `unique`, `ambiguous`, or `insufficient`, candidate count, contributing facts, and safe next step during observation. | P0 | A recipe made only of a low-cardinality role/tag is insufficient even if it happens to be unique in one sample. |
| Compact observation | Add field selection and `compact` mode with document-level provenance plus concise rows. | P0 | Never compact away `sensitive`, freshness, truncation, document/origin, or locator-quality signals. |
| Human completion | Add a native “Done — Return Control” action and explicit `human_step_completed`. | P0 | Local completion is the user-presence event; token consumption and fresh re-observation still occur atomically. |
| Inspect element | Add bounded `browser_inspect_element` for one fresh observation/element pair. | P1 | Read-only, no arbitrary selectors or JavaScript, bounded DOM ancestry, sanitized values, auth-origin restriction retained. |
| Geometric recovery | Prototype only as a corroborating resolver after semantic failure. | P1 experiment | Same document/origin, unchanged viewport and scroll, bounded mutation delta, two-sample stable box, same physical identity, unique overlap, topmost hit-test, exact native crop confirmation, mandatory postcondition. |
| `browser_act_at_point` | Reject for the MVP. | Deferred | It creates a new general actuation surface and weakens semantic review. Reconsider only if bounded recovery cannot meet measured provider coverage. |
| Goal Delegation | Structured, session-bound grant with shadow mode first. | P1 | Natural language is never authority; runtime policy cannot be expanded by page content or agent arguments. |

## Proposed observation contract

Example compact row:

```json
{
  "elementID": "e17",
  "role": "link",
  "name": null,
  "contextAnchor": {
    "kind": "nearest_heading",
    "text": "API Tokens"
  },
  "stableAttributes": {
    "href": "https://icloud.developer.apple.com/.../tokens"
  },
  "bbox": [72, 411, 184, 28],
  "state": { "disabled": false },
  "locatorQuality": {
    "status": "unique",
    "candidateCount": 1,
    "facts": ["role", "context_anchor", "href"]
  }
}
```

For a weak recipe:

```json
{
  "locatorQuality": {
    "status": "insufficient",
    "candidateCount": 18,
    "facts": ["role"],
    "recommendedAction": "contextual_reobserve_or_handoff"
  }
}
```

`candidateCount` should be computed from canonical required fact signatures in
one bounded pass over the observed candidate set, then confirmed by the normal
fresh resolver before action. It is diagnostic evidence, not a click grant.

## Proposed bounded inspect contract

`browser_inspect_element(session_id, observation_id, element_id, fields?)`
returns only:

- tag and semantic role;
- sanitized `href`;
- filtered `id`, `name`, `title`, directly resolved ARIA attributes, and
  allowlisted test attributes;
- typed context anchors;
- a bounded ancestry description or non-actionable DOM path;
- locator quality and candidate count;
- document, observation, generation, mutation count, and truncation status.

It must reject stale observations, restricted authentication origins, unknown
fields, oversized ancestry, opaque/token-like values, and any request for raw
HTML, arbitrary selectors, script evaluation, cookies, storage, or form values.

## Goal Delegation policy

### Grant shape

```json
{
  "version": 1,
  "goalDisplay": "Inspect CloudKit token configuration",
  "sessionID": "opaque-session",
  "audience": "webkitui-native-authority",
  "origins": ["https://icloud.developer.apple.com"],
  "navigation": {
    "pathPrefixes": ["/dashboard/database/teams/TDV6D5L785/containers/iCloud.com.lorislabapp.lumenbridge/"],
    "allowedQueryKeys": [],
    "maximumCount": 30
  },
  "actions": ["observe", "inspect", "scroll", "navigate"],
  "expiresInSeconds": 900,
  "hardStops": [
    "cross_origin", "authentication", "secret_or_token", "permission",
    "payment", "upload", "download", "message_send", "delete",
    "publish", "unknown_consequence"
  ]
}
```

`goalDisplay` is explanatory only. The remaining typed fields form the grant.
The native UI must show them before issuance. The grant is local, opaque,
non-exportable, session-bound, monotonic-expiry-bound, count-bounded, revocable,
and invalidated by handoff, reconnect, profile change, authentication origin,
unexpected redirect, or policy mismatch.

### Why the screenshot remains a hard stop

A navigation containing `newApiKey=true` is semantically adjacent to creation
of a credential even if it uses GET. HTTP method and URL shape cannot prove the
absence of server-side effects. `token`, `key`, `secret`, `credential`, and
similar sensitive classes therefore remain exact-confirmation or human-handoff
gates in the initial policy. No auto-approval decision should be based only on
the agent calling the operation “read-only”.

### Shadow-mode gate

Before automatic acceptance, run the policy engine in shadow mode across local
fixtures and opted-in provider sessions. Record only redacted decisions:

- would-allow / would-stop;
- matched rule identifiers;
- origin class and action class;
- false allow and false stop after human review;
- prompt count avoided;
- task completion and handoff rate.

No page text, URL query value, credential, DOM body, or screenshot is retained
by this telemetry.

## Handoff state machine

```text
agent_controlled
  -> human_controlled
  -> human_step_completed     (native Done button)
  -> resume_requested         (token consumed atomically)
  -> freshly_reobserved
```

`handoff_status` should expose `human_step_completed`, completion monotonic
time, and token state. Before completion, `handoff_resume` should return
immediately with `resumed=false` and no confirmation loop. The native Done
button itself is the explicit local consent to return control; resume still
fails closed if the origin is authentication-restricted or the token/session
does not match. Cancellation keeps human control.

## Threat implications

| Threat | New risk | Required control |
| --- | --- | --- |
| Prompt injection | Page text tries to broaden the goal or classify a mutation as reading. | Policy is compiled only from native user-approved typed fields. Page/model strings cannot mint or edit grants. |
| Confused deputy | A grant for one container is reused in another session/container. | Bind session, profile, origin, path scope, action, expiry, counter, and authority audience; evaluate immediately before each action. |
| URL exfiltration | Sensitive data is inserted in path/query during delegated navigation. | Provenance-aware URL policy, empty query allowlist by default, opaque/token detection, and cross-origin stop. |
| Locator substitution | Weak context or mutable nearby text points to another control. | Source-typed anchors, uniqueness count, fresh re-resolution, logical-target checks, exact confirmation for consequential actions. |
| Overlay/race | Geometry lands on a different visual layer. | Geometry is corroborating only; two samples, hit-test, same document/origin/viewport, unique overlap, native crop, postcondition. |
| Privacy leakage | Attributes or DOM inspection expose tokens/PII. | Field allowlist, bounded strings/ancestry, opacity and sensitive-name filters, query redaction, auth-origin block. |
| Approval fatigue | Excessive prompts train the user to approve blindly. | Auto-handle only within a visible bounded grant; summarize auto-decisions and stop once at a real boundary. |

## Smallest defensible implementation plan

### Slice A — friction reduction without delegated authority (P0)

1. Add typed context and filtered stable attributes to raw/runtime elements.
2. Build deterministic context-aware recipes and locator-quality diagnostics.
3. Add compact observation fields/mode with a compatibility test matrix.
4. Add `human_step_completed` and the native Done button.
5. Add adversarial fixtures for duplicate unnamed links, virtualized rows,
   malicious attributes, token-bearing URLs, hidden labels, and mutation races.

Acceptance: ambiguity is surfaced at observation time; the two example links
resolve uniquely without coordinates; no new sensitive value crosses MCP;
compact output is materially smaller; handoff completion is unambiguous.

### Slice B — inspection and geometric experiment (P1)

1. Add bounded `browser_inspect_element`.
2. Implement two-sample geometry evidence and hit-test telemetry behind a
   disabled-by-default experimental flag.
3. Do not add `browser_act_at_point`.

Acceptance: inspection disambiguates the fixture without JavaScript; geometry
never selects among semantically eligible candidates and fails closed on
scroll, mutation, overlay, origin, document, or viewport change.

### Slice C — Goal Delegation shadow mode, then narrow activation (P1)

1. Define and validate the versioned grant schema and native preview UI.
2. Implement policy evaluation in shadow mode and collect redacted decisions.
3. Red-team prompt injection, URL smuggling, user-info, query exfiltration,
   redirect, path normalization, DNS/private-address, handoff, reconnect,
   counter/expiry, and concurrent-client cases.
4. Activate only if there are zero false allows in the adversarial corpus and
   every real-provider false allow has a root-cause fix and regression.

Acceptance: at least 80% of repetitive non-sensitive navigation prompts in the
target scenario are avoided without auto-approving any hard-stop class. This is
an initial product target, not a current measurement.

## Validation gates

- **Code:** deterministic policy parser/evaluator; no page-derived policy;
  schema versioning; exhaustive denial reasons.
- **Unit tests:** anchor precedence, direct ARIA references, stable-attribute
  filtering, canonical URL policy, expiry/count/revocation, handoff state.
- **Adversarial tests:** duplicated labels, recycled nodes, hostile headings,
  secret-like IDs/queries, redirects, overlays, prompt injection, stale boxes.
- **Integration:** old and modern MCP clients; legacy text compatibility;
  structured-only/compact negotiation; cancellation and reconnect.
- **Performance:** p50/p95 observe latency, result bytes/tokens, recipe-quality
  computation, prompt reduction, false stops.
- **Accessibility/UX:** VoiceOver and keyboard operation of policy preview,
  Stop, activity indicator, Done button, and exact hard-stop dialogs.
- **Physical Mac:** signed installed app, real native confirmation/crop,
  handoff completion, locked Mac, timeout, multi-display/scaling, scroll.
- **Security review:** independent review of grant scope, URL provenance,
  geometric recovery, and credential/token exclusions.
- **Release:** separate signed-artifact and release gates; research or local
  tests do not establish readiness.

## Open questions and NO-GO blockers

- OPEN: Which modern MCP clients tolerate concise `content` plus complete
  `structuredContent` without losing model-visible semantics?
- OPEN: What query-key policy is useful enough without enabling data
  exfiltration or state-changing GETs?
- OPEN: Which provider routes genuinely need geometric recovery after context
  and stable attributes are implemented?
- OPEN: Can the native Done event safely replace the second resume dialog for
  every auth/handoff state on a physical signed build?
- NO-GO: automatic acceptance based only on natural-language goal, hostname,
  HTTP method, model risk classification, or page-provided instruction.
- NO-GO: auto-approval for keys/tokens/secrets, permissions, payments, sends,
  deletion, uploads, downloads, publication, cross-origin navigation, or an
  unknown consequence.
- NO-GO: coordinate actuation without fresh semantic identity, exact visible
  review, and verified postcondition.

## Local research reused

- `docs/research/2026-08-21-locator-recipes-notebooklm.md`
- `docs/research/2026-08-21-addressing-instrumentation-notebooklm.md`
- `docs/research/2026-08-21-navigation-capability-notebooklm.md`
- `docs/research/2026-08-21-provenance-notebooklm.md`
- `docs/research/2026-08-21-native-actuation-notebooklm.md`
- `docs/security-threat-model.md`

These notes were treated as historical leads and checked against the current
dirty checkout and current primary sources. No external provider behavior was
mutated or claimed as validated.
