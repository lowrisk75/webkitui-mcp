# Review of the Cloudflare Browser Run independent report — 2026-08-21

Source reviewed: `~/Downloads/Cloudflare Browser Run pour agents LLM — état de la preuve indépendante au 21 août 2026.md` (135 lines).

## Accepted after primary-source verification

- No independent, reproducible Browser Run result was identified for WebArena, WorkArena, Web Bench, WebVoyager, BrowserGym, or authenticated writes. Feature compatibility is not benchmark evidence.
- `vitest-browser-run` is a useful same-contract harness for local Playwright versus Browser Run, with profiles from 96 to 1,536 scenarios, but its repository publishes methodology rather than an independent result table. It is Cloudflare-affiliated evidence.
- Cloudflare issue [#2134](https://github.com/cloudflare/agents/issues/2134), opened 2026-08-19, confirms Code Mode 0.5.1 approval classification is a static tool-level boolean and cannot depend on actual arguments before durable pause.
- This limitation is structurally important for a generic CDP connector: one `Runtime.evaluate` can hide several page effects behind one broad method. WebkitUIMCP's per-operation preflight and exact-argument-bound confirmation remain a meaningful safety distinction.
- The report's proposed experiments are well targeted: transport distributions, session/handoff recovery, stale-target taxonomy, approval red-team, and recording/WebMCP canaries.

## Corrected or not yet independently verified

- The report says Cloudflare does not document masking all inputs in recordings. The current official [Session recording documentation](https://developers.cloudflare.com/browser-run/features/session-recording/) explicitly says all input-field content is masked by default (line 209 in the live page). This is a vendor guarantee, not an independent leak test. DOM text, attributes, and URLs still need canary testing.
- The claim that the Browser CDP connector has no default `requiresApproval` is consistent with the supplied code review and current product behavior, but the pinned GitHub source file could not be fetched by the web verifier. Treat it as **supported, pending local source checkout or raw-file verification**, not fully closed.
- “Zero browser connector e2e CI coverage” was not independently rechecked in this pass and remains a lead.
- SSO, real passkeys, client certificates, VPN/device posture, and persistence after Browser Run expiry remain **open**, not unsupported.

## Changes to the WebkitUIMCP plan

1. Keep the fixed six-tool MCP surface; never add a raw JavaScript/CDP escape hatch to the authenticated-write path.
2. Add adversarial tests proving alternative invocation paths cannot bypass capability checks or post-conditions.
3. Build benchmark outputs as distributions with explicit engine/version/mode, not isolated headline numbers.
4. Use canaries to test the future local audit recorder for text, attributes, URL, input, password, and third-party-frame leakage.
5. If Cloudflare credentials are later authorized, extend the transport harness with the exact same fixture and commands; record tier, region, versions, errors, and reconnect outcomes.

## Evidence classification

- **Measured here:** 135 source lines read; the live Cloudflare recording page says all inputs are masked by default; issue #2134 says argument-aware approval is absent in Code Mode 0.5.1.
- **Source-supported:** the Vitest harness shape and profiles; absence of published independent results after the supplied research search.
- **Conjectural/open:** exploitability of default Browser CDP, actual Browser Run leakage, authenticated-session fidelity, and any performance superiority.
