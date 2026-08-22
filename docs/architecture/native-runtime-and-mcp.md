# Native runtime and MCP surface

## Runtime

`WebKitRuntime` owns one `WKWebView` on `MainActor`. Heavy canonicalization,
ranking, diffing, and policy work stays in the Sendable core types rather than
running synchronously on the UI actor.

- A named isolated `WKContentWorld` receives a document-start mutation monitor.
- Readiness requires document completion and host-clock mutation quiescence.
  It never waits for network idle or `requestAnimationFrame`.
- Observations cover full-page interactive elements, not only the viewport.
- Every observation mints a new observation ID and ephemeral `eN` symbols.
- Page strings carry provenance at serialization time. Password values are
  omitted; other form values are `USER_ENTERED_SITE_DATA`.
- Cross-origin frames are reported opaque rather than silently flattened.
- Snapshot dimensions are pixels and include a backing scale factor. A flag
  states that GPU-composited effects may be missing.

## Sessions

`WebKitSessionRegistry` has a hard count bound and unforgeable UUID handles.
The default maximum is one session for a 16 GB workstation. It uses WebKit's
default persistent data store for authenticated-session fidelity and does not
use deprecated `WKProcessPool` isolation.

Each registry-created session installs a loopback-only SOCKS5 proxy through
`WKWebsiteDataStore.proxyConfigurations`, disables failover, resolves each
hostname once, and pins the selected public numeric address for the session.
The runtime also rejects local names and private/reserved IP literals before
navigation because local WKWebView traffic was measured bypassing the proxy.
Only TCP CONNECT is accepted. The low-level data-store initializer remains an
explicitly unprotected embedding/test surface.

## MCP

The stdio server implements the official `2026-07-28` stateless wire shape and
legacy `initialize` compatibility. State is visible as a `session_id` argument,
never hidden in the transport connection.

The deterministic six-tool surface is:

1. `browser_session`
2. `browser_navigate`
3. `browser_observe`
4. `browser_capture`
5. `browser_act`
6. `browser_transaction`

`browser_navigate` and `browser_act` require modern MCP multi-round human
confirmation bound to the exact arguments. Navigation additionally rejects URL
credentials, local names, and IP literals, then uses a private short-lived
origin-scoped capability. The approved top-level origin remains locked after
load, so HTTP and JavaScript cross-origin redirects are cancelled; human
handoff temporarily releases and then rebinds that lock. DNS rebinding remains
bounded for tested HTTP/TCP main-frame and fetch-subresource requests; HTTPS,
WebSocket, WebRTC, system IPC, and socket reuse remain unmeasured. Clicks route through fresh locator resolution,
capability authorization, the transactional ledger, and verified
postconditions. Legacy calls fail closed for both effect paths.
