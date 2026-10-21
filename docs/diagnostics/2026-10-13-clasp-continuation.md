# Clasp diagnostic continuation — bounded contracts

Source reviewed: Clasp consolidated native-MCP release diagnostic2026-10-13.
Owner Codex/WebKitUI, no Clasp source/account mutation. No private transcript,
credentials, session tokens, receipt contents or foreign windows copied.

## Existing paths worth qualifying first

- `browser_scroll` moves the document (or inferred page pane when the document
  cannot scroll); it does not select an arbitrary modal's list.
- If an offscreen checkbox/button is already in a fresh observation,
  `element_scroll_into_view(session_id, observation_id, element_id)` resolves that
  exact control and scrolls its nearest nested region. Its synthetic nested-region
  test passes in638 Debug. Observe again afterward; the old observation is invalid.
  This is not proof for ASC, closed shadows, opaque frames or undiscovered controls.
- `panel_open` takes the panel's accessible name as a string, never boolean true.
- `semantic_text_appears` uses exact text; `semantic_text_contains` is inclusion.
  Neither should use an invented expected label. A postcondition already true is
  not a transition proof. A persistent Suivant button is not expected to disappear.
- A dispatched-but-indeterminate response must be reconciled by fresh reads,
  never replayed as if the first click did not happen.
- DOM readiness/quiescence does not prove business data loaded. Wait for an
  observed business marker with a bounded deadline; no marker means unknown,
  not category deletion or successful persistence.
- `handoff_focus` brings back an active human-control window, not a pending
  confirmation. `confirmation_cancel` cancels the calling server's pending prompt.
  No current exact confirmation re-present operation is claimed.

## Next bounded implementation lots

R-017: discover scroll containers with observation-scoped IDs; explicit target
and bounded CSS-pixel delta, no caller selector or JS. Resolve same physical
container, reject stale/missing/ambiguous/foreign-frame targets before movement.
Receipt includes before/after and bounds, actual delta, target identity and old
observation invalidation. Test long modal + scrollable background unchanged,
horizontal/vertical boundaries, nested regions, removed/replaced target and handoff.

R-018: separate structural, attribute and text truncation facts. Add an explicit
observed dialog/control verification scope, preserving complete-global-observation
requirements for global absence. No inference from truncated aggregate ancestors.
Tests:4096+characters dialog, duplicate headings/buttons, preserved/renamed Next,
scope detached or replaced, ambiguous root, truncated target label, stale scope,
global target_absent still refused. Scope disappearance must not mean remote save.

R-019: exact pending request-bound re-presentation, calling-client ownership and
verified live helper identity. Never create a new approval, reset the decision,
extend expiration silently or equate focus with consent. Refused/expired/stale
request produces zero dispatch; human approval produces one. Local native tests
plus explicit human checks across focus/Space/overlapping windows are required.

R-020: publish operation-specific examples and explicit readiness scope, with
schema contract tests. Keep composition-free schema compatibility while callers
that erase union metadata are supported. Do not inflate max text as a guard bypass.

## Acceptance limits

638 href-less delegated anchor fixture proves that case, not the unknown real
ASC DOM. An authorized test account/owning mission must qualify real entry points.
No literal-IP policy bypass, Safari extension permission claim, app submission,
portal publication or cross-task page adoption is part of this local lot.
