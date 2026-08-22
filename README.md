# WebkitUIMCP

Native WebKit automation for Apple Silicon, exposed through MCP and designed for an LLM rather than a human.

This public repository contains the reusable engine, tests, architecture, sanitized research, and reproducible benchmarks. Private infrastructure endpoints, authenticated-site evidence, incident material, credentials, and user data are intentionally excluded and belong to a separate access-controlled companion repository; secrets never belong in either Git repository.

This repository is a Swift rewrite. The retained TypeScript/Playwright files are prior art only and are not the implementation being extended.

## What exists

- Native `WKWebView` runtime with an isolated ephemeral WebKit data store per MCP session; authentication remains available for that session without crossing project boundaries.
- MCP 2026-07-28 stdio server with legacy initialization compatibility.
- Six bounded tools: `browser_session`, `browser_navigate`, `browser_observe`, `browser_capture`, `browser_act`, and `browser_transaction`.
- Observation-scoped element symbols backed by semantic locator recipes and fresh action-time resolution.
- Five separate addressing counters: `address_resolution_failed`, `address_now_ambiguous`, `logical_target_changed`, `node_replaced_but_semantic_locator_recovered`, and `coordinate_invalidated_by_layout_change`.
- Provenance attached to every serialized page string.
- Checkpoint-plus-delta observation history and Minimal Failure Set coverage metrics.
- Optional local Ollama ranker with `think: false`, strict budgets, and deterministic fallback.
- Transaction ledger with preconditions, exact post-conditions, idempotency keys, indeterminate outcomes, receipts, and reconciliation without replay.
- Human confirmation through MCP multi-round tool results before every exposed
  click and open-world navigation.
- Legacy MCP clients receive the same exact-action authority boundary through a
  server-owned native macOS confirmation dialog; the model cannot supply or
  forge the approval value.
- Local human handoff: the actual WebKit session becomes a visible window for login, MFA, CAPTCHA, or sensitive input; the agent is locked out until confirmed resume and fresh re-observation.
- MCP sessions use a per-session loopback SOCKS5 boundary with failover disabled: hostnames are resolved once, public addresses are pinned, and private/reserved destinations plus non-TCP SOCKS commands fail closed.
- Each client can hold up to eight isolated browser sessions, and independent local/remote MCP clients can run concurrently. Every session owns its WebKit runtime, proxy boundary, cookies, storage, observations, transactions, and human-control window.
- Private remote clients can use the Aqua LaunchAgent broker plus a forced-command SSH relay; WebKit and authenticated profile data remain on the logged-in Mac.
- Web-content termination invalidates every observation immediately; recovery reloads the host-owned last URL without replaying an action. A forced-crash fixture verifies that an `HttpOnly` authenticated cookie plus `localStorage` and `sessionStorage` survive in the same view/data-store lifetime.

## Deliberate limits

- `browser_act` exposes click, native submit-control click, and bounded non-sensitive input/textarea fill. Fill verifies the freshly re-resolved semantic target's exact value; click/submit require an exact URL or newly appearing semantic text. UI state does not prove backend commit.
- Fill dispatches normal `input`/`change` events, so site handlers may autosave or cause server effects. It is destructive and human-confirmed; password controls require local human handoff.
- Actions are JavaScript-dispatched and report `trustedUserGesture: false`; they cannot satisfy browser APIs requiring physical user activation.
- No arbitrary JavaScript, raw CDP escape hatch, coordinate retry, proxy fleet, anti-bot bypass, or headless claim.
- Cross-origin frame contents are opaque.
- `takeSnapshot` may omit GPU-composited effects.
- No exactly-once or rollback claim for an uncooperative website.
- Concurrency is deliberately bounded to eight sessions per client because WKWebView has no per-view hard memory quota.
- The protected network path is the MCP session registry or `WebKitRuntime(protectedWebsiteDataStore:)`; the lower-level `WebKitRuntime(websiteDataStore:)` initializer is intentionally unprotected for fixtures and embedding.
- Proxy tests currently prove HTTP/TCP main-frame and fetch-subresource routing, pin reuse, local-address denial, and UDP-ASSOCIATE rejection. HTTPS, WebSocket, WebRTC, system IPC, and existing socket-pool behavior are not yet measured.

## Build and test

Requires the macOS 27 SDK for the current `WKJSHandle` probe.

```bash
swift build -c release --arch arm64
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
swift test --arch arm64
swift test -c release --arch arm64
```

Run the server:

```bash
swift run -c release --arch arm64 webkitui-mcp
```

`webkitui-mcp --help` prints the stdio contract and `webkitui-mcp --version`
prints the traceable server version without starting the server.
The sibling `webkitui-mcp-confirm` helper owns legacy native dialogs so closing
an AppKit alert cannot terminate or corrupt the long-lived stdio server.

The process reads newline-delimited JSON-RPC from stdin, writes protocol responses only to stdout, and reserves stderr for diagnostics.

Install the ARM64 binary and register it for future local sessions:

```bash
release_bin="$(swift build --show-bin-path -c release --arch arm64)/webkitui-mcp"
install -m 0755 "$release_bin" "$HOME/.local/bin/webkitui-mcp"
codex mcp add webkitui-mcp -- "$HOME/.local/bin/webkitui-mcp"
claude mcp add --scope user webkitui-mcp -- "$HOME/.local/bin/webkitui-mcp"
```

Restart conversations opened before registration: MCP tool catalogs are fixed
for a running conversation and are not retroactively replaced.

## MCP flow

1. `browser_session { operation: "open" }`
2. `browser_navigate` returns `input_required`; approve the exact destination.
3. `browser_observe`
4. Use the fresh `observationID` and `elementID` once.
5. `browser_act` returns `input_required`; approve the exact bound action.
6. Read or reconcile the receipt with `browser_transaction`.

With a legacy MCP client, navigation and actuation block on an exact native
macOS confirmation and return a normal terminal tool result. Human handoff is
two calls: the first transfers control to the visible window; after completing
the sensitive step, call `browser_session { operation: "handoff", ... }` again
and approve the native resume dialog. MCP 2026-07-28 clients continue to use
multi-round `input_required` results.

Use `browser_session { operation: "handoff" }` when a human must control the same local WebKit session. Declining resume leaves human control active.
OAuth and popup-gated actions must be clicked by the human after handoff; an
agent-generated JavaScript click remains intentionally untrusted. During human
control, HTTP(S) `target=_blank` and `window.open` requests are followed in the
same visible, observable WebKit view. Popup requests remain denied while the
agent controls the session.
Each handoff window becomes a regular foreground Mac app with a Dock icon and
the current site in its title. The Dock remains active while any session is
under human control. If
handoff is requested before navigation, it shows an explicit empty-page message
instead of a blank browser surface.

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

## Safety

The model cannot mint capability handles. Page content never becomes trusted policy. Password values are omitted from observations. Unknown dispatch is indeterminate and is never automatically retried. No commit, push, deployment, or external account mutation is performed by the project itself.

Please report vulnerabilities through GitHub private vulnerability reporting as described in [`SECURITY.md`](SECURITY.md).
