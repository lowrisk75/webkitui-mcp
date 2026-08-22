# Deep Research 4 — What the shipped agentic browsers actually do, and what bites them

Paste into Perplexity Pro / Deep Research. Answer in English; end with a raw URL
list, one per line, no markdown.

---

**Role.** You are doing competitive and safety due diligence before building an
agentic browser tool that will compete, on quality, with what the large providers
ship.

**Question.** As of late 2026, how do the shipped agentic browsing products
actually work under the hood, where do they measurably fail, and what is the
defensible ground left for a local-first native implementation?

Cover:

1. **The products, technically.** OpenAI Operator / ChatGPT Atlas, Perplexity
   Comet, Anthropic's Claude in Chrome, Google's Project Mariner / Gemini
   browsing, Browser Use, Browserbase / Stagehand, Playwright MCP, and any
   serious open-source contender. For each: page representation, element
   addressing, where execution happens (local vs cloud), and what they publish
   about accuracy.

2. **Measured performance.** Published success rates on shared benchmarks, and
   independent reproductions where they exist. Note where a vendor number has
   never been reproduced by anyone else.

3. **Documented failure modes.** Latency, cost per task, flakiness on real sites,
   bot detection and Cloudflare-class blocking, authentication walls, and what
   happens when the page changes mid-task.

4. **Prompt injection, seriously.** The published attacks on agentic browsers in
   2025-2026, including Comet and Atlas disclosures. What was the actual attack
   path, what was the fix, and did the fix hold? What mitigations have evidence
   behind them rather than press-release language?

5. **The local-first argument.** Where does running natively on the user's own
   machine, with their own session and no cloud round-trip, produce a measurable
   advantage — latency, privacy, authenticated access, cost? And where is it
   simply worse than a cloud browser farm? Be honest about both.

6. **What nobody does well yet.** Concrete, identifiable gaps a small
   well-engineered tool could actually close, as opposed to areas where scale
   wins and competing is futile.

**Constraints.** Separate what is documented from what is inferred. Prefer
primary sources: engineering blogs, security advisories, papers, source code. Date
everything.

**Output.** A technical report, then a raw list of every source URL, one per line,
no markdown, for direct import into NotebookLM.
