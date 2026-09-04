# Self-contained app lifecycle gate — 2026-08-29

## Outcome

`PASS LOCAL — EXTERNAL SIGNING AND CLEAN-MAC GATES RETAINED`

WebKitUI MCP 0.6.0 no longer requires a new installation to write a mutable
LaunchAgent plist or install a relay in `~/.local/bin`. The app owns its Unix
socket, embeds its relay, exposes an exact Codex setup command, and uses
`SMAppService.mainApp` for the user-approved launch-at-login path.

The visible product name is **WebKitUI MCP**. `Aqua` remains only in existing
internal executable and bundle identifiers so this source change does not
silently create a new application identity.

## Local runtime evidence

- Direct isolated broker launch created a mode `0600` Unix socket.
- `server/discover` returned MCP `2026-07-28`, product `webkitui-mcp`, version
  `0.6.0`.
- A concurrent second broker failed closed while the first socket was live.
- A broker restarted after an abrupt stop reclaimed only the stale socket.
- Normal Command-Q exited zero and removed the socket after an initial failing
  probe exposed the missing termination cleanup.
- Cleanup is bound to the captured socket device and inode. A path replaced by
  another file is not unlinked.

## Product and accessibility evidence

The exact unsigned Release app was inspected through the macOS accessibility
tree and pixels in French. It exposed:

- truthful service, login-item, license and socket states;
- Launch at Login recovery, receipt access, embedded-relay setup copy,
  documentation and explicit uninstall preparation;
- no clipped buttons or labels at the fixed 560 x 450 status-window size;
- the visible app/menu name `WebKitUI MCP`.

The unsigned copy reports that it must be moved to Applications. The signed
installed copy has now proved registration and approval; a real logout/login
is still required to prove automatic relaunch.

## Validation

- Swift Debug: 163/163 tests passed, with the installed-host exclusivity test
  deliberately skipped to avoid interrupting the active signed broker.
- Swift Release: 163/163 under the same bounded exclusion.
- Legacy npm fixtures: 22/22.
- `npm audit --audit-level=high`: zero vulnerabilities.
- strict Swift format, plist/shell lint and `git diff --check`: passed.
- gitleaks: 274.03 MB scanned, no leaks.
- Preview verifier confirms arm64 code, ServiceManagement linkage, icon,
  privacy manifest, legal/SBOM resources, embedded relay and exact setup path.

## Exact artifacts

- App: `/private/tmp/webkitui-production-ready-preview/WebKitUI-MCP-0.6.0-preview.zip`
  - SHA-256: `93e2cfd78da099f439cb0bc559f82aa439ea68f8b18ed0bbd52be8dde1689376`
- Standalone private-transport relay:
  `/private/tmp/webkitui-production-ready-preview/webkitui-mcp-relay-0.6.0.zip`
  - SHA-256: `6deae07c69999c54c8fca60761e42fbdb749f96a6e449d6ca5cc83c00e0e156e`

These archives are unsigned and are not release artifacts.

The exact app input was subsequently signed with Developer ID Application Team
`TDV6D5L785`. Signed archive:

- `/private/tmp/webkitui-0.6.0-self-contained-signed/WebKitUI-MCP-0.6.0-signed-local.zip`
- SHA-256: `8d9d2294a20bdff5bbd2995a5ea1b5087ab8c10d05cd8d8dda9c8c8c4195c71b`

The signing gate now preserves extended resources and requires a successful
pre-notarization check after ZIP round trip. A separate out-of-sandbox
extraction also passed. Gatekeeper reports `Unnotarized Developer ID`, as
expected before notarization.

## Signed local installation

The signed candidate was installed recoverably at
`/Users/kevinnadjarian/Applications/WebKitUI MCP.app` after backing up the
running legacy app and plist to
`/private/tmp/webkitui-0.6.0-pre-selfcontained-rollback.5nLk9M/`.

- Legacy LaunchAgent PID `61150` was stopped and remains unloaded.
- The plist was moved recoverably out of `~/Library/LaunchAgents` to
  `/private/tmp/webkitui-0.6.0-pre-selfcontained-rollback.5nLk9M/com.lorislab.webkitui-mcp.aqua.plist.removed-from-LaunchAgents`;
  its SHA-256 remains `03840a99e6311a67c44f5f38de20c4e99452718cdeb7e78f65c7e08600437733`.
  The old app was retained; no destructive removal occurred.
- Installed broker SHA-256:
  `c62397d45c9d8c4341a1609aa1f602e1bdef3f7018a54be92d5a1140d6f1ad9a`.
- Installed embedded relay SHA-256:
  `35fa8932e10fe37e2ec8cff8c2c67bf5376915b9bc47e8fda98ebc26966bd5bb`.
- Signature, Team ID, hardened runtime, secure timestamp and sealed resources
  passed after installation.
- Before authorization, the French signed UI reported the socket active and
  Launch at Login not enabled.
- Two clients discovered 11 tools and reused one default session.
- Command-Q removed the socket; relaunch restored it and the protocol probe
  passed again. Final observed PID: `91953`.
- After exact authorization, the signed UI reported `Ouverture de session —
  Activé`. macOS Background Task Management reported bundle
  `com.lorislab.webkitui-mcp.aqua` at `/Users/501/Applications/WebKitUI MCP.app`
  with disposition `enabled, allowed`. The old LaunchAgent remained unloaded
  and absent; the live two-client probe still passed.
- The macOS `Ouverture` Settings extension exited once and stayed visually empty
  on one retry. Its BTM record retained the historical cached name
  `WebkitUIMCP Aqua`, although both source and installed signed plists declare
  `WebKitUI MCP`. No broad BTM database reset was attempted.

## Remaining external gates

1. Complete the authorized real logout/login and record post-login automatic
   relaunch evidence. Pre-logout PID `91953`, socket, MCP probe and native BTM
   registration were freshly verified.
2. Physical keyboard and VoiceOver onboarding pass.
3. Notarization, stapling and Gatekeeper validation on a clean Mac.

The exact-SHA signing gate in `scripts/sign-exact-preview-local.sh` was executed
only for the authorized archive. The later exact local-install and Login Item
authorizations did not authorize notarization upload, publication, real
account/provider mutation, commit or push; none occurred.
