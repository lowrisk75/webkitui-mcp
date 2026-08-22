# Local extractive ranker — evidence and live measurement

Date: 2026-08-21

## Sources

- DeepSearsh: *Putting a Small Local Model Between the Page and the Agent*;
  `library/general-research/deepsearsh/putting-a-small-local-model-between-the-page-and-the-agent--f48c482f97.md`;
  origin `DeepSearsh/inbox/Putting a Small Local Model Between the Page and the Agent.md`;
  SHA-256 `f48c482f9728751865a299039bd10086dd0150004717faa39192a5031c6fd613`.
- NotebookLM `WebKITUI MPC`: measured state, contract blind spots, missed
  opportunities.
- NotebookLM `LLM`: the first question was blocked locally before upload; the
  short reformulation returned only UI placeholder text and no citations. It is
  excluded from decisions.

## Source-reported measurements

- WCXB deterministic extraction: 28 ms/page Resiliparse, 44 ms
  rs-trafilatura, 97 ms Trafilatura; overall F1 0.797, 0.859 and 0.791.
- Mind2Web's specialized 86M candidate ranker reports Recall@50 of
  85.3–88.9%; this does not predict zero-shot Qwen performance.
- Qwen3-4B-Base: MMLU 73.0 FP16, 70.9 GPTQ W4, 37.5 AWQ W3. These are not
  measurements of the deployed GGUF model.
- A local prefill break-even above 1.25× the frontier rate at 20% retention is
  algebra, not a measured property of this node.

## Live node measurements

Endpoint: private LAN host (redacted), 2026-08-21.

- `/api/tags`: `throttle-worker:latest`, Qwen3 4.0B, GGUF Q4_K_M,
  2,497,293,626 bytes, digest
  `1cd897f944a6bc09d85f28fb151338f3dbbdf16b5cbb0b76052d399b596ab5d8`.
- `/api/ps`: active context length 16,384; loaded size 5,091,677,704 bytes,
  VRAM 2,894,751,334 bytes.
- `/api/show`: Modelfile defaults include temperature 0.6 and expose thinking;
  every request must override both.
- Warm-up ranking request with `think:false`, temperature 0, seed 42:
  4.183 s total; load 0.820 s; 26 prompt tokens in 0.927 s; 22 output tokens
  in 2.404 s; no thinking field returned.
- Quality observation on that single fixture: for “Choose submit” with Cancel
  `e1` and Submit `e2`, it returned both IDs. One fixture is not a benchmark,
  but it disproves treating zero-shot selection as a deletion oracle.

## Contract decisions

- The local model only proposes an ordering over a closed, observation-scoped
  candidate set. Omitted candidates are appended; evidence is never deleted.
- Unknown or duplicate IDs, thinking output, malformed JSON, or budget excess
  trigger deterministic original-order fallback.
- Exact `ProvenancedText` remains in Swift. The model sees a redacted,
  provenance-bearing serialization; secrets never enter its prompt.
- The model has no tools and grants no authority. Locator re-resolution and
  capability policy remain downstream invariants.
- Candidate and prompt-byte budgets prevent a failed ranker from becoming an
  unbounded prefill path. Progressive disclosure is a later runtime API.
