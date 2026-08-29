# Privacy and retention defaults

Date: 2026-08-29  
Scope: native macOS Developer Preview

WebKitUI MCP keeps browser state local. It does not upload screenshots,
observations, receipts, cookies or credentials to LorisLabs. An MCP client or a
user can explicitly export or copy data; that destination then owns its
retention policy.

| Data class | Native default | Persistence | Removal boundary |
| --- | --- | --- | --- |
| Screenshot capture | Returned once to the requesting MCP client | Not written to disk by the native runtime | Released from process memory after the response; client copies are caller-managed |
| Semantic observation | Bounded current-session representation | Memory only | Invalidated by the next observation, navigation, handoff transition or session close |
| Browser cookies and site storage | Local persistent WebKit profile when explicitly selected | Profile-scoped macOS storage | User removes the local profile; never included in diagnostics or exports |
| Transaction ledger | Minimal plan, digests, phase and predicate evidence | HMAC-authenticated file, mode `0600`, profile-scoped; generation/head anchored in Keychain | Retained until explicit local profile/receipt removal; no automatic TTL; new writes fail closed at 10,000 records or 16 MiB |
| ReceiptV1 export | Redacted JSON and Markdown generated on request | Not automatically written by WebKitUI MCP | Caller chooses destination and removal |
| Credentials | Held by the separate signed credential boundary | SiliconPass/Keychain policy | Managed in the credential owner; never copied to observations, receipts or diagnostics |
| License lease | Product-bound signed token and masked status | macOS Keychain/local validation state | Deactivation/uninstall policy; never emitted in full by status or diagnostics |

## Why transaction records have no automatic TTL

Deleting an idempotency record on a timer can silently re-authorize a replay of
an old real-world mutation. The Developer Preview therefore prefers replay
safety: minimal local records remain until the user explicitly removes the
profile or its receipts. This is not cloud retention and is not a reason to put
personal data in an idempotency key. Callers must use random opaque keys.

The ledger is integrity-protected, not content-encrypted independently of the
user account. File permissions and the macOS account boundary protect it at
rest. Full-disk encryption remains an operating-system/user configuration.
The ledger and its Keychain anchor form one anti-rollback state: deleting or
restoring only the file fails closed. An explicit reset must remove both and
must warn that doing so also removes local replay memory.

## Diagnostic rules

- `doctor` reports booleans, versions, paths and recovery actions, never cookie,
  credential, token, page-text or query-string values.
- Authentication-origin failures expose only the canonical origin.
- No support bundle may include browser profiles, raw screenshots, semantic
  observations, ledger files, Keychain items or environment dumps.
- A user must explicitly select every ReceiptV1 or screenshot shared for
  support. Redaction is rechecked after export, not inferred from the filename.
- Production telemetry is absent by default. Any future funnel instrumentation
  requires consent, a documented event schema and a separate privacy review.

## Open product work

A signed UI for inspecting and explicitly removing profile-scoped receipt data
is still required before general availability. It must warn that deletion
removes local replay memory and must never be triggered remotely through MCP.
