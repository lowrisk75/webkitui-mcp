# Addressing instrumentation — NotebookLM review (2026-08-21)

Notebook: **WebKITUI MPC**

Notebook ID: private (redacted)

This note records three short English queries made with explicit consent and
`sensitivity: internal`. NotebookLM is treated as synthesis, not authority.

## Local research provenance

- *Representing a Live Web Page for an LLM Agent* —
  `library/evidence-and-decisions/deepsearsh/deep-research-report-2--79caa0fe0f.md`;
  origin `DeepSearsh/inbox/deep-research-report-2.md`;
  SHA-256 `79caa0fe0f2e7d377f9acd9659a29db81a472a268cfb09b4b13b8ebac49300b9`.
- *WebKit on Apple Silicon as an Agent Runtime in 2026* —
  `library/general-research/deepsearsh/webkit-on-apple-silicon-as-an-agent-runtime-in-2026--41abdb5f97.md`;
  origin `DeepSearsh/inbox/WebKit on Apple Silicon as an Agent Runtime in 2026.md`;
  SHA-256 `41abdb5f975aa5edea6966a4c1ab2496dbb697f08de0f22440366f9f63a2a1e2`.
- *Putting a Small Local Model Between the Page and the Agent* —
  `library/general-research/deepsearsh/putting-a-small-local-model-between-the-page-and-the-agent--f48c482f97.md`;
  origin `DeepSearsh/inbox/Putting a Small Local Model Between the Page and the Agent.md`;
  SHA-256 `f48c482f9728751865a299039bd10086dd0150004717faa39192a5031c6fd613`.
- *Shipped Agentic Browsers in 2026* —
  `library/evidence-and-decisions/deepsearsh/deep-research-report--3f465f7647.md`;
  origin `DeepSearsh/inbox/deep-research-report.md`;
  SHA-256 `3f465f764779fe98956dec44c922281b9ad615e17b15a393181749d0f051b579`.

## Measured locally

- The checkout is the existing TypeScript/Playwright/CDP implementation, not an
  empty directory. It has 19 MCP tools in `src/index.ts`.
- The macOS SDK selected by `xcrun --sdk macosx --show-sdk-path` is
  `MacOSX27.0.sdk` from Xcode beta.
- That SDK contains public macOS 27 declarations for `WKJSHandle`,
  `WKDOMNodeSnapshot`, `WKContentWorldConfiguration`, and `willSubmitForm`.
- The SDK does **not** contain `WKSerializedNode`; the research synthesis used
  the wrong name. `WKDOMNodeSnapshot` is the shipped declaration.
- The SDK documents that a `WKJSHandle` becomes `undefined` in another content
  world or frame, and after its source frame navigates. It therefore cannot be
  the durable model-facing element identity.

## Reported measurements — not revalidated in this turn

NotebookLM repeated these source-attributed results:

- VisualWebArena: GPT-4V 15.05% without SoM versus 16.37% with SoM.
- Multimodal-Mind2Web / SeeAct setting: 42.3% choice-based candidate grounding
  versus 25.6% SoM element accuracy.
- No cited benchmark publishes a standardized stale-address failure rate.

Sources named by the notebook include *VisualWebArena*, *Mind2Web*, the
page-representation deep-research report, and Playwright documentation. Exact
numbers remain historical research until checked against the primary papers.

## Conjectural risks and opportunities

- Virtualized lists can recycle a physical node while changing its logical row;
  actionability alone will not detect this.
- A unique, visible resolution can still be the wrong logical target.
  `logical_target_changed` needs explicit evidence (task oracle, invariant, or
  human label); otherwise its value must remain unknown rather than guessed.
- DOM generation counters can measure mutation and latency between observation
  and action, but mutation count alone does not prove semantic staleness.
- DOM/AX cross-checking, overlay interception checks, and recovery-loop success
  rates are promising measurements, but the notebook supplied no validated
  baseline for them.
- The notebook's claim that MCP multi-round-trip requests should drive recovery
  was not verified and is excluded from the initial architecture.

## Resulting design constraints

1. Keep ephemeral observation IDs separate from locator recipes and native
   handles.
2. Define the five requested counters before browser implementation, with
   mutually exclusive classification rules and an explicit `unknown` outcome.
3. Preserve observation generation, action generation, monotonic latency, frame,
   content world, semantic fingerprint, and corroborating geometry in each trace.
4. Re-resolve immediately before action; never silently fall back to coordinates.
5. Test replacement, ambiguity, virtualized-node recycling, navigation, frame
   changes, content-world mismatch, overlays, and post-resolution layout change
   in deterministic local fixtures.
