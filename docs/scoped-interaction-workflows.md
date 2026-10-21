# Bounded dialog and confirmation workflows

These operations do not prove backend persistence. Always retain your task's own
session ID. Never adopt another task's page from `status`.

## Compact/full observations and editable pickers

Request `fields: ["role", "name", "state"]` with `compact: true` to obtain
`stateAttributes`, including observed `aria-expanded`. Compact attributes are
plain strings with document provenance factored once; full attributes are
`ProvenancedText` values with `segments`. No arbitrary DOM attribute is exported.
`name` in compact corresponds to `accessibleName.segments` in full, not `label`.
The [normalization example](examples/normalize-observation.mjs) handles both,
retains original evidence, distinguishes missing fields from false state and binds
each element to its observation. Run `node scripts/test-observation-normalization.mjs`.
It is an adapter, never authorization or a way to reuse stale IDs.

`fillCapability` is present on text controls/pickers in both shapes and the inspector,
and omitted on unrelated controls to preserve the bounded wire budget. Absence is
unknown, not permission to fill:

| Value | Meaning / next step |
|---|---|
| `editable` | DOM allows text editing; framework acceptance and remote save remain unproved |
| `readonly` | native readonly or `aria-readonly=true`; do not fill |
| `disabled` | native/ARIA disabled; do not fill |
| `unsupported` | not an exact text editor (e.g. button combobox, select or checkbox) |
| `sensitive` | human/secretless credential workflow required; no fill bypass |

For a controlled combobox, click its observed picker and select an exact observed
option with an appropriate state postcondition. Do not assume typing is selection.
`select_option` is only for native selects. Never replay a dispatched-indeterminate
fill; read its value/selection again. Live editability is rechecked before dispatch.

Only an exact, explicitly labelled public `Token name` (also API/access token name)
on a text input can avoid the token-name false positive. Conflicting secret
metadata, password/autocomplete, opaque values, configuration-value redaction and
generic token fields retain their protections. This is not a client override or
a guarantee about an unobserved provider's DOM. Ambiguous fields use handoff.

## Human handoff argument matrix

These are the only accepted keys for each operation. All include `operation`;
retain your own `session_id`. Do not copy navigation timing arguments to handoff.

| Operation | Required besides operation | Optional keys | Effect |
|---|---|---|---|
| `handoff` | `session_id` | `compact`, `maximum_elements` | confirmed transfer both ways; no token |
| `handoff_start` | `session_id` | none | immediate human transfer; issues session-bound token |
| `handoff_status` | `session_id`, `resume_token` | none | read-only polling; no resume |
| `handoff_resume` | `session_id`, `resume_token` | `compact`, `maximum_elements` | confirmation, consumes token only when resume succeeds |
| `handoff_focus` | `session_id` | none | re-present active human window; no authority change |
| `confirmation_focus` | `session_id`, `confirmation_request_id` | none | re-present exact pending prompt; no approval |
| `confirmation_cancel` | `session_id` | none | cancel pending local prompt; no approval |
| `compatibility_start` | `session_id` | none | confirmed manual Safari fallback; no credentials copied |
| `client_handoff` | `session_id` | none | confirmed authority transfer; not sensitive-input handoff |
| `status` | none | `session_id` | metadata only; never permission to adopt another page |

`compact` defaults to true for returned handoff observations. `maximum_elements`
is 1–2000 (default40 compact/150 full). `timeout_ms` and `quiet_window_ms` belong
to `back`/`forward`/`reload`, not the handoff operations above. Unknown keys refuse
before dispatch. A token is not permission to skip the native confirmation.

## Scroll a dialog list, not its background

Observe first. A measured container reports `scrollable: true` in compact and full
observations (and in the inspector). This is a capability, not an ARIA role or
permission to click. Use both target fields, with bounded CSS-pixel deltas:

```json
{"session_id":"<own-session>","observation_id":"<fresh-observation>","element_id":"<observed-scroll-container>","delta_y":500}
```

Call `browser_scroll` with these arguments. The same physical container must still
exist and be scrollable. No semantic replacement or background fallback occurs.
The receipt includes before/after offsets, actual deltas and bounds; a zero delta
at a boundary means no movement. Observe again afterward. If the desired control
is already observed offscreen, `element_scroll_into_view` is also available.
Neither operation selects a checkbox or submits a form. Unsupported frames or
undiscovered controls still require explicit human handoff.

## Verify a transition inside an observed dialog

Start with a normal `browser_observe`, then obtain an explicit scoped observation:

```json
{"session_id":"<own-session>","scope_observation_id":"<fresh-global-observation>","scope_element_id":"<observed-dialog-root>"}
```

Only an observed main-document dialog/alertdialog root is accepted. The new
observation has fresh element IDs and `verificationScopeID`; subsequent actions
and reconciliation using it remain pinned to that physical dialog. A normal
observation without scope fields restores global observation.

Oversized aggregate duplicates may be omitted explicitly (`aggregateTextOmitted`;
compact `aggregate_text_omitted`). Structural completeness and
`semantic_text_complete` are separate facts. An omitted paragraph/context does
not justify a semantic-text appearance or absence claim. Use a legible new heading
or exact target state instead. Truncated leaf fields, pagination, filters and
unreadable content still prevent complete observation. Global `target_absent`
continues to require a complete global observation.

If the scoped root is hidden, detached, replaced or navigated away, verification
is unknown/indeterminate, never successful absence. Read globally to reconcile;
do not replay the action. To verify closing/replacing the root itself, use a
separate appropriate global condition, not absence within a vanished scope.

## Choose a postcondition that describes a transition

Values are strings, including booleans/counts:

| Situation | Postcondition example | Limitation |
|---|---|---|
| New exact heading | `{"type":"heading_equals","value":"Suivi"}` | must not already be true |
| Exact semantic text appears | `{"type":"semantic_text_appears","value":"Exact visible label"}` | exact, not a fragment; text must be complete |
| Observed text fragment | `{"type":"semantic_text_contains","value":"Exact fragment"}` | not an anticipated/invented label |
| Named panel opens | `{"type":"panel_open","value":"Panel accessible name"}` | never boolean `true` |
| Checkbox changes | `{"type":"checked_equals","value":"true"}` | same observed target |
| Button disappears/renames | `{"type":"target_absent","value":"true"}` | complete chosen scope, root retained |

A wizard can retain a button named Suivant on its next step. Its disappearance
cannot prove that transition; use the new heading. A predicate already true is
refused. A dispatched-indeterminate receipt means read/reconcile, never retry.

## Re-present one pending confirmation

Poll `browser_session operation=status` for your session. If
`native_confirmation_focus_available` is true, copy the exact `requestID` from
`last_confirmation_presentation`:

```json
{"operation":"confirmation_focus","session_id":"<own-session>","confirmation_request_id":"<exact-pending-request-UUID>"}
```

`focus_requested` means the bound, verified live helper was asked to re-present.
It is not proof of key focus or human perception; poll its measured metadata.
The helper emits phase `refocused`. The operation grants no approval, dispatches
no browser action, creates no replacement request and never extends expiration.
Stale/expired/cancelled requests are not revived. At most three requests are
accepted for one prompt, at least one second apart. A refused request does not
justify replaying the original action. `handoff_focus` is different: it only
re-presents an already active human-control browser window.

## Readiness is not business readiness

Navigation reports `readiness_scope=document_completion_and_mutation_quiescence`,
`business_readiness=not_verified`, and `remote_persistence_verified=false`.
Wait for an actual observed business marker with a bounded deadline. A first read
without data is unknown, not deletion. Even a verified UI transition is not
evidence that a remote server durably saved the change.
