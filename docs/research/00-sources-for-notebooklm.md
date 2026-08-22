# Deep Research 0 — Collecte de sources pour le NotebookLM du projet

Coller dans Perplexity Pro / Deep Research (ou Gemini Deep Research).
**La sortie doit être une liste d'URLs, une par ligne, rien d'autre.**

---

**Role.** You are a research librarian assembling the foundational corpus for a
NotebookLM project. The project is an **LLM-native browser automation tool built
on native WebKit for Apple Silicon**, exposed over MCP, with a small local model
used to reduce pages before they reach a frontier agent.

**Task.** Sweep the web and return the primary sources worth reading. Prioritise
things with code, measurements or normative text over commentary.

Cover all seven areas:

1. **Page representation for agents** — accessibility tree vs DOM vs screenshots
   vs set-of-mark; observation reduction; element addressing and handle stability.
   Include the WebArena / VisualWebArena / Mind2Web / WebVoyager / WorkArena /
   BrowserGym / AgentRewardBench papers and their leaderboards.

2. **WebMCP and browser-native agent APIs** — the W3C draft, `navigator.modelContext`,
   Chrome's origin trial, Firefox's position, any WebKit or Safari statement, and
   critical analyses.

3. **Model Context Protocol itself** — the specification, the 2026-07-28 revision,
   reference servers, and the published work on tool-schema context cost and
   lazy tool loading.

4. **WebKit on Apple Silicon** — WKWebView automation, off-screen rendering,
   `WKWebExtension`, the WebKit remote inspector protocol, `safaridriver`,
   Playwright's WebKit port, macOS accessibility APIs for web content, and WWDC
   sessions on any of it.

5. **Content extraction and small-model preprocessing** — Readability,
   Trafilatura, Resiliparse and their published benchmarks; HTML-to-Markdown;
   quantised small-model quality studies; summarise-then-act pipelines evaluated
   end to end.

6. **Agentic browsing in the wild** — OpenAI Operator / Atlas, Perplexity Comet,
   Claude in Chrome, Project Mariner, Browser Use, Stagehand / Browserbase,
   Playwright MCP, Chrome DevTools MCP. Engineering posts and source repos, not
   marketing pages.

7. **Security** — indirect prompt injection against browsing agents, the 2025-2026
   disclosures on shipped products, OWASP material on LLM agents, and mitigations
   with evidence behind them.

**Selection rules.**
- Primary sources first: arXiv papers, W3C and WHATWG specs, Apple and WebKit
  documentation, GitHub repositories, security advisories, engineering blogs from
  teams that ship.
- Exclude SEO listicles, vendor landing pages, and "top 10 tools" articles.
- Prefer 2025-2026 material; include an older source only when it is the canonical
  reference for something still in use.
- Deduplicate. One URL per distinct source. Aim for 60-120 URLs.
- Every URL must be directly reachable — no paywalls, no redirect shorteners, no
  PDFs behind a login. Prefer the arXiv abstract page over the PDF.

**Output format — this matters.**
Return **only** a list of URLs, one per line. No numbering, no bullets, no
markdown links, no titles, no commentary, no grouping headers, nothing before the
first URL and nothing after the last. The output will be pasted straight into
NotebookLM's bulk source importer.
