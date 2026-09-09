# SOTA delta after the Safari MCP server — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the one claim that survives Apple shipping a free first-party browser MCP — *approved, provenance-labelled, verifiable action on signed-in sites* — provable in the product rather than only asserted in the README.

**Architecture:** Four small additions, each a pure testable type in `WebKitUIMCPCore` plus a thin wiring line in `WebKitRuntime`, following the shape that already worked for `ConfirmationKeyboardPolicy` and `HostLeaseEviction.decide`. Nothing here widens the tool surface with a capability an agent could use to step around the confirmation gate. One task removes a tracked artefact that contradicts the central claim.

**Tech Stack:** Swift 6, Swift Package Manager, Swift Testing (`import Testing`) for the four main bundles, WebKit / AppKit, macOS 15+ on Apple silicon.

**Spec:** `docs/2026-08-29-full-sota-product-plan.md` is the parent product spec and still governs; this plan is the engineering delta caused by two events it predates — the licence returning to BUSL-1.1, and Apple publishing the Safari MCP server (<https://webkit.org/blog/18136/introducing-the-safari-mcp-server-for-web-developers/>, 15 tools, drives the user's real Safari, exposes JavaScript evaluation, no approval step, requires *Allow remote automation and external agents*). Sections "P1 — distribution and reliability" and "P1 — product experience" of the parent spec contain the two items this plan closes.

## Global Constraints

- `swift-tools-version: 6.0`; platform floor `.macOS(.v15)`; every build and test command passes `--arch arm64`.
- `xcrun swift-format lint --strict --recursive Sources Tests Package.swift` must exit 0 before any commit.
- Tests in `WebKitUIMCPCoreTests`, `WebKitUIMCPRuntimeTests`, `WebKitUIMCPServerTests`, `WebKitUIMCPLicensingTests` use Swift Testing. Only `WebKitUIMCPConfirmPolicyTests` uses XCTest. Do not mix.
- Run the suite serially: `swift test --arch arm64 --no-parallel --skip hostExclusiveSession`. Parallel WKWebView suites return `noDocument` on a loaded Mac.
- **Never call `performClick` in a test.** It runs a nested AppKit event loop; a `CFRunLoopStop` posted for it reaches the main run loop and Swift Testing's async entry point calls `exit(0)`, so the bundle stops mid-run with no summary and exit status 0. Send the button's action directly.
- Every Swift Testing bundle must print one `Test run with` line. `scripts/verify-native-installed.sh` fails the run otherwise; do not weaken that check.
- Licence is Business Source License 1.1. Never MIT, in any file or any commit message.
- The supported surface exposes no arbitrary JavaScript, no raw CDP, no coordinate retry, no headless claim. No task here may add one.
- Nothing in this plan is pushed. The public remote lives in the separate worktree `~/GitHub/webkitui-mcp-public`; publishing needs fresh explicit authorization.
- Commit message trailers, exactly:
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_019VwrQsCEcmT25v1DJUfJMw
  ```

---

## File Structure

**Created**

| File | Responsibility |
| --- | --- |
| `Sources/WebKitUIMCPCore/NavigationResponseFacts.swift` | Pure rule for which response facts may be recorded. No WebKit import. |
| `Sources/WebKitUIMCPCore/ConsoleJournal.swift` | Bounded, truncating store of site-authored console lines with a drop counter. No WebKit import. |
| `Tests/WebKitUIMCPCoreTests/NavigationResponseFactsTests.swift` | Unit tests for the rule above. |
| `Tests/WebKitUIMCPCoreTests/ConsoleJournalTests.swift` | Unit tests for bounding, truncation and drop counting. |
| `Tests/WebKitUIMCPServerTests/CapabilityClaimsCoherenceTests.swift` | Asserts the tracked tree and the README agree about what is refused. |

**Modified**

| File | Change |
| --- | --- |
| `Sources/WebKitUIMCPRuntime/WebKitRuntime.swift` | New result field, response-delegate recording, console message handler, console hook in the instrumentation script, console accessor. |
| `Sources/WebKitUIMCPRuntime/PinnedSOCKSProxy.swift` | Bounded contacted-host record in the metrics. |
| `README.md` | Apple comparison section and the explicit refusal list. |
| `docs/network-boundary.md` | States that subresource inspection is not offered and why. |

`src/`, `package.json`, `package-lock.json`, `tsconfig.json` and the Playwright fixture scripts leave the tracked tree in Task 1.

---

## Task 1: Stop the tracked tree contradicting the central claim

`README.md` promises "No arbitrary JavaScript, raw CDP escape hatch, coordinate retry, proxy fleet, anti-bot bypass, or headless claim." The public repository also tracks `src/index.ts`, which registers `webkitui_cdp_send`, described in its own text as "an escape hatch for anything not covered by the other tools". `package.json` marks the whole thing `webkitui-mcp-legacy-playwright-fixtures`, `private: true`, prior art — but a reader auditing the promise finds the contradiction in the same repository, on a product sold on refusals. The parent spec already asked for this under "P1 — distribution and reliability": *retain JavaScript fixtures only as explicitly private legacy validation assets.*

**Files:**
- Create: `Tests/WebKitUIMCPServerTests/CapabilityClaimsCoherenceTests.swift`
- Modify: `.gitignore`
- Remove from the index (keep on disk): `src/browser.ts`, `src/index.ts`, `package.json`, `package-lock.json`, `tsconfig.json`, `scripts/goat-test.mjs`, `scripts/goat-test-full.mjs`, `scripts/goat-test-worker-console.mjs`, `scripts/smoke-test.mjs`, `scripts/verify-installed-native.mjs`

**Interfaces:**
- Consumes: nothing.
- Produces: `CapabilityClaimsCoherenceTests`, the suite Task 5 extends with its README assertions.

- [ ] **Step 1: Confirm what is tracked and what the legacy shim offers**

```bash
cd ~/GitHub/webkitui-mcp
git ls-files src package.json tsconfig.json 'scripts/*.mjs'
grep -n 'webkitui_cdp_send' src/index.ts
```

Expected: the files are listed, and `src/index.ts` contains `webkitui_cdp_send`.

`scripts/verify-installed-native.mjs` is a Node script referenced by nothing in `scripts/verify-native-installed.sh`; confirm before removing it:

```bash
grep -rn 'verify-installed-native' scripts docs README.md
```

If anything references it, leave that one file tracked and note it in the commit message.

- [ ] **Step 2: Write the failing test**

Create `Tests/WebKitUIMCPServerTests/CapabilityClaimsCoherenceTests.swift`:

```swift
import Foundation
import Testing

/// README promises no arbitrary JavaScript and no raw CDP escape hatch. The public tree
/// also carried a retained Playwright shim registering `webkitui_cdp_send`, so a reader
/// checking that promise found the opposite in the same repository. Nothing compared the
/// claim to the tracked files.
@Suite("Capability claims coherence")
struct CapabilityClaimsCoherenceTests {
  private static var projectRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // WebKitUIMCPServerTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // project root
  }

  /// Only files git actually tracks. A shim kept on disk and ignored is prior art nobody
  /// can mistake for the product; a shim in the index is a published contradiction.
  private static func trackedFiles() throws -> [String] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", projectRoot.path, "ls-files"]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0, "git ls-files failed")
    return String(decoding: data, as: UTF8.self)
      .split(separator: "\n")
      .map(String.init)
      .filter { !$0.isEmpty }
  }

  @Test("No tracked file offers a CDP or JavaScript-evaluation tool")
  func noEscapeHatchIsTracked() throws {
    let forbidden = ["webkitui_cdp_send", "cdp_send", "webkitui_evaluate", "evaluateHandle"]
    var offenders: [String] = []
    for path in try Self.trackedFiles()
    where path.hasSuffix(".ts") || path.hasSuffix(".js") || path.hasSuffix(".mjs") {
      guard
        let body = try? String(
          contentsOf: Self.projectRoot.appendingPathComponent(path), encoding: .utf8)
      else { continue }
      for token in forbidden where body.contains(token) {
        offenders.append("\(path) offers \(token)")
      }
    }
    #expect(offenders.isEmpty, "tracked files contradict the refusal claim: \(offenders)")
  }
}
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
swift test --arch arm64 --no-parallel --filter noEscapeHatchIsTracked
```

Expected: FAIL, naming `src/index.ts offers webkitui_cdp_send`.

- [ ] **Step 4: Untrack the legacy shim, keeping it on disk**

```bash
cd ~/GitHub/webkitui-mcp
git rm --cached -r src
git rm --cached package.json package-lock.json tsconfig.json
git rm --cached scripts/goat-test.mjs scripts/goat-test-full.mjs \
  scripts/goat-test-worker-console.mjs scripts/smoke-test.mjs
```

Append to `.gitignore`:

```
# Retained Playwright/CDP prior art. It is not the product: the supported surface is the
# Swift/WKWebView server, and it deliberately exposes no JavaScript or CDP tool. Keeping
# these files in the index made the repository contradict that claim in public.
src/
package.json
package-lock.json
tsconfig.json
scripts/goat-test*.mjs
scripts/smoke-test.mjs
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
swift test --arch arm64 --no-parallel --filter noEscapeHatchIsTracked
```

Expected: PASS.

- [ ] **Step 6: Confirm nothing in the Swift build depended on those files**

```bash
swift build -c release --arch arm64
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
```

Expected: `Build complete!` and lint exit 0. `Package.swift` never referenced `src/`, so this is a confirmation, not a fix.

- [ ] **Step 7: Commit**

```bash
git add .gitignore Tests/WebKitUIMCPServerTests/CapabilityClaimsCoherenceTests.swift
git commit -F - <<'EOF'
build: stop the tracked tree contradicting the no-escape-hatch claim

README promises no arbitrary JavaScript and no raw CDP escape hatch, and the
public repository also tracked a retained Playwright shim registering
`webkitui_cdp_send`, described in its own text as an escape hatch. package.json
marked it legacy prior art, which a reader auditing the promise has no reason to
read first. The files stay on disk and are ignored; a coherence suite fails if a
tracked JavaScript file ever offers one of those tools again.

History still contains them. Rewriting it is a separate decision and is not done
here.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019VwrQsCEcmT25v1DJUfJMw
EOF
```

---

## Task 2: Record the main frame's HTTP status

Every action result says, correctly, that UI state never proves a backend commit. Part of why that stayed unanswerable is that nothing carried a response code at all. The main frame's status arrives through `WKNavigationDelegate`, not from the page, so it is the one network fact this runtime can report without asking a site to describe itself — and it is exactly the evidence a client needs to distinguish "the console rendered an error page" from "the request was accepted".

Subresource and XHR statuses are deliberately **not** added: WKWebView exposes no inspection API for them, and the only route would be patching `fetch`/`XMLHttpRequest` inside the page, which any site can observe and falsify. Apple's Safari MCP gets them from Web Inspector; this product cannot, and says so in Task 5.

**Files:**
- Create: `Sources/WebKitUIMCPCore/NavigationResponseFacts.swift`
- Create: `Tests/WebKitUIMCPCoreTests/NavigationResponseFactsTests.swift`
- Modify: `Sources/WebKitUIMCPRuntime/WebKitRuntime.swift` (struct at line 97, `navigate(to:)` at line ~514, response delegate at line 2052)
- Test: `Tests/WebKitUIMCPRuntimeTests/WebKitRuntimeTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `NavigationResponseFacts.mainFrameHTTPStatus(isForMainFrame: Bool, response: URLResponse?) -> Int?`
  - `WebKitNavigationResult.mainFrameHTTPStatus: Int?`, defaulted `nil`, therefore surfaced automatically in the `browser_navigate` payload because `MCPServer.swift:2487` encodes the whole result with `requireObject(.encoded(result), …)`.

- [ ] **Step 1: Write the failing unit test**

Create `Tests/WebKitUIMCPCoreTests/NavigationResponseFactsTests.swift`:

```swift
import Foundation
import Testing

@testable import WebKitUIMCPCore

@Suite("Navigation response facts")
struct NavigationResponseFactsTests {
  private func response(_ status: Int) throws -> HTTPURLResponse {
    let url = try #require(URL(string: "https://fixture.invalid/"))
    return try #require(
      HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil))
  }

  @Test("A main-frame HTTP response contributes its status")
  func mainFrameStatusIsRecorded() throws {
    #expect(
      NavigationResponseFacts.mainFrameHTTPStatus(
        isForMainFrame: true, response: try response(503)) == 503)
    #expect(
      NavigationResponseFacts.mainFrameHTTPStatus(
        isForMainFrame: true, response: try response(200)) == 200)
  }

  @Test("A subframe response contributes nothing")
  func subframeStatusIsRefused() throws {
    // The field is named for the main frame. An iframe's 404 recorded there would be a
    // lie a client cannot detect.
    #expect(
      NavigationResponseFacts.mainFrameHTTPStatus(
        isForMainFrame: false, response: try response(404)) == nil)
  }

  @Test("A non-HTTP response contributes nothing")
  func nonHTTPResponseIsRefused() throws {
    let url = try #require(URL(string: "about:blank"))
    let plain = URLResponse(
      url: url, mimeType: "text/html", expectedContentLength: 0, textEncodingName: nil)
    #expect(NavigationResponseFacts.mainFrameHTTPStatus(isForMainFrame: true, response: plain) == nil)
    #expect(NavigationResponseFacts.mainFrameHTTPStatus(isForMainFrame: true, response: nil) == nil)
  }

  @Test("A status outside the HTTP range contributes nothing")
  func implausibleStatusIsRefused() throws {
    #expect(
      NavigationResponseFacts.mainFrameHTTPStatus(
        isForMainFrame: true, response: try response(0)) == nil)
    #expect(
      NavigationResponseFacts.mainFrameHTTPStatus(
        isForMainFrame: true, response: try response(999)) == nil)
  }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
swift test --arch arm64 --no-parallel --filter NavigationResponseFactsTests
```

Expected: FAIL to compile, `cannot find 'NavigationResponseFacts' in scope`.

- [ ] **Step 3: Write the minimal implementation**

Create `Sources/WebKitUIMCPCore/NavigationResponseFacts.swift`:

```swift
import Foundation

/// Which facts a navigation response is allowed to add to the record.
///
/// Action results have always said that UI state never proves a backend commit, and
/// nothing carried a response code at all, so a client had no way to tell a rendered
/// error page from an accepted request. The main frame's status comes from the
/// navigation delegate rather than from the page, so it is the one network fact this
/// runtime can report without asking a site to describe itself.
///
/// Subresource statuses are deliberately absent. WKWebView exposes no inspection API for
/// them, and patching `fetch` inside the page would report whatever the page chose to
/// let us see.
public enum NavigationResponseFacts {
  /// The status to record, or `nil` when there is nothing trustworthy to record: a
  /// subframe, a non-HTTP response such as a `loadHTMLString` fixture, or a number
  /// outside the range a client could branch on.
  public static func mainFrameHTTPStatus(
    isForMainFrame: Bool,
    response: URLResponse?
  ) -> Int? {
    guard isForMainFrame, let http = response as? HTTPURLResponse else { return nil }
    guard (100...599).contains(http.statusCode) else { return nil }
    return http.statusCode
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
swift test --arch arm64 --no-parallel --filter NavigationResponseFactsTests
```

Expected: PASS, 4 tests.

- [ ] **Step 5: Write the failing runtime test**

In `Tests/WebKitUIMCPRuntimeTests/WebKitRuntimeTests.swift`, insert immediately before the line `  @Test("Session handles are bounded and unforgeable")`:

```swift
  @Test("A local fixture reports no main-frame HTTP status rather than inventing one")
  func fixtureLoadReportsNoHTTPStatus() async throws {
    // loadHTML has no HTTP response. Reporting 200 here would be the most convenient
    // lie available, so the field has to stay absent.
    let runtime = WebKitRuntime()
    let result = try await runtime.loadHTML(
      "<!doctype html><title>Fixture</title><p>Fixture</p>",
      baseURL: URL(string: "https://fixture.invalid/"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40))

    #expect(result.mainFrameHTTPStatus == nil)
  }

```

- [ ] **Step 6: Run it to verify it fails**

```bash
swift test --arch arm64 --no-parallel --filter fixtureLoadReportsNoHTTPStatus
```

Expected: FAIL to compile, `value of type 'WebKitNavigationResult' has no member 'mainFrameHTTPStatus'`.

- [ ] **Step 7: Add the field to the result**

In `Sources/WebKitUIMCPRuntime/WebKitRuntime.swift`, inside `public struct WebKitNavigationResult` (line 97), after `public let mutationCount: UInt64`:

```swift
  /// The main frame's HTTP status, from the navigation delegate rather than the page.
  /// Absent for a `loadHTMLString` fixture, a non-HTTP response, or a subframe. A
  /// default keeps every existing construction site compiling; only a real navigation
  /// fills it in.
  public var mainFrameHTTPStatus: Int?
```

Declare it `var` with no explicit value so it defaults to `nil` in the memberwise initializer. Do not add `CodingKeys`: nothing in `Sources` sets a key-encoding strategy, so the JSON key is the property name, matching the existing `documentID` and `requestedURL` keys.

- [ ] **Step 8: Run it to verify it passes**

```bash
swift test --arch arm64 --no-parallel --filter fixtureLoadReportsNoHTTPStatus
```

Expected: PASS.

- [ ] **Step 9: Record the status in the response delegate**

Add the storage next to the other per-navigation state. In `WebKitRuntime`, after `private var navigationAuditEvents: [WebKitNavigationAuditEvent] = []`:

```swift
  /// Cleared at the start of every navigation so a previous page's status can never
  /// attach to the next one.
  private var latestMainFrameHTTPStatus: Int?
```

In `public func navigate(to url: URL, …)`, directly after the existing line `pendingCrossOriginNavigationRequest = nil`:

```swift
    latestMainFrameHTTPStatus = nil
```

In `public func webView(_:decidePolicyFor navigationResponse:)` (line 2052), insert **before** the existing `guard downloadContinuation != nil else { return .allow }` — the guard returns early for every ordinary navigation, which is why nothing was recorded until now:

```swift
    if let status = NavigationResponseFacts.mainFrameHTTPStatus(
      isForMainFrame: navigationResponse.isForMainFrame,
      response: navigationResponse.response)
    {
      latestMainFrameHTTPStatus = status
    }
```

`WebKitUIMCPRuntime` already depends on `WebKitUIMCPCore` in `Package.swift`; add `import WebKitUIMCPCore` only if the file does not already have it:

```bash
grep -n '^import WebKitUIMCPCore' Sources/WebKitUIMCPRuntime/WebKitRuntime.swift
```

- [ ] **Step 10: Attach it where a real navigation builds its result**

```bash
grep -n 'WebKitNavigationResult(' Sources/WebKitUIMCPRuntime/WebKitRuntime.swift
```

For each construction site reached by `navigate(to:)` — not the `loadHTML` fixture path, which must keep reporting `nil` — add the argument:

```swift
      mainFrameHTTPStatus: latestMainFrameHTTPStatus,
```

Place it after `mutationCount:`. If a single helper builds the result for both paths, leave the helper alone and instead set the field on the returned value inside `navigate(to:)`:

```swift
    var result = /* existing expression */
    result.mainFrameHTTPStatus = latestMainFrameHTTPStatus
    return result
```

- [ ] **Step 11: Verify the whole runtime bundle and lint**

```bash
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
swift test --arch arm64 --no-parallel --filter '^WebKitUIMCPRuntimeTests\.'
swift test --arch arm64 --no-parallel --filter '^WebKitUIMCPCoreTests\.'
```

Expected: lint exit 0; `Test run with 142 tests` for the runtime bundle and a passing core bundle, both printing their summary line.

- [ ] **Step 12: Commit**

```bash
git add Sources/WebKitUIMCPCore/NavigationResponseFacts.swift \
  Tests/WebKitUIMCPCoreTests/NavigationResponseFactsTests.swift \
  Sources/WebKitUIMCPRuntime/WebKitRuntime.swift \
  Tests/WebKitUIMCPRuntimeTests/WebKitRuntimeTests.swift
git commit -F - <<'EOF'
feat: report the main frame's HTTP status, from the delegate and never from the page

Action results say UI state never proves a backend commit, and nothing carried a
response code, so a client could not tell a rendered error page from an accepted
request. The main frame's status now travels on the navigation result. It comes
from the navigation delegate, so a site cannot author it; a fixture load, a
non-HTTP response and a subframe all report nothing rather than the convenient
200.

Subresource statuses are still absent on purpose: WKWebView offers no inspection
API for them, and patching fetch inside the page would report whatever the page
allowed us to see.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019VwrQsCEcmT25v1DJUfJMw
EOF
```

---

## Task 3: Capture the console as untrusted site content

When an approved click dispatches, is measured as a trusted gesture, and the page still does nothing, the reason is usually in the console. The product currently offers no way to see it, so the operator's only recourse is a human handoff. Apple's server exposes console access; this one can too, with the difference that the lines must be labelled for what they are — text authored by the site, never instructions, exactly like the existing untrusted-label treatment of DOM text.

**Files:**
- Create: `Sources/WebKitUIMCPCore/ConsoleJournal.swift`
- Create: `Tests/WebKitUIMCPCoreTests/ConsoleJournalTests.swift`
- Modify: `Sources/WebKitUIMCPRuntime/WebKitRuntime.swift` (handler name at line 4762, registration at line 507, `userContentController(_:didReceive:)` at line 1478, instrumentation script)
- Test: `Tests/WebKitUIMCPRuntimeTests/WebKitRuntimeTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `ConsoleJournal.Line(level: ConsoleJournal.Level, text: String, monotonicNanoseconds: UInt64)`
  - `ConsoleJournal.maximumLines: Int` = 200, `ConsoleJournal.maximumCharactersPerLine: Int` = 2_000
  - `mutating func record(level:text:monotonicNanoseconds:)`, `var lines: [Line]`, `var droppedLines: Int`
  - `WebKitRuntime.consoleJournalSnapshot() -> [ConsoleJournal.Line]` and `WebKitRuntime.consoleDroppedLineCount() -> Int`

- [ ] **Step 1: Write the failing unit test**

Create `Tests/WebKitUIMCPCoreTests/ConsoleJournalTests.swift`:

```swift
import Foundation
import Testing

@testable import WebKitUIMCPCore

@Suite("Console journal")
struct ConsoleJournalTests {
  @Test("Lines are kept in order with their level")
  func linesAreKept() {
    var journal = ConsoleJournal()
    journal.record(level: .log, text: "first", monotonicNanoseconds: 1)
    journal.record(level: .error, text: "second", monotonicNanoseconds: 2)

    #expect(journal.lines.map(\.text) == ["first", "second"])
    #expect(journal.lines.map(\.level) == [.log, .error])
    #expect(journal.droppedLines == 0)
  }

  @Test("A single line cannot spend the whole budget")
  func longLineIsTruncated() {
    var journal = ConsoleJournal()
    journal.record(
      level: .warn, text: String(repeating: "x", count: 10_000), monotonicNanoseconds: 1)

    let line = journal.lines[0]
    #expect(line.text.count == ConsoleJournal.maximumCharactersPerLine)
    #expect(line.truncated)
  }

  @Test("A chatty page evicts its oldest lines and says how many it lost")
  func oldestLinesAreEvicted() {
    var journal = ConsoleJournal()
    for index in 0..<(ConsoleJournal.maximumLines + 25) {
      journal.record(level: .log, text: "line \(index)", monotonicNanoseconds: UInt64(index))
    }

    #expect(journal.lines.count == ConsoleJournal.maximumLines)
    #expect(journal.droppedLines == 25)
    // The newest lines are the ones worth keeping: the failure just happened.
    #expect(journal.lines.last?.text == "line \(ConsoleJournal.maximumLines + 24)")
    #expect(journal.lines.first?.text == "line 25")
  }

  @Test("Clearing on navigation leaves no line from the previous document")
  func clearingResetsEverything() {
    var journal = ConsoleJournal()
    journal.record(level: .error, text: "old document", monotonicNanoseconds: 1)
    journal.removeAll()

    #expect(journal.lines.isEmpty)
    #expect(journal.droppedLines == 0)
  }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
swift test --arch arm64 --no-parallel --filter ConsoleJournalTests
```

Expected: FAIL to compile, `cannot find 'ConsoleJournal' in scope`.

- [ ] **Step 3: Write the minimal implementation**

Create `Sources/WebKitUIMCPCore/ConsoleJournal.swift`:

```swift
import Foundation

/// Console output from the page under automation.
///
/// When an approved click is dispatched, measured as a trusted gesture, and the page
/// still does nothing, the reason is usually here. Every line is authored by the site,
/// so it is data and never an instruction, and it is bounded: a page that logs in a loop
/// must not be able to spend a client's whole context.
public struct ConsoleJournal: Codable, Equatable, Sendable {
  public enum Level: String, Codable, Equatable, Sendable {
    case log
    case info
    case warn
    case error
    /// An exception that reached `window.onerror`, which is the interesting case.
    case uncaught
  }

  public struct Line: Codable, Equatable, Sendable {
    public let level: Level
    public let text: String
    public let truncated: Bool
    public let monotonicNanoseconds: UInt64
  }

  public static let maximumLines = 200
  public static let maximumCharactersPerLine = 2_000

  public private(set) var lines: [Line] = []
  /// How many lines were evicted, so a client is told the record is partial rather than
  /// left to assume it is complete.
  public private(set) var droppedLines = 0

  public init() {}

  public mutating func record(level: Level, text: String, monotonicNanoseconds: UInt64) {
    let truncated = text.count > Self.maximumCharactersPerLine
    let bounded = truncated ? String(text.prefix(Self.maximumCharactersPerLine)) : text
    lines.append(
      Line(
        level: level, text: bounded, truncated: truncated,
        monotonicNanoseconds: monotonicNanoseconds))
    if lines.count > Self.maximumLines {
      let excess = lines.count - Self.maximumLines
      lines.removeFirst(excess)
      droppedLines += excess
    }
  }

  public mutating func removeAll() {
    lines.removeAll(keepingCapacity: true)
    droppedLines = 0
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
swift test --arch arm64 --no-parallel --filter ConsoleJournalTests
```

Expected: PASS, 4 tests.

- [ ] **Step 5: Write the failing runtime test**

In `Tests/WebKitUIMCPRuntimeTests/WebKitRuntimeTests.swift`, insert immediately before `  @Test("Session handles are bounded and unforgeable")`:

```swift
  @Test("The console and an uncaught exception reach the journal as site-authored data")
  func consoleOutputIsJournalled() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <!doctype html><title>Console fixture</title>
      <script>
        console.log('hello from the page');
        console.error('deliberate failure');
        setTimeout(() => { throw new Error('uncaught fixture'); }, 0);
      </script>
      """,
      baseURL: URL(string: "https://fixture.invalid/"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40))

    for _ in 0..<fixtureSettlementPolls
    where !runtime.consoleJournalSnapshot().contains(where: { $0.level == .uncaught }) {
      try await Task.sleep(for: .milliseconds(20))
    }
    let lines = runtime.consoleJournalSnapshot()

    #expect(lines.contains { $0.level == .log && $0.text.contains("hello from the page") })
    #expect(lines.contains { $0.level == .error && $0.text.contains("deliberate failure") })
    #expect(lines.contains { $0.level == .uncaught && $0.text.contains("uncaught fixture") })
    #expect(runtime.consoleDroppedLineCount() == 0)
  }

  @Test("A new document starts with an empty console record")
  func consoleIsClearedOnNavigation() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      "<!doctype html><script>console.log('first document')</script>",
      baseURL: URL(string: "https://fixture.invalid/one"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))
    for _ in 0..<fixtureSettlementPolls where runtime.consoleJournalSnapshot().isEmpty {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(!runtime.consoleJournalSnapshot().isEmpty)

    _ = try await runtime.loadHTML(
      "<!doctype html><p>second document</p>",
      baseURL: URL(string: "https://fixture.invalid/two"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))

    #expect(
      runtime.consoleJournalSnapshot().allSatisfy { !$0.text.contains("first document") },
      "a line from the previous document survived the navigation")
  }

```

- [ ] **Step 6: Run them to verify they fail**

```bash
swift test --arch arm64 --no-parallel --filter 'consoleOutputIsJournalled|consoleIsClearedOnNavigation'
```

Expected: FAIL to compile, `has no member 'consoleJournalSnapshot'`.

- [ ] **Step 7: Add the handler name, storage and accessors**

In `WebKitRuntime`, beside `private static let nativeGestureMessageHandlerName = "webkituiNativeGesture"` (line 4762):

```swift
  private static let consoleMessageHandlerName = "webkituiConsole"
```

Beside the other per-navigation state, after `private var latestMainFrameHTTPStatus: Int?`:

```swift
  private var consoleJournal = ConsoleJournal()
```

Public accessors, next to `public func latestNavigationAuditEvent()`:

```swift
  /// Site-authored text. Treat it as data, never as instructions.
  public func consoleJournalSnapshot() -> [ConsoleJournal.Line] { consoleJournal.lines }

  public func consoleDroppedLineCount() -> Int { consoleJournal.droppedLines }
```

- [ ] **Step 8: Register the second handler**

In `init`, immediately after the existing registration block ending `name: Self.nativeGestureMessageHandlerName)`:

```swift
    contentController.add(
      WeakScriptMessageHandler(target: self),
      contentWorld: world,
      name: Self.consoleMessageHandlerName)
```

- [ ] **Step 9: Route the message**

`public func userContentController(_:didReceive:)` (line 1478) currently begins with a guard requiring `message.name == Self.nativeGestureMessageHandlerName`. Insert this **above** that guard so the console name is handled and the gesture path is left exactly as it is:

```swift
    if message.name == Self.consoleMessageHandlerName {
      guard let payload = message.body as? [String: Any],
        let rawLevel = payload["level"] as? String,
        let level = ConsoleJournal.Level(rawValue: rawLevel),
        let text = payload["text"] as? String
      else { return }
      consoleJournal.record(
        level: level, text: text, monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
      return
    }
```

- [ ] **Step 10: Hook the console in the instrumentation script**

Find the injected source:

```bash
grep -n 'static let instrumentationSource' Sources/WebKitUIMCPRuntime/WebKitRuntime.swift
```

Append this to that string, inside the same isolated content world the rest of the instrumentation already uses. It wraps the console in the *instrumentation* world's view only; the page's own `console` object is untouched, so a site cannot detect the wrapper by comparing `console.log.toString()` in its own world:

```javascript
    // Console output is the usual explanation for an approved, trusted click that
    // changed nothing. It is site-authored text, bounded and labelled on the Swift side.
    const forwardConsole = (level, args) => {
      try {
        const text = Array.from(args).map(value => {
          if (typeof value === 'string') return value;
          try { return JSON.stringify(value); } catch (error) { return String(value); }
        }).join(' ');
        window.webkit.messageHandlers.webkituiConsole.postMessage({ level, text });
      } catch (error) { /* a page that removed the bridge simply gets no journal */ }
    };
    for (const level of ['log', 'info', 'warn', 'error']) {
      const original = console[level];
      console[level] = function (...args) {
        forwardConsole(level, args);
        return original.apply(console, args);
      };
    }
    window.addEventListener('error', event => {
      forwardConsole('uncaught', [event.message || String(event.error)]);
    });
    window.addEventListener('unhandledrejection', event => {
      forwardConsole('uncaught', ['unhandled rejection: ' + String(event.reason)]);
    });
```

- [ ] **Step 11: Clear the journal on a new document**

Find where the document identity is regenerated:

```bash
grep -n 'documentID = UUID().uuidString' Sources/WebKitUIMCPRuntime/WebKitRuntime.swift
```

At each site that marks a *new* document (not the initial property declaration at line ~384), add:

```swift
    consoleJournal.removeAll()
```

- [ ] **Step 12: Run the tests to verify they pass**

```bash
swift test --arch arm64 --no-parallel --filter 'consoleOutputIsJournalled|consoleIsClearedOnNavigation'
```

Expected: PASS, 2 tests. If the uncaught line never arrives, confirm the fixture's `setTimeout` throw reaches `window.onerror` by checking the `log` line arrived first — a missing `log` line means the bridge name is wrong, not that the error hook is.

- [ ] **Step 13: Expose it on the MCP surface**

`browser_observe` builds its payload at `Sources/WebKitUIMCPServer/MCPServer.swift:570` with `var observed = try requireObject(.encoded(observation), named: "browser observation")`. Add the console beside it, following the pattern of the manually-added `structured["redirected"]` at line 2488:

```swift
        if !runtime.consoleJournalSnapshot().isEmpty {
          observed["console"] = .object([
            "provenance": .string("untrusted_site_content"),
            "dropped_lines": .int(runtime.consoleDroppedLineCount()),
            "lines": try requireArray(
              .encoded(runtime.consoleJournalSnapshot()), named: "console lines"),
          ])
        }
```

Confirm the array helper's real name before writing it:

```bash
grep -n 'func requireArray\|func requireObject' Sources/WebKitUIMCPServer/*.swift
```

If no array helper exists, encode the whole journal as one object instead:

```swift
          observed["console"] = try requireObject(
            .encoded(runtime.consoleJournalForExport()), named: "console journal")
```

and add to `WebKitRuntime`:

```swift
  /// The journal as one encodable value, for a client that wants the drop count and the
  /// lines together.
  public func consoleJournalForExport() -> ConsoleJournal { consoleJournal }
```

- [ ] **Step 14: Verify the server bundle and lint**

```bash
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
swift test --arch arm64 --no-parallel --filter '^WebKitUIMCPServerTests\.'
swift test --arch arm64 --no-parallel --filter '^WebKitUIMCPRuntimeTests\.'
```

Expected: lint exit 0, both bundles printing their `Test run with` summary and passing.

- [ ] **Step 15: Commit**

```bash
git add Sources/WebKitUIMCPCore/ConsoleJournal.swift \
  Tests/WebKitUIMCPCoreTests/ConsoleJournalTests.swift \
  Sources/WebKitUIMCPRuntime/WebKitRuntime.swift \
  Sources/WebKitUIMCPServer/MCPServer.swift \
  Tests/WebKitUIMCPRuntimeTests/WebKitRuntimeTests.swift
git commit -F - <<'EOF'
feat: journal the console, bounded and labelled as site-authored data

An approved click that dispatches, measures as a trusted gesture, and changes
nothing usually explains itself in the console, and there was no way to look.
console.log/info/warn/error, window.onerror and unhandled rejections are now
recorded in the instrumentation world, capped at 200 lines and 2000 characters
each with an explicit dropped-line count, cleared on every new document, and
exposed under a provenance label of untrusted_site_content.

The page's own console object is untouched, so a site cannot detect the wrapper
by inspecting its own world.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019VwrQsCEcmT25v1DJUfJMw
EOF
```

---

## Task 4: Say which hosts the boundary actually allowed and blocked

`docs/network-boundary.md` promises the session's egress goes through one pinned loopback SOCKS proxy that refuses non-public resolutions. The proxy already counts accepted, blocked, pinned and timed-out connections, but never says *which* hosts, so the promise is auditable only in aggregate. Recording the distinct hosts, bounded, turns the strongest architectural claim into evidence a client can read back.

**Files:**
- Modify: `Sources/WebKitUIMCPRuntime/PinnedSOCKSProxy.swift` (metrics struct at line 5, `recordAccepted`/`recordBlocked` at lines 99–100)
- Test: `Tests/WebKitUIMCPRuntimeTests/PinnedSOCKSProxyTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `PinnedProxyMetrics.acceptedHosts: [String]`, `PinnedProxyMetrics.blockedHosts: [String]`, `PinnedProxyMetrics.hostsDropped: Int`, and `PinnedProxyMetrics.maximumRecordedHosts` = 50.

- [ ] **Step 1: Read the two call sites before changing their signatures**

```bash
sed -n 90,120p Sources/WebKitUIMCPRuntime/PinnedSOCKSProxy.swift
grep -n 'recordAccepted\|recordBlocked' Sources/WebKitUIMCPRuntime/PinnedSOCKSProxy.swift
```

Note every caller. Each needs a host argument; the compiler will name any you miss.

- [ ] **Step 2: Write the failing test**

In `Tests/WebKitUIMCPRuntimeTests/PinnedSOCKSProxyTests.swift`, add at the end of the existing suite:

```swift
  @Test("The metrics name the hosts allowed and refused, bounded and without duplicates")
  func metricsNameTheHosts() {
    var metrics = PinnedProxyMetrics()
    metrics.recordAccepted(host: "example.test")
    metrics.recordAccepted(host: "example.test")
    metrics.recordBlocked(host: "10.9.8.8")

    #expect(metrics.acceptedHosts == ["example.test"], "a repeat visit is not a new host")
    #expect(metrics.blockedHosts == ["10.9.8.8"])
    #expect(metrics.acceptedConnections == 2, "the counter still counts every connection")
    #expect(metrics.blockedConnections == 1)
    #expect(metrics.hostsDropped == 0)
  }

  @Test("A page contacting hundreds of hosts cannot grow the record without bound")
  func hostRecordIsBounded() {
    var metrics = PinnedProxyMetrics()
    for index in 0..<(PinnedProxyMetrics.maximumRecordedHosts + 10) {
      metrics.recordAccepted(host: "host\(index).test")
    }

    #expect(metrics.acceptedHosts.count == PinnedProxyMetrics.maximumRecordedHosts)
    #expect(metrics.hostsDropped == 10)
    #expect(metrics.acceptedHosts.first == "host0.test", "the first hosts are the interesting ones")
  }
```

- [ ] **Step 3: Run them to verify they fail**

```bash
swift test --arch arm64 --no-parallel --filter 'metricsNameTheHosts|hostRecordIsBounded'
```

Expected: FAIL to compile, `has no member 'recordAccepted'` on `PinnedProxyMetrics`.

- [ ] **Step 4: Write the minimal implementation**

Replace the struct at `Sources/WebKitUIMCPRuntime/PinnedSOCKSProxy.swift:5` with:

```swift
/// What the egress boundary did, in aggregate and by host.
///
/// The counters alone made the network-boundary contract auditable only as totals: a
/// client could see that something was blocked but never what. The host lists are
/// bounded, deduplicated and keep the earliest entries, because the first refusal is the
/// one that explains a failure.
public struct PinnedProxyMetrics: Codable, Equatable, Sendable {
  public static let maximumRecordedHosts = 50

  public var acceptedConnections = 0
  public var blockedConnections = 0
  public var pinnedHosts = 0
  public var timedOutConnections = 0
  public private(set) var acceptedHosts: [String] = []
  public private(set) var blockedHosts: [String] = []
  /// Distinct hosts the record could not hold, so a reader is told it is partial.
  public private(set) var hostsDropped = 0

  public init() {}

  public mutating func recordAccepted(host: String) {
    acceptedConnections += 1
    remember(host, in: &acceptedHosts)
  }

  public mutating func recordBlocked(host: String) {
    blockedConnections += 1
    remember(host, in: &blockedHosts)
  }

  private mutating func remember(_ host: String, in list: inout [String]) {
    guard !host.isEmpty, !list.contains(host) else { return }
    guard list.count < Self.maximumRecordedHosts else {
      hostsDropped += 1
      return
    }
    list.append(host)
  }
}
```

- [ ] **Step 5: Update the two call sites**

The existing helpers at lines 99–100 increment the counters directly. Replace them so the counting lives in one place:

```swift
  fileprivate func recordAccepted(host: String) { metrics.recordAccepted(host: host) }
  fileprivate func recordBlocked(host: String) { metrics.recordBlocked(host: host) }
```

Build to find every caller and pass the host each already has in scope — `pinnedAddress(for host:)` and `connect(host:port:)` both carry it:

```bash
swift build --arch arm64 2>&1 | grep -E 'error|warning' | head
```

Where a call site genuinely has no host in scope, pass the SOCKS request's target rather than inventing a placeholder; if that is impossible, leave that path calling only the counter and say so in the commit message.

- [ ] **Step 6: Run the tests to verify they pass**

```bash
swift test --arch arm64 --no-parallel --filter 'metricsNameTheHosts|hostRecordIsBounded'
swift test --arch arm64 --no-parallel --filter '^WebKitUIMCPRuntimeTests\.'
```

Expected: both new tests PASS and the runtime bundle still prints its summary with no failures. The existing proxy tests assert on `acceptedConnections` and `blockedConnections`; those counters are unchanged.

- [ ] **Step 7: Lint and commit**

```bash
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
git add Sources/WebKitUIMCPRuntime/PinnedSOCKSProxy.swift \
  Tests/WebKitUIMCPRuntimeTests/PinnedSOCKSProxyTests.swift
git commit -F - <<'EOF'
feat: name the hosts the egress boundary allowed and refused

The network-boundary contract was auditable only as totals: a client could see
that a connection was blocked and never which host. The proxy metrics now carry
bounded, deduplicated accepted and blocked host lists with an explicit dropped
count, keeping the earliest entries because the first refusal is the one that
explains a failure. The existing counters are unchanged.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019VwrQsCEcmT25v1DJUfJMw
EOF
```

---

## Task 5: State the Apple comparison and the refusals in the documentation

The comparison currently lives in a Reddit reply. The parent spec's "P1 — product experience" asked for a neutral comparison with Playwright MCP and cloud services; Apple's first-party server replaces that as the comparison that matters, and the refusals — no JavaScript tool, no multi-tab, no subresource inspection — are the product, so they belong beside the promise rather than in a thread.

**Files:**
- Modify: `README.md` (refusal list at line 73, deliberate-limits section beginning line 64)
- Modify: `docs/network-boundary.md`
- Modify: `Tests/WebKitUIMCPServerTests/CapabilityClaimsCoherenceTests.swift`

**Interfaces:**
- Consumes: `CapabilityClaimsCoherenceTests` from Task 1.
- Produces: nothing further.

- [ ] **Step 1: Write the failing test**

Add to `CapabilityClaimsCoherenceTests`:

```swift
  private static func text(_ relativePath: String) throws -> String {
    try String(
      contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
  }

  @Test("The README names every capability this product refuses")
  func refusalsAreDocumented() throws {
    let readme = try Self.text("README.md")
    // Each of these is a decision a reader will otherwise mistake for an oversight,
    // especially now that Apple's first-party server offers them.
    for refusal in [
      "arbitrary JavaScript",
      "raw CDP escape hatch",
      "subresource",
      "multiple tabs",
    ] {
      #expect(readme.contains(refusal), "README no longer explains refusing: \(refusal)")
    }
  }

  @Test("The network boundary document says subresource inspection is not offered")
  func networkBoundaryStatesTheCeiling() throws {
    let boundary = try Self.text("docs/network-boundary.md")
    #expect(boundary.contains("subresource"))
  }
```

- [ ] **Step 2: Run them to verify they fail**

```bash
swift test --arch arm64 --no-parallel --filter 'refusalsAreDocumented|networkBoundaryStatesTheCeiling'
```

Expected: FAIL, naming `subresource` and `multiple tabs` as missing.

- [ ] **Step 3: Extend the README's deliberate limits**

In `README.md`, replace the line

```
- No arbitrary JavaScript, raw CDP escape hatch, coordinate retry, proxy fleet, anti-bot bypass, or headless claim.
```

with

```
- No arbitrary JavaScript, raw CDP escape hatch, coordinate retry, proxy fleet, anti-bot bypass, or headless claim. A gate an agent can step around is not a gate: a JavaScript-evaluation tool would let one call do anything the confirmation was meant to authorize one action at a time.
- No multiple tabs. One session holds one exclusive host lease, which is what makes an approval refer to an unambiguous page.
- No subresource or XHR network inspection. WebKit exposes no API for it, and the only route would be patching `fetch` and `XMLHttpRequest` inside the page, which the site can observe and falsify. The main frame's HTTP status is reported instead, and it comes from the navigation delegate rather than from the page.
```

- [ ] **Step 4: Add the Apple comparison**

In `README.md`, immediately after the `## Deliberate limits` section, add:

```markdown
## Compared with the Safari MCP server

Apple's Safari MCP server (Safari 27 beta / Safari Technology Preview 247+) gives an
agent fifteen tools against your real Safari, including JavaScript evaluation, network
request inspection and console access, for seeing how a site you are building actually
renders. For that job it is the better tool: it is first-party, free and it is Safari.

This project answers a different question — acting on sites you are already signed in
to, where the failure that matters is not a broken layout but a click on the wrong
control:

| | Safari MCP server | WebKitUI MCP |
| --- | --- | --- |
| Purpose | inspect and debug a site you are developing | act on a site you are signed in to |
| Approval | none; autonomous once connected | native macOS confirmation before every exposed click and open-world navigation |
| JavaScript evaluation | exposed as a tool | deliberately absent, with no CDP or coordinate fallback |
| Browser | your real Safari, with *Allow remote automation and external agents* enabled in Settings | its own `WKWebView` and its own persistent profile |
| Personal data | states it has no access to your Safari data | authenticated sessions are the point; passwords are released only through a local human handoff and never reach MCP |
| Network detail | full request inspection through Web Inspector | main-frame HTTP status only, from the navigation delegate |
| Verification | inspection tools | an explicit postcondition per action, plus separate `confirmation_mode`, `dispatch_mode` and `trusted_gesture_state` fields |
| Requirements | macOS with Safari 27 beta or STP 247+ | macOS 15+ on Apple silicon, notarized |

Both can be installed at once, and for most developers both should be.
```

- [ ] **Step 5: State the ceiling in the network boundary document**

In `docs/network-boundary.md`, add to the list of things the boundary does not claim:

```
- Per-subresource request inspection. WebKit exposes no such API to an embedder, and
  patching `fetch` or `XMLHttpRequest` inside the page would report whatever the page
  allowed us to see, so it is not offered. The main frame's HTTP status is reported from
  the navigation delegate, and the proxy names the hosts it allowed and refused.
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
swift test --arch arm64 --no-parallel --filter '^WebKitUIMCPServerTests\.'
```

Expected: the bundle prints its summary and passes, including all four coherence tests.

- [ ] **Step 7: Commit**

```bash
git add README.md docs/network-boundary.md \
  Tests/WebKitUIMCPServerTests/CapabilityClaimsCoherenceTests.swift
git commit -F - <<'EOF'
docs: say what this refuses, and how it differs from Apple's Safari MCP server

Apple shipped a first-party MCP server that drives real Safari with fifteen
tools, JavaScript evaluation among them. That makes the generic "drive a browser
from an agent" claim worthless and the refusals load-bearing, so they are now
stated next to the promise instead of in a forum reply: no JavaScript tool, no
multiple tabs, no subresource inspection, each with the reason.

The comparison is neutral and says plainly that for developing a site theirs is
the better tool. A coherence test fails if the README stops explaining a refusal.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019VwrQsCEcmT25v1DJUfJMw
EOF
```

---

## Final verification

- [ ] **Run the full gate**

```bash
scripts/verify-native-installed.sh
```

Expected: eight `Test run with` summaries across the debug and release passes, no failures, and either a green finish or the single known line `installed webkitui-mcp is not built from this source` — which is correct until a reinstall, and is the operator's decision.

- [ ] **Reinstall, only with fresh explicit approval**

Reinstalling replaces the app and three CLI binaries, quits the broker and drops live browser sessions. The procedure, unchanged from 2026-09-07:

```bash
scripts/build-signed-local.sh <output-dir> \
  8333AB7CD909731530AC62DD28CCA47C8D288225 TDV6D5L785
```

then quit the broker, move the app aside as `.rollback-<date>-<sha>`, `ditto` the new bundle in, copy and re-sign the three CLI tools, relaunch, and rerun the gate.

---

## Out of scope for this plan

These are the remaining SOTA gaps, and none of them is code with a test cycle, so each needs its own plan rather than a task here. They are the open items of `docs/2026-08-29-full-sota-product-plan.md`, still accurate:

1. **Provider proof matrix** — one dated, independently read-back journey for Stripe, Google Play Console and Cloudflare, distinguishing verified, degraded, handoff-required and unsupported. This is the parent spec's P0 exit gate and the single largest gap.
2. **Physical-Mac authentication tests** — interactive login, locked Mac, closed lid, Touch ID lockout, Apple Watch, password fallback, cancellation, timeout. No simulator or local run substitutes for these.
3. **First-run diagnostic experience** — every failed `doctor` check explained with one recovery action.
4. **Commercial and legal truth** — seller identity, terms, one paid live canary, cancellation, entitlement revocation, readable end to end. Every external mutation needs its own authorization.
5. **Independent review of the native gesture and credential boundary** before Developer Preview is removed.

A per-project auto-approval grant is deliberately absent from both lists. Its design constraints are in `docs/research/2026-09-01-goal-delegation-and-browser-addressing-sota.md`, it requires a shadow-mode campaign with zero false allows before activation, and the hard NO-GO classes — secrets, payments, sends, deletions, uploads, publication, cross-origin navigation — do not move.

## Self-review

- **Spec coverage.** The two parent-spec items this plan closes are "retain JavaScript fixtures only as explicitly private legacy validation assets" (Task 1) and the neutral competitor comparison under P1 product experience (Task 5). Tasks 2, 3 and 4 are new, caused by Apple's launch reframing what evidence the product must produce. Every other parent-spec item is listed under "Out of scope" with a reason.
- **Placeholder scan.** No TBD, no "add error handling", no "similar to Task N". Three steps deliberately begin with a `grep` because the exact insertion site is in a 4800-line file and the anchor string, not a line number, is what stays correct: Task 2 step 10, Task 3 steps 10, 11 and 13, Task 4 step 5. Each names the string to search for and the exact code to add. Task 3 step 13 and Task 4 step 5 each state what to do if the expected helper or host is absent.
- **Type consistency.** `NavigationResponseFacts.mainFrameHTTPStatus(isForMainFrame:response:)` is defined in Task 2 step 3 and consumed in step 9 with the same label order. `WebKitNavigationResult.mainFrameHTTPStatus` is declared `var` with no explicit default in step 7 so the memberwise initializer keeps every existing construction site compiling, and step 10 relies on that. `ConsoleJournal.Level` cases `log/info/warn/error/uncaught` match the JavaScript array `['log','info','warn','error']` plus the two `'uncaught'` forwarders in step 10, and the `Level(rawValue:)` decode in step 9. `ConsoleJournal.Line.truncated` is asserted in the test at step 1 and set in the implementation at step 3. `PinnedProxyMetrics.recordAccepted(host:)` / `recordBlocked(host:)` replace the no-argument `fileprivate` helpers, and Task 4 step 5 accounts for the call sites.
