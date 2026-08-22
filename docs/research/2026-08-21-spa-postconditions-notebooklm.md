# SPA write postconditions — NotebookLM review (2026-08-21)

Notebook: `WebKITUI MPC` (private notebook ID redacted).

## Source-supported

- Web Bench reports a large read/write success gap; client-visible success is not equivalent to a committed write.
- WorkArena uses deterministic application/database state checks for grading rather than trusting success-looking UI text.
- A complete fresh observation can reject a postcondition already satisfied before dispatch; partial observations cannot prove absence.

## Locally measured

- None for this slice before implementation. The new predicates and same-page SPA transaction will be covered by deterministic tests.

## Conjectural / unmeasured

- No public ablation quantifies the gain from DOM-text, network-response, localized-mutation, or backend-state postconditions.
- Global text matching can false-positive on a success message left by an earlier operation.
- Exact text may false-negative when a toast is transient, pruned, inside a closed shadow root/cross-origin frame, or transformed by redaction.
- Promising measurements: postcondition false-positive/false-negative rates, time-to-proof, forced WebContent-process recovery, and browser proof versus backend proof.

## Implementation consequence

- Add exact-digest matching across semantic fields without binding proof to an ephemeral element ID.
- Require the predicate to be absent in the complete pre-dispatch observation; the existing ledger then rejects stale/pre-existing success text.
- Keep UI-semantic proof explicitly weaker than application/backend-state proof. Do not infer server commit from text alone.
