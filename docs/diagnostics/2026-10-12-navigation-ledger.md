# Navigation diagnostic — 2026-10-12

Current continuation: scoped fixes and recoverable local installation completed.
WebKitUI 0.6.30 (630) is installed and running. Codex relinquishes the sole writer
role after this ledger update; no coding subagents were used. Earlier read-only
statements below describe completed diagnostic passes, not the final install.
Synthesis/ASC sessions and other projects remain out of scope. Remaining limits
are listed below and must not be interpreted as fixed by this installation.

Owner: Codex, sole checkout writer. Started read-only and preserved the existing
dirty checkout. Scope: inspect the supplied navigation report and correlate local
installation/process evidence. No product edits, session adoption, navigation,
confirmation retry, screenshot, permission change, restart or provider write.

Source: `/private/tmp/WebKitUI-MCP-navigation-diagnostic-20261012.md`.
This ledger contains no credentials, tokens, OAuth URLs, page contents or private
transcript excerpts.

## Completed / evidence

- Inspected the report and the confirmation presenter, helper window lifecycle,
  outcome mapping and expired-session diagnostic in current source.
- The installed source manifest matches all three inspected files:
  `NativeConfirmationPresenter.swift`, `WebKitUIMCPConfirm/main.swift`, and
  `MCPServer.swift`. This is the installed 0.6.29 source, not an assumption based
  solely on version strings.
- Active broker PID 18516 runs from `/Applications/WebKitUI MCP.app`, with start
  time **2026-10-12 09:17:19 +0200**. The recoverable installation rollback
  directory has exactly that timestamp. The previous mission deliberately stopped
  the old broker and launched 0.6.29 then.
- This known restart is consistent with loss of a session opened before the
  installation. The report has no per-event timestamps/session correlation, so
  do not claim conclusive attribution of the individual failed capture. No later
  broker restart is evidenced by the current process start time.
- User-local DiagnosticReports contains two broker reports dated 2026-10-11,
  and none dated 2026-10-12 at inspection. This is not proof no crash occurred
  anywhere; no complete system-log or crash audit was performed.
- `unknown_to_this_app_process` means no matching live handle or recorded removal
  was found. Its message infers a restart; that message alone is not crash evidence
  and cannot exclude an invalid/foreign session ID.
- `confirmation_presented=true` is hard-coded for `.timedOut` by the server.
  The presenter can return that same outcome when its global turnstile wait
  expires **before a helper is launched**, or when a running helper times out.
  Therefore this field is not an independent presentation/visibility receipt.
- The helper already uses a raised nonactivating panel, all-Spaces/full-screen
  auxiliary behavior, and a two-second AppKit occlusion check. AppKit-reported
  visibility does not establish that a person actually saw the panel. There is
  no proven root cause for the reported invisible prompt.
- The presenter's helper stderr is discarded; its environment allowlist excludes
  the optional keyboard-diagnostic flag. Existing helper keyboard diagnostics are
  therefore not a production end-to-end visibility trace.
- A bounded global read-only status returned `no_client_session`, with one active
  broker session and two available slots. No session was adopted, closed or read.
  This response does not expose every session's human-control or pending-prompt
  state; do not infer those fields are false from their absence.
- ScreenCaptureKit -3811 remains a separate observation-tool failure reported by
  the supplied document, not a demonstrated cause of native prompt invisibility.
  No CUA capture or permission mutation was attempted in this investigation.

## Validations

- Current source hashes equal the installed source-manifest entries.
- Broker executable path/start time and installation rollback timestamp correlated.
- Read-only status request completed; connection closed normally.
- No tests/builds were run: no product code changed, and synthetic tests cannot
  establish physical visibility of the reported production prompt.

## Remaining / proposed bounded remediation

1. Separate queue timeout, helper launch, helper identity validation, window
   creation, window ordering, AppKit visibility/key state and final outcome.
   Do not return measured presentation/visibility as true from a timeout enum.
2. Add a bounded privacy-safe helper receipt/trace correlated by an opaque request
   ID and monotonic timestamps. Record only process/window IDs, lifecycle and
   public AppKit state; never request message, approval text, destination URL,
   account data, cookies or credentials. Do not accept approvals from a trace or
   weaken helper identity/confirmation validation.
3. Correlate broker generation/start time with session-loss reports. Treat a
   never-known handle as unknown, not conclusive evidence of restart/crash.
4. Qualify physical panel visibility in a synthetic local flow with an operator,
   including multiple Spaces/full-screen, focus changes, queue cancellation and
   no-dispatch on timeout. No live OVH replay is required to investigate visibility.
5. Keep the original invisible-confirmation incident open until physical evidence
   supports a cause and a tested fix. No additional install is performed here.

## Handoff

Installed app remains 0.6.29 (629) with the previously verified SiliconPass
connector. All existing dirty changes remain uncommitted and preserved. Codex
relinquishes the sole checkout writer role at this handoff. No subagents or
outstanding commands remain. The earlier installation evidence is in
`2026-10-11-vif-ovh-ledger.md`.

## Synthesis reports continuation

Inputs read completely:
- `/Users/kevin/Desktop/Synthesis-WebKitUI-diagnostic-20261012.md`
- `/Users/kevin/Desktop/Synthesis-WebKitUI-feedback-20261011.md`

Codex briefly reacquired sole writer ownership for this ledger update only. No
product code changed. No Synthesis checkout was accessed, no ASC session was
adopted, and no questionnaire, save, publication or submission was attempted.
Report session/observation IDs remain ephemeral leads, not authority to act.

### Verified locally

- The installed broker's live `tools/list` publishes a typed `browser_act` object:
  eleven operation enum values; a postcondition object with explicit type/value
  properties, twenty-one postcondition types and ten typed `oneOf` branches;
  five top-level conditional `allOf` branches. The reported `unknown & unknown`
  client rendering is not evidence the installed broker omits those fields.
  Client/importer schema compatibility remains unresolved; no redundant schema
  patch or weakening of validation was made.
- The first read-only schema probe omitted required client-capability metadata
  and was correctly refused with -32602. After supplying the protocol's required
  metadata, discovery succeeded. No page or session was opened by these probes.
- Both observation and action collectors already consider href-less anchors and
  div/li/span pointer controls. Observation additionally requires rendered state,
  bounded nonempty names and filters same-named pointer children. Therefore
  "anchor without href" alone is not a proven cause of the missing Configure
  control. Other tags, styles, descendants or semantic filters remain possible;
  the exact ASC control DOM has not been inspected.
- `isComplete` intentionally combines element pagination, semantic-scope filtering,
  semantic-text truncation, unreadable frames and pending dialogs. A fully paged
  element list can still be incomplete. Changing this flag to true or raising an
  arbitrary payload cap would not prove an absence baseline. An independent
  internally complete baseline is a separate design change, not implemented here.
- The broker creates a server per socket connection; each server gets a random
  authority UUID. Ownership is not keyed solely by the self-reported client name.
  Conversely, the connection identity is not an explicit task identity: tasks
  sharing one MCP connection are not distinguished by this ownership label.
  The reported cross-task page divergence is serious but is not reproduced or
  attributable from these reports alone. Do not assume correct task ownership
  solely from `owned_by_this_client`.
- Human-control window titles currently show a site host and optional self-reported
  requester name, but not a unique visible session/task identifier. This supports
  the need for bounded window/session correlation; it does not prove the user's
  historical screenshot belongs to a particular live handle.
- The global twenty-second unowned lease yield is guarded by session-owner,
  handoff-owner and resume-capability presence. Source inspection alone does not
  establish preservation under every disconnect/reconnect sequence.

### Remaining priority work

1. Privacy-safe native presentation receipts and a physical local confirmation
   after handoff/resume, as scoped above. Keep all approval and identity checks.
2. Synthetic two-task/connection regression for session isolation, reconnect,
   human-step completion and window/session correlation. Preserve existing
   sessions; use only test-created windows/handles.
3. A minimal redacted DOM/AX evidence sample for the missing Configure control,
   obtained only in coordination with the owning mission. Then build an ASC-like
   local card regression in both observation and action addressing. Do not infer
   that every blue text node is actionable or introduce coordinate-only clicks.
4. Client schema-import compatibility regression on the actual raw schema, plus
   examples. Do not erase per-operation constraints to improve rendering.
5. Design and test an internal completeness/baseline strategy separately from the
   bounded public payload; retain fail-closed global absence predicates meanwhile.

The Synthesis mission's state and business answers remain with its owner. Neither
this ledger nor a successful local test establishes a persisted/published ASC
declaration or release readiness. Installed WebKitUI remains 0.6.29 (629). No new
build, install or live UI action occurred. Read-only schema probes completed and
their sockets closed. Codex relinquishes sole checkout writer ownership again.

## Authorized correction phase — 0.6.30 in preparation

The operator explicitly requested implementation and installation. Codex is the
sole checkout writer; no subagents were started. Existing changes are preserved.
No Synthesis/ASC session is adopted, inspected or mutated. Installation will wait
for coordination if another task still holds an active session.

### Implemented / under validation

- A concrete rich-text pointer-card defect is reproduced: a href-less anchor
  with a same-named strong/em/small child inherited pointer styling, was suppressed
  in favor of that child, but that child was not in the pointer candidate set.
  All six local native/MCP cases failed on baseline and passed after observation
  and action helpers were corrected together. This is not proof of ASC's exact DOM.
- A queued confirmation now returns `queue_timed_out`, distinct from a launched
  helper timing out. The former reports no presentation; an unmeasured timeout
  reports presentation as unknown, never automatically true.
- The verified helper emits bounded presentation metadata on a separate stdout
  pipe: opaque request ID, PID/window number, monotonic time and AppKit flags.
  The parent bounds/drains the stream and binds its parsing to the verified
  process/request. Metadata never grants approval; existing signed-helper and
  exit-status checks remain. No action text, URL, account or credential is emitted.
- Presentation is placed explicitly on the pointer's current screen, constrained
  to its visible area, and requests activation before ordering the panel. The
  subsequent visibility sample also checks active Space and screen intersection.
  A physical qualification is still required before claiming the incident fixed.
- Handoff window titles and bars, confirmation titles, and session status now
  carry matching short session labels. Completing one of two local handoff
  windows must not complete the other. Connection ownership remains explicitly
  distinguished from task identity; no cross-task authority is inferred.
- Unknown-session diagnostics no longer assert restart/crash as a proven cause.
  A registry-generation ID supports correlation instead.
- `browser_act` publishes eleven concrete per-operation object branches rather
  than conditional-only allOf intersections. Runtime requirements/refusals remain
  unchanged; README documents examples and visibility/identity limitations.
- Version constants/plist/documentation now identify 0.6.30 (630); installed
  production app is still 0.6.29 until final signing/install evidence is recorded.

### Validation progress

- First focused pass: 13 server/presenter tests and six pointer-card parameter
  cases passed. Expanded server pass: 16 tests passed, including queue/timeout
  no-dispatch and native confirmation after reconnect/resume.
- New two-window test initially omitted the required handoff-request transition;
  corrected the fixture to follow the existing state machine, not the state machine
  to accommodate the fixture. Full Debug validation is running.
- Existing exact-title tests are being updated for the intentional visible
  session-label suffix. Packaging provenance must be regenerated after test-input
  edits; no artifact with a mismatching input manifest may be signed/installed.
- Strict format lint and diff whitespace checks passed on the current edits.

### Explicitly remaining

- Physical on-screen confirmation qualification and installed helper receipt check.
- Exact missing ASC control validation with its owning task, and actual client
  schema-import qualification (the raw JSON schema alone is not that client test).
- A complete internal baseline independent of bounded observation payload is not
  implemented: global absence predicates remain fail-closed on truncated text.
- Tasks sharing one transport connection remain one authority boundary; visible
  labels and diagnostics do not create task-level capability isolation.

### Final qualification progress

- Operator authorized restarting WebKitUI after coordinating other sessions.
- Full Debug validation passed: 555 Swift Testing cases across five targets plus
  13 XCTest keyboard-policy cases. Only `hostExclusiveSession` is excluded because
  the production app holds the real singleton lock. Commands rebuild sources;
  `--skip-build` is not used. Log: `/private/tmp/webkitui-630-debug-final.log`.
- The first full runs exposed only outdated exact-title expectations, now corrected
  for the intended session suffix. Full Release revalidation is in progress.
- The build router initially refused sandbox-local fallback with only about 7 GiB
  free internally. Escalated execution confirmed the external build volume and
  resumed the existing routing policy. No caches or user files were deleted and
  the disk-capacity guard was not changed.
- A first physical probe accidentally addressed an old `Products/Release` helper;
  its visual confirmation is NOT counted as 0.6.30 evidence. The operator then
  separately confirmed visibility of the signed 0.6.30 candidate's synthetic panel.
- The probe script initially compared UUID strings case-sensitively; corrected the
  script, not the product. The repeated exact-candidate probe emitted valid bound
  ordered/sampled records. Sampled: visible, AppKit-visible, key window, active
  Space and screen intersection all true. The local test was terminated after
  its 20-second limit, not approved. No browser session or external action existed.
- Confirmation titles with an opaque session suffix now localize the constant
  title before appending that suffix; packaged English/French checks cover this.
- Packaging correctly rejects changed source manifests. Sources are now frozen
  for the final archive; intermediate archives must not be installed. Installation
  verifies the final signed manifest against the checkout before stopping the broker.
- Internal storage subsequently exhausted during explicit-cache Release validation;
  the build failed before installation. The observed exhaustion does not establish
  that this build was its sole cause. With operator approval, the untracked cache
  `.build/out` was moved recoverably to
  `/Volumes/DeveloperStorage/BuildScratch/webkitui-630-cache.CnKNJf/out`, retaining
  `.build/out` as a symlink. No source or installed app was removed. Internal free
  space returned to about 7 GiB; Release validation resumed on the external cache.
- Final full Release validation passed: the same 555 Swift Testing cases and
  13 XCTest policy cases, with only `hostExclusiveSession` excluded. Log:
  `/private/tmp/webkitui-630-release-final.log`. Final strict recursive Swift format
  lint, whitespace checks and packaging/install shell syntax checks passed.

## Delivery — 0.6.30 (630) installed

- Final preview SHA-256:
  `3f62b9f40412f00480eace97968d6dbd4195135b568ea168129332195aa3ca40`.
  Final preview verifier passed, including English/French session-title localization,
  native probes, source provenance and embedded SiliconPass checks.
- Final signed archive:
  `dist/confirmation-session-0.6.30/signed-final/WebKitUI-MCP-0.6.30-signed-local.zip`.
  SHA-256 `0578a4d46b63504342b1aa0802733acfeaa92b71d44838fc0dee9a69a298b1f6`.
  Developer ID team `TDV6D5L785`; strict signature and round-trip pre-notarization
  verification passed. No notarization/upload/publication was performed. The earlier
  `signed/` archive is intermediate evidence, NOT the final installation artifact.
- Recoverable installation completed after explicit operator restart approval:
  `/Applications/WebKitUI MCP.app`, version 0.6.30, build 630. The old broker exited
  under SIGTERM, not SIGKILL. Rollback application:
  `/private/tmp/webkitui-0.6.30-install.heTr1K/rollback/WebKitUI MCP.app` (0.6.29).
  Preserve this rollback path; temporary-directory cleanup can remove it later.
- At 2026-10-12 11:18 CEST, exact installed broker process PID 1624 was running.
  Installed broker/helper/relay bytes match the final extracted signed candidate.
  Fresh checkout manifest matches installed manifest; manifest SHA-256:
  `820edb4df5682c4d6bc5a132c10a47d7b62c3c05c6dd017908efa5a6f208b953`.
- Installed transport verifier passed: version 0.6.30, 14 tools, two new owned
  sessions on separate clients, both closed, host lease released. No existing
  session was adopted. Installed raw schema exposes 11 operation object branches,
  zero conditional top-level allOf members and 10 postcondition branches.
- Installed strict deep signature and SiliconPass verifier passed: five connector
  tools, secret arguments rejected, vault neither read nor changed. Embedded input
  remains pinned to locally installed SiliconPass manager 0.2.2 (18); this is not a
  claim about an unverified upstream release newer than that manager.
- Logs: `/private/tmp/webkitui-630-preview-verify-final.log`,
  `/private/tmp/webkitui-630-sign-final.log`,
  `/private/tmp/webkitui-630-install-final.log`, and the Debug/Release logs above.

### Handoff: remaining work / limitations

- Requalify exact missing ASC controls and actual schema import with the owning
  task/client. Local synthetic pointer tests and raw schema checks do not prove
  those live cases fixed; do not reuse identifiers or account state from reports.
- Global absence predicates still fail closed on a truncated observation; a
  separate complete internal baseline has not been implemented.
- Tasks sharing one transport connection remain one authority boundary. Labels
  identify sessions, not separate task capabilities.
- The operator saw the signed 0.6.30 synthetic panel and its bound AppKit metadata
  was measured. This does not qualify every display/Space/full-screen combination
  or explain the external ScreenCaptureKit failure from the diagnostic report.
- No installation blocker remains. Disk space remains a machine-level concern;
  the external cache symlink requires the DeveloperStorage volume mounted.
- Preserve all existing dirty changes. No commit/push or other-project mutation
  occurred. Next coding provider must explicitly acquire sole-writer ownership.

## New OVH handoff diagnostic — read-only follow-up

Source: `/private/tmp/Vif-WebKitUI-OVH-Diagnostic-20261012/README.md`.
Read in full; the supplied directory contains only that README. No account/session
identifiers or observed URLs are copied here. Installed plist still identifies
0.6.30. Product code and external sessions were not changed by this follow-up.

- The report describes two native click timeouts after valid bounded arguments,
  with bound sampled presentation metadata and explicit no-dispatch outcomes.
  Therefore the observed click workflow remains unqualified despite the synthetic
  panel qualification; do not claim the OVH incident resolved by 0.6.30.
- Code confirms a default 60-second helper deadline and an AppKit visibility
  sample at two seconds. Positive sampled flags neither prove human perception
  nor continuous visibility through the deadline. The report establishes neither
  a physical click on either panel nor its routing failure.
- Helper keyboard event diagnostics are opt-in stderr output. The production
  presenter discards stderr and does not forward that diagnostic environment key.
  This supplied package has no event/lifetime logs to correlate retrospectively;
  request IDs alone do not imply a persisted log exists.
- `url_changes_from` is supported in current source/schema and checked against
  the fresh observation URL. Earlier malformed argument calls are separate from
  the two subsequent timeouts; do not use them to explain a helper deadline.
- The report still describes client-side unknown intersections. Installed raw
  schema had already verified eleven concrete operation branches; actual client
  import/cache/rendering remains unqualified, not proved fixed by raw discovery.
- SiliconPass fill failure is reported without an error payload; its cause is
  undetermined. Secretless connector packaging checks do not prove live fill.
- Next safe investigation, if authorized: a synthetic `browser_act` native
  confirmation using a fresh owned session, operator visibility/click feedback,
  bounded action-free event/lifetime diagnostics, and the actual client's fresh
  tool import. Never adopt the human-controlled OVH session, consume its handoff
  token or infer approval from flags. No automatic retry/restart was attempted.

## Robustness remediation — active Codex sole-writer ownership

Explicit scope: repair WebKitUI against the supplied diagnostics. Existing dirty
changes preserved; no commits, other-project writes, cloud uploads or account
actions. Fresh FULL reference audit completed and structurally validated before
new product edits. Private report session/token/account content is not reproduced.

Audit/plan/structured journal:
`/private/tmp/webkitui-robust-remediation.4lLi8h/`.
Baseline: 568 tests, Release build, installed signature/connector gates passed.
Platform reproduction: timer-only NSApplication.stop hung; application-defined
non-input wake returned promptly. This is not proof of the reported OVH cause.

Completed source work (not yet installed): production stop/wake, bounded live and
terminal presentation metadata, bounded helper termination/reaping, composition-
free typed tool discovery with strict runtime validation retained, SiliconPass
15s request/330s delivery budgets, one-shot/cancellable reply gate, expired callback
sink rejection, enum-only failure/recovery without remote error strings. Targeted
19-case suite passed; complete suite underway. A no-window event-loop verifier
and opt-in local native browser_act physical fixture were added. Version 0.6.31
(631) prepared; 0.6.30 remains installed at this checkpoint.

Remaining: final Debug/Release suites, formatter/syntax, exact provenance package,
signed helper timer and physical action gates, coordinated recoverable install,
installed transport/signature/embedded connector verification. Actual importer and
task-owned live SiliconPass/OVH qualification remain external gates. No retry of
foreign actions. Operator has freshly approved restart with sessions saved/paused.

### Final local checkpoint — 0.6.31 (631), 2026-10-12 12:12 UTC

The preceding active checkpoint is superseded for local validation/installation.
Final Debug and Release each PASS **576 tests** (563 Swift Testing + 13 XCTest).
Only hostExclusiveSession skipped: installed singleton owns the host; installed
two-client verifier separately PASS. Formatter, shell/Node syntax and diff checks
PASS. Final review caught an extra cancellation edge: a TERM-ignoring helper could
retain the turn until the general deadline. Fixed explicit-cancellation polling
and Task-cancellation precedence; 9-case confirmation regression suite PASS.

Physical local browser_act through the production presenter PASS with measured
trusted DOM event. Initial feedback was inconclusive; repeated with explicit
operator full-panel/approve feedback. Signed installed helper cancellation PASS:
bound decline and finished receipts, no browser action. Helper machine-code text
is unchanged between that physical cancellation and final installed helper
(SHA-256 `99a70770d884ef42511c2de036ffae00bb75a14479553058ecd1b80380d80fb5`).
This is not an exact final-broker physical action or original OVH closure claim.

- Final preview SHA-256: `fafe3184fa7e6900f0fb325729a44478968b16b3b14385279b13754cf97b6f3e`.
- Final signed archive: `dist/robustness-0.6.31/final/signed/WebKitUI-MCP-0.6.31-signed-local.zip`.
  SHA-256 `e1e19ff97417093f8e2035e1597badf8c4104738df9cf22ac18497a195245a28`.
  Earlier `dist/robustness-0.6.31/signed/` is intermediate, not final.
- Installed `/Applications/WebKitUI MCP.app`, 0.6.31 (631), Developer ID team
  TDV6D5L785, PID 35267 at checkpoint. Final signature, fresh checkout manifest and
  exact extracted broker/helper/relay byte comparisons PASS. Manifest SHA-256
  `12e2aec90a8b3bfd99a3b050ce75926635295683ae9adbcba665abae3bd212a1`.
- Final installed transport PASS: two new owned blank sessions, both closed,
  hostReleased true, 14 tools. Raw discovery PASS: composition-free schemas,
  11 act operations, 21 postcondition types; runtime conditional guards retained.
- Exact installed helper no-window timer stop/wake PASS. Embedded SiliconPass
  verifier PASS: five tools, secret arguments rejected, vault not read/changed.
  Connector pinned to installed manager 0.2.2 (18), not claimed latest upstream.
- Original 0.6.30 rollback: `/private/tmp/webkitui-0.6.31-install.XvEL21/rollback/WebKitUI MCP.app`.
  Intermediate 0.6.31 rollback: `/private/tmp/webkitui-0.6.31-install.dKB5Gx/rollback/WebKitUI MCP.app`.
  Temporary paths may be cleaned by the OS; preserve before long-term handoff.
- Final logs: `/private/tmp/webkitui-631-{debug,release}-final-tests.log`,
  `webkitui-631-{package,preview,sign,install}-final.log`,
  `webkitui-631-installed-final.log`, `webkitui-631-schema-final.log`,
  `webkitui-631-event-loop-final.log`. Final snapshot:
  `/private/tmp/webkitui-631-final-snapshot.json`, same HEAD/main, empty index,
  tracked worktree SHA-256 `2a4f1d4cb6758169959990a91728ec3c06e439d6d1ca9adc924eaa96b7552cf8`.

Remaining external gates: actual client catalog refresh/import in a new
conversation; task-owned live SiliconPass fill and OVH retry with fresh observation
and explicit authority. No foreign session/handoff token adoption. Wider physical
keyboard/display matrix and G9 final independent review are not claimed complete.
Structured journal validates as CHECKPOINT — EXTERNAL AUTHORIZATION REQUIRED,
not a global SOTA/readiness claim. Existing dirty changes preserved, no commit,
push, notarization, publication or other-project write. Codex sole-writer ownership
is relinquished at this handoff; next coding provider must acquire it explicitly.

## Build50 follow-up — Codex sole-writer ownership reacquired

Resuming from `/private/tmp/Vif-WebKitUI-OVH-Diagnostic-20261012/build50-followup.md`.
Full report read, no identifiers/account state copied. Source snapshot matches last
checkpoint exactly (tracked diff 2a4f1d4cb6758169959990a91728ec3c06e439d6d1ca9adc924eaa96b7552cf8).
Reported native navigation/form/public-text paths now work; download custody and
intermittent confirmation timeouts remain unqualified. No foreign session adopted,
download replayed, credentials inspected or restart authorized for this new batch.
Plan `/private/tmp/webkitui-robust-remediation.4lLi8h/WebKitUI-build50-plan-20261012.md`:
R-001 typed download confirmation errors; R-002 reproduce missing capture receipt;
R-003 bound late save-panel completion to its request and cancel owned failed downloads.

Build50 local corrections: all three regressions reproduced before product edits.
Typed confirmation errors, early isolated real-event capture, owned-download
cancellation/late-destination guard, and request-bound late trigger/timer handling
implemented. Focused five test functions (12 cases) PASS, log
`/private/tmp/webkitui-build50-targeted.log`; initial RED log
`/private/tmp/webkitui-build50-red.log`. No fabricated native trust or download
receipt; existing upload uncertainty tests retained via test-only transport removal.
Full Debug/Release validation IN PROGRESS. Installed 0.6.31 unchanged. Fresh restart
coordination requested; no restart or live portal action performed. Remaining:
complete suites, package/physical qualification and owning-client live confirmation/
download custody revalidation. Native modal lifecycle/page-loss cause not claimed fixed.

First complete Debug run caught a same-origin iframe receipt regression. Installation
blocked; Release was not started. `dist/robustness-0.6.32/preview` is SUPERSEDED and
must NOT be signed/installed. Target-window recorder correction under validation.
Fresh user restart approval received, but conditional on successful validations.

## Build50 final checkpoint — 0.6.32 (632) installed

Completed: R-001 typed download confirmation outcomes; R-002 early isolated
target-window capture of genuine native clicks (including same-origin iframe);
R-003 late save-destination rejection, owned failed-download cancellation and
request-bound timer/trigger handling. Existing trust, upload uncertainty and
cross-session isolation checks preserved. No live portal or credential action.

Validation: final Debug and isolated Release each PASS 579 tests (566 Swift Testing
across five bundles +13 XCTest), excluding only hostExclusiveSession. Three isolated
Release repetitions of moving-button regression PASS. Initial iframe regression
was fixed; one subsequent moving-button failure during concurrent helper probes
is retained in evidence, with interference only a hypothesis. Full final isolated
Release PASS. Future AppKit validations must run serially, not alongside helper UI
probes. Strict formatter lint and git diff --check PASS.

FINAL preview `dist/robustness-0.6.32/final/preview`, SHA256
`5ff5909d516fb669d0c06984a0e2da5543423757187fd48dc92b6e15b69c6a74`.
FINAL signed archive `dist/robustness-0.6.32/final/signed/WebKitUI-MCP-0.6.32-signed-local.zip`,
SHA256 `193e3ea571161f8f0b0dc5fc7222cf70d1e1b27778fdef914592146ddd5d02d7`.
Installed `/Applications/WebKitUI MCP.app`, version 0.6.32/build632, after fresh
operator coordination. Signature, exact three signed executable comparisons,
current-source/installed manifest comparison PASS. Installed manifest SHA256
`572b6a87bf3ed8dd8276096e545ecba241dc252f62f454e9891eff10a396f4df`.
Installed transport PASS: two fresh blank owned sessions, 14 tools, distinct session
ownership, both closed/hostReleased. SiliconPass embedded pin unchanged 0.2.2(18):
five tools, secret arguments rejected, vault not read/modified; not latest-upstream proof.
Rollback `/private/tmp/webkitui-0.6.32-install.H27vQr/rollback/WebKitUI MCP.app`.

Evidence `/private/tmp/webkitui-build50-{debug-final,release-isolated,targeted,frame,moving-1,moving-2,moving-3}.log`,
`/private/tmp/webkitui-632-{package-final,preview-final,sign-final,install-final,installed-final,format}.log`,
snapshot `/private/tmp/webkitui-632-final-snapshot.json`, external structured journal
and adjacent build50 plan. First `dist/robustness-0.6.32/preview` remains SUPERSEDED.

Remaining: owning-client fresh OVH confirmation/download custody qualification;
native save-panel lifecycle and page-loss root cause; manual downloads without a
managed request (currently cancelled by existing policy); G9 independent review.
No global robustness or incident-closure claim. No keys recreated/exported/read,
foreign sessions adopted, cloud upload, commit, push, notarization or publication.
All pre-existing dirty changes preserved. Codex sole-writer ownership relinquished
at this checkpoint; next coding provider must explicitly acquire before writing.

## Native controls follow-up — sole writer Codex reacquired

New user authorizes download UX and native find improvements inspired by Navigateur
(read-only reference). Full retest-0.6.32 report read; no private IDs copied. Source
matches installed checkpoint, snapshot `/private/tmp/webkitui-633-start.json`.
Plan `/private/tmp/webkitui-robust-remediation.4lLi8h/WebKitUI-native-controls-plan-20261012.md`.
First lot R-004: reproduce composed-tree hit-testing disagreement using synthetic
custom/slotted controls, without weakening trusted-click safeguards. Remaining
R-005 cancellable native save sheet and R-006 Cmd-F search. No restart authorized
for this batch; no foreign/live session or credential action. Existing changes preserved.

## Native controls checkpoint — PARTIAL INFRA BLOCKED

Completed local R-004: synthetic custom shadow/slotted button reproduced observed
actionable/native targetNotActionable mismatch. Native click arm now uses existing
composed-tree hitReaches, preserving identity/geometry/trust and rejecting unrelated
overlay. RED `webkitui-633-shadow-red.log`, GREEN `webkitui-633-shadow-green.log`
under `/private/tmp`: four functions/five cases PASS (shadow/covered, iframe,
moving target, blob capture). No live portal cause/acceptance inferred.

Remaining source changes (NOT acceptance-qualified):
`Sources/WebKitUIMCPRuntime/NativeBrowserControls.swift`, runtime integration and
EN/FR strings: cancellable request/window-bound save sheet; local native search
Cmd-F/G/Shift-G/Escape, focus and stale-result invalidation. Initial controls build
succeeded after delegate conformance fix, but Swift Testing stopped during actual
sheet test without summary, twice; exit0 is NOT PASS. Native sheet test is opt-in;
dedicated run-loop probe `/private/tmp/webkitui-controls-probe.swift` prepared,
not compiled/run. Find/controller final tests and full suites NOT RUN successfully.
Do not ship these pending changes based on R-004 green alone.

Blocker: `/Volumes/DeveloperStorage` is absent, only 6GiB internal free; m2-build
refuses fallback. `/private/tmp/webkitui-633-controls-final.log` records refusal.
No cache deletion, disk guard bypass, installation or restart. Installed 0.6.32(632)
unchanged. Fresh coordinated restart approval received, conditional on validation;
reconfirm pause if sessions have resumed before eventual installation.

Next: reconnect M.2 DeveloperStorage; run focused controls/find/shadow tests and
dedicated save-sheet probe serially with bounded watchdog; require summary counts;
complete Debug/Release, fresh version/artifact/signature and UI qualification.
Native destination panel currently under test, manual unmanaged downloads unchanged;
privacy-safe structured download-stage diagnostics still remaining. Live OVH belongs
to owning task; no keys/accounts/foreign sessions touched. Navigateur read-only.
No commit/push/upload/notarization/publication. Sole-writer ownership relinquished
for handoff; next writer must reacquire. Existing dirty changes preserved.

## Native controls resumed — Codex sole writer reacquired

DeveloperStorage mounted again, ~12GiB available (internal ~5.7GiB). Compiler via
M.2 dispatcher responds; no disk guard bypass or cache deletion. Resume snapshot
`/private/tmp/webkitui-633-resume.json` matches blocked snapshot: HEAD unchanged,
tracked diff 8fa00767409504a33841b4c0814e3b11d5be369019a1e1d4a04bacfc56cc86c2.
Continue focused tests then dedicated native sheet probe serially. Installed 0.6.32
unchanged; new controls still pending acceptance. No foreign session/account actions.

## Native controls validation — source frozen 0.6.33 (633)

R-004 local synthetic shadow/slotted click correction PASS; portal causality not
inferred. R-005 asynchronous native destination sheet bounded to its request and
parent; dedicated NSApplication.run probe PASS cancel/revoke/parent-close and
duplicate refusal, no Save automated or file written. R-006 native human-only
Cmd-F/G/Shift-G/Escape and stale callback invalidation focused PASS. Guard-refusal
tests replace the earlier opt-in native-sheet test; no skipped-case acceptance.
Privacy-safe download failures now expose fixed stage and booleans, bound to the
exact request completion rather than mutable latest-attempt state; no raw URL,
path, label or credential added. Unmanaged download policy unchanged.

Final Release source: 583 tests PASS (570 Swift Testing plus 13 XCTest), five
summaries, no failure; `/private/tmp/webkitui-633-release.log`. Preliminary Debug
also 583 PASS but predates final callback binding, so is NOT final acceptance.
Final Debug/probe serial validation running: `webkitui-633-debug-final.log`, then
`webkitui-633-native-final.log` under `/private/tmp`. Plists, localization syntax,
shell syntax and git diff whitespace PASS. No new installation; installed632
unchanged. Source frozen for fresh package/signature gates. M.2 ~10GiB free;
no cache deletion or storage guard bypass. Codex remains the sole coding writer.

## FINAL native-controls checkpoint — installed 0.6.33 (633)

Final Debug and Release each 583 PASS (570 Swift Testing +13 XCTest), all five
summaries/no failures, hostExclusiveSession excluded as before. Serial checked-in
native sheet wrapper PASS cancel/revoke/parent-close, duplicate refusal/one-shot,
no Save automated/file written. Logs `/private/tmp/webkitui-633-{debug-final,release,native-final}.log`.
Native local search and shadow-button correction tested; actual portal cause and
end-to-end download custody remain owning-task qualification, no live retries.

Fresh preview/provenance PASS; final accepted signed archive is ONLY
`dist/robustness-0.6.33/final/signed-retry/WebKitUI-MCP-0.6.33-signed-local.zip`,
SHA256 2cfaeb4ef386a464089eaf929d14898eca6a6261a506bb70279ff7698b213464.
Preview SHA256 0e62866b0934119364851c78b8955682dbff06b6dc58adc6d96ddb9a22ef113a.
Installed source manifest SHA256
9080cc9c2d50c52d93bcc308fcf920f103702aaff8ba03f209837a5fefd302a6.
Coordinated restart/install PASS; exact source, signatures and broker/helper/relay
bytes checked. Rollback632 preserved at
`/private/tmp/webkitui-0.6.33-install.GQbckv/rollback/WebKitUI MCP.app`.
Installed transport PASS:14 tools, two distinct fresh blank sessions both closed,
hostReleased. Logs `/private/tmp/webkitui-633-{package-final,preview-final,sign-retry,install-final,installed-final}.log`.
SiliconPass embedded pin remains0.2.2(18), five tools/secret-argument rejection,
vault not read/changed; not independently verified latest upstream.

Important retained reliability evidence: initial signing round-trip and exact
archive recheck failed presentation metadata gate. Dedicated exact-helper probe
then observed request/PID-bound visible flags; single fresh signing attempt passed
both unchanged gates. Cause not established. Logs `webkitui-633-sign-final.log`,
`webkitui-633-sign-recheck.log`; probe evidence
`/private/tmp/webkitui-633-presentation.YhjD7a`. Earlier `final/signed` archive is
NOT ACCEPTED; do not install it. No gate weakened/no global robustness claim.

Snapshot `/private/tmp/webkitui-633-final-snapshot.json`,2026-10-12T20:51:01.676221+00:00,
HEAD52a3dc1352dc18282d348bd3327f7fc78e78016d, empty index, tracked diff
0ef3e0060b9661d051e69bf3cad33e926b44327aadf44ac25d6c49c6244d3bbb.
Remaining: owning-client physical Save/live transfer custody, intermittent helper
presentation investigation, wider device UX and G9. Manual unmanaged downloads
retain existing cancellation policy. No foreign sessions/accounts/keys touched,
Navigateur read-only, no commit/push/upload/notarization/publication. All existing
changes preserved. Codex sole-writer ownership relinquished for safe handoff;
next coding provider must explicitly reacquire before writing.

## Retest633 resumed — Codex sole writer reacquired

Read supplied retest633 fully; live shadow-control progress confirmed, final actual
download timeout/page loss remains separate OPEN. No private report identifiers
copied. Snapshot /private/tmp/webkitui-634-start.json exactly matches final633
HEAD/index/tracked diff (different discovery hash algorithm initially looked like
drift; same snapshot tool confirms no drift). Plan external
WebKitUI-download-633-plan-20261012.md beside remediation journal. R-007 bounded
timeout stage evidence first; R-008 synthetic Blob/navigation reproduction before
causal correction; R-009 Always Allow session/persistent scope awaits user choice.
Installed633 unchanged, no new restart approval; no live retry/credential access.

### Retest633 local correction progress — 2026-10-13

R-007 locally implemented: timeout now uses exact request-bound dispatch/stage
evidence while preserving download_timeout/download_receipt_timed_out. Additional
navigation action/response, new-window, destination-selection, URL-change and
main-frame-commit booleans, no raw values. No automatic replay/recovery navigation.
Focused actual120s server timeout + covered-target refusal PASS; runtime timeout
retains trusted dispatch and existing page PASS. Logs under /private/tmp:
webkitui-634-download-focused.log, webkitui-634-timeout-baseline.log.

R-008 subcase RED: explicitly requested same-origin Blob navigation without a
download attribute failed unsupportedDownload. Minimal request/origin-bound
conversion GREEN verifies synthetic SHA and preserves form. Deferred Blob exports
with/without _blank PASS; cross-origin and ordinary HTML refusals PASS. Evidence
webkitui-634-blob-red.log and webkitui-634-blob-green.log. Actual OVH timeout/page
loss cause still OPEN; do not infer closure from this distinct local subcase.

Prepared0.6.34(634); strict format PASS; complete Debug/Release serial validation
running. No package/install or restart, installed633 unchanged. R-009 user wants
local UI to choose session vs persistent duration. Not implemented in this batch;
duration is separate from action scope. Client names self-reported, connection UUID
not restart-stable: never treat name as authenticated persistent-client identity.
Unknown/consequential actions still require exact confirmation; no blanket bypass.

External previous remediation directory unexpectedly absent on2026-10-13;
historical ledger references retained but those files no longer available. Current
634 snapshots/logs remain. No cleanup performed by Codex. This durable ledger is
the current safe handoff, prior acceptance details cannot replace missing evidence.
Next gates: complete suites, fresh package/signature, fresh coordinated restart
approval, then owning-task live qualification. Codex remains sole coding writer.

Download-only checkpoint: complete Debug/Release each587 PASS (574 Swift Testing
+13 XCTest), five summaries/no failure. Logs webkitui-634-{debug-final,release-final}.log;
snapshot webkitui-634-download-checkpoint.json. These precede the authorized
remembered-permissions feature: final shipping suites must rerun after that lot.
User now approves local UI choices navigation vs navigation+clicks/typing, each
session vs persistent. Once/cancel defaults, clear consequences warning and local
revocation required. Unknown click effects cannot be perfectly classified. No
client-name-based persistent authority. New lot continues under sole writer Codex;
installed633 unchanged, no artifact or restart yet.

### Remembered site permissions implementation — in progress

User explicitly selected UI choices navigation-only vs navigation+clicks/typing,
with session vs remembered duration. Added typed helper choices (exit8–11), optional
request flags, explicit native menu, FR/EN disclosures, and native revoke-all menu.
No choice by default; Cancel/Approve Once do not store grants. Native presenter
accepts remembered code only for opted-in request, permitted persistence and bound
approval metadata. No MCP grant operation. Session grant bound client/session/site/
profile; persistent grant explicitly ALL agents in exact profile/site, never based
on a claimed client name. URL credentials, foreign scheme/port/origin, invalid or
oversized preference data fail closed. Private data stores cannot persist grants.
Downloads/uploads/native form submissions/dialogs/auth/control-transfer still use
their existing separate gates. Clicks/typing can have consequential site effects;
the native warning states that limitation rather than promising classification.
Receipts report authorization_source, distinguishing reuse from exact confirmation.

Core three store tests PASS; first integration compile failed test ID Int/Int64,
corrected. First MCP self-grant test expected wrong envelope, corrected without
weakening assertion. Final focused7 functions PASS, including parameter cases;
webkitui-634-permissions-gates.log. UI menu layout/key-loop qualification being
compiled; not yet physical UI qualified. Existing full587 Debug/Release are
PRE-PERMISSIONS and not final shipping acceptance. Complete suites and source
provenance must rerun after feature source freeze. Installed633 unchanged. Codex
sole writer continues; no real grants, accounts or foreign sessions touched.

Permission menu layout/key loop PASS in session-only and persistent modes:
webkitui-634-menu-{session,persistent}.log. No input posted/default grant false.
FR/EN resource lint and shell syntax PASS. README/security threat model reconciled
to profile-wide persistent authority, consequential clicks/typing, separate gates,
revocation affecting future admissions only. Final post-permissions Debug running
serially, webkitui-634-permissions-debug-final.log. Initial sandbox could not access
M.2; retried with authorized escalation, no internal fallback or guard bypass.
Fresh coordinated restart question sent; no new approval received yet. Installed
633 unchanged; physical UI, final Release, package/signature/install remain OPEN.

Final post-permissions Debug PASS594 (581 Swift Testing across five bundles:
180 server,237 runtime,18 policy,90 core,56 adversarial; plus13 XCTest), no failures.
Release running serially, webkitui-634-permissions-release-final.log. Strict
swift-format lint PASS (webkitui-634-permissions-format.log). Structured scoped
remediation journal validates with allow-in-progress. Snapshot saved at
webkitui-634-permissions-checkpoint.json. User explicitly confirmed all other
sessions saved/paused and permits634 restart after tests/package validation.
This grants local installation only, not portal actions or public distribution.

## 0.6.34 installed checkpoint — 2026-10-13

Completed: final Debug and Release each594 PASS (581 Swift Testing, five summaries,
plus13 XCTest; no failures). Only hostExclusiveSession excluded because installed
singleton owns the host; installed two-client test covers fresh sessions instead.
Three native-sheet probes PASS (cancel/revoke/parent-close), log
webkitui-634-native-final.log. Initial direct script launch exit126 (not executable),
rerun via sh PASS; permissions unchanged. Preview package and archive verification
PASS, logs webkitui-634-package-final.log and webkitui-634-package-verify.log.
Exact signing plus round-trip signature/presentation/event-loop/menu gates PASS,
webkitui-634-sign-final.log. No failed634 signed artifact accepted or overwritten.

Accepted archive: dist/robustness-0.6.34/final/signed/WebKitUI-MCP-0.6.34-signed-local.zip
SHA25690801ae3b652560e9d3251b56067a5c8aebfbd6b5abb93eea6e6f03d897abf54.
Input preview SHA2567c7b643ebebeb80ba1ea1eb7475d8452e8f9fbc4d45d6a46743c90a53a13cb81.
Installed /Applications/WebKitUI MCP.app is0.6.34(634), signature strict/deep and
source manifest/binary byte comparisons PASS. Manifest SHA256
d646f3ffad6d78a158be7a3f2d13d74900764cdf5f3586d1f40fe2472d26be50.
Rollback633: /private/tmp/webkitui-0.6.34-install.ThrzHi/rollback/WebKitUI MCP.app.
Installation log webkitui-634-install.log; coordinated restart expressly approved.
Installed MCP qualification PASS14 tools,2 distinct freshblank sessions, bothclosed,
hostReleased true; webkitui-634-installed-verification.log. No foreign sessions or
live provider actions used.

Physical installed-helper menu: user confirms four options entirely visible.
First standalone synthetic run returned11 (persistentInteractions), not requested8;
recorded discrepancy without claiming first-option mapping. Second explicit first
option selection confirmed by user returned8 (sessionNavigation), with bound
visible/active-space/intersecting decision/finished receipts. Logs
webkitui-634-permission-ui{,-second}.{out,err}; neither isolated helper run has any
store/backend or creates a real grant. No input synthesized by Codex.

Remaining: owning-task actual OVH export timeout/page-loss qualification; current
local Blob correction is not proof of its cause. Historical intermittent633
presentation cause remains unresolved despite634 packaged/installed checks PASS.
Persistent-store reload tested using isolated backend, not a real user grant or
Mac-restart persistence experiment. SiliconPass pin0.2.2(18),5tools verified without
vault read/change; latest upstream not established. Historical temporary FULL audit
missing; no fresh global security/SOTA/readiness claim. No commit/push/publication.
Scoped journal: /private/tmp/WebKitUI-download-remediation-20261013.md. Final snapshot
/private/tmp/webkitui-634-installed-final-snapshot.json. Codex relinquishes sole
coding-writer ownership for handoff; next writer must reacquire. Dirty changes
preserved; no ongoing tests/probes or pending implementation in this local lot.

## Export new-window correction resumed — Codex sole writer reacquired

User authorizes correction following ovh-export-retry-20261013.md (read-only source
in AirDrop project; no other-project writes). Baseline635-start snapshot matches
634-installed-final except timestamp; HEAD/index/worktree unchanged. Installed634.
New receipt: trusted native dispatch/new-window requested, no navigation policy,
no destination/download, parent URL changed and document unusable. Actual cause
still hypothesis. Plan R-010: RED local blank-popup asynchronous Blob export;
retain request-bound isolated destination web view using provided configuration;
strict origin/attachment policy, one request lifetime, cleanup on every terminal
path, parent document never repurposed. Then targeted boundary/lifecycle tests,
full serial Debug/Release, package/signature, fresh restart approval and installed
checks. No live OVH replay, secrets, session sign-in or credential recreation.
Research: current Apple createWebViewWith configuration and didBecomeDownload
delegate docs support native callback architecture, not OVH causality. Existing
DeepSearsh bounded negative evidence reused; NotebookLM N/A no cloud consent.

R-010 focused GREEN: webkitui-635-popup-qualified.log,4functions including3export
cases (blank async Blob/script HTTP/link HTTP, cookie required for attachment) and
5failure cases (timeout/foreign origin/ordinary HTML/close/cancel destination),
each failure twice with fresh explicit test observation proving cleanup/no slot
leak. Original form/URL/value preserved, synthetic hash receipt verified.
Early expanded attempts failed legacy102 domain mismatch; retained logs
popup-focused,focused-retry,focused-final. SDK WebKitErrors.h confirms exact
WebKitErrorDomain/code102; old filter only matched WKError.errorDomain. Both exact
known domains now recognized as interrupted navigation, never as file success.
Diagnostics add new_window_source_main_frame/new_window_target_absent/
download_window_created booleans only. New view bound requestUUID/delegateidentity,
same origin/GET and attachment/explicitdownload/Blob policy; no URL replay in parent,
ordinary hidden HTML or agent-visible tab. Original configuration/profile retained.
Version prepared635; full serial Debug/Release/native gates running. Sourcefreeze
snapshot webkitui-635-source-freeze.json. User expressly confirms other sessions
saved/paused and permits635 restart after validation. Installed634 still unchanged.
Scoped journal /private/tmp/WebKitUI-popup-remediation-20261013.md validates.

Final635 Debug PASS596:180server+239runtime+18policy+90core+56adversarial
Swift Testing, plus13XCTest, five summaries/no failures. Strict format PASS empty
webkitui-635-format.log; version plist lint PASS. Release in progress serially under
webkitui-635-validate.sh driver; no concurrent AppKit validation or source edits.
Installed634 unchanged. Source freeze maintained, no OVH/live credential actions.

## 0.6.35 installed checkpoint — 2026-10-13

Completed R-010 local new-window export correction, prepared and installed635.
Final Debug/Release each596 PASS (180server+239runtime+18policy+90core+56adversarial
Swift Testing plus13XCTest), five summaries/no failures. Only hostExclusiveSession
excluded for installed singleton; separate installed two-client test PASS below.
Format/diff/plist PASS. Three native-sheet probes PASS, webkitui-635-native-final.log.
No positive human save-panel selection performed in this session; synthetic files
used injected destinations, native probes cover cancellation/revocation/parentclose.

Fresh preview/package verification PASS, webkitui-635-{package-final,package-verify}.log.
Exact signing and extracted archive signature, event-loop, menu layout/key-loop and
bound visible-presentation gates PASS twice, webkitui-635-sign-final.log. No failed
635 package accepted. Signed archive:
dist/robustness-0.6.35/final/signed/WebKitUI-MCP-0.6.35-signed-local.zip
SHA256dcb8f4116a8b9f57d7b56d4b637873ae1ac1dc74b1b587a490cad5a449e2df3c.
Preview SHA256389df734426448ace3bcdcd2b021e06ff369c63a6a07bc806ee2ea541288de71.
Installed /Applications/WebKitUI MCP.app is0.6.35(635); strict/deep signature,
source manifest and executable byte comparisons PASS, webkitui-635-install.log.
Installed manifest SHA256657c19e68ba64be3f6108c2c79086868ba6251e32a2e550ccd43a6122dcb701c.
Coordinated restart expressly approved;634 rollback preserved:
/private/tmp/webkitui-0.6.35-install.yv2jZ2/rollback/WebKitUI MCP.app.
Installed verifier PASS14tools/2distinct freshblank sessions, bothclosed and
hostReleased true; webkitui-635-installed-verification.log. No foreign sessions,
real permissions, credential files or portal actions used.

Remaining work: owning OVH mission may qualify one final export after its own
admission gates. Require native destination selection AND on-disk artifact receipt;
never infer success from click/window/loading. Actual OVH cause still unproven;
local blank-popup mechanism reproduced/fixed is not provider causality proof.
If failure, new flags distinguish source/target frame and retained export view,
alongside request-local navigation/dispatch/destination flags. No blind replay,
fallback endpoint, user/key creation or secret-bearing diagnostics authorized.
Historical intermittent presentation cause and missing FULL audit remain OPEN;
no all-fixed/global audit/latest-upstream-SiliconPass/readiness claim. SiliconPass
existing pin0.2.2(18),5tools verified without vault access, unchanged in this lot.
Scoped journal /private/tmp/WebKitUI-popup-remediation-20261013.md; final snapshot
/private/tmp/webkitui-635-installed-final-snapshot.json. Codex relinquishes sole
coding-writer ownership for handoff, next writer must reacquire. Existing dirty
changes preserved; no ongoing tests/probes or pending local implementation.
