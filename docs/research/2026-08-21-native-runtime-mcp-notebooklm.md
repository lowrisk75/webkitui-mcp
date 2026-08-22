# 2026-08-21 — Native runtime and MCP counter-audit

## NotebookLM queries

- Main notebook: measured native runtime limits.
- Main notebook: failure modes for a MainActor WebKit runtime, isolated
  instrumentation, bounded sessions, readiness, process recovery, and a small
  MCP surface.
- Main notebook: missed opportunities. This call repeated the previous answer,
  so it supplied no independent opportunity evidence.
- `LLM` notebook: missed opportunities for a native WebKit MCP runtime.

## Source-verified facts

- MCP `2026-07-28` is stateless at the protocol layer. Application state must
  use explicit handles. Modern stdio messages are newline-delimited JSON-RPC;
  stdout must contain no non-MCP output. Sources:
  [release](https://blog.modelcontextprotocol.io/posts/2026-07-28/),
  [stdio specification](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/basic/transports/stdio.mdx).
- Modern request metadata is in `params._meta`; result metadata, including
  `io.modelcontextprotocol/serverInfo`, is in `result._meta`. Every successful
  modern result has `resultType`. Source:
  [official schema](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/schema/2026-07-28/schema.ts).
- Tool lists should be deterministic and cacheable. Source:
  [tools specification](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/server/tools.mdx).
- The official Swift SDK is still pre-1.0 and its published release page refers
  to the older handshake-era protocol. The 2026 release announcement lists
  updated TypeScript, Python, Go, and C# SDKs, not Swift. The server therefore
  implements the small required wire subset directly and keeps legacy
  `initialize` compatibility.
- Apple's beta type is `WKDOMNodeSnapshot`, not `WKSerializedNode`. Source:
  [Apple documentation](https://developer.apple.com/documentation/webkit/wkdomnodesnapshot).

## Measured locally on 2026-08-21

- Eight native runtime tests passed in 0.769 s on arm64 after compilation.
- Five MCP wire tests passed in 0.073 s on arm64 after compilation.
- A 1280×800-point offscreen `WKWebView` snapshot produced a valid
  2560×1600-pixel PNG on this Retina configuration. The runtime now reports the
  backing scale factor explicitly.
- A real stdio process answered `server/discover` with one newline-delimited
  response and exited on stdin EOF.
- Password input values were absent from the encoded observation fixture.

## Conjectural or unmeasured

- There is still no same-page, same-Mac public WKWebView-versus-Chromium memory
  and latency comparison.
- The chosen 300 ms default mutation quiet window is a policy default, not a
  benchmark optimum.
- Offscreen snapshots can miss composited GPU effects; the runtime reports this
  caveat but has not yet implemented a presented-window fallback.
- The second notebook proposed MRTR auth handoff, cooperative context paging,
  hierarchical plan/grounding separation, and code mode. Only the MCP MRTR
  mechanism and cited research leads are grounded; product gains remain
  unmeasured here.

## Bugs found by the counter-audit

- Initial MCP tests incorrectly placed `_meta` at the JSON-RPC envelope. Reading
  the official schema caught and corrected both implementation and tests.
- NotebookLM twice named nonexistent `WKSerializedNode`; it was rejected in
  favor of the SDK-verified `WKDOMNodeSnapshot`.
- Page input values initially inherited first-party-content provenance. They now
  use `USER_ENTERED_SITE_DATA`, and password values are never serialized.
