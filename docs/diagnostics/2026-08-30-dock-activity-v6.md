# WebKitUI MCP — Dock and private activity journal V6

Date: 2026-08-30
Source: dirty HEAD `4ccca1cd988c52856056edd911087705b8244c2c`

## Result

- Dock visibility: the broker now uses AppKit activation policy `.regular`
  instead of `.accessory`. Reopening the running app presents its status
  window through `applicationShouldHandleReopen`.
- Private activity journal: every MCP tool call records only an allowlisted
  tool name, timestamp, outcome, duration and bounded error type.
- Structural privacy boundary: the event API accepts no parameters, URL, page
  content, element text, credential, cookie, keystroke or response body.
- Storage: owner-only `0700` directory and `0600` JSONL files; symlink and
  hard-link unsafe paths fail closed. The active 5 MiB file rotates through at
  most seven archives.
- UI: French/English activity window with refresh, redacted JSON export and
  confirmed clear. Clearing activity preserves authenticated transaction
  receipts.

## Evidence

- Final Debug: 193/193 tests PASS, excluding only the live installed-host
  exclusivity test.
- Final Release: 193/193 tests PASS with the same deliberate exclusion.
- Legacy fixture: 22/22 and TypeScript build PASS.
- Strict recursive Swift format, localization parity, plist lint and
  `git diff --check`: PASS.
- Computer Use: PASS for regular-app discovery, status-window reopen, French
  AX identifiers, activity-window layout and `0 évènements récents · rotation
  automatique activée`.
- Exact unsigned preview:
  `/private/tmp/webkitui-dock-activity-preview-v6-r2/WebKitUI-MCP-0.6.0-preview.zip`
- Preview SHA-256:
  `b68f321994586e04ea839fd416531d7cb5b25a2c50e4038780bd4b2d609e16bc`
- Source manifest SHA-256:
  `f414d6557b92332cfc992a26f2bf3d543c5f8eaf8c862fb293d457bc1bb95fed`
- Tracked diff SHA-256:
  `609f7c13beadf20cf9f6abd2c278987fc19aaba371b9b9ec50d6461156d55472`
- Globe ICNS remains byte-identical at SHA-256
  `652b1bd14edeb7a56a22f8dc6e5ca8589555e0673d680de333a6b30281f69466`.

## Gate boundary

The installed notarized V5 remains active and unchanged. The V6 preview is
superseded by the exact Developer ID signed archive:

`/private/tmp/webkitui-dock-activity-signed-v6/WebKitUI-MCP-0.6.0-signed-local.zip`

Its SHA-256 is
`ee0513115ea94ddad067fae71459418a4164fefbe7f2d36eee3d9a4d3135b5bd`.
The signing attestation binds it to unsigned preview SHA-256
`b68f321994586e04ea839fd416531d7cb5b25a2c50e4038780bd4b2d609e16bc`
and Team `TDV6D5L785`.

A fresh extraction in `/private/tmp/webkitui-v6-recheck.N4639D` passed strict
deep signature and the complete pre-notarization verifier outside the sandbox.
Gatekeeper reports the expected pre-upload state `Unnotarized Developer ID`.
The same sandboxed checks can return Code Signing subsystem false negatives;
only the equivalent out-of-sandbox verification is used as evidence.

The V6 visual smoke app was terminated after inspection. No notarization,
installation, logout, restart or publication was performed. The V5 broker
remains the installed runtime until a separately authorized V6 install.
