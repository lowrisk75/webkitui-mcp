# Pinned egress proxy — 2026-08-22

## Primary API evidence

- Contrary to NotebookLM's first answer, `WKWebsiteDataStore.proxyConfigurations` is a public API since macOS 14 and accepts `Network.ProxyConfiguration` values.
- Network.framework publicly exposes SOCKSv5 and HTTP CONNECT proxy configurations, match domains, excluded domains, credentials, and failover control.
- No published WKWebView latency or agent-success benchmark for DNS-pinning proxy enforcement was found.

## Counter-audit

- A host-only DNS preflight remains TOCTOU because WebKit resolves independently.
- A local proxy must receive the hostname, resolve it itself, reject non-public results, and connect to the selected numeric address.
- SOCKS UDP associate must fail closed. WebRTC and other non-HTTP transports still require separate measurement because proxy coverage cannot be assumed.
- Pinning can hurt CDN failover; pins therefore belong to one browser session, not global persistent state.
- The opportunity notebook's prompt-cache routing and cryptographic cookie/IP claims are conjectural and are not adopted.

### Post-implementation NotebookLM audit

- **Sourced but not locally measured:** WebRTC ICE may use direct UDP rather than the data-store proxy. It remains outside the claimed boundary.
- **Conjectural:** system-mediated Apple Pay/passkey traffic and pre-existing shared-worker/socket reuse may bypass the proxy. The notebook supplied no direct measurement for this exact WKWebView configuration.
- **Rejected as unsupported:** the suggested `https://localhost:password@allowlisted-safe-domain.com` parser differential does not establish that WebKit and this proxy parse different hosts; the proxy receives WebKit's SOCKS destination rather than reparsing the original URL.
- The implementation now rejects SOCKS BIND/UDP before resolution and closes an already-established relay without writing a late SOCKS error into application data.

## Local measurements

- Raw SOCKS test: 2 TCP connections, 1 resolver call, 1 pinned host.
- A direct `127.0.0.1` WKWebView navigation bypassed the configured proxy (0 proxy connections); the protected runtime now rejects it before WebKit.
- WKWebView hostname test: 2 navigations through the proxy, 1 resolver call, 1 pin.
- HTTP fetch-subresource routing is also exercised through the configured data-store proxy.
- These tests cover HTTP/TCP only. HTTPS, WebSocket, WebRTC/UDP, system IPC, and socket-pool reuse remain unmeasured.

## Implementation target

- Per-session local SOCKSv5 proxy, no failover, hostname resolved once and pinned in memory.
- Reject local names, IP-literal private/reserved/link-local/multicast/documentation ranges, and every DNS answer set with no public address.
- TCP CONNECT only; reject BIND and UDP ASSOCIATE.
- Test policy classification, pin reuse, local-host denial, and WKWebsiteDataStore routing before claiming rebinding resistance.
