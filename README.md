# WebKitUI MCP

Native WebKit automation for Apple Silicon, exposed through MCP and designed for an LLM rather than a human.

This repository is a Swift rewrite. The retained TypeScript/Playwright files are prior art only and are not the implementation being extended.

## What exists

- Native `WKWebView` runtime using the persistent system WebKit data store for real authenticated sessions.
- MCP 2026-07-28 stdio server with legacy initialization compatibility.
- Ten bounded tools, including explicit page/element scrolling and bounded text extraction for rendered virtualized logs.
- Observation-scoped element symbols backed by semantic locator recipes and fresh action-time resolution.
- Five separate addressing counters: `address_resolution_failed`, `address_now_ambiguous`, `logical_target_changed`, `node_replaced_but_semantic_locator_recovered`, and `coordinate_invalidated_by_layout_change`.
- Provenance attached to every serialized page string.
- Observation-time privacy minimization: non-rendered controls are removed
  before bounding, sensitive/token-like fields never serialize values, and a
  select exposes only its visible selected label.
- Checkpoint-plus-delta observation history and Minimal Failure Set coverage metrics.
- Optional local Ollama ranker with `think: false`, strict budgets, and deterministic fallback.
- Transaction ledger with preconditions, exact post-conditions, idempotency keys, indeterminate outcomes, receipts, and reconciliation without replay.
- Human confirmation before every exposed click and open-world navigation.
  Navigation defaults to a server-owned native macOS dialog so a client cannot
  silently decline the round trip; MCP multi-round navigation remains opt-in.
- Legacy MCP clients receive the same exact-action authority boundary through a
  server-owned native macOS confirmation dialog; the model cannot supply or
  forge the approval value.
- Local human handoff: `handoff_start` immediately returns an opaque session-bound resume token while the actual WebKit session becomes a visible window. `handoff_status` is non-blocking; `handoff_resume` consumes the token only after local confirmation and returns a fresh observation. The agent remains locked out throughout human control.
- The packaged handoff app installs a native Edit menu, so standard first-responder
  shortcuts such as Command-X/C/V/A work inside WebKit form controls.
- MCP sessions use a per-session loopback SOCKS5 boundary with failover disabled: hostnames are resolved once, public addresses are pinned, and private/reserved destinations plus non-TCP SOCKS commands fail closed.
- The production CLI enforces one browser controller across all local/remote MCP processes for the macOS account; the lease is released on close or process death.
- Private remote clients can use the app-owned broker plus a forced-command SSH relay; WebKit and authenticated profile data remain on the logged-in Mac.
- The app broker owns one live browser across MCP client reconnects. Every
  reconnect invalidates observations, pending approvals, capabilities, and
  transaction coordinators before returning the preserved session handle.
- The native host starts the AppKit event loop before MCP work and keeps the live
  `WKWebView` attached to one opaque window. Agent control orders that window
  out; human handoff presents the same view without reparenting it. A packaged
  visual smoke mode checks the actual WindowServer pixels.
- The stdio relay stays alive across broker restarts. It reconnects before the
  next undispatched request and never silently replays a request whose outcome
  became unknown during a restart.
- A secretless SiliconPass fill can return `credential_not_found`; WebkitUIMCP
  then offers a native human handoff for manual sign-in and addition/update in
  SiliconPass. No credential value crosses MCP, JSON, logs, or the clipboard.
- Web-content termination invalidates every observation immediately; recovery reloads the host-owned last URL without replaying an action. A forced-crash fixture verifies that an `HttpOnly` authenticated cookie plus `localStorage` and `sessionStorage` survive in the same view/data-store lifetime.

## Deliberate limits

- `browser_act` exposes click, native submit-control click, bounded non-sensitive input/textarea fill, Enter/Tab/Escape, blur, and explicit input commit. Fill verifies the freshly re-resolved semantic target's exact value; other actions require a transactional URL, exact/contains semantic text, checked, selected, enabled, value, bounded state-attribute, dialog, or selected-option postcondition. Contains matching stores SHA-256 plus bounded rolling parameters rather than plaintext in the transaction plan. UI state does not prove backend commit.
- Fill dispatches normal `input`/`change` events, so site handlers may autosave or cause server effects. It is destructive and human-confirmed; password controls require local human handoff.
- `approval_mode: "native"` sends confirmed click/submit and Enter/Tab/Escape through public AppKit `NSEvent` handling on the freshly re-resolved `WKWebView` target. An isolated message handler must observe the matching DOM event with `event.isTrusted == true` before the receipt reports trust. Missing/mismatched receipts fail indeterminate; no flag is synthesized. `approval_mode: "mcp"`, fill, blur, and commit remain JavaScript-dispatched and report untrusted.
- Action results separately expose `confirmation_mode`, `dispatch_mode`, and `trusted_gesture_state`. Native confirmation alone never establishes event trust.
- `browser_read_text` reads only currently rendered virtualized lines. Use bounded scroll plus another read for additional ranges.
- No arbitrary JavaScript, raw CDP escape hatch, coordinate retry, proxy fleet, anti-bot bypass, or headless claim.
- Cross-origin frame contents are opaque.
- Some identity providers require a complete browser surface and do not render
  inside an app-embedded `WKWebView`. The exact App Store Connect to Apple
  Account embedding returns `full_browser_required` with an internal
  `safari_compatibility` requirement. That backend is not exposed as a second
  MCP and currently fails closed until available. WebKitUI never copies cookies,
  passkeys, AutoFill data, or credentials between backends.
- `takeSnapshot` may omit GPU-composited effects.
- No exactly-once or rollback claim for an uncooperative website.
- Low concurrency is intentional because WKWebView has no per-view hard memory quota.
- The protected network path is the MCP session registry or `WebKitRuntime(protectedWebsiteDataStore:)`; the lower-level `WebKitRuntime(websiteDataStore:)` initializer is intentionally unprotected for fixtures and embedding.
- Proxy tests currently prove HTTP/TCP main-frame and fetch-subresource routing, pin reuse, local-address denial, and UDP-ASSOCIATE rejection. HTTPS, WebSocket, WebRTC, system IPC, and existing socket-pool behavior are not yet measured.

## Build and test

The product targets macOS 15+ on Apple silicon. Building the optional
`WKJSHandle` probe requires the macOS 27 SDK; those APIs stay feature-gated.

```bash
swift build -c release --arch arm64
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
swift test --arch arm64
swift test -c release --arch arm64
```

For a reproducible verification of the current checkout plus the signed local
installation and its two-client transport:

```bash
scripts/verify-native-installed.sh
```

Run the server:

```bash
swift run -c release --arch arm64 webkitui-mcp
```

Before registration, run the secret-free local readiness check:

```bash
webkitui-mcp doctor
```

It checks the native confirmation helper, local owner-authentication policy,
architecture, macOS version, and locally stored license state. It does not open
a website, read browser data or credentials, authenticate the user, or contact
the license service.

`webkitui-mcp --help` prints the stdio contract without starting the server.
The sibling `webkitui-mcp-confirm` helper owns legacy native dialogs so closing
an AppKit alert cannot terminate or corrupt the long-lived stdio server.

The process reads newline-delimited JSON-RPC from stdin, writes protocol responses only to stdout, and reserves stderr for diagnostics.

For a disposable direct process, install the CLI and register it normally:

```bash
release_bin="$(swift build --show-bin-path -c release --arch arm64)/webkitui-mcp"
release_dir="$(dirname "$release_bin")"
install -m 0755 "$release_bin" "$HOME/.local/bin/webkitui-mcp"
install -m 0755 "$release_dir/webkitui-mcp-confirm" "$HOME/.local/bin/webkitui-mcp-confirm"
codex mcp add webkitui-mcp -- "$HOME/.local/bin/webkitui-mcp"
claude mcp add --scope user webkitui-mcp -- "$HOME/.local/bin/webkitui-mcp"
```

For authenticated sessions that must survive Codex conversation reconnects,
build the self-contained app instead:

```bash
scripts/package-preview.sh dist
scripts/verify-package-preview.sh dist
```

Unzip `WebKitUI-MCP-0.6.0-preview.zip`, move `WebKitUI MCP.app` to the
Applications folder, and open it. In the status window:

1. Enable **Launch at Login**. macOS may require approval in System Settings.
2. Copy and run the Codex setup command. It points to the relay embedded in the
   app bundle and the owner-only local Unix socket.
3. Keep the app in Applications after registration so the saved relay path
   remains valid.

The app uses Apple's Service Management API and does not install a mutable
plist in `~/Library/LaunchAgents`. **Prepare to uninstall** disables Launch at
Login while preserving receipts and license data; then quit the app and move it
to the Trash. The preview archive is unsigned. Signing, notarization, clean-Mac
installation and publication are separate release gates.

Each MCP client receives isolated observations, confirmations, transactions,
and capability grants over the same durable browser. A logical
`browser_session close` detaches that client authority but deliberately keeps
the live browser; quitting the app destroys that in-memory page session.

Restart conversations opened before registration: MCP tool catalogs are fixed
for a running conversation and are not retroactively replaced.

## MCP flow

1. List the secretless persistent profile with `browser_session { operation: "profiles" }`, then `browser_session { operation: "open", profile_id: "default" }`.
2. `browser_navigate` opens a native exact-destination approval dialog by
   default. Use `approval_mode: "mcp"` only when the client reliably supports
   multi-round elicitation.
3. `browser_observe`; use `element_scroll_into_view` or `browser_scroll`, then observe again when needed.
4. Use the fresh `observationID` and `elementID` once.
5. For a login form, call `browser_fill_siliconpass`. If it returns
   `credential_not_found`, accept the native handoff and add or update the
   credential directly in SiliconPass.
6. `browser_act` returns `input_required`; approve the exact bound action.
7. Read, export as canonical `ReceiptV1`, or reconcile the receipt with
   `browser_transaction`. One redacted canonical object produces both JSON and
   Markdown; only the SHA-256 of the idempotency key is exported. Exported
   evidence never authorizes replay.

Large semantic pages can be read without oversized MCP results: `browser_observe`
supports role/name filters, `maximum_elements`, `maximum_field_characters`, and
`element_offset`; follow `nextElementOffset` until it is absent.
The enforced limits and the remaining release measurements are documented in
[`docs/performance-budgets.md`](docs/performance-budgets.md).
The authority boundaries, attack paths, current controls and residual release
gates are maintained in
[`docs/security-threat-model.md`](docs/security-threat-model.md).
Local data lifetimes and explicit-export boundaries are documented in
[`docs/privacy-retention.md`](docs/privacy-retention.md).
The stable diagnostic allowlist and forbidden support data are documented in
[`docs/support-diagnostics.md`](docs/support-diagnostics.md).

SiliconPass credential release is deliberately stronger than ordinary browser
confirmation. After the exact native fill summary is approved, macOS evaluates
`deviceOwnerAuthentication` uses zero Touch ID reuse and delegates the
available authentication method to macOS. WebKitUI does not infer that Touch ID,
Apple Watch, password fallback, or closed-lid authentication will be available
on a particular Mac. If the Mac is locked or authentication UI cannot be
presented, WebKitUI receives only
`user_presence_unavailable`: no secret is released and no automatic retry is
performed.

Restricted authentication origins such as `idmsa.apple.com` return only their
canonical origin and a local handoff requirement. Observe, text, capture,
scroll, credential fill, and actuation remain blocked until the human leaves
that origin. A cross-origin redirect is not reported as an ambiguous WebKit
failure: it returns `redirect_requires_human_approval` with source and target
origins only.

When App Store Connect embeds that restricted Apple Account origin, WebKitUI
returns `full_browser_required` instead of opening a known-stalled handoff
window. The single MCP reports the missing internal `safari_compatibility`
backend. Until that integration is implemented and physically verified, the
flow remains human-only and no Safari state is transferred.

Navigation blocks on an exact native macOS confirmation by default and returns
a normal terminal tool result. Human handoff is
two calls: the first transfers control to the visible window; after completing
the sensitive step, call `browser_session { operation: "handoff", ... }` again
and approve the native resume dialog. MCP 2026-07-28 clients continue to use
multi-round `input_required` results.

Use `browser_session { operation: "handoff" }` when a human must control the same local WebKit session. Declining resume leaves human control active.
The handoff window becomes a regular foreground Mac app with a Dock icon and
uses the same rendered view as semantic observation and capture.

## Linux headless lane

`linux/` is a separate, ephemeral Playwright worker for disposable workloads on
a dedicated Linux VM. It does not inherit Mac cookies or passwords and it does
not replace native WebKit. Route authenticated sessions and human handoff to the
Mac; route public, unauthenticated headless work to Linux. See
[`linux/README.md`](linux/README.md) and
[`docs/architecture/linux-headless-worker.md`](docs/architecture/linux-headless-worker.md).

## Evidence

- Architecture: [`docs/architecture/`](docs/architecture/)
- Private remote transport and deployment gates: [`docs/architecture/private-remote-transport.md`](docs/architecture/private-remote-transport.md)
- Dated research and NotebookLM audits: [`docs/research/`](docs/research/)
- Same-Mac runtime benchmark: [`Benchmarks/README.md`](Benchmarks/README.md)
- Public/private publication boundary: [`docs/architecture/public-private-boundary.md`](docs/architecture/public-private-boundary.md)
- Vulnerability reporting and release invariants: [`SECURITY.md`](SECURITY.md)

The first measured local lane uses 30 runs of the same deterministic fixture at 2560×1600. It compares WKWebView with Playwright 1.61.1 driving installed Chrome 151. It does **not** yet measure full process-tree memory, visible-window behavior, authenticated task success, or Playwright's pinned Chromium binary; no broader superiority claim is made.

## Licensing

Future versions first distributed with this checkout's [`LICENSE`](LICENSE) use
the Business Source License 1.1. Personal noncommercial use, qualifying
noncommercial organizations, non-production development and testing, and a
bounded evaluation period are permitted. Other commercial production use
requires a written LorisLabs commercial license.

The intended Team offer is EUR 299 per organization per year for up to five
authorized developers. After purchase, activation is performed locally:

```bash
webkitui-mcp license activate WEBKITUI-XXXX-XXXX-XXXX-XXXX
webkitui-mcp license status
```

The key and signed entitlement are stored in the macOS Keychain with
device-only accessibility. Status output is masked, and the MCP protocol never
receives or exposes the commercial license key. In this Developer Preview the
entitlement is verified evidence, not a capability gate; commercial rights
still come only from the separate written agreement.

This change is not retroactive: revisions already published under MIT remain
MIT. Each BSL version converts to Apache-2.0 on its Change Date. See
[`LICENSING.md`](LICENSING.md) for the exact boundary, intended launch policy,
and unresolved legal publication gates.

## Safety

The model cannot mint capability handles. Page content never becomes trusted policy. Password values are omitted from observations. Unknown dispatch is indeterminate and is never automatically retried. No commit, push, deployment, or external account mutation is performed by the project itself.
