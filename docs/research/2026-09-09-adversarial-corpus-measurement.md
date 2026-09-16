# Adversarial corpus measurement

Measured on 2026-09-15. The corpus asks a deliberately narrow question: when a
hostile page supplies text, URLs, control state, and misleading destinations, does
WebKitUI MCP preserve the truth at the observation, confirmation, action, receipt, and
audit boundaries? It does not measure whether an autonomous agent resists prompt
injection.

## Result

The final corpus reports **53 passing Swift tests covering 57 concrete fixture
executions**. The difference is explicit: the destination suite groups four non-network
schemes into one parameterized Swift test and drives the host and path bidi cases through
two pages in one test. The confirmation-forgery family presents five confirmations per
fixture to exercise the burst annotation, for 60 recorded dialogs. Across the whole
corpus, 88 actual confirmation messages were inspected and Task 4 performed eight
actions with eight verified ReceiptV1 exports.

| Family | Swift tests | Concrete fixture executions | First product-bearing run | Final |
| --- | ---: | ---: | ---: | ---: |
| Hostile page truthfulness and harness | 17 | 17 | 17/17 | 17/17 |
| Confirmation forgery | 12 | 12 | 12/12 | 12/12 |
| Submission destination truth | 16 | 20 | 15/16 tests; 19/20 executions | 16/16; 20/20 |
| Receipt and audit leakage | 8 | 8 | 6/8 | 8/8 |
| **Total** | **53** | **57** | **50/53 tests; 54/57 executions** | **53/53; 57/57** |

“First product-bearing run” means the first run in which the fixture reached its product
assertions. The confirmation-forgery harness initially treated the deliberately declined
action result as a tool failure and stopped before those assertions; after that harness
error was corrected, all 12 product assertions held on their first execution. This is not
counted as a product pass or product finding. Likewise, the Task 1 implementation step in
which the test target did not yet exist is not a security measurement.

The hidden-instruction family found no unlabelled path. Visible, ARIA, label, option,
clipped, off-screen, white-on-white, and live-region content that surfaced retained
first-party-site provenance. `display:none`, `visibility:hidden`, zero-size, and generated
pseudo-element content stayed absent. The confirmation family found no string that
escaped JSON quoting or forged the ordered application-owned sections, including CR/LF,
JSON escapes, all tested bidi controls, zero-width characters, stacked combining marks,
full-width text, and a 100 kB label.

## Findings

| ID | Rank | Finding | Disposition |
| --- | --- | --- | --- |
| AC-01 | P1 | A `formaction` changed after observation was not read again for confirmation. The action resolver used the live DOM, while the dialog showed the old recipient from the snapshot. | **Fixed.** The same observation-scoped locator and physical identity now resolve the live control before the dialog, and the fresh sanitized destination is shown. The mutation fixture failed before the change and passes after it. |
| AC-02 | P2 | An accessible name bounded during observation was compared with its unbounded live value. A control with a 100 kB or combining-mark-heavy name could be observed but not resolved again. This was a refusal/availability defect; no dispatch was reported. | **Fixed.** Each target retains the observation's field bound and applies that same bound to live locator facts. The two extreme-label confirmation fixtures caught the regression during integration. |
| AC-03 | P1 | A normal page URL kept literal query values. The query canary therefore appeared in the observation and was copied into the confirmation's current-page line. It did not appear in the action result, ReceiptV1, navigation audit, or activity log. | **Fixed.** Model-visible URLs retain at most 16 query names and replace every value with `<redacted>`; the runtime keeps the exact URL locally. The raw `location.href` observation path now uses the same projection. Both failing surface tests pass. |
| AC-04 | P1 | A URL fragment remains visible in the observation and confirmation. The fragment can identify meaningful SPA state, but it is also the HashJack injection channel described by the security research. It did not reach action results, receipts, navigation audit, or activity logs. | **Accepted/open for this measurement.** The fixture pins the current boundary. Removing or provenance-wrapping fragments needs a separate product decision; this task did not silently discard them. |

The plan's pre-existing sanitization question did not become a finding in the measured
path. Web URL parsing serialized Cyrillic hosts as ASCII punycode, compatibility-normalized
the full-width host, rejected a bidi-bearing host into the explicit `UNKNOWN` path, and
the confirmation projected valid destinations to origin only, dropping a bidi-bearing
path. No bidi or control scalar reached the operator, so the destination line did not
need a second `safeConfirmationText` pass for these fixtures.

## Receipt and secret boundary

The receipt family placed one query canary in the page URL and in `href`, `formaction`,
form `action`, and `src`; it placed a different canary in a password value. Every run
performed the native-confirmed submit-control click, proved a newly rendered semantic
heading, and exported the verified transaction receipt. Assertions encoded each surface
to JSON bytes and searched the bytes, so a future field is covered without naming it.

After AC-03 was fixed, neither literal canary appeared in observation, confirmation,
action result, canonical/base64/Markdown ReceiptV1 output, the latest navigation audit
event, or the activity-log export. The fixture uses only inline HTML and a `data:` image;
it performs no fixture network request.

## What this does not measure

- Human clickthrough, comprehension, or whether the operator notices a truthful warning.
- Attention exhaustion beyond verifying that the fifth dialog states the burst count and
  the existing twentieth-request policy remains covered elsewhere.
- An attacker who authors or compromises the trusted task itself.
- Any behavior, planning quality, or attack susceptibility of the model driving the
  tools. No model drives this deterministic corpus.
- Screenshot/OCR or other pixel-derived instructions, live provider behavior, external
  network exfiltration, or cross-session secret flow.

These exclusions matter. **53/53 is a contract-test result, not an attack-success rate
and not a safety percentage.**

## Comparison with published measurements

The rates summarized in the companion
[security research](2026-09-09-agentic-browser-security-sota.md) measure attacks against
agents and therefore are not numerically comparable with this corpus:

- RedTeamCUA/RTC-Bench reports Operator at 7.57% ASR, versus 42.9% for Claude 3.7
  Sonnet CUA, 48% for Claude 4 Opus CUA, and 66.19% for GPT-4o; attempt rate reached
  92.5%. Those trajectories include an acting agent and a confirmation policy.
- Prismata reports WebArena ASR falling from 85.5% to 0.7%, with benign task success
  falling 3.3 percentage points. It measures an intra-page trust-segmentation defense
  across model-driven tasks.
- NIST/CAISI moved measured ASR from 11% to 81% by strengthening the attack, while WARP
  found evaluation cues lowered ASR by 10.9 percentage points. Those results are why this
  report does not turn a deterministic fixture pass count into a robustness claim.

This corpus instead measures whether specific product boundaries preserve provenance,
dialog structure, destination truth, and secret absence. An agent benchmark can now use
those boundaries as tested infrastructure; it is still required to produce an ASR.

## Reproduction

Source snapshot: branch `main`, base `0979da728d04bc973fa4f351f6a38d5f77ff98fd`
plus the uncommitted corpus working tree measured here. No network fixture, installed-app
claim, signing step, provider journey, push, or publication is part of this evidence.

Machine and toolchain:

- Mac model `Mac16,1`, Apple M4, `arm64`
- macOS 27.0 (`26A428`), Darwin 27.0.0
- Xcode 27.0 (`27A266a`)
- Apple Swift 6.4 (`swiftlang-6.4.0.34.1`, `clang-2100.3.34.1`)
- Swift Testing 2084, target `arm64e-apple-macos14.0` as reported by the runner

Commands:

```bash
swift test --arch arm64 --no-parallel --filter WebKitUIMCPAdversarialTests
swift test --arch arm64 --no-parallel --skip hostExclusiveSession
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
git diff --check
```

The final full-suite command reports the adversarial target separately so its result
cannot disappear inside the rest of the project. Exact final counts are recorded after
the final run in the validation section below.

## Validation

Fresh validation on 2026-09-15 completed with exit status 0:

- `swift test --arch arm64 --no-parallel --skip hostExclusiveSession`: **466 tests,
  0 failures** — 122 server tests in 8 suites, 170 runtime tests in 11 suites,
  18 licensing tests in 3 suites, 90 core tests in 13 suites, 53 adversarial tests
  in 4 suites, and 13 confirm-policy XCTest cases.
- `swift test --arch arm64 --no-parallel --filter WebKitUIMCPAdversarialTests`:
  **53 tests in 4 suites passed**, covering the 57 concrete fixture executions
  counted above.
- Focused recounts after the full run independently passed all **170 runtime tests**
  and all **18 licensing tests**.
- `swift test --arch arm64 --no-parallel --filter CapabilityClaimsCoherenceTests`:
  **5 tests passed**, including the guard that keeps the README claim tied to this
  narrow measurement.
- `xcrun swift-format lint --strict --recursive Sources Tests Package.swift` and
  `git diff --check`: exit status 0 with no output.
- `rg -n performClick Tests/WebKitUIMCPAdversarialTests`: no match. The corpus never
  bypasses the product's native actuation boundary through the fixture harness.

No commit, installed-app validation, push, upload, or publication was performed.
