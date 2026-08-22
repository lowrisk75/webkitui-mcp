# Cloudflare Browser Run gap analysis — 2026-08-21

## Decision

Cloudflare Browser Run is the strongest newly verified infrastructure reference for agent browsers. WebkitUIMCP should adopt its human handoff and auditable-session ideas, but not its raw model-authored CDP authority model. The products optimize different layers: Cloudflare for remote scale and generality; WebkitUIMCP for local authenticated-session fidelity and verifiable writes.

## Local-first check

No Cloudflare Browser Run entry was found in the current DeepSearsh catalog. The prior WebkitUIMCP reports discuss hosted browsers generically but predate this April–August 2026 product surface.

## Evidence ledger

### VERIFIED — current primary sources

- Browser Run exposes headless Chrome through CDP, Puppeteer, Playwright, Quick Actions, MCP clients, and experimental WebMCP. It added Live View, human handoff, and rrweb session recording in April 2026. [Launch post](https://blog.cloudflare.com/browser-run-for-ai-agents/)
- The current Agents browser tool lets the model write sandboxed code against the complete live CDP surface. A durable runtime supports approval pauses and session modes `one-shot`, `dynamic`, and `reuse`. [Agents browser docs](https://developers.cloudflare.com/agents/tools/browser/)
- LLM-generated browser code runs in an isolated Worker without direct external network access; CDP traffic is proxied by the host and output is truncated to about 6,000 tokens. [Browser-agent security notes](https://developers.cloudflare.com/agents/examples/browser-agent/)
- Live View preserves the same tabs and cookies while a human performs login, MFA, CAPTCHA, or sensitive input, then hands control back. Its example keys UI tabs by stable CDP `targetId`. [Live View example](https://github.com/cloudflare/agents/tree/main/examples/browser-live-view)
- Recordings are opt-in structured rrweb events, retained 30 days, capped at two hours, and available only after session close. Inputs are masked by default; canvas, cross-origin frames, media, and WebGL are not captured. [Recording documentation](https://developers.cloudflare.com/browser-run/features/session-recording/)
- Cloudflare's edge WebMCP bridge can proxy a site's MCP server from the visitor's origin with existing same-origin credentials. The preview also explicitly marks decoded-but-unverified C2PA claims as `signatureVerified: false`. [WebMCP launch](https://blog.cloudflare.com/webmcp/)
- Current published service limits are operational, not agent-quality results: paid accounts default to 200 concurrent session browsers and three new instances per second; inactivity defaults to 60 seconds and can be extended to ten minutes. [Limits](https://developers.cloudflare.com/browser-run/limits/)

### CONTRADICTED / documentation drift

- The June browser-agent example still states one fresh session per execution and “no authenticated sessions.” Newer browser docs and the live-view example document durable `dynamic`/`reuse` sessions with preserved cookies. Treat the old limitation as stale documentation, not a current product fact.
- The April launch post says 120 concurrent paid browsers; the August limits page says 200. Use the dated limits page.

### OPEN — no measurement found

- No independent task-success result was found for Browser Run on WebArena, WorkArena, Web Bench, or an authenticated-write benchmark.
- No Cloudflare publication found separates stale-address, target-replacement, ambiguity, geometry, and logical-target-change failures.
- No controlled local-WebKit versus remote-Browser-Run latency, memory, or authenticated-session study was found.
- No causal evaluation found for Live View, recording, WebMCP, or model-authored CDP on write success.
- Cloudflare publishes service capacity and billing measurements, not end-to-end agent correctness.

## NotebookLM synthesis

The required WebKITUI MPC notebook was asked for measurements, blind spots, and missed opportunities. The separate LLM opportunity notebook was also queried.

### Supported by primary sources

- Cloudflare has substantially stronger session observability and human takeover than the current WebkitUIMCP prototype.
- The open-ended CDP tool offers much broader debugging and network visibility than public WKWebView APIs.
- Published agent-quality measurements are absent.

### Conjectural or rejected

- Claims that remote browsers systematically fail hardware-bound authentication were not accepted as universal. Cloudflare explicitly supports human login in durable sessions; passkey and device-posture behavior needs direct testing.
- Claims of near-100% local-WebKit authenticated-write success were rejected as unsupported.
- The second notebook's h5i memory figures and zero-copy framebuffer idea are leads only; they do not measure WKWebView or Browser Run.
- “Stateless MCP means no durable ledger” was rejected. Cloudflare Durable Objects can hold durable authority; the question is whether its browser tools implement transaction semantics, not whether the platform can.

## Capability comparison

| Capability | Browser Run | WebkitUIMCP now | Decision |
|---|---|---|---|
| Remote scale | 200 concurrent browsers published | One local session by default | Out of scope; do not compete |
| Arbitrary browser/debug access | Full model-authored CDP | No arbitrary JavaScript | Keep narrow write authority |
| Auth session | Durable remote reuse + human login | Native persistent WebKit store | Measure fidelity, do not assert victory |
| Human takeover | Live View, same session | Not yet exposed | P0 opportunity |
| Recording | rrweb replay, cloud retention | Transaction receipts/evidence | Add local provenance-aware audit trail |
| Write correctness | No transaction benchmark found | Preconditions, post-conditions, idempotency ledger | Preserve and benchmark |
| Addressing diagnosis | No five-way counters found | Five exact counters | Preserve as measurable contribution |
| WebMCP | Experimental Chrome support and edge bridge | None | Explore as untrusted optional adapter |
| Context control | Code Mode discovery + ~6k-token output cap | Six fixed MCP tools + deterministic observations | Borrow progressive read discovery only if measured |

## Prioritized opportunities

1. **P0 — local human handoff:** present the actual WKWebView in a real window, pause the run, explicitly transfer control, and resume only after a fresh observation. Never expose passwords or session tokens to the model.
2. **P0 — provenance-aware local recording:** record transaction phases, locator recipes, addressing counters, post-condition evidence, process termination, and human/agent control transitions. Do not record raw input values by default.
3. **P1 — optional WebMCP adapter:** discover page tools but classify descriptors/results as first-party site content, never trusted policy. Wrap state-changing calls in the same capability and transaction ledger as DOM actions.
4. **P1 — failure benchmark:** compare Cloudflare-style arbitrary CDP, Playwright locators, and WebkitUIMCP semantic recipes on DOM replacement, virtualized rows, layout drift, and ambiguous labels.
5. **P2 — read-only code plans:** evaluate a bounded, non-networked DSL for composing read operations. Do not allow generated code to invoke write capabilities or bypass provenance.

## Smallest defensible next slice

Implement a local handoff state machine and audit events before broadening MCP actuation beyond click. Required states: `agent_controlled`, `handoff_requested`, `human_controlled`, `resume_requested`, `freshly_reobserved`. Password fields remain omitted, and any observation made before human control expires.

### Implemented and locally measured after the research decision

- The runtime handoff test passed in 0.929 s: observation and dispatch were blocked during human control, the pre-handoff observation became stale, and the first post-handoff action required the returned fresh observation.
- The MCP handoff test passed in 0.637 s: decline retained human control; a later accepted, single-use response returned a fresh observation.
- The handoff audit encoded no fixture input value. This is a narrow fixture result, not a general secret-leak proof.

## Validation gates

- Prove agent actions cannot dispatch during human control.
- Prove resumption invalidates all pre-handoff observation IDs and locator caches.
- Prove the audit log contains no password/secret values.
- Kill the WebContent process during handoff and verify deterministic recovery state.
- Measure handoff and re-observation latency on this Mac.
- Do not claim Cloudflare superiority/inferiority without the missing controlled benchmark.
