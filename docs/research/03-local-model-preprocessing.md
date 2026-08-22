# Deep Research 3 — Putting a small local model between the page and the agent

Paste into Perplexity Pro / Deep Research. Answer in English; end with a raw URL
list, one per line, no markdown.

---

**Role.** You are designing the preprocessing stage of an agentic browser. A page
is fetched locally, then reduced by a small model running on a private server
(Qwen3 4B class, quantised, CPU or a modest GPU) BEFORE anything reaches the
frontier model that holds the tools.

**Question.** Is that stage worth it, and what does the evidence say about doing
it well — and about doing it badly?

Cover:

1. **Extraction before any model runs.** Readability/Trafilatura/Resiliparse-class
   extractors, boilerplate removal, HTML-to-Markdown. Published precision/recall on
   real corpora, and the honest failure modes (SPAs, infinite scroll, paywalls,
   comment threads). How much of the win is available with zero inference?

2. **What a 4B model can and cannot be trusted to do.** Measured quality on
   summarisation, structured extraction and classification at that size — with
   the quantisation level stated, because Q4 and Q3 are not the same model. Where
   is the cliff?

3. **The cost that is usually forgotten.** Reasoning tokens, prefill on long
   pages, and latency on CPU-only or partially-offloaded inference. Under what
   conditions does the local stage cost more wall-clock than it saves in frontier
   tokens? Give break-even reasoning, not slogans.

4. **Lossy compression that keeps the task solvable.** Evidence on
   summarise-then-act pipelines: how often does the small model drop exactly the
   detail the agent needed? Any benchmark that measures END-TO-END task success
   with and without the preprocessing stage, rather than summary quality in
   isolation.

5. **The security seam.** A page is untrusted input. Research on indirect prompt
   injection surviving summarisation, and on whether a schema-constrained small
   model launders or contains the attack. Quantified propagation rates if they
   exist. What actually stops it: provenance marking, byte-exact quoting,
   capability limits on the tooled agent?

6. **How the good systems are built.** Real architectures that put a small model
   in front of a large one for web content — what they route locally, what they
   escalate, and how they decide.

**Constraints.** Cite measurements, not vendor claims, and say which is which.
Note dates. If a point is not covered by the literature, say so plainly rather
than filling the gap.

**Output.** A technical report, then a raw list of every source URL, one per line,
no markdown, for direct import into NotebookLM.
