# Lumen feedback: native MCP resume blocked by privacy inventory limit

Date: 2026-10-20. Reporter: Codex / Lumen mission.
Status: REPRODUCED WORKFLOW BLOCKER; no product patch or installed-app change.
Priority: P1 for the recovery deadlock, P2 for the human-navigation gap.

## Observed result

An explicitly authorized Reddit post update could not reach the editor. Native
navigation succeeded, but observation returned `privacy_scan_limit_exceeded`.
The recommended handoff did not recover the workflow: after the person returned
control, resuming attempted another observation and returned the same stable
error. Navigation remained refused as `human_control_active`. No edit, fill,
save, new topic, or message was dispatched.

This reports an availability/recovery failure, not a request to weaken privacy.
No unfiltered DOM or secret content was retrieved.

## Environment and evidence scope

- Installed native app Info.plist: version 0.6.40, build 640.
- CLI doctor: existing local Release executable, exit 0; not rebuilt or installed.
  That CLI is not proven byte-identical to the installed broker.
- Doctor reports arm64 / macOS 27.0.1, native helper available, readiness
  `ready_without_siliconpass_fill`. Credential authorization is unavailable in
  that invocation (public LA error code 4099). This is not evidence that the
  interactive app cannot authenticate, or the cause of the Reddit privacy error.
- Provider origin: https://www.reddit.com. Paths, queries, author identity,
  post text, screenshot, session handles and opaque grants are excluded.
- Local source is dirty and contains other missions' work. It was inspected
  read-only. Installed source provenance was not established.

Files delivered alongside this note:
1. `2026-10-20-lumen-native-mcp-events.json`: curated, sanitized event sequence.
   This is not a raw transport, browser-profile or receipt export.
2. `2026-10-20-lumen-native-mcp-doctor.json`: official allowlisted CLI JSON.

## Reproduction sequence from this mission

1. Navigate an owned native session to a Reddit page; document readiness is ready.
2. Observe; receive `privacy_scan_limit_exceeded` with automatic retry forbidden
   and browser_session handoff recommended.
3. Start handoff. The human clicks the explicit return-control button.
4. Status reports human_step_completed.
5. Resume with browser_session handoff, compact=true, maximum_elements=5.
6. The operation returns the same privacy-limit code instead of a usable
   agent-controlled state. No unfiltered observation is returned.
7. Status still reports human_step_completed; navigation to the intended post
   is refused as human_control_active and dispatched=false.
8. The human followed site links to a different Reddit page; a resume from that
   changed page also hit the privacy limit.
9. Closing/reopening the owned session preserves the browser and returns a reused
   session. The human authority state still prevents agent navigation.
   No other session was closed or adopted.

The agent initially told the person to paste the target URL into the handoff
window's address bar. The person reported that no address bar is available.
That suggestion was incorrect. The actual toolbar was not independently
visually inspected, so absence is user-reported rather than visual proof.

## Expected recovery

Privacy failures should continue to withhold all unsafe semantics. The user
should nevertheless have a supported way to leave the problematic document:

- Separate successful explicit authority return from successful semantic
  extraction. A resume could report agent control plus observation_unavailable,
  retaining all normal navigation confirmation and privacy guards.
- Alternatively provide a real local human URL/navigation control, or another
  bounded recovery route with explicit destination confirmation.
- Preserve the fact that no site save or dispatch has been established.
- Expose safe budget diagnostics (limit category and bounded counters only) to
  distinguish root/value/character limits without serializing values.
- Describe close/open preservation accurately; it did not reset this handoff.
- Do not silently retry a write, reset another mission, remove the filter, or
  increase privacy budgets without appropriate qualification.

## Read-only source leads; not established root cause

The current checkout maps privacy inventory failures to handoff in
`Sources/WebKitUIMCPServer/MCPServer.swift`.
`Sources/WebKitUIMCPRuntime/BrowserTextPrivacy.swift` contains independent
value, character and root budgets. The observed stable error does not identify
which budget was hit. No current provider DOM, sensitive values or trigger was
collected, so neither a specific false positive nor installed-source identity
is established.

Please cover recovery with a synthetic budget-exhaustion fixture: human return,
privacy-failed observation, exact-destination navigation, preserved filter and
no write replay. Qualify the resulting behavior on the installed native app;
source tests alone will not close the provider workflow.

## Separate fallback failures

CUA Safari selection failed with code -10005 / failedToCreateImageDestination.
The in-app browser was unavailable. These explain why fallback could not finish
the task, but are not attributed to WebKitUI without further evidence.

## Retention and scope

Only this feedback note and its two sanitized attachments are added. Existing
files and product code are preserved. No build, simulator, background process,
new temporary build folder, restart, installation, commit, push or public issue.
The user explicitly requested delivery of this feedback and logs to the native
MCP project. No private transcript or account data is copied.

