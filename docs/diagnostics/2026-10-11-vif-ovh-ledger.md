# Vif / OVH diagnostic — hybrid mission ledger

Latest continuation: the same-origin frame correction is now installed as
**0.6.29 (629)** after the operator confirmed the human OVH step finished. The
32 targeted cases pass in Debug and Release; installed transport and signature
checks pass. No live OVH qualification was performed. See the final continuation
below for current handoff state.

Owner and sole checkout writer for this mission: Codex. No delegated coding agents.
Scope: investigate the supplied WebKitUI Native MCP diagnostic, correct locally
reproducible connector defects, validate without touching OVH, and leave a
privacy-safe handoff. No install, package, commit, push, publication, account
mutation, browser-session adoption, or live OVH action was authorized or performed.

Current state: **Incident B corrected and Incident C guidance improved in the
checkout; Incident A remains unqualified pending a physical end-to-end trace.**
Changes remain uncommitted. Codex relinquishes the checkout writer role at the end
of this mission.

The later local-install continuation below supersedes only the installation and
version restriction. It does not authorize OVH, App Store Connect, publication,
notarization, commit, or push actions.

## Baseline

- Started read-only on `52a3dc1352dc18282d348bd3327f7fc78e78016d` with an
  already dirty checkout.
- Existing uncommitted work covered README, runtime, release constants, server,
  Info.plist, runtime/server tests, and two diagnostic ledgers. It includes the
  previously installed 0.6.26 / build 626 work. Preserve all of it.
- Source diagnostic:
  `/Users/kevin/Desktop/WebKitUI-MCP-Diagnostic-2026-10-11.txt`.
- The report contains no passwords, cookies, OAuth tokens, private keys, or raw
  account captures. None were sought or added here.
- The current checkout and installed 0.6.26 were not assumed equivalent merely
  from their version strings. No installed binary was replaced or exercised.

## Completed

- Read the diagnostic, dirty diff, fill transaction planning, canonical observation
  state, confirmation presenter/helper, and relevant server/runtime tests.
- Confirmed Incident B in source: a top-level `fill` required the semantic
  `@value` entry before dispatch, while an embedded fill required the exact
  observed element's `@tag`. A valid editable target can lack an observable value
  entry before insertion, producing `preconditionUnknown` without dispatch.
- Added a synthetic local regression whose visible, actionable input initially has
  no canonical semantic `@value`; after its input event it exposes the exact value.
  The test fails with the previous top-level precondition and passes after the fix.
- Top-level and embedded fills now use the same target-specific `@tag` presence
  precondition. Dispatch still re-resolves and pins the observed node. The exact
  semantic value digest and `@validation_accepted == true` remain mandatory
  postconditions. No unknown predicate was made true and no confirmation rule was
  weakened.
- Improved Incident C's pre-dispatch refusal. When a filtered, truncated,
  paginated, or unreadable observation makes a global appearance/absence baseline
  impossible, the error now says not to repeat that global condition and names
  applicable first-party or target-local alternatives (heading, title, URL, or
  observed target state).
- Inspected Incident A without claiming a cause. The current helper already uses a
  raised nonactivating panel, joins Spaces, orders the window to the front, and
  exits as `hidden` when AppKit reports no visible occlusion state after two
  seconds. A reported `timed_out` therefore means that narrow AppKit check did not
  report hidden; it does not establish that the operator actually saw the panel.

## Remaining

- Incident A needs a privacy-safe physical reproduction and end-to-end correlation:
  request creation, helper launch/PID and verified executable identity, window
  number/owner, key/main/visible/occlusion state, screen and Space context where
  public APIs permit it, response/timeout, and proof of non-dispatch. Distinguish
  helper started, window ordered, AppKit-visible, and human-perceived; do not encode
  request text, URLs, cookies, credentials, or page values in the trace.
- Do not label Incident A fixed from unit tests or the existing occlusion probe.
  Its root cause remains unknown.
- No local OVH fixture or live OVH qualification was performed. A future authorized
  pass should cover empty/non-empty input, textarea, controlled re-render, iframe,
  and exact readback/validation, then one bounded live OVH retry with no secret fill
  and no automatic replay.
- No version bump, package, signing, installation, or release gate was performed for
  this mission.

## Validations

- Sandboxed `swift test` initially stopped at the repository build router's
  external-disk/free-space guard. The existing scoped Swift-test permission was
  used to access the configured external build disk; no routing or disk policy was
  changed.
- Regression with the previous precondition: failed before dispatch as expected.
- Corrected focused regression: passed.
- Focused compatibility set passed: exact fill, missing-value-entry fill, invalid
  field handling, textarea canonicalization, and both filtered-baseline variants.
  Result: 5 test functions, including 2 parameterized baseline cases.
- Full Debug server-module run passed: **160 tests in 10 suites**, 112.685 seconds.
  This includes native-confirmation helper/turnstile tests, top-level and embedded
  fill paths, contenteditable paths, confirmation modes, postconditions, upload,
  handoff, and transaction behavior.
- Strict Swift format lint for the two touched source/test files passed.
- `git diff --check` passed.

## Reproduction commands

```sh
swift test --filter emptyFieldWithoutValueEntryIsVerified --no-parallel
swift test --filter 'emptyFieldWithoutValueEntryIsVerified|verifiedFill|invalidFillIsNotVerified|normalizedTextareaFillIsVerified|filteredBaselineCannotProveNewText' --no-parallel
swift test --filter MCPServerTests --no-parallel
xcrun swift-format lint --strict Sources/WebKitUIMCPServer/MCPServer.swift Tests/WebKitUIMCPServerTests/MCPServerTests.swift
git diff --check
```

## Mission delta and handoff

- `Sources/WebKitUIMCPServer/MCPServer.swift`: target-specific fill precondition and
  actionable incomplete-baseline guidance.
- `Tests/WebKitUIMCPServerTests/MCPServerTests.swift`: missing-value-entry regression
  and guidance assertions.
- This ledger.
- All other dirty files and earlier ledger content predate this mission and were
  preserved. Because the two touched files already contained substantial
  uncommitted work, use the descriptions above or the adjacent test name to isolate
  this mission's delta; do not discard the surrounding changes.
- No private transcript is required for continuation. A receiving provider must
  acquire sole checkout-writer ownership before editing.

## Authorized local installation — continuation

The user asked Codex to manage the local installation. Codex reacquired sole
checkout-writer ownership. Scope: version 0.6.27 / build 627, arm64 Release tests,
Developer ID signing with the installed app's existing team, recoverable local
replacement, relaunch, and installed source/machine-code/signature/transport
verification.

- Installed baseline is signed 0.6.26 / 626, identifier
  `com.lorislab.webkitui-mcp.aqua`, team `TDV6D5L785`.
- Matching Developer ID Application identity is available locally.
- Read-only broker preflight found all three session slots occupied. One reported
  human control active on App Store Connect and ownership by another client.
  No session was adopted, closed, or otherwise changed. Build/sign preparation may
  proceed, but installation must wait until active work is released; restarting now
  would interrupt it.
- Version constants, bundle metadata, and README advanced to 0.6.27 / 627.
- Remaining: Release gate, package/sign verification, idle-session recheck,
  recoverable install/relaunch, and installed verification.

## SiliconPass vault MCP embedding — continuation

The user expanded the authorized local installation to include the latest
SiliconPass MCP connector. The spelling “CMP” was resolved from live repository
and installed-product evidence: the component is `siliconpass-vault-mcp`.

### Source and trust boundary

- The sibling SiliconPass checkout was inspected read-only and left untouched. It
  is dirty on `checkpoint/sync-e2ee-2026-08-09`; the connector implementation and
  integration are untracked/in-progress there, so Git tags alone cannot identify
  the current local build.
- `/Applications/SiliconPassCredentialBrokerManager.app` was signed on 2026-10-11
  after the connector source's last modification. Its version is **0.2.2 (18)**,
  its connector identifier is `com.lorislab.siliconpass.vault-mcp`, and its team is
  `TDV6D5L785`. The installed connector is universal, hardened, and its real MCP
  process qualification passed with exactly five tools.
- WebKitUI embeds only that secretless connector and its localization resource
  bundle. It does not embed SiliconPass vault code, vault/App Group access,
  Keychain groups, credentials, or keys. The connector still calls the separately
  installed, signed SiliconPass broker over its pinned native XPC boundary.
- The exact source connector file SHA-256 is
  `4a996fc453868e2ea8a7fa83ccccaee1ebec22e65cc26920ec8c840c77741b14`.
  Its normalized multi-architecture `__TEXT,__text` SHA-256 is
  `4d407402a755c0f41d21d0e2879cf5421d9dfd08b4062d47bc81f0bc6547a9a0`.
  Both, the manager version/build, connector identity, expected team, and protocol
  version are pinned in `Support/Packaging/SiliconPassVaultMCP.plist`.

### Completed implementation

- Advanced WebKitUI to **0.6.28 / 628** so the new embedded bytes do not reuse the
  already installed 0.6.27 identity.
- Packaging now refuses a missing, differently versioned, differently signed, or
  differently hashed SiliconPass manager input. It embeds the connector and
  resource bundle under `Contents/Resources/CredentialBroker/`.
- Added independent verification of signature identifier/team, hardened runtime,
  machine-code hash, forbidden entitlements, resource plists, and a live stdio MCP
  handshake. The process test proves the five-tool closed contract and rejection
  of an unknown secret argument without reading or changing a vault.
- Extended release provenance, the CycloneDX SBOM, preview verification,
  pre-notarization verification, exact signing, signing attestation, and installed
  verification to cover the SiliconPass component.
- Documented the embedded path and explicit `codex mcp add siliconpass-vault`
  command. No MCP client configuration was changed automatically.

### Validation and local installation

- Full 0.6.27 Release test gate passed before this continuation. The first full
  installed verifier then reported two runtime lease tests as
  `hostControllerLockUnavailable` because it ran while the installed broker owned
  the production lock; all other reported suites passed. This is a test-host
  isolation failure, not evidence those two behaviors passed.
- The 0.6.28 Release build completed. Preview packaging and archive round-trip
  verification passed, including native AppKit probes and the embedded connector
  process test. Final artifact hashes are recorded after the final ledger-bound
  rebuild below.
- Developer ID signing and both pre-notarization passes succeeded for team
  `TDV6D5L785`; the embedded connector was re-signed with its exact SiliconPass
  identifier. No notarization or upload occurred.
- Pre-install status was `no_client_session`, `holder: null`, with two preserved
  unowned pages. The app restart therefore did not interrupt another client's
  owned session or a human handoff; the two in-memory pages were discarded.
- A recoverable 0.6.28 installation completed and relaunched. Its 0.6.27 rollback
  is `/private/tmp/webkitui-0.6.28-install.j8E1IS/rollback/WebKitUI MCP.app`.

### Remaining and blockers

- Incident A remains unresolved and still needs the privacy-safe physical trace
  described above. Incidents B and C have code/tests but no authorized live OVH
  qualification was performed.
- The SiliconPass connector requires the matching SiliconPass 0.2.2 broker manager
  and an unlocked SiliconPass app for real missions. No vault mission, credential
  read/write, client registration, background-item registration, account change,
  publication, notarization, commit, or push is authorized or performed here.

### Final delivery evidence

- Final unsigned preview:
  `dist/vif-ovh-siliconpass-0.6.28-final/WebKitUI-MCP-0.6.28-preview.zip`,
  SHA-256 `da6c8f568a3dc97ece8e8cf31bc4a20b18b1f32cfbd8d964cf4a10ca66eb14b7`.
- Final signed local archive:
  `dist/vif-ovh-siliconpass-0.6.28-final/signed/WebKitUI-MCP-0.6.28-signed-local.zip`,
  SHA-256 `1f602590abc218e1a3e678771d5dfd08e8222b71c4fe0d9a9d95acf13a8cb01e`.
- Final preview verification and both signed pre-notarization/round-trip passes
  succeeded. No notarization or upload occurred.
- Final app installed and relaunched as **0.6.28 (628)**. The immediately previous
  0.6.28 staging install is recoverable at
  `/private/tmp/webkitui-0.6.28-final-install.EO8JFE/rollback/WebKitUI MCP.app`;
  the earlier 0.6.27 rollback also remains at the path recorded above.
- Installed source manifest exactly matched the current release-input manifest.
  Strict Swift format lint and `git diff --check` passed. Installed deep signature
  verification passed.
- Installed machine code matched the current Release build for the broker,
  confirmation helper, and relay. The embedded signed SiliconPass connector passed
  identifier/team/runtime/entitlement/machine-code/resource checks and its live
  five-tool process qualification without vault access.
- Installed transport verification passed with version 0.6.28, 14 WebKitUI tools,
  two isolated clients and explicit closure of both test sessions. A later status
  read observed other preserved session slots but no holder and no human handoff;
  none was adopted or closed.

## 0.6.28 fill-report continuation — 2026-10-11

Codex resumed as sole checkout writer, starting read-only and preserving all prior
uncommitted changes. Source report:
`/private/tmp/WebKitUI-MCP-fill-diagnostic-20261011.md`.
No session was adopted, no credential or cookie was inspected, and no live OVH
action, broker restart, installation, account mutation, commit or push occurred.

### Completed

- Matched the installed source manifest to the inspected baseline runtime and
  server hashes before editing. The reported installed 0.6.28 and the inspected
  baseline source were therefore not equated solely by their version strings.
- Reproduced both reported fill errors in synthetic same-origin iframe fixtures:
  native `targetNotActionable` and MCP `operationUnsupportedForControl(textbox)`.
  All eight initial cases also lacked the empty value in observation.
- Found the frame-realm mismatch: child-frame inputs/textareas fail `instanceof`
  checks against the outer window constructors. Corrected observation, editability
  and native value-setter checks to use the element's owning window.
- Native fill now hears its Tab commit in the owning document and follows the
  actual top-level focus chain through frames/shadow roots before reselection.
  It does not accept a stale child-document active element when top focus moved.
- Native fill arming now rechecks visibility and owner-document hit testing,
  refusing a field covered during confirmation rather than focusing through it.
  This is not a new guarantee about overlays in every ancestor frame.
- Added local fixture coverage for no-type/text/email inputs, textarea, fields
  without IDs, duplicate names with distinct labels, outer decoys, both dispatch
  modes, empty-to-text and text-to-empty, exact value/validation verification,
  cancellation, coverage, unstable geometry, and protected/non-editable controls.
  Confirmation and fail-closed transaction predicates remain unchanged.

### Validation progress and limitations

- Red proof: all eight original frame fill cases failed on the installed-source
  baseline. After the correction all eight passed, including exact empty readback,
  native trusted receipts and unchanged decoy fields.
- First compatibility pass passed three server tests (including both confirmation
  modes) and five runtime tests, including controlled rerender, native validation
  commit, unsupported combobox fill and the stolen-focus fence.
- The expanded matrix initially found two fixture expectations requiring
  correction: a select's enclosing label includes its option text (now explicitly
  aria-labelled), and a target relocated once before dispatch is intentionally
  re-resolved at its stable new geometry by existing same-origin behavior. The
  safety test now checks continuous post-approval motion, not a claim that every
  stable relocation is rejected. Strict observation-to-dispatch geometry pinning
  for same-origin controls is not implemented by this scoped correction.
- Final regression and formatting results are recorded below when complete.
- The next expanded run passed all ten runtime tests and the ordinary/server
  verified-fill and invalid-value tests. Its coverage case correctly left the
  field unchanged but failed a test expectation of `isError=true`: the existing
  transaction contract returns structured `indeterminate` for this unknown
  dispatch outcome. The test now explicitly requires `indeterminate`,
  `dispatch_error=targetNotActionable`, `action_replayed=false` and unchanged DOM;
  no production error or verification semantics were relaxed to satisfy it.

### Remaining / handoff

- Installed app remains **0.6.28 (628)** with the already embedded SiliconPass
  connector. These new fill changes exist only in the checkout; no version bump,
  signed artifact or installation was performed for this continuation.
- Preserve the report's human-controlled OVH form. Install/restart only after that
  session is safely finished or the operator explicitly agrees to interruption.
- The frame defect reproduces the error signatures but does not prove OVH's DOM
  topology or complete its live qualification. After an authorized installation,
  obtain fresh observations and one bounded human-confirmed non-secret test; do
  not automatically replay previous identity/policy creation actions.
- Truly unnamed ambiguous duplicates, ancestor-frame overlay coverage, the
  read-text/observe discrepancy and the original invisible-confirmation incident
  remain separately unqualified. Do not claim them fixed by the frame fixture.
- No private transcript content, credentials or account captures are needed for
  handoff. Preserve all unrelated dirty changes and keep a single checkout writer.

### Final validation and writer handoff

- Final source-built regression passed: four server tests / seven parameter cases
  and ten runtime tests / twenty-five parameter cases, **32 cases total**. This
  includes all new frame fixtures, exact value and validation, cancellation,
  covered/unstable targets, protected controls, cross-origin trusted receipts,
  controlled rerender, rich-text editing and stolen-focus refusal.
- Command: `swift test --no-parallel --filter
  'sameOriginFrameFill|nativeRichTextFill|nativeControlledFillActuation|nativeFillCommitsValidation|humanFillFenceBlocksStolenFocus|sameOriginFrameContentIsObserved|clickInsideAFrameLandsThere|crossOriginNativeTextActionsCarryTrustedFrameReceipt|verifiedFill|invalidFillIsNotVerified|fillOnAComboboxExplainsItself'`.
  Do not use `--skip-build` with the local m2-build Swift wrapper for this evidence:
  that attempt selected an older test binary (new tests absent) and was discarded.
- Strict `xcrun swift-format lint` on the three touched Swift files and
  `git diff --check` passed. No full-suite/release/signing/install gate was run for
  this new correction. Runtime source SHA-256:
  `59499125e98bc4c7a79bf26de3cc41c312da3d17567a3b2788288988153de8e0`.
- Codex relinquishes the sole checkout writer role at this handoff. There are no
  running coding subagents or outstanding test commands. Installation and live
  qualification remain pending as described above; existing dirty work remains
  uncommitted and preserved.

## 0.6.29 local-install continuation

The operator reported the human OVH step finished and authorized proceeding with
the pending local installation. Codex reacquired the sole checkout writer role,
checked the dirty checkout read-only and preserved all existing work. Version
constants, app plist and preview documentation now identify 0.6.29 (629). Packaging
uses the pinned embedded SiliconPass connector; no vault or live OVH action is part
of this installation. Build, signing, recoverable installation and final evidence
are in progress; no commit, push, notarization or publication is authorized.

### Completed installation — 2026-10-12

- Release packaging completed and archive/provenance/native probe verification
  passed. The same 32 targeted regression cases passed in Release on 0.6.29.
  Strict recursive Swift-format lint and `git diff --check` passed.
- Unsigned preview SHA-256:
  `7fa842ae5463a7634c49fc4fb159559b1ee151d181dc4cbd4a875529748de892`.
- Exact Developer ID signing and both pre-notarization verification passes
  succeeded for team `TDV6D5L785`, without upload or notarization. Signed archive:
  `dist/fill-frame-0.6.29/signed/WebKitUI-MCP-0.6.29-signed-local.zip`, SHA-256
  `a87387b67aac002519d976c20461b29c90ee48f5041c53e9c06e931aa1a3d8b2`.
- A read-only preflight returned `no_client_session`; it did not establish that
  every broker page was unowned. The operator's explicit completion/install
  instruction authorized the restart; no page was adopted or replayed.
- The first AppleEvent quit attempt did not stop the installed broker. Installation
  aborted before replacing anything. A bounded SIGTERM to the exact installed
  broker PID then stopped it; no SIGKILL or unrelated process termination was used.
- Installed and relaunched **0.6.29 (629)** at `/Applications/WebKitUI MCP.app`.
  The complete previous 0.6.28 app is recoverable at
  `/private/tmp/webkitui-0.6.29-install.xYtVEf/rollback/WebKitUI MCP.app`.
  Aborted staging directories were retained; no user data was deleted.
- Installed source manifest equals the generated current release-input manifest.
  The installed broker, confirmation helper and relay are byte-identical to the
  exact signed candidate. Deep strict installed signature verification passed.
- Installed two-client transport qualification passed: version 0.6.29, 14 tools,
  separate test sessions, explicit closure and host release. No existing session
  was adopted or acted on.
- The installed embedded SiliconPass connector passed its signature, pinned
  machine-code/resource and five-tool process checks. Unknown secret arguments
  were refused; no vault was read or changed. The policy matches the checkout.
- Remaining: a bounded, explicitly authorized live OVH qualification; the separate
  limitations and invisible-confirmation investigation above remain unresolved.
  No full-suite gate, account mutation, credential fill, commit, push, client
  registration, notarization or publication occurred in this continuation.
- All commands have completed. Codex relinquishes the sole checkout writer role;
  all pre-existing uncommitted work remains preserved.
