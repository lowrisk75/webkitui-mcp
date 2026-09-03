# Network boundary contract

Date: 2026-08-30
Applies to: native macOS WebKit runtime

WebKitUI MCP is not a complete per-process network sandbox. The protected
runtime provides a narrower, testable boundary for ordinary WebKit website
traffic:

- top-level `http` and `https` navigation rejects local names and non-public IP
  literals before WebKit receives the request;
- the per-session `WKWebsiteDataStore` uses one loopback SOCKSv5 proxy with
  failover disabled;
- the proxy resolves a hostname once, pins the numeric address, rejects a
  non-public resolution and permits TCP CONNECT only;
- SOCKS UDP ASSOCIATE is rejected.

Deterministic fixtures verify HTTP main-frame and fetch traffic, repeated TCP
pin reuse, HTTPS TLS-attempt routing, WebSocket handshake-attempt routing,
local-address denial and UDP rejection. A routed attempt proves that WebKit
reached the proxy; it does not prove remote TLS or WebSocket success.

The boundary does not claim control over WebRTC/ICE, system-mediated IPC,
Apple Pay, passkeys, OS services, extensions, another process, or a connection
pool created outside the configured data-store lifetime. Those paths are not
part of the public-only egress guarantee. Do not load an untrusted page when
complete private-network isolation depends on blocking those channels; use an
OS-enforced network sandbox or isolated machine instead.

The lower-level `WebKitRuntime(websiteDataStore:)` initializer is deliberately
unprotected for fixtures and embedding and must never be described as protected
egress. Marketing, support and release notes may claim only the mechanisms and
fixtures listed above.
