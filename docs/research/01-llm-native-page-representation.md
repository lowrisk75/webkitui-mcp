# Deep Research 1 — How should a web page be represented FOR a model?

Paste into Perplexity Pro / Deep Research (or Gemini Deep Research). Answer in
English; end with a raw URL list, one per line, no markdown.

---

**Role.** You are a Principal Engineer designing the page-observation layer of an
agentic browser. The consumer is an LLM, not a human. Every token spent on
describing the page is a token not spent on reasoning about it.

**Question.** What is the state of the art, as of late 2026, for representing a
live web page to an LLM agent — and what does the measured evidence say?

Cover, with numbers wherever they exist:

1. **The competing representations.** Raw DOM/HTML, cleaned HTML, the
   accessibility tree (AXTree), screenshots with set-of-mark annotation, hybrid
   text+vision, and structured extraction. For each: tokens consumed per page on
   real sites, and task success rate on published benchmarks.

2. **Benchmarks that actually measure this.** WebArena, VisualWebArena, Mind2Web
   / Multimodal-Mind2Web, WebVoyager, WorkArena, BrowserGym, AgentRewardBench,
   and anything newer. Which representation wins on which benchmark, and by how
   much? Where do the benchmarks disagree, and why?

3. **Element addressing.** How do the best systems give the model a handle to
   click? Numeric marks, backend node ids, XPath, CSS, ARIA-derived ids, semantic
   labels. Which survive a re-render, a scroll, or a virtualised list — and what
   is the measured rate of stale-handle failures?

4. **Compression that does not lose the task.** Viewport-only vs full page,
   pruning by interactivity, collapsing repeated structures, diffing against the
   previous observation instead of re-sending the page. Measured token savings
   AND measured effect on success rate — a compression that costs accuracy is not
   a saving.

5. **Where vision is genuinely required.** Canvas apps, charts, drag-and-drop,
   CAPTCHAs, visual-only affordances. Is there evidence that text-only
   representations fail on a bounded, identifiable class of pages?

**Constraints.** Prefer papers with released code and reproducible numbers, and
engineering write-ups from teams shipping real agents. Say explicitly when a
claim is a vendor assertion rather than a measurement. Note publication dates —
this field moved fast in 2025-2026 and older results may be obsolete.

**Output.** A technical report, then a raw list of every source URL, one per
line, no markdown formatting, so it can be imported directly into NotebookLM.
