# ASC upload diagnostic — hybrid mission ledger

Owner and sole checkout writer: Codex. No delegated coding agents.
Scope authorized: correct reproducible connector defects from the supplied ASC
import diagnostic, validate locally, then install the signed local update as
explicitly requested in the continuation. Current checkout is the source of truth.
No Apple/account writes, notarization upload, commit, push or public publication.

The installation continuation below supersedes only the installation/version
restriction. Historical validation sections retain their original scope.

Current state: **0.6.26 / build 626 signed, installed and relaunched**. Local
fixes, Release gate, installed source/machine-code/signature and two-client
transport verification complete. Changes remain uncommitted. Codex relinquishes
the checkout writer role at completion. Live visibility/schema/Apple follow-ups
remain unqualified and are not claimed resolved by installation.

## Baseline

- Started read-only on `52a3dc1352dc18282d348bd3327f7fc78e78016d`.
- Existing uncommitted TestFlight work: README, runtime, release constants, server,
  Info.plist, runtime/server tests and the 2026-10-07 ledger. Preserve all of it.
- Byte snapshots and SHA-256 manifest of those eight baseline files retained at
  `/private/tmp/webkitui-asc-upload-baseline-x7qrhqcu/`.
- Source diagnostic: `/Users/kevin/Desktop/WebKitUI Native MCP — diagnostic import ASC.md`.
  It reports the four-resource import and review submission as resolved; those
  remote results were not independently queried in this connector mission.
- No private transcript, cookies, credentials, page values or transfer tokens
  copied into this ledger. Fixtures must use synthetic local data.

## Completed

- Read diagnostic, existing handoff ledger, dirty diff, upload implementation,
  native file-panel delegate, action schemas and confirmation helper.
- Confirmed source defect: an unconsumed armed selection is treated as proof
  that no panel opened. No preflight rejects an already pending file panel.
- Confirmed source publishes a typed `browser_act` object and observation bounds
  (1–2000 elements; 64–4096 characters). Client rendering as `unknown` remains
  unqualified; do not claim the schema is missing or the client is fixed.
- Confirmation helper already presents a raised panel across Spaces and checks
  occlusion. Reported user visibility/timeouts have no reproduced root cause yet.
- Reproduced pending-panel defect in both timing variants before fixing it:
  one extra click and `upload_panel_not_opened` despite the delegate still pending.
- Reproduced a second defect with a document capture handler that opens the
  chooser but prevents the target gesture listener from seeing the click:
  all four files selected, yet the MCP result omitted their receipt/digest match.
- Added refusal before confirmation and a recheck after confirmation. Neither
  path clicks, arms files, cancels the chooser or changes human-control authority.
- Report selection receipts on the uncertain-dispatch path using the same
  per-dispatch timestamp floor as the normal path. No trusted gesture is invented.
- Unconsumed selections now retain dispatch uncertainty and report pending-panel
  state instead of asserting a dispatched click with no panel. Guidance and
  tool description explain the direct upload path and bounded handoff recovery.
- Before installation, mission delta was limited to README, server, server tests and this new ledger.
  Other five baseline files remain byte-identical to the start of this mission.

## Remaining

- No remaining local implementation or validation work for the reproduced defects.
- Separate live follow-ups: physical confirmation-panel visibility, client schema
  rendering and actual Apple qualification. No authorization to mutate ASC is
  inferred from the diagnostic's historical authorization.

## Validations

- Initial read-only source inspection complete.
- First regression invocation was stopped by the build router's internal-disk
  free-space guard. Elevated retry accessed the external build disk and compiled;
  no cache cleanup, routing configuration change or local-disk override performed.
- Red regression: pending-panel test, 2 variants, exit 1 with 9 failed assertions.
  `/private/tmp/webkitui-asc-upload-red.log`.
- Red receipt regression: ordinary four-file menu path passed; suppressed-gesture
  variant selected files but omitted MCP selection evidence, exit 1.
  `/private/tmp/webkitui-asc-upload-receipt-red.log`.
- Focused corrected run passed, exit 0: 10 server test functions (including
  parameterized pending-panel, no-panel and four-file variants) + 3 runtime upload
  functions. Direct menu fixture verifies four digests, count 22→26, filenames,
  DOM readback and absence of local paths in the result. The capture-handler case
  keeps `nativeGestureReceiptUnavailable` while reporting selected files.
  `/private/tmp/webkitui-asc-upload-focused.log`.
- Strict Swift formatting lint and `git diff --check` passed.
- Full Debug server-module suite passed, exit 0: **159 test functions in 10
  suites**, final summary present (123.396 s). Covers native/MCP confirmations,
  human-control refusal/resume, filtered-baseline refusals, pathless receipts,
  digest mismatch and single-use selection cleanup alongside the new regressions.
  `/private/tmp/webkitui-asc-upload-server.log`.
- No full package/Release suite, installed-binary check or live Apple run performed
  in this mission. Runtime source, version/build, plist, runtime tests and the
  previous mission ledger remain byte-identical to the initial snapshot.

## Reproduction commands

```sh
swift test --filter 'upload|Upload|actPostconditionContract|toolList' --no-parallel
swift test --filter MCPServerTests --no-parallel
xcrun swift-format lint --strict Sources/WebKitUIMCPServer/MCPServer.swift Tests/WebKitUIMCPServerTests/MCPServerTests.swift
git diff --check
```

The machine's Swift wrapper routes builds to its identified external disk.
Sandboxed routing failed; elevated invocations succeeded without changing that
policy. Do not use an unrelated/stale build directory for `--skip-build`.

## Blockers and handoff

- No implementation blocker established. Installed Apple UI, physical prompt
  visibility and client-side schema rendering require separate live qualification.
- `file_picker_visible` is the existing file-panel delegate lifecycle flag. It
  proves a pending chooser callback, not that a system panel is foreground/key or
  perceived by the operator. This patch does not make a physical visibility claim.
- Do not reuse diagnostic observation IDs, reimport assets, steal a live browser
  session or bypass human control. Local fixtures do not prove Apple acceptance.
- Writer role is relinquished at completion; a receiving provider must acquire
  sole ownership before writing. Compare against the recorded byte snapshot to
  separate this mission's README/server/server-test delta from prior TestFlight
  work. Preserve the entire existing diff. No private transcript is needed.

## Authorized local installation — continuation

User requested installation after the local corrections. Codex reacquires sole
checkout writer ownership. Scope: version 0.6.26 / build 626, arm64 Release build,
Developer ID signing matching the installed team, recoverable local replacement,
restart and installed-source/signature/transport verification. No notarization
upload, Apple portal action, public release, commit or push.

- Read-only continuation baseline: installed app is signed 0.6.25 / 625, team
  TDV6D5L785. Developer ID identity is available. No standalone CLI/relay exists
  in `~/.local/bin`; update the app and its embedded relay.
- Local two reproduced defects are fixed. Physical prompt visibility and client
  `unknown` schema rendering remain unqualified and are not claimed resolved.
- Existing broker reports two active sessions and one free slot; no session was
  adopted, closed, transferred or read. Recheck activity before replacing app.
- Version constants, bundle and README advanced to 0.6.26 / 626.
- Continuation checkout snapshot:
  `/private/tmp/webkitui-asc-install-baseline-za2rodv0/`.
- Original 0.6.25 app copied to
  `/private/tmp/webkitui-0.6.26-install.t5u9gczj/previous-installed.app` before any
  installed-app mutation. Baseline metadata records binary/source-manifest hashes.
- Fixed-path recoverable installer prepared at
  `/private/tmp/install-webkitui-0626.py`; syntax checked. It stages and verifies
  the signed candidate before stopping the exact installed broker, preserves an
  atomic rollback copy, then verifies/relaunches the replacement. No broad kill,
  profile reset or other-app replacement.
- Remaining: Release tests, package/sign, rollback copy, local install/relaunch,
  installed machine-code/source-manifest/signature/version/transport checks.

### Release gate

- Full arm64 Release run passed, exit 0: server 159, runtime 221, licensing 18,
  core 90, adversarial 56 = **544 Swift Testing functions**, plus **13 XCTest
  confirmation-policy tests**. All five Swift Testing summaries present and no
  failed result. `hostExclusiveSession` skipped because the installed broker
  owns the host, as in the documented installed-verification workflow.
- Log: `/private/tmp/webkitui-0626-release-tests.log`.
- Strict formatting and diff checks passed after the version increment.
- Packaging uses the same validated external Swift cache:
  `/Volumes/DeveloperStorage/BuildScratch/Auto/webkitui-mcp-0f44ae353cdc/swiftpm`.
- Remaining: finish package/sign, recoverable replacement/relaunch, installed
  source/machine-code/signature/version and live local transport verification.

### Signed candidate ready

- Release package and archive/resource/provenance verifier passed, exit 0.
  Preview SHA-256:
  `ecb79c129a89728a69b4149c3abb017b2af89fd82a0294dde80b3776f55b537f`.
- Exact preview signed with the installed app's Developer ID/team. Strict deep
  verification and signed-archive roundtrip passed, including local helper launch
  probes. These probes do not prove the reported physical visibility issue fixed.
- Signed archive:
  `dist/asc-upload-0.6.26/signed/WebKitUI-MCP-0.6.26-signed-local.zip`.
  SHA-256 `a729bda03565292dd97c5427977a5dbf7a9a3e34e19423a6863081b920babd9c`.
- Extracted candidate's source manifest equals the current checkout's generated
  manifest. No source input changed across packaging/signing.
- Pre-install read-only broker status now reports one active session, two free
  slots, no session owned/adopted by this task. Installation requires app restart;
  the persistent profile store is not part of the replacement.

### Installation completed and verified

- Exact signed candidate installed at `/Applications/WebKitUI MCP.app` and
  relaunched. Normal AppleEvent quit succeeded; no SIGTERM/SIGKILL was needed.
  Bundle version/build are **0.6.26 / 626**.
- Original app retained at
  `/private/tmp/webkitui-0.6.26-install.t5u9gczj/rollback/WebKitUI MCP.app`;
  independent `previous-installed.app` copy also retained. No browser profile
  data copied, cleared or modified by the installer.
- Strict deep signature passed. Installed source manifest equals the current
  checkout's release-input manifest, SHA-256:
  `2f8482f71545a90ff0eab38af34ebdefc435c3dcbce98886e2e75a6119050ed3`.
- All three installed executables' `__TEXT,__text` machine code matches the freshly
  built arm64 Release broker, helper and embedded relay. Verification receipt:
  `/private/tmp/webkitui-0.6.26-install.t5u9gczj/installed-verification.json`.
- Live local two-client transport gate passed, exit 0: both clients discover
  version 0.6.26 and 14 tools, acquire separate owned sessions, reject cross-client
  access and close only their own sessions, releasing the host. No Apple URL or
  account action was used for this check.
- Installer/verification log: `/private/tmp/webkitui-0626-install.log`.
  Detailed transport log:
  `/private/tmp/webkitui-0.6.26-install.t5u9gczj/transport-verification.log`.
- No remaining installation work. Full Debug package suite was not repeated;
  the preceding Debug server/runtime gates and the full current Release gate are
  the evidence recorded here. No notarization upload or public release performed.
- Sole writer role relinquished at completion. Preserve all uncommitted work and
  use this ledger for provider handoff; no private transcript is required.
