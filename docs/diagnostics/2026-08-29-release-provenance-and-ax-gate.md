# WebKitUI MCP release provenance and non-disruptive AX gate

Date: 2026-08-29

## Scope

This gate hardened the current dirty-worktree Release input without replacing
or restarting the installed signed app. It performed no logout, global
VoiceOver activation, signing, installation, Apple upload, deployment,
publication, commit or push.

## Changes

- `scripts/generate-release-provenance.sh` creates a deterministic
  `SOURCE-MANIFEST.sha256` and `ReleaseProvenance.plist` for the exact package
  inputs. The plist records the 40-character Git revision, branch, clean/dirty
  state, tracked/index/status digests, build configuration and architecture.
- Preview and pre-notarization verifiers reject missing or inconsistent
  provenance, forbidden secret-bearing manifest paths, localization syntax or
  EN/FR key drift.
- The companion exposes stable accessibility identifiers, avoids duplicate
  VoiceOver reading for status labels and sets a predictable initial keyboard
  responder.
- `scripts/notarize-exact-app.sh` requires a confirmation value bound to the
  exact input SHA-256 before it can contact Apple. It verifies the Developer ID
  app, submits with a Keychain profile, saves the submission and developer log,
  staples, validates Gatekeeper and emits a new final SHA-256. Its no-approval
  guard was exercised locally and exited `65` before creating output or making
  a network request.
- The pre-notarization gate rejects `com.apple.security.get-task-allow=true`,
  consistent with Apple's current Developer ID notarization requirements.

Apple's current command-line workflow accepts a ZIP containing the app, uses
`notarytool submit --wait`, then staples the accepted ticket. Credentials are
referenced through a Keychain profile rather than placed in the script:
[Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) and
[Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Fresh validation

- Swift Debug: 163 tests passed; installed-host exclusivity intentionally
  skipped to preserve the active broker.
- Swift Release: 163 tests passed with the same bounded skip.
- Legacy npm compatibility: 22 passed, 0 failed.
- `npm audit`: 0 vulnerabilities.
- `gitleaks --no-git --redact`: no leaks in approximately 274 MB.
- Strict Swift format for the companion, shell syntax and `git diff --check`:
  passed.
- Fresh unsigned app ZIP:
  `/private/tmp/webkitui-production-ready-local.KwNPt5/WebKitUI-MCP-0.6.0-preview.zip`
  SHA-256
  `b78f9e2f2462271fe807e57230359d7f8586d52818dd4aa2c587cfa15426e340`.
- Standalone relay ZIP SHA-256:
  `edf728435caf24548785385db24d81fff080cfde36f53a724caaa56907c04773`.
- Embedded source-manifest SHA-256:
  `d0e5b751c5375a51d697dd432736f730686166f47314e13913a686e4b9ca7461`.
- Embedded status digest:
  `a639af1ae23d8ee8200347d23c7c2b83cec16459b417583582fd24f7d90c4810`.
- Provenance truthfully reports `SourceTreeState=dirty` at HEAD
  `72ad3504cba0e849c4da9bb88c281ba7ddb2f7c2`.

## Boundary

The previously installed Developer ID app remains locally valid and running,
but it predates this provenance and AX hardening. The current unsigned archive
must receive a new exact-input Developer ID signature before it can become the
notarization candidate. Physical VoiceOver/keyboard use, logout/login relaunch,
clean-Mac install and notarization remain separate proofs.
