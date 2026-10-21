# WebKitUI MCP catalogue launch packet

Prepared 2026-10-20. Mission EF139C69-293E-4677-8178-C76E0D9D7951. Owner: Codex. Status: publication authorized and executed. GitHub connector assets are public; official Registry status is active; the Glama page is independently verified public. Search ranking/indexing and Docker qualification are not established.

Live Registry metadata: https://registry.modelcontextprotocol.io/v0.1/servers/io.github.lowrisk75%2Fwebkitui-mcp/versions/0.6.24

Live connector download: https://github.com/lowrisk75/webkitui-mcp/releases/download/v0.6.24/webkitui-mcp-0.6.24-macos-arm64.mcpb

Live Glama page: https://glama.ai/mcp/servers/lowrisk75/webkitui-mcp

Publication receipts are saved under `docs/diagnostics/2026-10-20-catalogue-{github,registry,glama}-receipt.json`. Original app release assets and notes were preserved. The preparation gates and plan below are retained as the reviewed packet; they do not mean approval is still pending.

## Copy to submit

**Name:** WebKitUI MCP — Native WebKit for Mac

**Short description:** Connect AI agents to native WebKit on Mac, with persistent sign-ins and human approval.

**Description:** Give your AI agent a native WebKit browser on your Mac. WebKitUI MCP supports website navigation, rendered-page inspection, bounded interaction with controls and authenticated downloads. Persistent WebKit profiles retain sign-ins, while native confirmations and human handoff keep you involved in browser actions and private steps. Safari sign-ins are separate and are not imported. Requires an Apple silicon Mac with macOS 15 or later and the running WebKitUI MCP companion app. Developer Preview; source available under Business Source License 1.1. Commercial production use requires a separate agreement.

**Categories:** Browser Automation; Developer Tools.

**Glama's two-sentence field:** Native WebKit browser automation for MCP agents on Apple silicon Macs (macOS 15+), with persistent sign-ins, human approval and local handoff. Runs locally through a companion app; Developer Preview under BUSL-1.1, with a separate agreement required for commercial production use.

**Repository / destination:** https://github.com/lowrisk75/webkitui-mcp

**Download / installation:** https://github.com/lowrisk75/webkitui-mcp/releases/tag/v0.6.24

Machine-readable source: `Support/Catalogue/listing.json`. Do not describe the BUSL release as OSI open source, claim Safari cookie access, publish unmeasured speed/memory advantages, or promote dirty-checkout features as shipped.

## Channels

| Channel | Candidate | Remaining dependency |
| --- | --- | --- |
| Glama | GitHub repository listing, short Glama copy above | Submitted once; public page independently observed. Docker qualification and search placement unverified. Auto-assigned Browser Automation and Agent Orchestration categories. |
| Official MCP Registry | `io.github.lowrisk75/webkitui-mcp`, version `0.6.24`, generated `dist/catalogue-0.6.24/server.json` | Published and independently verified active/latest; public MCPB hash matches. |
| Smithery | Same signed local-relay MCPB, name `lowrisk75/webkitui-mcp` if available | Namespace/account verification and final approval; optional second wave, no remote endpoint |

The official Registry is a metadata registry, not artifact hosting. The proposed release asset URL in `server.json` is intentionally not yet live. A schema-valid candidate is not an accepted listing. Glama's automated Linux/Docker health checks cannot establish this macOS app's runtime quality. Do not add a fake Linux Docker deployment to obtain a badge.

## Approval packet for the external steps

**Identity:** GitHub owner `lowrisk75`; product WebKitUI MCP; publisher namespace `io.github.lowrisk75`. Glama account identity must be verified after login, not inferred from the repository owner.

**GitHub action:** Add the generated `webkitui-mcp-0.6.24-macos-arm64.mcpb` plus distinct `MCPB-SHA256SUMS` and `MCPB-PROVENANCE.json` assets to release `v0.6.24`. Preserve the original app ZIP, release tag, app checksum file and release notes. This is a new connector distribution artifact, not a new app version. Use the generated exact hash in `dist/catalogue-0.6.24/provenance.json` when requesting approval. No source push is needed for that asset upload.

Prepared MCPB SHA-256: `9b080516c5cf9977094fc3839b508bc5a7dfa95b0efccb62eafe2bd02ae04afb`. GitHub CLI identity observed as `lowrisk75`. The Glama form is accessible after human login/onboarding; its linked GitHub publisher identity has not yet been independently checked.

**Registry action:** Publish generated `server.json` to https://registry.modelcontextprotocol.io after verifying the uploaded asset hash. Content is the prepared title, short description, repository, version, stdio package URL and SHA-256. Immediate public metadata publication. Correction is a registry status update or replacement version under the publisher's current rules; no assumption of history erasure.

**Glama action:** Submit the public GitHub repository, title and copy above for indexing. Public discoverability and automated repository scanning may follow. No paid hosting, GitHub App permission grant, remote browser hosting or access to private projects is included. Correct the listing through its owner interface if needed. Ownership may use the personal GitHub account; `glama.json` is prepared locally but not pushed.

**Timing:** after review of this packet and account verification. Each final submit requires fresh approval under the commercial skill. Do not execute shell snippets from this document as implied approval.

## Distribution validation

The app archive retrieved from the public release has SHA-256 `9e3457301514015a47552c2f7abe7643e796b55664c6298f089acce554cfad43`. Strict deep code-sign verification passed; the bundle identifies Developer ID team `TDV6D5L785`, arm64 and a stapled notarization ticket. This is signature/ticket inspection, not a fresh clean-Mac installation test or a fresh Gatekeeper verdict.

The connector copies the original signed relay bytes and licence files without a Swift rebuild. Its MCPB manifest requires macOS; the accompanying copy additionally states macOS 15+ and Apple silicon. It connects to the running app's default socket and does not launch, install, replace, restart or re-sign the app. A broker-available workflow remains a prerequisite.

Generate locally with:

```bash
python3 scripts/package-catalogue.py /path/to/WebKitUI-MCP-0.6.24-notarized.zip
```

Output: `dist/catalogue-0.6.24/`. The original archive hash is pinned; a mismatching archive is refused. Packaging is deterministic. The new outer MCPB has no separate notarization; the relay's original signature remains intact. MCP client installation and real-browser activation remain separate checks.

## Demonstration: 45-second recording plan

This is a recording script, **not a claim that a live demo video has been recorded**. Record only a dedicated public test task with no private browser tabs, notifications, URLs, sign-ins or user data. Use the released 0.6.24 app; do not demonstrate later local features under that version label.

| Time | Actual screen to record | Caption |
| --- | --- | --- |
| 0–5 s | Title card | Your agent. A native Mac browser. You stay in control. |
| 5–12 s | Companion open; generic MCP client starts one new session | Native WebKit on your Mac. |
| 12–22 s | Request `https://example.com`; show real native confirmation and a deliberate human approval | Review the destination before navigation. |
| 22–32 s | Rendered Example Domain page and the corresponding bounded MCP observation | Let the agent inspect the rendered page. |
| 32–39 s | Transfer that task into the real human-control window | Take over when a step needs you. |
| 39–45 s | Closing card with repository and requirements | WebKitUI MCP · macOS 15+ · Apple silicon · Developer Preview |

No fake terminal results, fabricated receipts, claims of backend saving, or simulated approval clicks. The vector cover `Support/Catalogue/cover.svg` is promotional artwork, not an app screenshot. Final recording remains pending a dedicated live session without interrupting another mission's installed app.

## Acquisition experiment

Target: developers already using MCP clients on Apple silicon who need browser work with persistent sign-ins and local human intervention. Offer: a Developer Preview plus the exact installation guide. Start with the official Registry and Glama; defer paid promotion.

Observe for 14 days after both listings become live. Keep channel-tagged links only where accepted by the directories. Record listing visits if available, release-asset downloads (which may include bots/repeats), explicit user reports of a successful first browser task, support friction and opt-in repeat use. No hidden product telemetry is introduced.

Primary activation: a new user successfully opens a session, approves navigation to a public page and obtains a rendered observation. Track self-reported channel separately from measured referrals. Raw GitHub download counts are not unique users or proof of activation. Baseline and attribution are currently unavailable.

Decision: fix repeated installation blockers before expanding. At 14 days, retain useful listings; expand promotion if at least five independently confirmed new users complete activation. Fewer than five activations with at least 50 attributable visits calls for installation/copy review; fewer visits leaves reach inconclusive. These are proposed experiment thresholds, not performance forecasts.

## Primary sources checked

- [Official Registry package types](https://github.com/modelcontextprotocol/registry/blob/main/docs/modelcontextprotocol-io/package-types.mdx)
- [Registry publishing quickstart](https://github.com/modelcontextprotocol/registry/blob/main/docs/modelcontextprotocol-io/quickstart.mdx)
- [MCPB manifest specification](https://github.com/modelcontextprotocol/mcpb/blob/main/MANIFEST.md)
- [Glama submission and ownership FAQ](https://glama.ai/mcp/faq)
- [Glama ownership metadata](https://glama.ai/blog/2025-07-08-what-is-glamajson)
- [Smithery publishing, including MCPB](https://smithery.ai/docs/build/publish)
- [Public WebKitUI 0.6.24 release](https://github.com/lowrisk75/webkitui-mcp/releases/tag/v0.6.24)
