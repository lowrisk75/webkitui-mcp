# INDEPENDENT APPLE APP AUDIT & MONETIZATION REPORT

AUDIT-MANIFEST: WebKitUI MCP; /Users/kevin/GitHub/webkitui-mcp; FULL, bounded
read-only baseline audit for Velya/Clasp feedback. Date2026-10-13 UTC. Report path
docs/diagnostics/2026-10-13-feedback-baseline-audit.md, relocated from its original
/private/tmp/WebKitUI-638-baseline-audit-20261013.md under the new durable-evidence
resource instructions; originally explicitly external under
remediation contract. AUDIT_ARTIFACT created after SNAPSHOT-END. Revision
52a3dc1352dc18282d348bd3327f7fc78e78016d, main, dirty inherited tree owner Unknown.
Scope native Swift packages, broker/helper/relay, credential boundary, local
licensing, packaging/release scripts, privacy/localization, retained legacy JS.
Developer ID local preview; notarization/public distribution status Unknown.
macOS27.0.1 build26A434, Mac SDK27.0, SwiftPM/Swift6 package, arm64 Mac runtime.
External mutations excluded: portals/cloud/services, secrets, sign-in, publication,
other-project writes, git commits/push. Budget60min from18:53UTC, closure by19:53.
Caches/builds on authorized M.2; evidence /private/tmp/webkitui-638-audit-*.

| Project | WebKitUI MCP |
| Project path | /Users/kevin/GitHub/webkitui-mcp |
| Revision | 52a3dc1352dc18282d348bd3327f7fc78e78016d |
| Audit date | 2026-10-13 |

## SNAPSHOT-START

dist/robustness-0.6.38/validation/baseline-start.json (archived unchanged).

## SNAPSHOT-END

dist/robustness-0.6.38/validation/baseline-audit-end.json, worktree diff SHA256
f2c0d9b319c747f93c1aa6b2646c2d225e615038aaff9cf67b3d7372bc991bad,
empty index e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.
Valid for SNAPSHOT-END at 2026-10-13T19:26:14Z. Product unchanged. Two Python caches
created by hermetic tests moved to declared temporary evidence; empty generated
directory removed, source/status restored. No user data deleted.

## EXECUTIVE VERDICT

NO-GO, indicative4/10, confidence Medium: confidentiality gap in rendered/aggregated
text, collector discovery limits, and incomplete server suite accounting prevent
release acceptance. Scores do not average away the privacy gate. Best value lever:
reliable private browser automation with measured gestures and honest receipts.
This is a bounded whole-system baseline, not proof of comprehensive penetration
testing or provider compatibility. Live Apple/Cloudflare/OVH proofs remain open.

## 1. SYSTEM & SURFACE MAP

| Surface / owner | Platform / command | Test | Build/package | Runtime | Device | Signature/deployment | Dependency/criticality |
|---|---|---|---|---|---|---|---|
| Core / Unknown | SwiftPM swift test | PASS | PASS | N/A | N/A | N/A | authority/ledger Critical |
| Runtime / Unknown | WKWebView/AppKit swift test | PASS | PASS | PASS fixtures | NOT RUN physical matrix | N/A | WebKit/network/credential Critical |
| Server / Unknown | native MCP swift test | BLOCKED accounting | PASS | NOT RUN standalone installed in this audit | N/A | N/A | runtime/confirmation Critical |
| Broker/helper/relay / Unknown | native executables swift build -c release | PARTIAL within suite | PASS | BLOCKED human CTA matrix | NOT RUN | PASS installed strict signature | local socket and helper Critical |
| Licensing / Unknown | actor/Keychain/network API | PASS fixture suite | PASS | NOT RUN live purchase | N/A | NOT RUN live deployment | external lease Important |
| Packaging / Unknown | scripts, provenance | FAIL one hermetic script | PASS existing bundle manifest matches | N/A | N/A | PASS installed signature | SiliconPass pinned connector Critical |
| Release loop / Unknown | Python hermetic tests | PASS12 | N/A | N/A | N/A | NOT RUN production | public distribution Important |
| Legacy JS / historical | package.json private Playwright fixtures | NOT RUN | NOT RUN | N/A | N/A | N/A | explicitly unsupported current product |

No SwiftUI imports found; SwiftUI action scan N/A. AppKit actions inspected through
CompanionController selectors; no proven no-op found. No CI directory detected at
.github. Source of truth Package.swift, not generated Xcode. Native resources
include EN/FR, privacy plist, source manifest, SBOM and embedded SiliconPass.

## 2. SCORES & TECHNICAL SCORECARD

| Dimension | Score | Confidence/evidence | Weakness |
|---|---|---|---|
| Technical architecture | 7/10 | Medium [SUPPORTED] STATIC CURRENT | large runtime with duplicated JS policy |
| Code quality | 6/10 | Medium [VERIFIED] BUILD CURRENT | server suite incomplete; release script test stale |
| Apple platform integration | 7/10 | Medium [VERIFIED] TEST CURRENT | fixture event trust not complete human/VoiceOver matrix |
| Distribution readiness | 3/10 | High [FAILING] STATIC CURRENT | confidentiality gate; notarization/store not verified |

## 3. STRENGTH REGISTER & SOTA COMPLIANCE

S-001 [VERIFIED] TEST CURRENT High: runtime243, core90, policy18 and adversarial56
summaries PASS; fixture privacy tests are useful but miss configuration row text.
S-002 [VERIFIED] BUILD/BUNDLE CURRENT High: Release build PASS; installed637 source
manifest matches current generator and strict/deep code signature verifies.
S-003 [SUPPORTED] STATIC CURRENT High: canonical HTTPS credential sink excludes IP,
IDN, implicit ports; local connection deadlines/admission bounded. No live broker
credential challenge performed. Receipt and postcondition failure remain explicit.
Swift/concurrency tested; SwiftUI N/A; privacy FAIL; security PARTIAL; AX/localization
PARTIAL; performance/energy NOT RUN; test accounting FAIL; bundle/signature PASS.

## 4. FAILURE REGISTER & GAP ANALYSIS

| ID | Evidence / freshness / confidence | Severity / Pre-existing | Finding / minimal correction |
|---|---|---|---|
| F-011 | [FAILING] STATIC CURRENT High | Critical / Yes | observation sensitive flag gates text/value but accessibleName/label still serialize directly, and readText uses unredacted rendered text. Credential configuration row/ancestor names can contain plaintext values. Central browser-local redaction and canary fixtures across reads/locators required. |
| F-012 | [SUPPORTED] STATIC CURRENT Medium | Important / Yes | collector candidates include a[href] and only a/div/li/span cursor:pointer fallback. Visible href-less delegated controls without those hints can be absent. Actual ASC DOM Unknown; reproduce locally before changing rule, qualify provider separately. |
| F-013 | [VERIFIED] STATIC CURRENT High | Important / Yes | isComplete also rejects semanticTextTruncated; full collector results do not prove all visible actionable controls discovered. Clarify scope, do not weaken postcondition safeguards. |
| F-014 | [FAILING] TEST CURRENT High | Important / Yes | initial Swift test returned0 with only4/5 Swift Testing bundle summaries. Server isolated retry subsequently PASS181; initial incomplete run remains recorded. Preserve exact accounting. |
| F-015 | [FAILING] TEST CURRENT High | Important / Yes | scripts/test-release-gates.py ValueError locating old shell substring. Fix test extraction against production shape without reducing assertions. |
| F-016 | [OPPORTUNITY] STATIC CURRENT Medium | Nit / Yes | operation-specific session argument schemas/localized handoff instructions and operation capabilities could reduce caller errors; privacy declassification/profile isolation are distinct product designs. |

Finding aliases F-011..016 correspond to remediation R-011..016 below and in the
durable ledger. Server retry completed on unchanged product before remediation.
Coverage gaps: real provider DOM, positive native save selection, locked Mac,
independent secret custody, session expiration cause and production accounts.
No unexpected installed documents found in maxdepth3 inventory; full binary secret
scan not run. Raw production logs/credentials never inspected.

## 5. PRIVACY, SECURITY & CLAIM TRACEABILITY

Claim credentials never copied to observations (docs/privacy-retention.md):
credential input sink is separated, but DOM-rendered configuration values can reach
names/text. Verdict FAIL for broad claim, no direct vault read demonstrated.
Data flow: site DOM -> observation/read_text -> requesting MCP client, not necessarily
vendor telemetry. Native privacy manifest declares no tracking/collected data and
UserDefaults/boot-time reasons; plist lint PASS, store/legal audit NOT RUN.
Network boundary/private-address policy and separate credential origin gates
retained, no permission broadening recommended. Explicit native/session/persistent
site grants are not proof of safe arbitrary page effects. Screenshots are a separate
visual export surface; masking DOM strings cannot establish image redaction.

## 6. PRODUCT, UX, ACCESSIBILITY & LOCALIZATION

Activation via app/status menu and registered relay; core value is bounded semantic
observation and native actuation. Recovery uses handoff and new observations rather
than automatic mutation replay. Human task feedback reports working handoff but
English guidance in a French UI and possible expired handles, causes Unknown.
EN/FR resources installed; source handlers wired. Human visual inspection, dark/
light, text-size and VoiceOver complete matrices NOT RUN (no foreign sessions or
new coordinated human UI qualification authorized in baseline audit).

Interaction ledger:

| Screen / CTA | Wiring/effect | Static | Runtime | Verdict |
|---|---|---|---|---|
| Broker status/refresh/activity | native selectors open status/journal | SUPPORTED | NOT RUN, preserve live sessions | PARTIAL |
| Revoke permissions | native menu shared store revokeAll | SUPPORTED | NOT RUN human menu | PARTIAL |
| Browser native fill/click | fresh target + measured event + receipt | SUPPORTED | PASS runtime fixtures | PASS bounded |
| Download/destination | request-owned WKDownload and native destination gate | SUPPORTED | PASS synthetic provider destinations; human positive NOT RUN | PARTIAL |
| Human Done/resume | control-state handoff/tokenized resume | SUPPORTED | within existing fixtures, physical NOT RUN | PARTIAL |
| ASC audio entry | text visible, collector address absent in feedback | SUPPORTED | NOT RUN live; no mutation authorized | BLOCKED |

## 7. COMMERCIAL VIABILITY & MONETIZATION

Opinion: wedge is auditable authenticated Mac automation for technical operators.
Activation/aha: first approved action with verifiable result and no cookie export.
Conversion depends on reliability, privacy and predictable recovery; leakage and
repeated handoff create flight risk. Personal hypothetical WTP15EUR/month after
privacy/provider qualification, confidence Low; not market data or pricing change.
Competitor prices Unknown/not researched because task is remediation, not a market
study. No monetization/paywall changes authorized or proposed for this batch.

## 8. PRODUCT ROADMAP

P0 R-011: shared browser-local redaction, canaries across observations/read/inspect/
confirmation and ancestor labels, no sensitive-fill declassification. Accept zero
canary bytes plus preserved public name/type and unrelated controls.
P1 R-012: delegated href-less local entry fixture; address unique control or report
ambiguity, verify independent dialogue observation, no stale/refused dispatch.
P1 R-014/R-015: full suite accounting and hermetic delivery-gate regression repair.
P2 R-013/R-016: honest metadata/schema/guidance; isolated-profile and safe config-fill
design require separate scope before changing authority/privacy posture.

## 9. VALIDATION LEDGER

| Validation | Result | Evidence / exit / class |
|---|---|---|
| Release tests | FAIL accounting | webkitui-638-audit-tests.log, exit0 but4summaries, PRODUCT |
| Runtime/core/policy/adversarial | PASS |243/90/18/56 functions, same log, PRODUCT |
| Server isolated retry | PASS | webkitui-638-audit-server-retry.log,181 functions/11suites,247s, exit0; does not retroactively make initial combined run complete |
| Release build | PASS | webkitui-638-audit-build.log exit0,34s, BUILD |
| Hermetic release loop | PASS |12tests, webkitui-638-audit-scripts.log,6s |
| Release-gate extractor test | FAIL | same log ValueError substring not found, PRODUCT |
| Installed bundle/source signature | PASS | codesign --verify --deep --strict, source manifest cmp, plist lint exit0 |
| Script syntax / diff | PASS | node --check verifier, git diff --check exit0 |
| SwiftUI action scan | N/A | no SwiftUI sources; native AppKit selector inspection instead |
| Physical UI/accessibility/energy | NOT RUN | operator/provider matrices not authorized or available here |
| Notarization/Store/production | NOT RUN | excluded external mutations |

Critical/Important revalidated at final source: R-011/R-012/R-013 unchanged source;
R-014/R-015 exact current failures recorded. No source edits during audit. Server
retry result must be appended before remediation gate acceptance. Audit scores
do not use historical pass counts as fresh proof.

## 10. EVIDENCE INDEX

Runtime WebKitRuntime.swift: observationSource6583, sensitivity7188, exported
accessibleName7309/label7334 (line offsets may shift only after remediation),
textSnapshotSource8230 vicinity, isComplete434. CredentialFillSink.swift origin
initializer; ConnectionAdmission.swift deadline policy; CompanionController.swift
menu128 and actions237 onward; Package.swift native products.
Scripts/test-release-gates.py51 extractor, scripts/verify-native-installed.sh43
summary gate. Private feedback files are input leads, not secret-bearing transcripts.
All evidence under /private/tmp/webkitui-638-audit-*. No user credentials or private
report IDs copied. This external report is the only intentional audit document;
source remains dirty as at start, ownership Unknown for inherited changes.
