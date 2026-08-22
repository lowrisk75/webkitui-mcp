# MFS coverage — primary-source and NotebookLM counter-audit

Date: 2026-08-21

## Sources checked

- Primary preprint: Enomoto, Obara, Zhang, Oyamada, *Revisiting Observation
  Reduction for Web Agents*, arXiv:2605.29397, 2026-05-28.
  <https://arxiv.org/abs/2605.29397>
- DeepSearsh title: *Representing a Live Web Page for an LLM Agent: Measured
  State of the Art as of August 2026*.
  - `library_path`:
    `library/evidence-and-decisions/deepsearsh/deep-research-report-2--79caa0fe0f.md`
  - `origin`: `DeepSearsh/inbox/deep-research-report-2.md`
  - SHA-256:
    `79caa0fe0f2e7d377f9acd9659a29db81a472a268cfb09b4b13b8ebac49300b9`
- NotebookLM `WebKITUI MPC`, private ID redacted:
  definitions, implementation blind spots, missed opportunities.
- NotebookLM `LLM`, private ID redacted:
  missed-opportunity counter-audit.

## Measured or defined by the primary paper

- An ablation unit is `(element identifier, information kind)`. Information is
  `@tag`, `@text`, or one named HTML attribute.
- Published coverage is binary per instance: the reduced observation either
  contains the complete approximate MFS or it does not. Dataset coverage is the
  fraction of covered instances.
- The published reduction ratio is the mean per-instance retained character
  fraction, not a token ratio and not a global aggregate ratio.
- Exact cardinality-minimum search is exponential. The paper constructs an
  approximate, 1-minimal set from agent self-reports and `ddmin`; the code must
  not label supplied sets as proven global minima.
- Coverage correlations across trajectory-generating models were reported as
  0.82–0.88 on WorkArena and 0.66–0.71 on WebLinx. These are correlations from
  the paper, not measurements of WebKitUIMCP.
- Limitations: extractive reducers only; observed successful trajectories only;
  representation transformations with identical retained elements are not
  distinguished; the underlying MFS datasets are not redistributed.

## Counter-audit decisions

- Dynamic element identifiers are not replaced by semantic locators inside this
  metric. Candidate reduction and MFS are compared on the same immutable
  observation. Cross-snapshot identity belongs to addressing telemetry.
- Unit recall is useful for debugging but must not be called MFS coverage. A
  reducer retaining 9/10 critical units still has published coverage 0 for that
  instance.
- Token retention is useful for cost diagnosis but must remain separate from the
  paper's character-based reduction ratio.
- Missing-unit diagnostics include only missing MFS units, never every removed
  page unit, preventing irrelevant mutation noise.
- Multiple successful paths require multiple collected MFS instances; one MFS
  cannot prove task-wide necessity.

## Conjectural opportunities, deferred

- Statistical repeatability for non-deterministic MFS construction oracles.
- Temporal MFS variants for checkpoint/delta corruption and stale-state use.
- Post-condition MFS for transaction verification.
- Semantic and visual equivalence metrics for non-extractive transformations.

## Engineering decision

Implement the published binary coverage and mean character-retention ratio
exactly. Add per-instance missing-MFS diagnostics, unit recall, and an optional
token-retention ratio under distinct names. Reject malformed or mismatched
datasets rather than silently changing denominators.
