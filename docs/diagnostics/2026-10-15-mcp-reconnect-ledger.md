# MCP reconnect diagnosis — mission D5D805F8

Owner: Codex, sole checkout writer for this diagnostic. Read-only start preserved
the inherited modified and untracked work; no product source or configuration was
changed.

## Completed

- Confirmed Claude and Codex both configure `webkitui-mcp` as the installed stdio
  relay with the same local Unix socket.
- Reproduced relay error `-32097` while the installed broker application was not
  running.
- Launched the existing installed WebKitUI MCP application. No software was
  installed or updated.
- Verified the broker owns the expected socket and completed a direct MCP
  `initialize` handshake in 0.01 seconds.
- Verified `claude mcp get webkitui-mcp` reports `Status: Connected`.

## Remaining / blockers

- No blocker for the current reconnect. The user can retry `/mcp` in the existing
  Claude session.
- Launch at Login remains disabled. Enabling it is an optional user/system-setting
  decision and was not changed during this mission.

## Validation and resources

- No simulator or temporary directory was created.
- The diagnostic relay invocations exited normally; no diagnostic child process
  remains.
- The installed broker process PID 58785 was launched by this mission and is
  intentionally retained because it is required for continued MCP use. Throttle
  resource ID: `746A93CF-1AA9-466A-8346-011517BD1F31`.
- No other process, socket, file, or resource was removed or cleaned up.

This ledger contains no private transcript content.
