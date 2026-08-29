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

The native app broker retains one host-owned registry across MCP transports. Each
transport gets a separate server authority surface, so clients may initialize
and discover tools concurrently without sharing observations, pending
approvals, transaction coordinators, or capability grants. They reuse the same
live browser handle; the main-actor runtime serializes browser state and a new
observation invalidates older addresses across clients. Direct stdio mode
remains process-scoped.

The `WKWebView` keeps one stable, opaque `NSWindow` owner for its entire
lifetime. The packaged WebKitUI MCP app starts the real AppKit event loop before it
accepts MCP work. During agent control the window is ordered out rather than
made nearly transparent; human handoff presents that same window and never
reparents the WebKit layer. Resume orders it out again before a fresh
observation. A LaunchServices smoke mode verifies the WindowServer pixels, not
only the DOM or `takeSnapshot` result.

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

The deterministic ten-tool surface is:

1. `browser_session`
2. `browser_navigate`
3. `browser_observe`
4. `browser_read_text`
5. `browser_scroll`
6. `element_scroll_into_view`
7. `browser_capture`
8. `browser_act`
9. `browser_fill_siliconpass`
10. `browser_transaction`

`browser_session(operation: "profiles")` lists only `default`, the proven
persistent data store used by this host. Opening accepts only that exact
identifier; cookies, origins, and credentials are never listed. The official
named-data-store enumeration API crashes in macOS 27 build 26A5416b, so UUID
profiles fail closed rather than risking the native host. A live durable browser
can be reused only with the same profile.

`browser_read_text` returns bounded body text and rendered scrollable/log-like
regions. Virtualized lines that are not currently in the DOM require an
explicit scroll and another read.

`browser_fill_siliconpass` sends only a fresh origin/document/physical-field
binding to the mutually authenticated SiliconPass broker. It never accepts a
credential value or submits the form. A `credential_not_found` receipt triggers
a native offer to continue under human control so the user can sign in and add
or update the credential in SiliconPass.

`browser_observe` filters before applying its element bound. Controls hidden by
HTML, a zero box, CSS display/visibility/opacity, `aria-hidden`, or `inert` are
absent. Visible fields classified by password/OTP autocomplete, sensitive
identifier, or opaque token-like value retain only `sensitive=true`; their
value is absent from the observation, canonical state, and locator recipe.
Selects expose the selected option's visible label instead of its technical
value.

`browser_navigate` requires a native, server-owned human confirmation bound to
the exact destination by default; `approval_mode: "mcp"` keeps modern
multi-round elicitation available as an explicit compatibility choice.
`browser_act` requires modern MCP multi-round human confirmation bound to the
exact arguments. Navigation additionally rejects URL
credentials, local names, and IP literals, then uses a private short-lived
origin-scoped capability. The approved top-level origin remains locked after
load. A cross-origin redirect is cancelled and returned as
`redirect_requires_human_approval` with canonical origins only; paths, query
parameters, and the underlying WebKit cancellation message are omitted. Human
handoff temporarily releases and then rebinds that lock.

`idmsa.apple.com` is a restricted authentication origin. Agent observation,
text reads, capture, scroll, actuation, and credential fill fail closed and
force the live view into human control. Agent resume is rejected until the
human leaves the origin. A bounded local probe returns only configuration
booleans and `auth_ui_not_ready` when the document is complete while a progress
indicator and only invisible authentication controls remain. It never returns
JavaScript messages, field metadata, URLs beyond the origin, cookies, storage,
or values. DNS rebinding remains
bounded for tested HTTP/TCP main-frame and fetch-subresource requests; HTTPS,
WebSocket, WebRTC, system IPC, and socket reuse remain unmeasured. Clicks route through fresh locator resolution,
capability authorization, the transactional ledger, and verified
postconditions. Legacy calls fail closed for both effect paths.
