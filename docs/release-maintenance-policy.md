# Release maintenance policy

Date: 2026-08-30
Applies to: WebKitUI MCP Developer ID direct distribution

## Update channel

WebKitUI MCP uses one direct-download channel. It has no automatic updater and
never installs an update silently. A valid published update is a complete macOS
app ZIP that is:

- signed with the LorisLabs Developer ID Team `TDV6D5L785`;
- accepted by Apple notarization and stapled;
- published with version, build, SHA-256, release notes and source provenance;
- independently checked after a ZIP extraction with strict code signing,
  stapler validation and Gatekeeper.

Anything missing one of those properties is a preview, not an update.

Signing and notarization run from an immutable source snapshot or isolated
worktree. The snapshot manifest freezes the release candidate without blocking
later development in the live checkout; later edits are a different candidate
and do not alter the identity of already notarized bytes.

## Supported upgrade and rollback

Version 0.6.0 is the first compatibility baseline. Until a later release
explicitly documents a wider path, upgrades are supported only from the latest
published version to the immediately following version.

The user quits WebKitUI MCP, keeps a recoverable copy of the installed app,
replaces the app bundle, then relaunches and verifies the version and local MCP
socket. Application Support data and Keychain state are not removed by an app
replacement. A rollback may restore only the immediately previous notarized
artifact while it remains supported and only when its release notes say that
the local data format is backward compatible. Otherwise rollback fails closed
and requires a fixed forward release.

Several relay clients may share the one installed broker. Before replacement or
restart, enumerate or warn active clients because the operation interrupts all
connections. Concurrent clients are normal runtime use and are not themselves a
source-release conflict; simultaneous writers to the same checkout still
require coordination.

`Prepare to uninstall` disables Launch at Login. Uninstalling the app does not
silently delete receipts, transaction replay state, browser data or license
state; data removal is a separate explicit user action.

## Minimum supported version

Only the latest published stable version is supported. A prior version remains
eligible for rollback until the replacement release is verified or its release
notes declare a security or data-format incompatibility. No unpublished build,
preview ZIP or locally rebuilt dirty-tree artifact is supported for users.

## Incident and revocation ownership

The LorisLabs repository administrators own security triage, release
revocation, replacement artifacts and incident communication. Suspected
vulnerabilities use GitHub private vulnerability reporting as defined in
`SECURITY.md`; public issues must not contain exploit or credential details.

For a confirmed release incident, the owner must:

1. freeze promotion and identify the exact affected version, build and hash;
2. preserve the notarization, signing and source-provenance evidence;
3. remove or clearly mark the affected download wherever the owner controls it;
4. rotate or revoke compromised credentials or certificates through their
   owning service, without copying secrets into the repository;
5. issue either a notarized forward fix or an explicit unsupported notice;
6. verify the replacement from a fresh extraction before restoring promotion.

There is no promise of background revocation or silent remote disablement.
Provider, Apple, GitHub and certificate actions remain explicit external gates.

## Release evidence retention

Keep the previous notarized artifact, its SHA-256, source revision/provenance,
signing attestation, Apple submission ID, Gatekeeper result and rollback notes
for at least one supported upgrade cycle. Never retain Apple credentials,
private keys, browser sessions or customer secrets in release evidence.
