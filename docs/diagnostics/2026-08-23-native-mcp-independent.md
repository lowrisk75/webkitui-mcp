# WebkitUIMCP native — independent diagnostic (2026-08-23)

Recipient session: `01a02dbd-f73d-7301-be29-8d98eee9ddce`

Scope: independent read-only validation of the installed native MCP and the
current source checkout. No broker, relay, Codex session, OAuth flow, or Apple
portal action was stopped or mutated.

## Result

The 0.5.2 rendering and handoff regressions pass in Debug and Release. The
remaining independently reproduced failure is MCP client availability: a new
conversation cannot initialize WebkitUIMCP while Byty keeps the Aqua broker's
single client attachment.

## Evidence

- `codex mcp list` reports `webkitui-mcp` enabled and configured as
  `~/.local/bin/webkitui-mcp-relay` with the Aqua Unix socket.
- This new conversation exposes no WebkitUIMCP `browser_*` tools.
- Direct `initialize` against the installed relay and Aqua socket, outside the
  command sandbox, returns:

  ```json
  {"jsonrpc":"2.0","error":{"message":"Aqua broker restarted after dispatch; request outcome unknown and was not replayed","code":-32098},"id":1}
  ```

- `launchctl` reports Aqua running as PID `91013`, with no recorded exit.
- Process attribution identifies relay PID `91881` as a child of
  `codex resume 01a02b12-b667-7c60-a907-7e52538e761e`, the active Byty
  session. No process was killed.
- Focused Debug tests passed: durable browser reconnect, legacy native handoff
  fallback, server human handoff, live rendered WebView, and fresh-address-space
  resume (5/5).
- The same focused tests passed in Release (5/5).
- Computer Use cannot target the non-packaged Aqua broker as an application, so
  this independent session could not prove the live Codemagic handoff pixels.

## Diagnosis

The blank-window correction is covered and green. The current user-facing
failure is that the broker silently closes a second client in `claimClient()`;
the relay maps that close to the ambiguous `-32098` restart/outcome-unknown
error. At Codex startup this prevents MCP initialization, so the conversation
receives no WebkitUIMCP tool catalogue.

Therefore, “open a new conversation once” is insufficient while the previous
Byty conversation remains attached.

## Recommended follow-up

1. Return an explicit `client_busy`/owner-safe diagnostic for a rejected second
   attachment instead of `-32098`.
2. Define a safe authority transfer or detach mechanism for conversations,
   preserving the durable `WKWebView` and invalidating observations/approvals.
3. Alternatively, serialize multiple MCP clients at the broker with explicit
   lease ownership; do not allow concurrent browser authority.
4. Re-run the real Codemagic capture → handoff → visual inspection → resume
   sequence only after Byty deliberately releases or transfers the lease.

## Delivery status

An attempted `codex exec resume` delivery was rejected with
`thread-store conflict` because the recipient session already has an active
writer. Computer Use is prohibited from controlling the Codex app. This file is
the persistent shared-checkout handoff and should be consumed by the recipient
session before further WebkitUIMCP changes.
