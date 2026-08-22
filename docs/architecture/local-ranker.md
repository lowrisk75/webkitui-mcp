# Local extractive ranker

The Qwen worker is an optional ordering hint, never a summarizer, deletion
oracle, security classifier, or action authority. Inputs and outputs use short
observation-scoped IDs; Swift retains the exact provenance-bearing evidence.

`LocalRanker.prepare` either returns a bounded Ollama payload or an immediate
deterministic fallback. The payload always sets `think:false`, `stream:false`,
temperature zero, a fixed seed, a bounded output, and a strict JSON schema. It
contains no tools. Password/secret segments are redacted before serialization.

`LocalRanker.resolve` rejects thinking text, malformed JSON, unknown IDs and
duplicate IDs. Valid omissions are appended in original order, so model failure
cannot destroy evidence. Ranking does not extend an element lease: every action
still re-resolves its locator and passes capability policy.
