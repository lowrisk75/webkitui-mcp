# Provenance and capability control — NotebookLM counter-audit

Date: 2026-08-21

## Scope and notebook identity

- Primary notebook: `WebKITUI MPC`, private ID redacted.
- Opportunity notebook: `LLM`, private ID redacted, 295 sources reported (285 collected by
  the identity call).
- Both identities were checked before asking questions. Answers were settled and
  cited, but NotebookLM remains a synthesis aid rather than primary proof.

## Source-reported measurements (not reproduced here)

- The primary notebook reports Spotlighting reducing attack success from above
  50% to below 2% in its cited Microsoft evaluation.
- It reports CaMeL at 77% task success with security guarantees versus 84%
  undefended, with zero successful attacks on the cited AgentDojo evaluation.
- It reports structured HTML at 1.1% attack effectiveness versus 3.9% for flat
  text over 5,200 cited trials. This supports retaining structure and provenance;
  it does not prove our schema.
- The second notebook reports raw element identifiers reducing unseen-site
  Mind2Web StepSR from 39.7% to 12.4%, supporting semantic rather than physical
  identities. This is adjacent evidence, not a provenance benchmark.
- None of these measurements tests WebKitUIMCP or its proposed Swift types.

## Bugs identified for this implementation

- Labels do not prevent semantic laundering: page data can still cause the model
  to propose a privileged action. Authority must be checked independently.
- Byte or character offsets drift after decoding and normalization. Preserve
  provenance as segments and transform each segment; do not maintain a detached
  offset table over flattened text.
- Origin and frame identity can become stale between observation and action.
  Re-resolve and re-check the live security origin at the action boundary.
- A transformation log can grow without bound. Use bounded typed steps and make
  truncation explicit.
- A total trust ranking is incorrect: provenance classes are categories, not a
  scalar. Mixed content retains the union of its classes.
- Strict information-flow policy can reject legitimate cross-domain tasks. Make
  grants explicit and scoped; do not invent a universal allow rule.

## Missed opportunities

### In scope now

- Separate knowledge from authority: a model may know an origin, locator, or
  handle name without possessing a runtime-issued capability.
- Keep mixed-trust strings as independently labelled segments.
- Make authority origin-, action-, input-provenance-, and time-scoped.

### Later, conjectural for this product

- Combine semantic post-conditions with visual-region evidence for SPAs.
- Store checkpoint objects by semantic identity and temporal state rather than as
  one flat transcript.
- Add cooperative memory release/fault primitives after checkpoint+deltas exist.
- Cryptographically bind capability grants across process boundaries. An
  in-memory unguessable handle is sufficient only for the current single-process
  core prototype.

## Engineering decision

Implement segment-level `ProvenancedText` and an actor-isolated capability
authority. The authority, not the serialized name, owns grants. No trust
promotion API is added. Live frame/origin revalidation remains a required action
boundary invariant for the WebKit adapter.
