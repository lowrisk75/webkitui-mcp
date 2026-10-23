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
| Browser download | User-approved native save-panel destination; MCP receives only filename, response metadata, size, digest and optional decoded profile UUID | File remains only at the destination selected by the user | User removes the downloaded file; cookies, headers, body and absolute destination path are never serialized to MCP |
| Transaction ledger | Minimal plan, digests, phase and predicate evidence | HMAC-authenticated file, mode `0600`, profile-scoped; generation/head anchored in Keychain | Retained until explicit local profile/receipt removal; no automatic TTL; new writes fail closed at 10,000 records or 16 MiB |
| ReceiptV1 export | Redacted JSON and Markdown generated on request | Not automatically written by WebKitUI MCP | Caller chooses destination and removal |
| Credentials | Held by the separate signed credential boundary | SiliconPass/Keychain policy | Managed in the credential owner; never copied to observations, receipts or diagnostics |
| License lease | Product-bound signed token and masked status | macOS Keychain/local validation state | Deactivation/uninstall policy; never emitted in full by status or diagnostics |

Optional license activation, refresh and deactivation send only the entered
license key, the stable local machine identifier, the app version and the fixed
product identifier to `https://license.lorislab.fr`. The client uses an
ephemeral, cookie-free, cache-free session, rejects redirects, accepts only a
bounded JSON response from the same HTTPS origin, and does not send browser
content, profile data, credentials, observations or receipts. The signed lease
is stored in Keychain; the service's server-side retention and deletion terms
remain a publication/legal gate.

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

## Rendered text filtering and limits

Known credential fields and recognized credential configuration rows/form values
are filtered inside the browser before semantic observations, text reads and
locator facts are returned. Filtering includes aggregate names and ancestor text;
it does not trust a site's "Variable" label as proof a token is public. Public
configuration names/types and independent action controls remain visible where
they can be separated safely. Inventory limits fail closed instead of returning
unfiltered text. Sensitive-fill restrictions are not relaxed by this filter.

This is not a guarantee that every secret in arbitrary unstructured site content
or screenshots is detected. Do not serialize raw page payloads for diagnostics;
visual exports need their own review. Live provider markup must be qualified.

`observation_is_complete` covers discovered collector results, not proof that every
visible clickable control was discovered. `observation_completeness_scope` states
that limit explicitly. Truncation/opaque-frame/global postcondition gates remain.
Visible href-less anchors are candidates without an invented link role; a rendered
candidate or pointer cursor is not proof its handler will perform the desired action.

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
- **Site report** (Status window, "Report this site…", notice version 2026-10-22):
  a voluntary report in the LorisReports envelope shape. It carries the page's
  scheme and host, this app's version and build, macOS version, locale, the
  reason chosen from a fixed list, the person's own description, the load
  counters `browser_session diagnose` reports, and, when a visible label is
  given, the structure around that label: allowlisted tag names, roles and attribute *names*,
  fixed cursor/display categories and shadow-root membership. CSS class values and
  arbitrary custom tags/attribute names are omitted; hidden and sensitive matches
  are excluded. The global privacy inventory must complete, and artifacts are
  limited to 65,536 bytes each.
  It never carries page text, field values, attribute values, cookies, paths,
  query strings, titles, screenshots, receipts or any identifier of the
  session. The whole report is shown before a Mail draft to
  support@lorislab.fr is opened; the app has no sending path of its own. The
  files stay under `~/Library/Application Support/WebkitUIMCP/SiteReports/`
  with owner-only permissions until the person deletes them.

## Open product work

A signed UI for inspecting and explicitly removing profile-scoped receipt data
is still required before general availability. It must warn that deletion
removes local replay memory and must never be triggered remotely through MCP.
