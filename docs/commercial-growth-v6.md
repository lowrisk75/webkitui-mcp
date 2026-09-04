# WebKitUI MCP 0.6.0 V6 — production and growth plan

Date: 2026-08-30  
Status: **historical commercial draft superseded by the MIT 0.6.1 Developer
Preview strategy — no publication, outreach, account mutation or spend**

## Current truth

- Product: Developer Preview for Apple-silicon Macs running macOS 15 or later.
- Positioning: **Trusted Browser Writes for macOS**.
- Primary user: developers and agent teams that must perform low-volume,
  high-value actions in authenticated web consoles with local human approval.
- Evidence-backed outcome: bind an exact intent, approve it locally, dispatch,
  verify the resulting UI state and retain a redacted receipt.
- Not for: headless scale, scraping fleets, arbitrary JavaScript, anti-bot bypass
  or universal identity-provider compatibility.
- Current release strategy: free MIT Developer Preview focused on adoption and
  technical feedback; no license checkout or evaluation window.
- No verified sales or statistically useful funnel evidence exists yet.

## Dated distribution checkpoint

- Anonymous public read-back refreshed at `2026-08-30T20:56:52Z`.
- Public GitHub `main`: `ab3d8f6d19b34447e36b558a29362dbf61ed9947`.
- GitHub repository: public and active; anonymous API read-back reports zero
  Releases and zero tags.
- Public product URL
  `https://lorislab.fr/developers/webkitui-mcp/`: HTTP 404 at fresh read-back.
- An isolated, validated ten-file Hostinger candidate is recorded in
  [`website-deployment-v6.md`](website-deployment-v6.md); it has not been
  deployed.
- Historical signed V6 local ZIP SHA-256
  `ee0513115ea94ddad067fae71459418a4164fefbe7f2d36eee3d9a4d3135b5bd`
  is superseded for production by disclosure-aligned source manifest
  `54cc39ae5b43bf13b35fe9697a0288d75a6a826412fc4cae93e2285836c22faf`.
- V6 notarization, V6 installation and V6 clean-user acceptance are not done.
- The Official MCP Registry is in preview. It currently supports npm, PyPI,
  NuGet, OCI and MCPB packages; a plain macOS app ZIP is not a listed package
  type. MCPB can point to a GitHub/GitLab release artifact, but adopting MCPB
  requires a separate packaging and installation design.

## Production gates before promotion

1. Commit the exact disclosure-aligned source, rebuild it cleanly, then sign,
   notarize, staple and verify Gatekeeper for that new exact ZIP.
2. Close the credential-rotation gate and verify every old credential fails.
3. Install V6 recoverably, prove one broker, Dock reopen, activity journal,
   MCP connection, quit/relaunch and rollback without logout or restart.
4. Run clean-user install/uninstall and physical keyboard/VoiceOver checks.
5. Align the clean public source/tag with the exact released binary provenance.
6. Restore the product, support, privacy, terms, download and purchase pages;
   verify that every public URL returns the intended content rather than 404.
7. Finalize seller identity, commercial terms, renewal/cancellation, support,
   tax and privacy wording with qualified legal/accounting review.
8. Complete one test-mode purchase-to-activation-to-revocation canary before
   any live sale. A paid live canary remains a separate authorized gate.
9. Publish one dated compatibility matrix and one reproducible redacted demo.
10. Run the final independent release audit. Promotion begins only on GO.

## Message hierarchy

### One-line value proposition

WebKitUI MCP lets an AI agent perform sensitive browser actions on a Mac only
after local human approval, then verifies the visible result and records a
redacted receipt.

### Three proof points

- Local authority: authenticated WebKit session and confirmations stay on the
  user's Mac.
- Safer writes: stale or ambiguous targets fail closed; indeterminate actions
  are reconciled and never replayed automatically.
- Auditable outcome: the same transaction produces bounded machine-readable
  and human-readable redacted receipts.

### Claims to avoid

Do not claim “secure”, “zero tracking”, “exactly once”, “works on every site”,
“full browser compatibility”, “undetectable”, “best” or quantified savings.
Use the precise mechanisms and dated compatibility evidence instead.

## Launch sequence

| Order | Channel | Offer and destination | Activation event | Stop or iteration rule |
|---|---|---|---|---|
| 1 | Product page | 30-day Developer Preview and notarized download | successful `doctor`, then first observation | stop traffic if any URL, signature or install path fails |
| 2 | GitHub Release | exact V6 asset, checksum, limits and install steps | verified download plus successful setup | withdraw the launch if provenance or Gatekeeper differs |
| 3 | Existing users and opted-in contacts | factual release note with disclosed LorisLabs affiliation | qualified reply or successful evaluation | one message only; no unsolicited bulk follow-up |
| 4 | Relevant technical community | provider case study and redacted receipt, not a sales pitch | install, technical feedback or reproducible issue | stop after removal, negative rule signal or poor fit |
| 5 | Show HN, only when frictionless trial exists | runnable product, technical story and direct download | substantive feedback and completed evaluation | do not post until the author writes the submission personally and is available to answer |
| 6 | Official MCP Registry exploration | only after a safe supported package format exists | registry install and successful first session | do not publish experimental metadata; versions are immutable and cannot currently be unpublished |

The Official MCP Registry and every community submission are separate public
publication gates. Current rules must be read again immediately before use.

## Minimal measurement

Use consented, aggregate events only:

1. `product_view`
2. `download_start`
3. `doctor_pass` or bounded failure category
4. `first_observation`
5. `evaluation_week_1_active`
6. `checkout_start`
7. `paid_activation`
8. `refund_or_cancel`

Never send URLs visited through WebKitUI, page content, element labels,
credentials, cookies, keystrokes, receipts or activity-journal contents.

First 20 qualified evaluations are a learning cohort, not a scale campaign.
Review activation failures individually with consent. Revisit positioning or
onboarding if fewer than 10 of 20 reach `first_observation`; revisit pricing
only after at least five qualified purchase conversations or real checkouts.

## Ready-to-adapt owned-channel copy

### Product-page hero

**Trusted Browser Writes for macOS**

Let an AI agent bind a sensitive web action, ask for your approval on the Mac,
verify what changed and keep a redacted receipt. Developer Preview for
Apple-silicon Macs on macOS 15 or later.

Primary action: **Start the 30-day evaluation**  
Secondary action: **See how approval and verification work**

### Short release announcement

WebKitUI MCP 0.6.0 is a Developer Preview for human-approved browser writes on
Apple-silicon Macs. It keeps authenticated sessions local, fails closed on
ambiguous targets, reconciles indeterminate actions without automatic replay
and exports redacted transaction receipts. The release includes a notarized
app, checksum, install guide, limits and dated compatibility evidence.

### Technical-demo outline

1. Observe one authenticated console without exposing credentials.
2. Bind one exact, reversible UI action and its expected postcondition.
3. Show the native confirmation with the exact target and intent.
4. Perform the action and display the verified result.
5. Export the redacted receipt and show what is structurally absent.
6. Trigger an ambiguity fixture and show the fail-closed result.

## External approval packets still required

- Notarization: exact clean-commit V6 signed ZIP SHA-256 and exclusions.
- Installation: exact notarized ZIP SHA-256, target path and rollback.
- Website: exact repository/commit, paths and public URLs.
- GitHub Release: exact source commit/tag, asset SHA-256, title and notes.
- Community post: exact account, community, title/body/link/flair/time.
- MCP Registry: exact immutable `server.json`, package and version.
- Stripe/Worker/live sale: exact account, price, deployment and canary scope.

## Current sources

- MCP Registry quickstart: <https://modelcontextprotocol.io/registry/quickstart>
- MCP Registry package types: <https://modelcontextprotocol.io/registry/package-types>
- MCP Registry FAQ: <https://modelcontextprotocol.io/registry/faq>
- GitHub Releases documentation:
  <https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository>
- Show HN guidelines: <https://news.ycombinator.com/showhn.html>
