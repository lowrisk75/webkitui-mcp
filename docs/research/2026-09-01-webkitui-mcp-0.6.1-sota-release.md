# WebKitUI MCP 0.6.1 — SOTA release decision packet

Date: 2026-09-01
Snapshot: `4ccca1cd988c52856056edd911087705b8244c2c` plus preserved local work
Scope: native macOS browser authority, human handoff, release positioning and
Developer Preview distribution. Research is not release proof.

## Executive decision

Proceed with 0.6.1 (601) as a free, clearly labelled Developer Preview after
the exact Developer ID, notarization, installed-runtime and public-byte gates
pass. Do not position it as a generic replacement for Safari MCP or a solved
prompt-injection system.

The defensible wedge is narrower: a persistent local WKWebView session for
authenticated workflows, explicit native human handoff, fail-closed semantic
actuation, transaction evidence and secretless credential boundaries. The
0.6.1 handoff fix is necessary for this promise, but physical validation and a
notarized public artifact remain open.

## Baseline and reused local research

| Label | Document | Origin / SHA-256 | Reuse and limitation |
|---|---|---|---|
| SUPPORTED | Goal Delegation and reliable browser addressing | `library/evidence-and-decisions/deepsearsh/2026-09-01-goal-delegation-and-browser-addressing-sota--f42f6a878e.md`; project and DeepSearsh inbox; `f42f6a878e4d6c8c419fea50b56e5fe0ce2a9cb0f778bf36b1cb730fbe679647` | Defines explicit human completion and typed authority. Predates the final 0.6.1 implementation evidence. |
| STALE | Competitors and safety research prompt | `library/market-and-competitors/webkitui-mcp/04-competitors-and-safety--912968a8c9.md`; project/public project; `912968a8c97fd9159a6b36d9eedc6731d845df1e41a03989eb434ff1a940da4a` | Useful question set, not an answered or current market report. |
| SUPPORTED | Commercial alignment V6 | `library/market-and-competitors/webkitui-mcp/commercial-alignment-v6--b6d3440b77.md`; audit output; `b6d3440b7770e5d1d8db50985856bb50d7092d9e3ab71f7ea944a64a93f8e81a` | Confirms that paid commerce was not ready. The 0.6.1 decision therefore removes payment from scope. |
| SUPPORTED | Security threat model | `library/security-and-privacy/webkitui-mcp/security-threat-model--c84ba7d207.md`; project; `c84ba7d207536cd17c8e4277dd0252ce449f2f6646241ec987a702c07f168de9` | Current design context, but final signed bytes and physical provider behavior still require revalidation. |

## Focused research plan and stop gates

Questions that change this release decision:

1. Does Apple now ship an overlapping Safari MCP? Stop when an official WebKit
   source establishes scope, runtime and privacy boundary.
2. Which browser-agent controls are currently expected? Stop when primary
   platform guidance establishes deterministic safeguards for authenticated
   sessions.
3. Can the release be promoted in `r/mcp`? Stop when current subreddit rules
   and recent comparable posts establish launch, disclosure and flair rules.

Out of scope: broad benchmark claims, paid pricing, cloud-browser parity,
commerce deployment, automated Reddit posting and claims of universal site
compatibility.

## Current evidence ledger

| Label | Claim | Current primary evidence | Limitation / consequence |
|---|---|---|---|
| VERIFIED | Safari 27 beta and Safari Technology Preview ship an Apple Safari MCP for web development, exposing DOM, network, screenshots, console and page-state tooling through `safaridriver --mcp`. | [WebKit, Introducing the Safari MCP server, 2026-07-01](https://webkit.org/blog/18136/introducing-the-safari-mcp-server-for-web-developers/) | It targets debugging and explicitly lacks access to Safari personal information. WebKitUI must not market mere WebKit/Safari control as unique. |
| VERIFIED | Apple's Safari MCP runs locally and sends captured page data to the chosen agent, not Apple. | Same WebKit source | Local execution alone is not a unique claim. WebKitUI's persistent authenticated session and native authority controls require their own evidence. |
| VERIFIED | Current Chrome guidance treats page tool definitions and outputs as untrusted, recommends origin restriction, token bounds, explicit confirmation and defense in depth, and says model-only protection cannot guarantee safety. | [Chrome for Developers, Agent security considerations for WebMCP, 2026-06-09](https://developer.chrome.com/docs/agents/security) | Guidance is not an independent audit of WebKitUI. It supports keeping deterministic native gates and avoiding “prompt injection solved” language. |
| VERIFIED | MCP authorization guidance requires audience binding and rejects token passthrough for protected HTTP resources. | [Model Context Protocol authorization specification](https://modelcontextprotocol.io/specification/2025-06-18/basic/authorization) | WebKitUI uses local transports for this preview; the principle supports session/audience binding but does not directly certify its handoff token. |
| VERIFIED | `r/mcp` permits self-promotion only after launch, requires disclosure, rejects AI-generated promotional slop and requires Showcase flair for authored work. | [Current r/mcp rules JSON](https://www.reddit.com/r/mcp/about/rules.json), checked 2026-09-01 | A draft is allowed locally; posting must wait until the release and landing page are live and needs separate approval. |
| SUPPORTED | Recent Showcase posts lead with a concrete problem, implementation details, limitations and direct disclosure rather than generic hype. | [Recent r/mcp listing](https://www.reddit.com/r/mcp/new.json?limit=25), checked 2026-09-01 | Community examples are signals, not rules or guaranteed performance. |
| VERIFIED | Current repository tests exercise a real AppKit button click and cross-server token lifecycle; the capability is session-bound, expiring, digest-only and single-use. | Current source/tests and `audit-output/webkitui-mcp-remediation-20260901T210245Z.md` | Corrected installed runtime, VoiceOver, notarization and public bytes are not yet proven. |

## SOTA capability and constraint matrix

| Area | Defensible 0.6.1 statement | Hard limit |
|---|---|---|
| Authenticated continuity | One long-lived local broker can preserve its WKWebView page across MCP transport reconnects. | Must be verified again on the signed installed candidate. |
| Human handoff | Native Done action produces explicit success/error state; resume authority is scoped, expiring and one-use. | Physical keyboard and VoiceOver paths are still open. |
| Actuation | Fresh semantic resolution, ambiguity rejection, native confirmations and postconditions reduce accidental mutation. | No browser agent can infer hostile page intent perfectly. |
| Secrets | Credentials stay behind the private credential broker boundary and sensitive auth origins restrict observation. | Public preview must not claim support for every credential provider. |
| Safari MCP comparison | Complementary: WebKitUI focuses on agent workflows and local authority; Apple's server focuses on Safari web debugging. | Do not claim to replace or outperform Safari MCP without comparable measurements. |
| Distribution | Free Developer Preview, Developer ID direct distribution, published hashes and provenance. | Unsigned local output is not a downloadable release. |

## Threat, privacy, accessibility and operations

- Treat all page text and site-provided tool metadata as untrusted data.
- Keep consequential actions behind deterministic confirmation and direct
  postconditions; natural-language goals never become authority.
- Bind handoff capabilities to the host session, expiry and single consumption;
  never persist raw tokens or include them in logs.
- Publish no claim about VoiceOver, keyboard recovery, Gatekeeper or same-session
  continuity until the signed installed candidate passes those exact gates.
- Preserve a rollback copy for installation, publish SHA-256 for final assets,
  and independently download and verify public bytes.

## Prioritized opportunities

1. P0: ship the handoff reliability patch as 0.6.1 after physical and Developer
   ID gates.
2. P0: publish a transparent limitations section and reproducible verification
   commands beside the download.
3. P1: measure authenticated task completion, reconnection recovery and prompt
   count on an opted-in provider matrix; do not generalize from one Apple page.
4. P1: add adversarial prompt-injection and cross-origin exfiltration evals tied
   to deterministic allow/deny outcomes.
5. P2: evaluate interoperability/complementarity with Safari MCP instead of
   duplicating its debugging surface.

## Validation gates and NO-GO blockers

| Gate | Binary criterion | Current state |
|---|---|---|
| Code/test | Full suites, formatting and shell contracts pass on 0.6.1 source. | In progress |
| Bundle | Exact Release preview verifies version/build, provenance, SBOM, locales and architecture. | In progress |
| Physical UX | Signed installed Done button works by click, keyboard and VoiceOver without losing the authenticated page. | OPEN |
| Security | Capability mismatch, expiry, replacement and replay remain fail-closed; final signed entitlements are inspected. | Partial |
| Release | Developer ID, Apple Accepted, staple, Gatekeeper and independent ZIP round-trip pass. | OPEN |
| Public | GitHub asset and LorisLabs page return the final bytes/claims; public hashes read back. | OPEN |
| Promotion | Live product exists; exact r/mcp draft, disclosure and Showcase flair rechecked immediately before posting. | OPEN |

NO-GO for publication while physical handoff, notarization, public-byte readback
or landing-page availability is absent. NO-GO for claims such as “secure”,
“prompt-injection proof”, “works on every site”, “faster than Chrome/Safari”, or
“SOTA” without a named, reproducible measurement.

NotebookLM status: `N/A`. No exact notebook URL or consent to upload this
packet to Google was supplied.
