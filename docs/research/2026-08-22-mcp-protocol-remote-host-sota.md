# MCP protocol and remote Mac host — 2026-08-22

## Scope

Make the native WebKit runtime usable by fresh Codex and Claude Code clients,
then define a private Proxmox-to-Mac path without moving the authenticated
browser session off the Mac.

## Source-verified

- MCP `2026-07-28` is a separate modern era: `server/discover`, per-request
  `_meta`, no `initialize`, and in-band multi-round `input_required` results.
  Legacy `initialize` must negotiate only a 2025-era revision.
- A modern `server/discover` result advertises modern revisions only. The
  official example returns `supportedVersions: ["2026-07-28"]`.
- Every modern request requires protocol version and client-capabilities keys
  in `params._meta`. Unsupported versions use MCP error `-32022` with the
  requested and supported revisions.
- OpenAI Secure MCP Tunnel provides outbound-only access from a private host to
  supported OpenAI products. It needs a Platform tunnel, runtime API key, and a
  continuously running `tunnel-client`; it is not a public distribution path.
- Safari 27 beta ships Apple's local Safari MCP server. Apple says it exposes
  DOM, network, screenshots, console and interactions, but not Safari AutoFill
  or unrelated browser activity.

Primary sources:

- https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/server/discover.mdx
- https://github.com/modelcontextprotocol/typescript-sdk/blob/main/docs/protocol-versions.md
- https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/schema/2026-07-28/schema.ts
- https://developers.openai.com/api/docs/guides/secure-mcp-tunnels
- https://webkit.org/blog/18136/introducing-the-safari-mcp-server-for-web-developers/

## NotebookLM synthesis — not authority

The required follow-up queries to both notebooks were attempted again before
the broker work. The gateway blocked them before content was sent because it
could not verify the NotebookLM Companion as hidden. No answer from that attempt
is used below.

The `WebKITUI MPC` notebook identified the version-era contradiction and the
need for stateless confirmation retries. Its first opportunity answer contained
only UI progress text and is unusable.

The `LLM` notebook suggested host-side credential isolation, checkpoint/delta
delivery, explicit remote control locks, and aggregate WebKit helper memory
telemetry. It also proposed JIT multi-action scripts and zero-copy remote
viewports; those two proposals are conjectural and are not adopted because they
weaken transaction boundaries or do not apply across a network.

The post-implementation `WebKITUI MPC` audit returned only progress UI and no
cited answer, so it contributes no finding. The second notebook repeated four
opportunities: local multi-action execution, host-side credential isolation,
provenance-gated JIT, and aggregate helper-memory telemetry. Its quoted latency,
memory, and token figures were not independently verified in this slice and are
therefore not treated as measurements. JIT execution remains rejected; memory
attribution remains a separate open measurement.

## Measured before correction

- Installed clients: Codex CLI `0.149.0`; Claude Code `2.1.239`.
- Host: macOS `27.0` build `26A5416b`; SafariDriver included with Safari 27.
- The server's discovery result incorrectly advertised both modern
  `2026-07-28` and legacy `2025-11-25`.
- A manually issued modern version through legacy `initialize` negotiated
  `2025-06-18`; this manual sequence is not a valid modern connection.
- A pre-upgrade Codex conversation retained the old Chrome/Playwright tool
  catalog. That proves client catalog caching, not a native-server failure.

## Implementation target

1. Advertise only modern revisions through `server/discover`.
2. Validate required modern request metadata and return `-32022` for an
   unsupported modern revision.
3. Negotiate supported legacy revisions only through `initialize`, preferring
   `2025-11-25` when the client requests an unsupported revision.
4. Add wire tests for era separation, malformed metadata, and version errors.
5. Verify with fresh real Codex and Claude Code processes, not only raw JSON.
6. Keep remote transport private. Prefer a narrowly constrained SSH stdio path
   for the existing Proxmox host; evaluate Secure MCP Tunnel separately because
   it needs external organization credentials and configuration.

## Open gates

- Real fresh-client multi-round confirmation behavior in Codex and Claude Code.
- Interrupted real-site write behavior and warm observe/action latency.
- Authenticated task success through a restarted interactive Proxmox client.
- External Secure MCP Tunnel account availability and policy approval.

## Measured after correction

- Discovery advertises only `2026-07-28`; unsupported modern versions return
  `-32022`; unsupported legacy initialization counter-offers `2025-11-25`.
- Legacy requests carrying ordinary `_meta.progressToken` remain legacy.
- A new pending navigation, actuation, or handoff confirmation supersedes the
  prior pending confirmation of the same type and session.
- A production host lease permits the first registry to open WebKit, rejects a
  concurrent second registry, then permits it after the first closes.
- Swift format lint passed. The targeted server suite passed 15 tests and the
  host-lock test passed independently.
- Before concurrent credential-sink work appeared, full debug and ARM64 release
  validation each passed 107 tests: 15 server, 31 runtime, and 61 core tests.
- A fresh isolated Claude Code process discovered and invoked
  `mcp__webkitui-mcp__browser_session`; its final run succeeded.
- A fresh ephemeral Codex process discovered
  `webkitui-mcp/browser_session` and reached Codex's non-interactive approval
  boundary. It did not execute because that process used approval policy
  `never`; this proves discovery and fail-closed authorization, not execution.
- At installation time, the ARM64 release binary matched its build artifact at SHA-256
  `c455b6706237fca5e3efaa07ba285f13a49116f396c13ca6b86c339feb62d223`.
- An installed-binary, two-process wire test opened the first controller,
  rejected the concurrent second controller, released the lease on close, and
  then allowed the second controller to open.

## Concurrent-work boundary

During final validation, another user session added an untracked private
credential sink and modified `WebKitRuntime.swift`. Its credential-specific
files were not edited by this slice. The final combined checkout passed 112
tests in both debug and ARM64 release: 16 server, 35 runtime, and 61 core.
Strict format lint still fails in files owned by that concurrent credential
slice; every protocol/remote file passes strict lint. Therefore the combined
dirty checkout is not yet a clean release candidate even though its tests pass.

## Private remote deployment measurements

Measured on the actual private Linux-to-Mac route on 2026-08-22:

- A dedicated SSH key is source-restricted, `restrict`-scoped, and forced to a
  fixed Unix-socket relay. Host-key pinning matched the Mac's local Ed25519 host
  key. PTY allocation failed as intended; shell and forwarding are unavailable.
- A per-user Aqua LaunchAgent owns a mode `0600` Unix socket in a mode `0700`
  directory. The accepted peer UID must equal the broker UID.
- The first socket implementation inherited nonblocking mode into accepted
  clients and closed after `browser_session(open)` with POSIX error 35. Clearing
  `O_NONBLOCK` on each accepted socket fixed persistent `open → status → close`.
- A second AppKit fault reproduced the user's blank/no-icon report: setting the
  activation policy before `finishLaunching()` was reset. Calling
  `finishLaunching()` first, moving the window to the active Space, and ordering
  it forward produced an on-screen titled placeholder, regular policy, and an
  application icon. Accepted resume returned to accessory policy and hid it.
- Abrupt SSH termination released the host controller lease. A fresh connection
  opened on its first attempt after 664 ms; no action was replayed.
- Ten cold discovery connections: min 369 ms, median 958 ms, max/p95 4,213 ms,
  mean 1,266.1 ms. Five cold session opens: min 713 ms, median 1,053 ms,
  max/p95 1,159 ms, mean 973.2 ms. These include SSH startup under concurrent
  builds and do not measure warm observe/action latency.
- Final installed ARM64 artifacts exactly matched their release build outputs:
  server `139639db…7362`, Aqua broker `960b837a…197c`, and relay
  `866b2db4…4699` (SHA-256 abbreviated here; full values remain in the local
  validation transcript).

Measured, not inferred: remote MCP transport, persistent multi-message relay,
native session lifecycle, Aqua handoff presentation, and crash-release of the
controller lock now work together. Still unverified: an interrupted real-site
write, authenticated benchmark success, and steady-state action latency.
