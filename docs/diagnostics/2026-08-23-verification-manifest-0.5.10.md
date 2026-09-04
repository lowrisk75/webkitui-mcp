# WebKitUI MCP 0.5.10 verification manifest

Date: 2026-08-23

## Reproduce

Run from the checkout root:

```bash
scripts/verify-native-installed.sh
```

The command fails closed and verifies:

- `git diff --check` and strict Swift formatting;
- Debug and Release tests, excluding only `hostExclusiveSession` while the
  installed broker intentionally owns the production host lease;
- installed application version and strict nested code signature;
- active LaunchAgent and Unix socket;
- protocol version, the exact ten-tool catalogue, secretless `default` profile,
  and two simultaneous clients reusing one durable browser session;
- SHA-256 values for the installed broker, CLI, and relay.

Final execution result: exit status 0, with 120 passing tests in Debug and 120
passing tests in Release. The separately repeated scroll/text test passed 3/3
in Debug and 3/3 in Release after its fixture timeout was made explicit for a
loaded WebKit host.

Installed SHA-256 values:

- Aqua broker: `9c4067f1a8106170fed15071b514ef5d08f3f2d423f7a8a63cc231c2de292aea`
- CLI: `e54303117cbfd58f8aa6634b42b1fdeffd2acd030b58298ae1954255615af87a`
- Relay: `7e3625604f5659eef9ce1ae2d22e03544ebb1434a39e3baea9b07446f7a5abd3`

The two-client production assertion is implemented by
[`verify-installed-native.mjs`](../../scripts/verify-installed-native.mjs), not
by a mocked server.

## Native rendering evidence

The public Codemagic authentication route rendered in the installed handoff
window instead of a white surface. The redacted-safe capture, taken before any
credential entry, is preserved at
[`2026-08-23-codemagic-human-control-0.5.8.jpeg`](evidence/2026-08-23-codemagic-human-control-0.5.8.jpeg),
SHA-256
`c19356d7dde975e8c9799d7d186953ccaca6bea9d8e633672e1df5912e9e28c2`.

## Command-V regression

Version 0.5.10 installs a native `Edit` menu in every native host. The
`nativePasteCommand` regression test verifies that its `Paste` item dispatches
the standard `paste:` selector with key equivalent `v` and the Command modifier.
Computer Use additionally confirmed that both `WebkitUIMCP` and `Edit` are
present in the installed application's menu bar during a real handoff.

No clipboard contents are read or persisted by the verifier. A final physical
Command-V check with the user's existing clipboard remains a human interaction
and must not be simulated by replacing that clipboard.

Physical verification result: the user confirmed in the live 0.5.9 handoff
window that Command-V successfully pasted into the WebKit form control.

## Direct stdio host evidence

The white-window defect also existed in conversations configured with the
direct `~/.local/bin/webkitui-mcp` transport: that executable awaited stdin but
never ran the AppKit event loop. Version 0.5.10 runs stdin handling from a main
actor task while `NSApplication.run()` owns the host thread.

The packaged direct-host smoke test rendered a green WindowServer surface with
the heading `WebkitUIMCP direct stdio visual smoke test`, a semantic WebKit
tree, and the native `Edit` menu. This proof is independent of the Aqua relay
smoke test.

## External-state boundary

The evidence does not claim an App Store Connect upload or Codemagic build. It
does not persist credentials, OAuth tokens, cookies, or password-manager state.
