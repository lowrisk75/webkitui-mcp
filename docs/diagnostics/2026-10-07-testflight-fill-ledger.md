# TestFlight description fill — mission ledger

Owner: Codex. Scope: this checkout's observation, fill eligibility, MCP contract
and explicitly authorized signed local update/install to 0.6.25 / build 625.
One writer: Codex; no delegated coding agents. No App Store Connect writes,
notarization upload, public release, commit or push are part of this work.

Current state: final corrected signed app installed/relaunched. Complete Debug
and Release tests, installed machine-code equality, source manifest, version and
signature gates passed. The final two-client ownership assertion is blocked by
another client's owned session; preserve it and do not claim full-script success.
Historical milestones below retain the initial narrower scope and failed-gate
evidence; they do not override the current state.

## Baseline and evidence

- Started read-only at `52a3dc1` (0.6.24); checkout clean.
- User reports installed build 624 refusing a freshly observed roleless `div`
  before dispatch. Local server guard corroborates the error; binary equivalence
  and Apple's actual DOM have not been verified.
- Runtime already tests `element.isContentEditable` at dispatch and supports
  contenteditable insertion. Observation omits this fact; server accepts only
  input, textarea or role=textbox. Selectors only discover explicit `true`.
- No private receipts or clipboard contents read or copied into this ledger.

## Completed

- Read observation mapping, inspection, fill guard, dispatch and tool schema.
- Added measured `contentEditable` to full/compact observation and inspection;
  retained sensitive-field refusals, exact target identity and live editability checks.
- Discover valid true/empty/plaintext-only contenteditable forms in observation,
  page-content probing and action resolution; publish frame-native fill capability.
- Prevent editable text from becoming a mutable accessible-name identity; fix the
  required tag fallback when an anonymous control has only corroborating facts.
- Expose explicit postcondition properties alongside precise union branches;
  include url_prefix, validation_state, character_count_equals and panel_open,
  align value_equals and other existing limits with the runtime parser.
- Add synthetic 1624-character roleless-editor regressions, refusal cases and
  native AppKit paragraph-replacement coverage. Fixtures do not reproduce Apple's
  unknown HTML or claim server persistence.
- Confirmed that no generic container-to-child redirection is currently justified
  by the supplied evidence. Preserve exact observed target identity.

## Remaining

- Local implementation and scoped validation complete; changes remain uncommitted.
- Live Apple qualification and client schema rendering remain external follow-ups.

## Validations

- Initial `git status --short`: clean.
- Initial test runs exposed mutable accessible-name identity, then a missing
  required identity clause on anonymous controls. Both addressed locally.
- Synthetic length assertion and receipt decode mistakes in tests corrected.
- Final focused run: exit 0, server 4 tests and runtime 1 test; includes 4 editor
  variants, 3 pre-confirmation refusals and 2 native AppKit variants. Exact 1624
  character readback and stable semantic identity verified on synthetic fixtures.
- Neighbor regressions: exit 0, server 5 tests and runtime 8 tests. Includes
  input/textarea, invalid-state refusal to verify, compact wire payload, native
  validation commit, controlled rerender, editor block isolation, stolen-focus
  refusal, contextual locator quality and cross-origin native text actions.
- Total: 18 passing test functions across the two final runs, including
  parameterized cases. Full suite, Release build and installed build not tested.
- Final strict Swift formatting and `git diff --check`: exit 0.
- Sandbox could not use formatter temporary files / external build routing;
  authorized elevated invocations succeeded. No storage cleanup performed.
- No live Apple qualification performed.

## Blockers / handoff qualification

- Actual Apple target might be a wrapper. Obtain fresh observation/inspection
  on installed 0.6.25; never reuse diagnostic IDs. Live Apple writes/saves are not
  authorized by this provider-installation continuation.
- Local fixtures cannot prove Apple's framework validation or server persistence.
  Live qualification still needs native-confirmed fill, field readback, validation,
  authorized save and reload. Beta draft persistence remains unverified.
- Client-side rendering of the schema as an unknown signature is not reproduced;
  a server contract change alone cannot establish that the client renders it.

## Reproduction commands

```sh
swift test --filter 'verifiedContenteditableFill|rolelessFillRefusals|actPostconditionContract|toolList|nativeRichTextFillReplacesExistingDraft' --no-parallel
swift test --skip-build --filter 'verifiedFill|invalidFillIsNotVerified|normalizedTextareaFillIsVerified|compactObservation|validationAndCharacterCountObservation|fillOnAComboboxExplainsItself|fillOnARichTextEditorIsHonest|contextualLocatorQuality|nativeControlledFillActuation|nativeFillCommitsValidation|nativeFillInsideLargeEditorStaysInItsBlock|nativeFillRefusesStolenFocus|crossOriginNativeTextActionsThroughMCP' --no-parallel
xcrun swift-format lint --strict Sources/WebKitUIMCPRuntime/WebKitRuntime.swift Sources/WebKitUIMCPServer/MCPServer.swift Tests/WebKitUIMCPServerTests/MCPServerTests.swift Tests/WebKitUIMCPRuntimeTests/WebKitRuntimeTests.swift
git diff --check
```

## Initial handoff before installation authorization

Five changed files: runtime, server, their two test files and this ledger.
No version bump, installation, private-value storage, App Store Connect action,
commit or push. The installed 0.6.24 behavior is unchanged by these source edits.
Take over only after Codex relinquishes the writer role; review the local diff
against `52a3dc1` before any new writes. Live qualification is the next gate,
not a reason to replay the original failed diagnostic IDs.

## Authorized local update — continuation

User explicitly requested continuing through update and installation. Codex
reacquired sole writer role. Scope extended to version 0.6.25 / build 625,
Developer ID signing, recoverable replacement of the installed local app,
restart and installed-runtime verification. App Store Connect, publication,
notarization and Git commit/push remain outside this continuation.

Remaining: package, sign, back up existing app, install/restart, verify installed
source/signature/version/transport and full test gates. Preserve profile data.

### Installation completed

- Version source/bundle/README updated to 0.6.25 / 625.
- Release arm64 packaging completed (127.50 s); source manifest unchanged across
  build. Exact preview SHA256:
  `46f480ef1c5c0b45ca6fd2213b3bbccaf4171edc0020f568a86677d3395020bb`.
- Exact Developer ID signing and archive roundtrip verification passed, matching
  the installed app's existing team. Signed archive SHA256:
  `a9bb56d37a3b77dc2b00878c692eeff32466b92afd88a741d5d3bf4f171e1d31`.
- Installed at `/Applications/WebKitUI MCP.app`; graceful quit and relaunch passed.
  Bundle 0.6.25 / 625, strict deep signature and copied source manifest verified.
- Recovery copies retained under `/private/tmp/webkitui-0.6.25-install.M4aoDN/`:
  `rollback/WebKitUI MCP.app` and `previous-installed.app` (0.6.24).
  Browser profile stores were not copied, cleared or altered by the installer.
- No standalone CLI existed in `~/.local/bin`; app and embedded relay updated.
- Full installed verifier running; log:
  `/private/tmp/webkitui-0625-installed-verification.log`.
- This is a signed local update; no notarization upload or public release performed.

### Full-gate finding and final candidate

Initial full verifier did not pass: large default observations reached 1,053,829
bytes (>1,048,576), due to encoding false capability on every control. The server
bundle also exited without its final test summary; the verifier correctly refused
success (4/5 bundles). Other Debug bundles completed: runtime 221, licensing 18,
core 90, adversarial 56, plus XCTest confirmation policy 13.

Correction: serialize `contentEditable` only when true; inspection still reports
an explicit boolean. Added an absence assertion to the existing wire-budget test.
Focused Debug rerun passed (server 5 test functions, runtime 1, including all
editor/refusal/native variants and the previously failing budget gate).

Final corrected candidate rebuilding/signing/reinstalling via
`/private/tmp/finish-webkitui-0625-update.sh`; log
`/private/tmp/webkitui-0625-final-update.log`. Same local version/build (0.6.25/625),
no published release. The earlier installed candidate is interim; final source
and executable equality must be verified after the second install.

### Final corrected installation

- Final signed archive:
  `dist/testflight-fill-0.6.25-final/signed/WebKitUI-MCP-0.6.25-signed-local.zip`
  SHA256 `be8a59db3e62125ed37da657e97d8e258537618f6e5859beb5f9c77deb1f451a`.
- First final-install attempt preserved the interim installation because normal
  AppleEvent quit did not stop its broker. No replacement occurred in that attempt.
- Successful retry used SIGTERM only after checking the exact installed broker's
  executable path. Candidate copied, deep signature/version/source-manifest checks
  passed, and app relaunched. Final backup:
  `/private/tmp/webkitui-0.6.25-install.Ji3Cgz/` (interim 0.6.25).
  Original 0.6.24 rollback remains in `...install.M4aoDN/`.
- Full installed verifier restarted on the final candidate. Initial failed-gate log
  preserved at `/private/tmp/webkitui-0625-installed-verification.initial.log`;
  current log `/private/tmp/webkitui-0625-installed-verification.log`.

### Final Debug gate

Full Debug suite passed with all five Swift Testing bundle summaries present:
server 157, runtime 221, licensing 18, core 90, adversarial 56 (542 test
functions), plus 13 XCTest confirmation-policy tests. Only the documented
`hostExclusiveSession` test skipped because the installed broker owns its lease.
Full Release gate now compiling/running under the same installed verifier.

## Final continuation result / handoff

Completed: WebKitUI MCP **0.6.25 (625)** installed at
`/Applications/WebKitUI MCP.app`, signed Developer ID, final candidate relaunched.
Original 0.6.24 rollback preserved. Eight changed checkout files remain
uncommitted (runtime, server, release constants, plist, README, two test files,
this ledger); no other project modified and no private page/field values saved.

Final installed verifier evidence:

- Debug: 542 Swift Testing functions + 13 XCTest tests, all pass.
- Release: the same 542 + 13, all pass. All five bundle summaries present in
  each configuration; documented hostExclusiveSession skip retained.
- Strict formatting and diff checks passed.
- All three installed executables match freshly built arm64 Release machine code.
- Sealed source manifest matches current release inputs; strict deep signature
  passes; installed bundle version/build are 0.6.25/625.
- Two socket clients discover 0.6.25 and 14 tools, with separate handles.
  Final assertion that both clients own their returned sessions fails for the
  second handle (`owned_elsewhere`). A fresh isolated verifier invocation produces
  the same result. Source review confirms capacity-based reuse preserves another
  owner's authority; no ownership transfer/close/forced restart performed to make
  this assertion pass. Overall installed-verifier exit is **1**, not a full pass.
- Prior two-client check on the interim 0.6.25 candidate passed; it is historical
  evidence only and does not substitute for the final candidate check.

Remaining: fresh live Apple field inspection/fill/save/reload qualification;
client schema refresh/rendering qualification; rerun only the final transport/
ownership gate when its two sessions can be acquired without disturbing other
clients. Full tests need not be repeated unless code changes or a new failure
requires it. Final verification log and signed archive paths are recorded above.
Codex relinquishes the writer role at completion of this continuation.

## Velya diagnostic received — read-only follow-up

Source: `/Users/kevin/GitHub/Velya/audit-output/MCP_DIAG_ASC_AND_WEBKITUI_20261007.md`.
Read report and current checkout; no Velya/ASC repository changes, no live Apple
requests, no private receipts read. Prior uncommitted changes preserved.

Completed source findings:

- Relay retries connection but contains no app-launch path. Its unavailable error
  confirms no dispatch but does not tell the client which app to launch. Broker
  launch delay in the report remains a runtime observation, not a proven root cause.
- Handoff already centers the window, moves it to the active Space, raises its
  level, requests activation and Dock attention. `surface_presented` measures
  visible screen intersection, not foreground/key status or user perception.
  No additional cause for the reported first-focus miss established from source.
- Compact observations are built from the same complete server-held observation.
  Explicit compact field selection reduces serialization without filtering the
  server's baseline. To qualify a semantic postcondition, request enough elements
  and field characters, no role/name filters and require
  `observation_is_complete=true`. Sparse output is not permission to infer absence
  from an incomplete baseline. This existing capability addresses part of the
  requested observation-cost improvement; zero-row server baselines do not exist.

Remaining candidates: actionable relay startup error or bounded verified app
launch; independent handoff foreground receipt and physical focus reproduction;
compact-baseline usage guidance/qualification. No new provider patch or install
performed in this read-only follow-up.

ASC submission changes described by the report belong to `asc-mcp-server` and
were not validated in this checkout. That repository already has reported local
changes; any follow-up must preserve them and explicitly account for partial
remote writes rather than claiming a no-op failure or silently omitting products.
