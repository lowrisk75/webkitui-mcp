# WebKitUI MCP security threat model

Date: 2026-08-29  
Scope: native macOS authority, MCP server, WebKit runtime, SiliconPass boundary,
transaction ledger, ReceiptV1 and optional private relay

## Assets and trust boundaries

Protected assets are browser session state, credentials, commercial
entitlements, exact user intent, transaction evidence and the right to dispatch
a native browser input. Page content and MCP caller text are untrusted. The
native confirmation process, macOS user-presence policy, credential broker and
authenticated local ledger are separate authority boundaries. A receipt is
evidence and never authority.

## Threat register

| Threat | Attack | Current control and evidence | Residual risk / release gate |
| --- | --- | --- | --- |
| Confused deputy | A caller reuses authority for another action, origin, field or value. | Capabilities bind action, canonical origin, input provenance and expiry. Native confirmation binds exact arguments and is single-use. Unit and MCP integration tests cover mismatches and reuse. | Physical provider matrix must prove the displayed summary is understandable under real dialogs. |
| Approval substitution | Approval UI describes A while dispatch performs B, or a stale approval is consumed. | Confirmation and dispatch have distinct receipts; the opaque state is exact-argument-bound, expires and is consumed before execution. The helper must be adjacent, strictly signed by the same non-empty Team ID and accept the current invocation protocol. | The final signed artifact and installer chain still require independent verification. |
| Stale observation / navigation race | DOM, document, origin or virtualized row changes between observation and action. | Observation-scoped symbols, document/origin checkpoints, fresh semantic re-resolution, ambiguity rejection and precondition recheck. Navigation invalidates authority. | Hostile same-origin UI can still change after final resolution; direct postconditions and independent provider evidence remain mandatory. |
| Clickjacking / overlay | A trusted native click lands on a different visible layer. | The runtime targets the visible styled wrapper, re-resolves immediately before AppKit dispatch and verifies state afterward. Hidden or ambiguous targets fail closed. | No generic browser can prove third-party visual intent. Provider canaries and handoff remain required for unexpected overlays or cross-origin frames. |
| Replay / local ledger rollback | An indeterminate write or exported receipt triggers the mutation again, or a valid older ledger is restored after a newer write. | One process-wide authority owns each profile-scoped ledger. The bounded durable ledger records dispatching before the action, crash-recovers to indeterminate, authenticates generation and predecessor linkage, and anchors its pending/committed head in Keychain. Missing, deleted, tampered or rolled-back state fails closed; reconciliation never replays. ReceiptV1 declares evidence-only replay safety. | Independent read-back is required before a new user-approved attempt. Removing both the ledger and its Keychain anchor is an explicit user reset that also removes replay memory. |
| Prompt injection | Page text instructs the agent to disclose data or call a dangerous tool. | Page content has untrusted provenance; no raw JavaScript evaluator is exposed by the native MCP; mutating tools require exact native approval; credential values never enter observations or MCP results. | The model can still propose a bad action. The human must judge the exact native summary; high-risk providers remain compatibility-gated. |
| Secret leakage | Credentials, idempotency material or sensitive fields escape through observations, logs, receipts or relay. | Password values are omitted; credential fill is a private signed boundary; semantic expected values use digests; ReceiptV1 hashes the idempotency key and exports evidence results only. Tests cover provenance redaction and adversarial receipt non-disclosure; retention and diagnostic allowlists are explicit. | Physical logs and user-selected exports must still be inspected before release. |
| Capability theft | A local peer copies a handle or reaches the broker directly. | Handles are random, bounded, origin/action-specific and insufficient without authority. XPC peer requirements pin production identities and keep custom peers separated. | Final signed identifiers and designated requirements need release-artifact verification. |
| Relay impersonation / SSRF | A relay reaches local/private networks or accepts an unauthorized controller. | Private transport uses authenticated controller leases, strict web-origin parsing, DNS/IP fail-closed policy and origin-scoped subresource capability. | Remote production operation is out of Developer Preview scope and requires a separate external review. |
| Entitlement forgery / rollback | An invalid token or clock rollback is presented as a valid commercial entitlement. | Signed product-bound leases require explicit version and active lifecycle claims; grace is available only to a previously valid token, the clock rollback guard fails closed, status checkpoints are bounded, and status is masked. Invalid tokens never reach secure storage. | The Developer Preview capabilities are not license-gated. Therefore this control validates entitlement evidence but does not yet enforce commercial authorization. Live purchase, capability gating, refund, revocation and renewal require exact deployment authorization and independent read-back. |

## Fail-closed invariants

1. Confirmation is necessary but is not itself a trusted browser gesture.
2. A native dispatch is not success until a direct postcondition is satisfied.
3. Unknown dispatch becomes indeterminate and is never automatically retried.
4. A fresh observation invalidates prior element symbols.
5. Authentication restrictions reveal only a canonical origin and recovery state.
6. Credentials never cross the MCP observation or receipt boundary.
7. Human handoff keeps control until an explicit tokenized resume succeeds.
8. Exported evidence cannot create, extend or replay authority.

## Open release work

- Verify helper signatures, Team ID equality and downgrade rejection again from
  the packaged signed artifact.
- Verify screenshot, observation, ledger and diagnostic retention on the signed
  installed artifact.
- Run physical locked-Mac, closed-lid, biometric lockout, cancellation and
  accessibility matrices.
- Commission an independent review of AppKit gesture dispatch, the
  SiliconPass boundary and provider-specific clickjacking behavior.
- Preserve dated redacted traces for every provider row; marketing may cite
  only rows with independent external evidence.
