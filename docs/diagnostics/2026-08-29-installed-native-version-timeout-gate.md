# Installed native version and timeout gate

Date: 2026-08-29T11:56:23Z
Repository HEAD: `72ad3504cba0e849c4da9bb88c281ba7ddb2f7c2`
Status: `PASS — exact signed 0.6.0 local artifact installed and verified`

## Scope and authority

This checkpoint was read-only with respect to the installed application and
LaunchAgent. No broker restart, replacement, install, credential operation,
provider mutation, publication, commit or push was performed. The materially
dirty worktree was preserved.

## Fresh evidence

- Source format and `git diff --check`: PASS.
- Credential broker runtime/XPC suites: 7/7 PASS.
- MCP server suite: 35/35 PASS, including secretless fill, password rotation,
  missing-credential handoff and `user_presence_unavailable` feedback.
- The active LaunchAgent remains running as PID 5377 from
  `WebkitUIMCP Aqua SOTA 20260829.app`.
- The active bundle is Developer ID signed by Team `TDV6D5L785`, is valid on
  disk and satisfies its designated requirement.
- Its `CFBundleShortVersionString` is `0.5.12` (build 512), while current source
  and the installed verifier require `0.6.0`.
- A two-client `server/discover` probe against the active socket did not return.
  After local hardening, the probe terminated explicitly in 10.35 seconds with
  `server/discover timed out after 10000 ms`; no verifier process was retained.

## Local hardening completed

- `SyntheticCredentialBrokerXPCClient` now bounds every broker callback wait to
  15 seconds and fails closed as unavailable when the peer stays silent.
- `verify-installed-native.mjs` now bounds both socket connection and every RPC
  to 10 seconds, clears timers on completion and cannot hang indefinitely on an
  old or silent broker.

## Interpretation

Source behavior is locally validated. Installed-native compatibility is not.
The running signed 0.5.12 broker cannot prove the 0.6.0 protocol or newly added
credential feedback. Existing client connections make an unapproved restart
disruptive, so the failed probe must not be converted into a product failure or
a release claim.

## Gate resolution after explicit authorization

The authorized replacement exposed a packaging regression: the first signed
0.6.0 app omitted SwiftPM's
`WebKitUIMCP_WebKitUIMCPLicensing.bundle` and crash-looped before accepting a
client. The LaunchAgent was stopped, the packaging and its verifiers were
hardened, and a fresh signed r3 artifact was built and installed. Its plist now
contains one canonical executable argument.

Final local evidence:

- `scripts/verify-native-installed.sh`: exit 0;
- Debug: 163 tests PASS, one intentional installed-host exclusion;
- Release: 163 tests PASS, one intentional installed-host exclusion;
- installed app: 0.6.0 (600), Team `TDV6D5L785`, valid designated requirement;
- live broker: PID 61150, 11 tools, two clients, one shared `default` session;
- app ZIP SHA-256:
  `f652999256009e7d552fb931dae5f0f3e3742b566a47650638eb3d4e37baa929`;
- installed broker SHA-256:
  `6d2851509c458092cd0eb2ebb0bea590d3a0fecd0b6267db1821b26e72f02b56`;
- installed confirmation helper SHA-256:
  `0735189398f4e126dadf70d577b1c0bde734cd3b98737d687bf9dc9aa7a1f08d`.

Rollback is retained at
`/private/tmp/webkitui-0.6.0-install-rollback-20260829`. No notarization,
provider/account mutation or publication was performed. Those remain separate
gates.

Final worktree status digest at this checkpoint:
`9a34beabf686c7c618625ad796d76d1401f5a37a5a323126fc202ccb4c8a0a4a`.
