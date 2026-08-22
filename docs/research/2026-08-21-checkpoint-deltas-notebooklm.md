# Checkpoint plus deltas — source and counter-audit

Date: 2026-08-21

## Sources

- RFC 6902, JSON Patch: ordered operations terminate on error; `test` provides
  an explicit precondition. <https://datatracker.ietf.org/doc/html/rfc6902>
- DeepSearsh, *Representing a Live Web Page for an LLM Agent*:
  `library/evidence-and-decisions/deepsearsh/deep-research-report-2--79caa0fe0f.md`;
  origin `DeepSearsh/inbox/deep-research-report-2.md`; SHA-256
  `79caa0fe0f2e7d377f9acd9659a29db81a472a268cfb09b4b13b8ebac49300b9`.
- DeepSearsh, *Virtualisation de mémoire contextuelle…*:
  `library/evidence-and-decisions/deepsearsh/virtualisation-de-me-moire-contextuelle-et-me-moire-d-expe-rience-incre-mentale-pour-agents-llm-e-tat-de-l-art-dag-snapshots-et-trimming-structurel--1b98415df7.md`;
  origin `DeepSearsh/inbox-archive/Virtualisation de mémoire contextuelle et mémoire d’expérience incrémentale pour agents LLM état de l’art, DAG, snapshots et trimming structurel.md`;
  SHA-256 `1b98415df79e1d122810fa7a0e29bbf940208c7f3d4d9e37ac2cdffc0f830f9c`.
- NotebookLM `WebKITUI MPC`: measured state, design bugs, opportunities.
- NotebookLM `LLM`: opportunity scan; its final answer returned no citations, so
  none of its numerical claims is treated as evidence.

## Source-reported measurements

- Nine complete AXTree observations: 39,011 tokens; nine character diffs:
  13,670 tokens. GPT-5.1-high success was 58.8% in both conditions.
- Gemini 2.5 Flash lost success with diffs: 50.0% to 48.2% at high budget and
  39.4% to 33.3% at low budget. Checkpoints therefore remain mandatory.
- These measurements are reported by the research source; this implementation
  does not reproduce the WorkArena experiment.

## Blind spots resolved

- The digest authenticates an immutable serialized history state. It is not an
  actionability check against the continuously mutating live DOM.
- Entries use stable keys `(frame, observation element, field)`, never sorted
  array indices. Canonical sorting only stabilizes bytes.
- Every replace and remove carries an expected old-value digest. Base and result
  state digests make missing, reordered, or corrupted deltas fail closed.
- Delta application is copy-on-write and atomic from the caller's perspective.
- Document or security-origin changes force a checkpoint. Subframe provenance
  remains attached to values and frame IDs remain in keys.
- The chain has a hard maximum depth. No model-specific 65% threshold is baked
  in; tokenizer-aware crossover remains a later measured policy.

## Conjectural opportunities deferred

- Cost-triggered checkpoints comparing locally measured delta and checkpoint
  tokens for the selected planner model.
- Branching snapshot DAG after linear reconstruction is proven.
- Quiescence-aware semantic extraction in the live WebKit adapter.
- Temporal MFS and post-condition failure sets.
