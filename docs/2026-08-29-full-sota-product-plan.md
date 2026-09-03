# WebKitUI MCP — FULL SOTA product plan

Date: 2026-08-29
Status: historical checkpoint; its commercial-license assumptions were
superseded by the MIT 0.6.1 Developer Preview decision on 2026-09-03. Physical,
signed and live release gates remain open; no publication or release implied.

Evidence ledger:
`audit-output/webkitui-mcp-remediation-20260829T075000Z.md`.

## Product thesis

WebKitUI MCP is **Trusted Browser Writes for macOS**: a local browser runtime
for sensitive, human-authorized web actions where an agent must bind an exact
intent, obtain native approval, dispatch a real trusted gesture when the site
requires one, verify the resulting UI state, and preserve a useful receipt.

The product does not try to replace Playwright, Selenium or cloud browsers for
high-volume automation. Its defensible category is low-concurrency, high-value
browser writes on a user's Mac, especially in authenticated consoles where
authority, replay safety and evidence matter more than throughput.

## Truthful public contract

- Developer Preview; macOS 15+ on Apple silicon. macOS 27-only probes and
  enhancements remain feature-gated.
- MIT Developer Preview with no evaluation time limit, seat limit or
  commercial-use restriction.
- No claim of exactly-once execution, universal site compatibility,
  undetectability, anti-bot bypass or absolute security.
- Indeterminate writes are reconciled and never blindly replayed.
- Provider behavior is compatibility evidence, not a permanent guarantee.
- Credentials remain in SiliconPass and are released only after fresh local
  user authentication; browser tools never receive the secret value.

## Current evidence

- Native WebKit runtime and MCP surface exist locally.
- Exact approval, native AppKit dispatch, postconditions, transaction receipts,
  handoff and reconciliation have automated coverage.
- `webkitui-mcp doctor` reports local helper, OS/architecture, credential
  authorization availability and license state without network access, browser
  access or credential release.
- Google Play Console exposed real gaps in trusted gesture dispatch, styled
  controls, nested scrolling, keyboard commit, reconciliation and payload size;
  those findings remain the provider acceptance baseline.
- Stripe and Cloudflare infrastructure have been prepared separately, but legal
  identity, public terms, fulfillment canary and publication remain independent
  release gates.
- No verified customer sales or statistically useful funnel data are available.

## P0 — proof before promotion

- [ ] Maintain one provider proof matrix with exact version/date and independent
  read-back for Stripe, Google Play Console and Cloudflare.
- [ ] Demonstrate one complete receipt: bound intent → native approval →
  `trustedUserGesture: true` → native dispatch → direct UI postcondition →
  independent external evidence.
- [x] Test every state postcondition: checked, selected, enabled, attribute,
  value, dialog appearance and selected option.
- [x] Test keyboard commit, explicit blur, closest-scroll-container behavior and
  hidden Material control wrapper resolution.
- [x] Prove that an indeterminate mutation is not replayed.
- [x] Bound semantic observations server-side by role, name, visibility and text
  budget; prove hidden dialog content is excluded when requested.
- [ ] Publish a dated compatibility matrix that distinguishes verified,
  degraded, handoff-required and unsupported flows.

Exit gate: a clean Mac can reproduce the three provider journeys from a written
script, with redacted receipts and no secret in MCP logs.

## P0 — activation and user authority

- [x] Add a secret-free `webkitui-mcp doctor` command.
- [x] Document device-owner authentication without promising a particular
  Touch ID, Apple Watch, password or closed-lid method before physical proof.
- [x] Return fail-closed recovery metadata when user presence is unavailable;
  release no secret and do not retry automatically.
- [ ] Add a first-run diagnostic experience that explains every failed check and
  links to one recovery action.
- [ ] Test interactive login, locked Mac, closed lid, Touch ID lockout, Apple
  Watch approval, password fallback, cancellation and timeout on physical Macs.
- [ ] Package install, update, uninstall and helper recovery into one signed,
  reversible flow.

Exit gate: a new user reaches the first verified read-only browser observation
in under ten minutes, or receives a precise local recovery instruction.

## P0 — commercial and legal truth

- [ ] Read back the exact existing Throttle seller identity and Stripe merchant
  identity; do not invent a new legal entity.
- [ ] Finalize commercial terms, privacy notice, renewal/cancellation rules,
  support scope and OEM/hosted-use boundary.
- [ ] Keep product page, Checkout, invoice, agreement and license claims exactly
  aligned.
- [ ] Run one paid live canary, cancellation/refund and entitlement revocation;
  verify no residual real entitlement remains.
- [ ] Instrument only consented, minimal funnel events: product view, evaluation
  start, checkout start, paid activation, activation failure and renewal state.

Exit gate: seller, price, taxes, renewal, fulfillment and revocation are
independently readable end to end. This gate requires fresh operation-specific
authorization for every external mutation.

## P1 — product experience

- [x] Replace capability lists with one proof-first interactive narrative:
  Bind → Approve → Dispatch → Verify.
- [x] Show “ideal for” and “not for” before pricing.
- [x] Offer a neutral comparison with Playwright MCP and cloud browser services:
  local human authority versus ecosystem breadth, scale and managed operations.
- [x] Export a stable, redacted JSON receipt and a human-readable Markdown
  receipt from the same canonical data.
- [ ] Add provider recipes with versioned locators, postconditions, failure
  recovery and expiration signals.
- [x] Make handoff resume tokenized, pollable and non-blocking; expose
  `control_state` in status.
- [x] Add performance budgets for cold start, observation size, action latency,
  memory and nested-list traversal.

## P1 — security and privacy

- [x] Threat-model confused deputy, approval substitution, stale observations,
  clickjacking, navigation races, replay, prompt injection and secret leakage.
- [x] Fuzz capability binding, canonical page digests, receipt redaction and
  transaction reconciliation.
- [x] Verify signed helper provenance and reject mismatched or downgraded
  components.
- [x] Define retention defaults for screenshots, observations and receipts;
  keep sensitive evidence local unless explicitly exported.
- [ ] Commission an independent review of the native gesture and credential
  boundary before removing Developer Preview.

## P1 — distribution and reliability

- [ ] Produce reproducible signed release artifacts, checksums, SBOM and
  third-party notices.
- [ ] Exercise clean install and upgrade from the previous public version.
- [ ] Run crash, WebContent termination, network loss and interrupted-handoff
  recovery suites.
- [x] Define support diagnostics that are secret-free by construction.
- [ ] Keep Swift product metadata canonical; retain JavaScript fixtures only as
  explicitly private legacy validation assets.

## P2 — measured expansion

- [ ] Validate pricing interviews and evaluation conversion before adding tiers.
- [ ] Consider a higher-priced OEM/hosted license only after Team demand is
  proven; do not grant redistribution through Team.
- [ ] Add providers only through the same dated acceptance matrix.
- [ ] Explore remote orchestration only if local authority, explicit approval
  and secret isolation remain intact.

## Public page acceptance checklist

- [x] Hero: “Trusted Browser Writes for macOS.”
- [x] Visible Developer Preview and macOS 15+ Apple-silicon requirement.
- [x] Primary CTA starts the evaluation; secondary CTA enters Team purchase.
- [x] Illustrative receipt is labeled as such and never presented as universal
  provider proof.
- [x] Trust boundaries and non-goals are adjacent to the proof.
- [x] Exact Team price, seats, Macs, term and scope are visible.
- [ ] Accessibility, reduced motion, keyboard navigation, canonical metadata and
  EN/FR content are verified.
- [ ] Product, buy and thank-you paths never disagree about availability.

## Product scorecard

Release decisions use evidence, not a blended vanity score:

- Safety: zero unauthorized or blindly replayed writes in the acceptance suite.
- Verifiability: every supported write has a direct state postcondition and a
  dated independent read-back recipe.
- Activation: median time to first verified observation and first verified
  write, with failure reason distribution.
- Reliability: success, indeterminate and handoff rates per provider/version.
- Privacy: zero credential values in MCP payloads, logs and exported receipts.
- Commercial: evaluation starts, qualified activations, paid conversions,
  refunds and renewals; missing data is reported as unknown, never zero.

## Definition of FULL SOTA for this product

FULL SOTA is reached only when the product has a narrow, reproducible advantage
in trusted local browser writes; physical-Mac authentication gates; dated
provider evidence; adversarial safety tests; a clean signed lifecycle; truthful
public claims; and an independently verified purchase-to-revocation path.
Research, local tests, a deployed checkout or a polished page alone cannot
satisfy that definition.
