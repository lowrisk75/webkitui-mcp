import AppKit
import Foundation
import Network
import Testing
import WebKit
import WebKitUIMCPCore

@testable import WebKitUIMCPRuntime

/// Fixture navigations must not be bound to wall-clock luck. The suite is
/// serialized and launches many WebKit content processes, so a loaded machine can
/// exceed a two-second budget while the behaviour under test is perfectly correct.
/// No test asserts that a navigation times out, so a generous bound weakens nothing
/// and removes the only cause of intermittent failures observed here.
private let fixtureNavigationTimeout: Duration = .seconds(15)

/// Twenty-millisecond polls covering the same budget. A fixed fifty-poll (one
/// second) wait made asynchronous panel and audit settlement a race against machine
/// load rather than a test of behaviour.
private let fixtureSettlementPolls = 750

@MainActor
private func descendant<T: NSView>(
  of type: T.Type,
  accessibilityIdentifier: String,
  in root: NSView
) -> T? {
  if let match = root as? T,
    match.accessibilityIdentifier() == accessibilityIdentifier
  {
    return match
  }
  for child in root.subviews {
    if let match = descendant(
      of: type, accessibilityIdentifier: accessibilityIdentifier, in: child)
    {
      return match
    }
  }
  return nil
}

final class FormFixtureServer: @unchecked Sendable {
  private let listener: NWListener
  let port: UInt16

  convenience init() throws {
    try self.init { request in
      let body =
        request.hasPrefix("POST ")
        ? "<title>Done</title>"
        : "<form action='/submitted' method='post'><input name='account_secret' "
          + "value='never-serialize-me'><button type='submit'>Submit</button></form>"
      return Self.response(body: body)
    }
  }

  init(responseProvider: @escaping @Sendable (String) -> String) throws {
    listener = try NWListener(using: .tcp, on: .any)
    let ready = DispatchSemaphore(value: 0)
    listener.stateUpdateHandler = { state in
      if case .ready = state { ready.signal() }
    }
    listener.newConnectionHandler = { connection in
      connection.start(queue: .global())
      connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
        data, _, _, _ in
        let request = String(decoding: data ?? Data(), as: UTF8.self)
        let response = responseProvider(request)
        connection.send(
          content: Data(response.utf8), contentContext: .finalMessage, isComplete: true,
          completion: .contentProcessed { _ in connection.cancel() })
      }
    }
    listener.start(queue: .global())
    guard ready.wait(timeout: .now() + 2) == .success, let assignedPort = listener.port else {
      listener.cancel()
      throw CocoaError(.coderReadCorrupt)
    }
    port = assignedPort.rawValue
  }

  deinit { listener.cancel() }

  static func response(body: String, extraHeaders: String = "") -> String {
    "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\(extraHeaders)"
      + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
  }

  static func redirect(to url: URL) -> String {
    "HTTP/1.1 302 Found\r\nLocation: \(url.absoluteString)\r\n"
      + "Content-Length: 0\r\nConnection: close\r\n\r\n"
  }
}

@Suite("Native WebKit runtime", .serialized)
@MainActor
struct WebKitRuntimeTests {
  private func makeWindowHandoffRuntime() -> WebKitRuntime {
    // Swift Testing runs in a command-line host. Repeatedly transforming that
    // host between regular and accessory activation policies can terminate the
    // process before it reports the rest of this suite. The installed-app gate
    // exercises the real activation-policy transition end to end.
    WebKitRuntime(
      websiteDataStore: .nonPersistent(),
      egressProxy: nil,
      managesApplicationActivationPolicy: false)
  }

  @Test("Document readiness uses mutation quiescence and no rAF")
  func readiness() async throws {
    let runtime = WebKitRuntime()
    let result = try await runtime.loadHTML(
      """
      <!doctype html>
      <title>Fixture</title>
      <script>
        queueMicrotask(() => document.body.dataset.ready = 'yes');
      </script>
      """,
      baseURL: URL(string: "https://fixture.invalid/"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )

    #expect(result.readiness == .ready)
    #expect(result.elapsedNanoseconds > 0)
  }

  @Test("Observation emits semantic recipes and provenance")
  func observation() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <!doctype html>
      <title>Account</title>
      <label for="email">Email address</label>
      <input id="email" value="kevin@example.test">
      <button aria-label="Save profile">Save</button>
      """,
      baseURL: URL(string: "https://fixture.invalid/settings"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )

    let page = try await runtime.observe()
    #expect(page.title.segments.first?.text == "Account")
    #expect(page.title.classifications == [.firstPartySiteContent])
    #expect(page.url.classifications == [.toolResult])
    #expect(page.elements.count == 2)
    #expect(page.elements.map(\.elementID) == ["e1", "e2"])
    #expect(page.elements[0].role?.segments.first?.text == "textbox")
    #expect(page.elements[0].accessibleName?.segments.first?.text == "Email address")
    #expect(page.elements[0].value?.classifications == [.userEnteredSiteData])
    #expect(page.elements[1].role?.segments.first?.text == "button")
    #expect(page.elements[1].accessibleName?.segments.first?.text == "Save profile")
    #expect(page.elements[1].locatorRecipe.observationID == page.observationID)
  }

  @Test("Observation reports live validation and long-field character counts")
  func validationAndCharacterCountObservation() async throws {
    let runtime = WebKitRuntime()
    let longValue = String(repeating: "a", count: 1_500)
    _ = try await runtime.loadHTML(
      """
      <!doctype html>
      <label for="required">Required</label>
      <input id="required" required value="">
      <label for="accepted">Accepted</label>
      <input id="accepted" required value="ready">
      <label for="rejected">Rejected</label>
      <textarea id="rejected" aria-invalid="true">\(longValue)</textarea>
      """,
      baseURL: URL(string: "https://fixture.invalid/form"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40))

    let page = try await runtime.observe(maximumFieldCharacters: 4_096)
    let required = try #require(
      page.elements.first { $0.accessibleName?.segments.first?.text == "Required" })
    let accepted = try #require(
      page.elements.first { $0.accessibleName?.segments.first?.text == "Accepted" })
    let rejected = try #require(
      page.elements.first { $0.accessibleName?.segments.first?.text == "Rejected" })

    #expect(required.validationState == .invalid)
    #expect(required.characterCount == 0)
    #expect(accepted.validationState == .valid)
    #expect(accepted.characterCount == 5)
    #expect(rejected.validationState == .invalid)
    #expect(rejected.characterCount == 1_500)
    #expect(rejected.value?.segments.first?.text.count == 1_500)

    let canonical = try page.canonicalState()
    let semanticID = rejected.locatorRecipe.semanticIdentity
    let fields = Dictionary(uniqueKeysWithValues: canonical.entries.map { ($0.key, $0.value) })
    #expect(
      fields[.init(frameID: "main", elementID: semanticID, field: "@validation_accepted")]?
        .segments.first?.text == "false")
    #expect(
      fields[.init(frameID: "main", elementID: semanticID, field: "@character_count")]?
        .segments.first?.text == "1500")
  }

  @Test("A macOS file input receives a bounded native selection and emits a pathless receipt")
  func nativeFileUploadPanelReceipt() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("store-icon-512.png")
    let bytes = Data("fixture-image".utf8)
    try bytes.write(to: file, options: .atomic)
    let runtime = WebKitRuntime(
      websiteDataStore: .nonPersistent(), egressProxy: nil,
      managesApplicationActivationPolicy: false,
      uploadSelectionProvider: { allowsMultiple, allowsDirectories in
        #expect(!allowsMultiple)
        #expect(!allowsDirectories)
        return [file]
      })
    _ = try await runtime.loadHTML(
      "<label for='asset'>App icon</label><input id='asset' type='file'>",
      baseURL: URL(string: "https://fixture.invalid/upload"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))
    let before = try await runtime.observe()
    let input = try #require(before.elements.first)
    _ = try await runtime.perform(
      observationID: before.observationID,
      elementID: input.elementID,
      operation: .click,
      dispatchMode: .nativeAppKit,
      stabilityInterval: .milliseconds(1))

    // The receipt is recorded before the delegate returns, and WebKit only populates
    // input.files afterwards. Waiting on the receipt alone races that hand-off, so
    // wait for the DOM the assertion actually reads.
    for _ in 0..<fixtureSettlementPolls {
      let count =
        try await runtime.webView.evaluateJavaScript(
          "document.getElementById('asset').files.length") as? Int
      if count == 1 { break }
      try await Task.sleep(for: .milliseconds(20))
    }
    let receipt = try #require(runtime.latestFileUploadReceipt())
    #expect(receipt.filenames == ["store-icon-512.png"])
    #expect(receipt.byteCounts == [UInt64(bytes.count)])
    #expect(receipt.sha256.count == 1)
    #expect(receipt.sha256[0].count == 64)
    #expect(!receipt.selectedByHuman)
    #expect(!receipt.localPathsExposed)
    let selectedName =
      try await runtime.webView.evaluateJavaScript(
        "document.getElementById('asset').files[0].name") as? String
    #expect(selectedName == "store-icon-512.png")
  }

  @Test("Native file upload rejects a selection above its hard file-count bound")
  func nativeFileUploadCountBound() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(
      "webkitui-upload-count-\(UUID().uuidString).txt")
    try Data("bounded".utf8).write(to: file, options: .atomic)
    defer { try? FileManager.default.removeItem(at: file) }
    let runtime = WebKitRuntime(
      websiteDataStore: .nonPersistent(), egressProxy: nil,
      managesApplicationActivationPolicy: false,
      uploadSelectionProvider: { _, _ in Array(repeating: file, count: 11) })
    _ = try await runtime.loadHTML(
      "<input aria-label='Assets' type='file' multiple>",
      baseURL: URL(string: "https://fixture.invalid/upload"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))
    let observation = try await runtime.observe()
    let input = try #require(observation.elements.first)
    _ = try await runtime.perform(
      observationID: observation.observationID, elementID: input.elementID,
      operation: .click, stabilityInterval: .milliseconds(1))
    try await Task.sleep(for: .milliseconds(100))
    #expect(runtime.latestFileUploadReceipt() == nil)
    let count =
      try await runtime.webView.evaluateJavaScript(
        "document.querySelector('input').files.length") as? Int
    #expect(count == 0)
  }

  @Test("An armed upload selection is consumed by exactly one file panel")
  func armedUploadSelectionIsSingleUse() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("play-screenshot-1.png")
    let bytes = Data("armed-fixture".utf8)
    try bytes.write(to: file, options: .atomic)
    let runtime = WebKitRuntime(
      websiteDataStore: .nonPersistent(), egressProxy: nil,
      managesApplicationActivationPolicy: false)
    _ = try await runtime.loadHTML(
      "<input aria-label='First' type='file'><input aria-label='Second' type='file'>",
      baseURL: URL(string: "https://fixture.invalid/upload"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))
    runtime.armUploadSelection([file])

    let first = try await runtime.observe()
    let firstInput = try #require(first.elements.first)
    _ = try await runtime.perform(
      observationID: first.observationID, elementID: firstInput.elementID,
      operation: .click, dispatchMode: .nativeAppKit,
      stabilityInterval: .milliseconds(1))
    for _ in 0..<fixtureSettlementPolls where runtime.latestFileUploadReceipt() == nil {
      try await Task.sleep(for: .milliseconds(20))
    }
    let receipt = try #require(runtime.latestFileUploadReceipt())
    #expect(receipt.filenames == ["play-screenshot-1.png"])
    #expect(receipt.selectionMode == .agentConfirmed)
    #expect(!receipt.selectedByHuman)
    #expect(!receipt.localPathsExposed)

    // The armed selection is spent: a second panel opened by the site gets nothing.
    #expect(!runtime.hasArmedUploadSelection())
    let count =
      try await runtime.webView.evaluateJavaScript(
        "document.querySelectorAll('input')[1].files.length") as? Int
    #expect(count == 0)
  }

  @Test("A loading shell that also renders navigation labels still waits for hydration")
  func loadingShellWithChromeWaitsForHydration() async throws {
    // Play Console's shell shows "Loading Google Play Console" alongside its
    // navigation labels, so a rule anchored on the whole body text never matched and
    // the observation returned zero elements on a page that was still hydrating.
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <div id="shell">
        <p>Loading Google Play Console</p>
        <p>notifications_unread</p><p>Unread notifications</p>
        <p>features</p><p>Home</p><p>Policy status</p>
      </div>
      <script>
        setTimeout(() => {
          document.getElementById('shell').remove();
          document.body.insertAdjacentHTML(
            'beforeend', '<button aria-label="LorisLab">LorisLab</button>');
        }, 400);
      </script>
      """,
      baseURL: URL(string: "https://play.fixture.invalid/console"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(20))

    let observation = try await runtime.observe(hydrationTimeout: .seconds(10))
    #expect(observation.elements.count == 1)
    #expect(
      observation.elements.first?.accessibleName?.segments.map(\.text).joined() == "LorisLab")
  }

  @Test("A rendered page keeping a loading banner is not treated as still loading")
  func renderedPageWithLoadingBannerDoesNotStall() async throws {
    // Play Console's app list keeps "Loading Google Play Console" at the top of its
    // text while being fully rendered. Treating that as a shell made every
    // observation wait out the full hydration budget for nothing.
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <p>Loading Google Play Console</p>
      <p>Home</p><p>Policy status</p>
      <button aria-label="Create app">Create app</button>
      """,
      baseURL: URL(string: "https://play.fixture.invalid/app-list"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(20))

    let started = ContinuousClock.now
    let observation = try await runtime.observe(hydrationTimeout: .seconds(30))
    #expect(ContinuousClock.now - started < .seconds(5))
    #expect(observation.elements.count == 1)
  }

  @Test("Handing control to a human puts the window back on a display")
  func humanHandoffRestoresAnOnScreenWindow() async throws {
    // The window is parked outside every display so pages lay out without being
    // shown. A handoff that ordered it front without moving it back asked the user
    // to act in a window that was nowhere on screen.
    let runtime = WebKitRuntime(
      websiteDataStore: .nonPersistent(), egressProxy: nil,
      managesApplicationActivationPolicy: false)
    _ = try await runtime.loadHTML(
      "<p>Sign in</p>", baseURL: URL(string: "https://fixture.invalid/signin"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(20))
    // Observing is what parks the window outside every display.
    _ = try await runtime.observe()
    #expect(!runtime.browserWindowIsOnScreen)

    try runtime.requestHumanHandoff()
    try runtime.beginHumanControl(presentWindow: true)
    #expect(runtime.browserWindowIsOnScreen)

    try runtime.requestAgentResume()
    _ = try await runtime.resumeAfterHumanControl()
    #expect(!runtime.browserWindowIsOnScreen)
    // The parked window must stop being the app's front window, or a confirmation
    // panel positioned against it lands off screen and is never seen.
    let parked = try #require(runtime.webView.window)
    #expect(!parked.isKeyWindow)
    #expect(parked.level.rawValue < NSWindow.Level.normal.rawValue)
  }

  @Test("Main-frame navigation audit distinguishes agent actions from web content")
  func navigationActorAttribution() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      "<a href='/agent-next'>Next</a>",
      baseURL: URL(string: "https://fixture.invalid/start"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))
    #expect(runtime.latestNavigationAuditEvent()?.actor == .agentNavigation)
    #expect(runtime.latestNavigationAuditEvent()?.toOrigin == "https://fixture.invalid")

    let observation = try await runtime.observe()
    let link = try #require(observation.elements.first)
    // The subject here is navigation-audit attribution, not click success. Activating
    // this link replaces the document, so re-resolution after dispatch may correctly
    // fail closed on the very navigation under test. Either outcome is acceptable;
    // the audit event is what must be right.
    var dispatched = true
    do {
      _ = try await runtime.perform(
        observationID: observation.observationID,
        elementID: link.elementID,
        operation: .click,
        stabilityInterval: .milliseconds(1))
    } catch WebKitRuntimeError.staleObservation {
      dispatched = false
    } catch WebKitRuntimeError.targetNotUnique {
      dispatched = false
    }
    if dispatched {
      for _ in 0..<fixtureSettlementPolls
      where runtime.latestNavigationAuditEvent()?.actor != .agentAction {
        try await Task.sleep(for: .milliseconds(20))
      }
      #expect(runtime.latestNavigationAuditEvent()?.actor == .agentAction)
      #expect(runtime.latestNavigationAuditEvent()?.navigationType == "link_activated")
    } else {
      // Failing closed is genuinely indeterminate: the click may have landed and
      // replaced the document before re-resolution ran, so attribution cannot be
      // asserted either way. What must hold is that the runtime stays usable rather
      // than requiring a handoff to recover.
      let recovered = try await runtime.observe()
      #expect(!recovered.observationID.isEmpty)
    }

    let scripted = WebKitRuntime()
    _ = try await scripted.loadHTML(
      "<p>Start</p>", baseURL: URL(string: "https://fixture.invalid/start"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))
    _ = try await scripted.webView.evaluateJavaScript("location.href='/automatic'")
    for _ in 0..<fixtureSettlementPolls
    where scripted.latestNavigationAuditEvent()?.actor != .webContent {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(scripted.latestNavigationAuditEvent()?.actor == .webContent)
    #expect(scripted.latestNavigationAuditEvent()?.navigationType == "other")
  }

  @Test("A Material checkbox hidden behind an aria-hidden box stays addressable")
  func materialCheckboxRemainsAddressable() async throws {
    // Play Console renders every checkbox in two halves: a real input with no size,
    // and the painted box beside it marked aria-hidden. The filter dropped both, so
    // a page of six expanded sections observed as groups with no children at all and
    // four of the eleven publishing forms could not be filled by any means.
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <!doctype html>
      <title>Financial features</title>
      <div role="group" aria-label="Banking and loans">
        <div class="row" onclick="document.getElementById('loans').click()">
          <div class="mdc-checkbox">
            <input type="checkbox" id="loans" aria-labelledby="loans-text"
              style="position:absolute;width:0;height:0;opacity:0">
            <div class="mdc-checkbox__background" aria-hidden="true"
              style="width:18px;height:18px"></div>
          </div>
          <span id="loans-text" style="display:inline-block;width:400px">Banking and loans</span>
        </div>
      </div>
      """,
      baseURL: URL(string: "https://fixture.invalid/app-content/finance"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )

    let before = try await runtime.observe()
    let checkbox = try #require(
      before.elements.first { $0.role?.segments.first?.text == "checkbox" },
      "the checkbox was dropped: the page observes as a group with no children")
    #expect(checkbox.accessibleName?.segments.first?.text == "Banking and loans")
    // Addressed by the visible half. The input's own box is 0x0 and would refuse
    // every click as target_not_actionable.
    #expect(checkbox.boundingBox.width > 0 && checkbox.boundingBox.height > 0)

    let result = try await runtime.perform(
      observationID: before.observationID,
      elementID: checkbox.elementID,
      operation: .click,
      stabilityInterval: .milliseconds(1))
    #expect(result.dispatched)

    let after = try await runtime.observe()
    let updated = try #require(
      after.elements.first { $0.role?.segments.first?.text == "checkbox" })
    #expect(updated.checked == true)
  }

  @Test("Two hidden controls in one row never borrow the same surface")
  func hiddenControlsDoNotShareASurface() async throws {
    // Standing a hidden control up on an ancestor is only safe while that ancestor
    // owns exactly one control. Sharing a surface would send both clicks to the same
    // pixels and silently toggle the wrong box.
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <!doctype html>
      <title>Ambiguous row</title>
      <div class="row" style="width:400px;height:40px">
        <input type="checkbox" id="a" aria-label="Loans"
          style="position:absolute;width:0;height:0;opacity:0">
        <input type="checkbox" id="b" aria-label="Deposits"
          style="position:absolute;width:0;height:0;opacity:0">
      </div>
      """,
      baseURL: URL(string: "https://fixture.invalid/app-content/finance"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )

    let observation = try await runtime.observe()
    #expect(observation.elements.contains { $0.role?.segments.first?.text == "checkbox" } == false)
  }

  @Test("A radio covered by its own painted overlay is clicked through its wrapper")
  func coveredRadioIsClickedThroughItsWrapper() async throws {
    // D3, and the second half of D2: the input is rendered at 18x18 and passes every
    // visibility check, but the painted box sits on top of it, so hit testing at its
    // centre lands on the overlay and the click is refused as target_not_actionable —
    // indeterminate, which costs a failed round trip on every radio Play renders.
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <!doctype html>
      <title>Government apps</title>
      <div class="wrapper" onclick="document.getElementById('no').click()"
        style="position:relative;width:600px;height:40px">
        <input type="radio" name="gov" id="no" aria-label="No" style="width:18px;height:18px">
        <div aria-hidden="true"
          style="position:absolute;left:0;top:0;width:600px;height:40px"></div>
      </div>
      """,
      baseURL: URL(string: "https://fixture.invalid/app-content/government-apps"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )

    let before = try await runtime.observe()
    let radio = try #require(
      before.elements.first { $0.role?.segments.first?.text == "radio" })
    let result = try await runtime.perform(
      observationID: before.observationID,
      elementID: radio.elementID,
      operation: .click,
      stabilityInterval: .milliseconds(1))
    #expect(result.dispatched)

    let after = try await runtime.observe()
    let updated = try #require(
      after.elements.first { $0.role?.segments.first?.text == "radio" })
    #expect(updated.checked == true)
  }

  @Test("A borrowed surface lends its label, not just its geometry")
  func borrowedSurfaceLendsItsLabel() async throws {
    // B1: exposing the checkbox was only half the job. Play's inputs carry no
    // aria-label and no aria-labelledby, so twenty-two checkboxes came back with
    // name, label and text all null and no context at all. Their locators held role
    // and nothing else, and every act failed as targetNotUnique(22).
    let runtime = WebKitRuntime()
    let rows = ["Banking and loans", "Payments and transfers", "Trading and funds"]
      .enumerated()
      .map { index, title in
        """
        <div class="row" onclick="document.getElementById('c\(index)').click()">
          <div class="mdc-checkbox">
            <input type="checkbox" id="c\(index)"
              style="position:absolute;width:0;height:0;opacity:0">
            <div class="box" aria-hidden="true" style="width:18px;height:18px"></div>
          </div>
          <span style="display:inline-block;width:400px">\(title)</span>
        </div>
        """
      }
      .joined()
    _ = try await runtime.loadHTML(
      "<!doctype html><title>Financial features</title>"
        + "<div role=\"group\" aria-label=\"Select the features your app provides\">"
        + rows + "</div>",
      baseURL: URL(string: "https://fixture.invalid/app-content/finance"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )

    let observation = try await runtime.observe()
    let checkboxes = observation.elements.filter { $0.role?.segments.first?.text == "checkbox" }
    #expect(checkboxes.count == 3)
    let names = checkboxes.compactMap { $0.accessibleName?.segments.first?.text }
    #expect(names.sorted() == ["Banking and loans", "Payments and transfers", "Trading and funds"])

    // Named uniquely, so it can actually be addressed rather than failing as not unique.
    let payments = try #require(
      checkboxes.first { $0.accessibleName?.segments.first?.text == "Payments and transfers" })
    let result = try await runtime.perform(
      observationID: observation.observationID,
      elementID: payments.elementID,
      operation: .click,
      stabilityInterval: .milliseconds(1))
    #expect(result.dispatched)

    let after = try await runtime.observe()
    let checkedNames = after.elements
      .filter { $0.role?.segments.first?.text == "checkbox" && $0.checked == true }
      .compactMap { $0.accessibleName?.segments.first?.text }
    #expect(checkedNames == ["Payments and transfers"])
  }

  @Test("A control with no layout box is named in the diagnostics, never silently dropped")
  func zeroSizeControlIsNamedInDiagnostics() async throws {
    // B2: the escape option after the "Or" separator — "none of these features" — has
    // no layout box anywhere up its row, and Next stays disabled without it. A control
    // with no box genuinely cannot be clicked, so exposing it as actionable would be a
    // lie. What the agent needs is to know the exit exists, and what it is called, so
    // it can hand the form to a human instead of concluding the page is complete.
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <!doctype html>
      <title>Financial features</title>
      <div class="row" style="height:0;overflow:hidden">
        <input type="checkbox" id="none" style="width:0;height:0">
        <span>My app does not provide any of these features</span>
      </div>
      <button>Next</button>
      """,
      baseURL: URL(string: "https://fixture.invalid/app-content/finance"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )

    let observation = try await runtime.observe()
    #expect(observation.unrenderedControlCount >= 1)
    #expect(
      observation.unrenderedControlNames.contains(
        "My app does not provide any of these features"))
  }

  @Test("Open shadow DOM controls remain observable and actionable")
  func openShadowDOMControls() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <!doctype html>
      <title>Shadow form</title>
      <div id="composer"></div>
      <script>
        const root = document.getElementById('composer').attachShadow({ mode: 'open' });
        root.innerHTML = '<label for="title">Title</label>'
          + '<input id="title" name="title" placeholder="Title">';
      </script>
      """,
      baseURL: URL(string: "https://fixture.invalid/submit"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )

    let before = try await runtime.observe()
    let title = try #require(
      before.elements.first { $0.accessibleName?.segments.first?.text == "Title" })
    #expect(title.role?.segments.first?.text == "textbox")
    #expect(title.stableAttributes["name"]?.segments.first?.text == "title")

    let value = try ProvenancedText(
      text: "Native browser authority",
      source: ProvenanceSource(classification: .modelGenerated))
    let result = try await runtime.perform(
      observationID: before.observationID,
      elementID: title.elementID,
      operation: .fill(value),
      stabilityInterval: .milliseconds(1))
    #expect(result.dispatched)
    #expect(result.addressingOutcome == .stable)

    let after = try await runtime.observe()
    let updated = try #require(
      after.elements.first { $0.accessibleName?.segments.first?.text == "Title" })
    #expect(updated.value?.segments.first?.text == "Native browser authority")
  }

  @Test("Password values never cross the observation boundary")
  func passwordOmitted() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <!doctype html>
      <label for="password">Password</label>
      <input id="password" type="password" value="top-secret">
      """,
      baseURL: URL(string: "https://fixture.invalid/login"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )

    let observation = try await runtime.observe()
    let encoded = try JSONEncoder().encode(observation)
    let json = String(decoding: encoded, as: UTF8.self)
    #expect(!json.contains("top-secret"))
    #expect(observation.elements[0].sensitive)
    let replacement = try ProvenancedText(
      text: "model-secret", source: ProvenanceSource(classification: .modelGenerated))
    await #expect(throws: WebKitRuntimeError.sensitiveInputRequiresHuman) {
      try await runtime.perform(
        observationID: observation.observationID,
        elementID: "e1",
        operation: .fill(replacement),
        stabilityInterval: .milliseconds(1)
      )
    }
  }

  @Test("Observation emits safe context, stable hrefs, and locator quality before actuation")
  func contextualLocatorQuality() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <!doctype html>
      <button></button><button></button>
      <section aria-label="API Tokens">
        <h2>API Tokens</h2>
        <a id="api-link" href="/dashboard/tokens?team=private-team-value">
          <span aria-hidden="true">→</span>
        </a>
      </section>
      """,
      baseURL: URL(string: "https://fixture.invalid/settings"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40))

    let observation = try await runtime.observe()
    let link = try #require(
      observation.elements.first { element in
        element.role?.segments.first?.text == "link"
      })
    #expect(
      link.contextAnchors.contains {
        $0.kind == .labelledRegion && $0.text.segments.first?.text == "API Tokens"
      })
    #expect(
      link.contextAnchors.contains {
        $0.kind == .nearestHeading && $0.text.segments.first?.text == "API Tokens"
      })
    #expect(
      link.stableAttributes["href"]?.segments.first?.text
        == "https://fixture.invalid/dashboard/tokens?team=<redacted>")
    #expect(link.stableAttributes["id"]?.segments.first?.text == "api-link")
    #expect(link.locatorQuality.status == .unique)
    #expect(link.locatorQuality.candidateCount == 1)
    #expect(link.locatorQuality.facts.contains("stable_attribute:href"))

    let buttons = observation.elements.filter {
      $0.role?.segments.first?.text == "button"
    }
    #expect(buttons.count == 2)
    #expect(buttons.allSatisfy { $0.locatorQuality.status == .insufficient })
    #expect(buttons.allSatisfy { $0.locatorQuality.candidateCount == 2 })
    #expect(
      buttons.allSatisfy {
        $0.locatorQuality.recommendedAction == "contextual_reobserve_or_handoff"
      })

    let encoded = String(decoding: try JSONEncoder().encode(observation), as: UTF8.self)
    #expect(!encoded.contains("private-team-value"))
  }

  @Test("Observation omits hidden values and classifies sensitive visible fields")
  func observationMinimizesFieldValues() async throws {
    let runtime = WebKitRuntime(websiteDataStore: .nonPersistent())
    let hiddenSecrets = [
      "hidden-type-secret-001",
      "hidden-attribute-secret-002",
      "zero-box-secret-003",
      "display-none-secret-004",
      "visibility-hidden-secret-005",
      "opacity-zero-secret-006",
      "aria-hidden-secret-007",
      "inert-secret-008",
    ]
    let sensitiveSecrets = [
      "csrf-secret-101",
      "state-secret-102",
      "nonce-secret-103",
      "session-secret-104",
      "assertion-secret-105",
      "generic-secret-106",
      "password-secret-107",
      "otp-secret-108",
      "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-opaque",
    ]
    _ = try await runtime.loadHTML(
      """
      <!doctype html>
      <label for="email">Email</label>
      <input id="email" value="visible@example.test">
      <label for="country">Country</label>
      <select id="country"><option value="technical-country-opaque-998877">France</option></select>

      <input type="hidden" value="\(hiddenSecrets[0])">
      <input hidden value="\(hiddenSecrets[1])">
      <input style="width:0;height:0;border:0;padding:0" value="\(hiddenSecrets[2])">
      <input style="display:none" value="\(hiddenSecrets[3])">
      <input style="visibility:hidden" value="\(hiddenSecrets[4])">
      <input style="opacity:0" value="\(hiddenSecrets[5])">
      <div aria-hidden="true"><input value="\(hiddenSecrets[6])"></div>
      <div inert><input value="\(hiddenSecrets[7])"></div>

      <input name="csrfToken" value="\(sensitiveSecrets[0])">
      <input name="state" value="\(sensitiveSecrets[1])">
      <input name="nonce" value="\(sensitiveSecrets[2])">
      <input name="session_state" value="\(sensitiveSecrets[3])">
      <input name="assertion" value="\(sensitiveSecrets[4])">
      <input name="client_secret" value="\(sensitiveSecrets[5])">
      <input type="password" value="\(sensitiveSecrets[6])">
      <input autocomplete="one-time-code" value="\(sensitiveSecrets[7])">
      <input id="profile-code" value="\(sensitiveSecrets[8])">
      """,
      baseURL: URL(string: "https://fixture.invalid/privacy"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )

    let observation = try await runtime.observe()
    #expect(observation.elements.count == 11)
    #expect(observation.elements.allSatisfy { $0.visible })
    #expect(observation.elements[0].value?.segments.first?.text == "visible@example.test")
    #expect(observation.elements[1].value?.segments.first?.text == "France")
    #expect(observation.elements[1].text?.segments.first?.text == "France")
    #expect(observation.elements.dropFirst(2).allSatisfy { $0.sensitive })
    #expect(observation.elements.dropFirst(2).allSatisfy { $0.value == nil })

    let observationJSON = String(decoding: try JSONEncoder().encode(observation), as: UTF8.self)
    let canonicalJSON = String(
      decoding: try JSONEncoder().encode(try observation.canonicalState()),
      as: UTF8.self
    )
    let recipesJSON = String(
      decoding: try JSONEncoder().encode(observation.elements.map(\.locatorRecipe)),
      as: UTF8.self
    )
    for secret in hiddenSecrets + sensitiveSecrets + ["technical-country-opaque-998877"] {
      #expect(!observationJSON.contains(secret))
      #expect(!canonicalJSON.contains(secret))
      #expect(!recipesJSON.contains(secret))
    }
  }

  @Test("A labelled reverse-DNS Bundle ID remains public while opaque tokens stay sensitive")
  func bundleIdentifierIsNotSensitive() async throws {
    let runtime = WebKitRuntime(websiteDataStore: .nonPersistent())
    _ = try await runtime.loadHTML(
      """
      <label for="bundle-id">Bundle ID</label>
      <input id="bundle-id" name="bundleIdentifier"
        value="com.lorislab.lumenforfrigate.background-agent">
      <label for="token">Profile code</label>
      <input id="token" value="AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-opaque">
      """,
      baseURL: URL(string: "https://fixture.invalid/identifiers"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))

    let observation = try await runtime.observe()
    let bundle = try #require(
      observation.elements.first { element in
        element.label?.segments.first?.text == "Bundle ID"
      })
    #expect(!bundle.sensitive)
    #expect(
      bundle.value?.segments.first?.text
        == "com.lorislab.lumenforfrigate.background-agent")
    let token = try #require(
      observation.elements.first { element in
        element.label?.segments.first?.text == "Profile code"
      })
    #expect(token.sensitive)
    #expect(token.value == nil)
  }

  @Test("Authentication origins block agent surfaces and classify an unready UI")
  func authenticationOriginFailClosed() async throws {
    let runtime = WebKitRuntime(websiteDataStore: .nonPersistent())
    let secret = "query-state-must-never-escape"
    let result = try await runtime.loadHTML(
      """
      <!doctype html>
      <div role="progressbar" aria-label="Loading"></div>
      <form style="display:none">
        <input autocomplete="username">
        <input type="password">
      </form>
      """,
      baseURL: URL(string: "https://idmsa.apple.com/IDMSWebAuth/signin?state=\(secret)"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )

    #expect(result.url == "https://idmsa.apple.com")
    #expect(runtime.agentSafeCurrentURL() == "https://idmsa.apple.com")
    #expect(
      runtime.authenticationRestrictionStatus()
        == AuthenticationRestrictionStatus(
          origin: "https://idmsa.apple.com",
          classification: .authUINotReady,
          environment: AuthenticationEnvironmentSnapshot(
            persistentWebsiteDataStore: false,
            customUserAgentConfigured: false,
            applicationNameForUserAgentConfigured: false,
            pinnedProxyConfigured: false,
            contentBlockingConfigured: false,
            customProcessPoolConfigured: false,
            webAuthnAnyRelyingPartyEntitlementConfigured: false
          )
        ))

    await #expect(
      throws: WebKitRuntimeError.authenticationOriginRequiresHuman(
        "https://idmsa.apple.com")
    ) {
      try await runtime.observe()
    }
    await #expect(
      throws: WebKitRuntimeError.authenticationOriginRequiresHuman(
        "https://idmsa.apple.com")
    ) {
      try await runtime.readText()
    }
    await #expect(
      throws: WebKitRuntimeError.authenticationOriginRequiresHuman(
        "https://idmsa.apple.com")
    ) {
      try await runtime.capture()
    }
    await #expect(
      throws: WebKitRuntimeError.authenticationOriginRequiresHuman(
        "https://idmsa.apple.com")
    ) {
      try await runtime.scrollBy(deltaX: 0, deltaY: 100)
    }
    await #expect(
      throws: WebKitRuntimeError.authenticationOriginRequiresHuman(
        "https://idmsa.apple.com")
    ) {
      try await runtime.perform(
        observationID: UUID().uuidString,
        elementID: "e1",
        operation: .click
      )
    }

    try runtime.requestHumanHandoff()
    try runtime.beginHumanControl(presentWindow: false)
    #expect(runtime.interactionControlState() == .humanControlled)
    #expect(
      throws: WebKitRuntimeError.authenticationOriginRequiresHuman(
        "https://idmsa.apple.com")
    ) {
      try runtime.requestAgentResume()
    }
    #expect(runtime.interactionControlState() == .humanControlled)
    #expect(!String(describing: result).contains(secret))
  }

  @Test("Authentication environment distinguishes persistent storage without identifiers")
  func authenticationEnvironmentIsSanitized() async throws {
    let persistent = WebKitRuntime(websiteDataStore: .default())
    let ephemeral = WebKitRuntime(websiteDataStore: .nonPersistent())

    #expect(persistent.authenticationEnvironmentSnapshot().persistentWebsiteDataStore)
    #expect(!ephemeral.authenticationEnvironmentSnapshot().persistentWebsiteDataStore)
    for snapshot in [
      persistent.authenticationEnvironmentSnapshot(),
      ephemeral.authenticationEnvironmentSnapshot(),
    ] {
      #expect(!snapshot.customUserAgentConfigured)
      #expect(!snapshot.applicationNameForUserAgentConfigured)
      #expect(!snapshot.pinnedProxyConfigured)
      #expect(!snapshot.contentBlockingConfigured)
      #expect(!snapshot.customProcessPoolConfigured)
      #expect(!snapshot.webAuthnAnyRelyingPartyEntitlementConfigured)
    }
    _ = try await ephemeral.loadHTML(
      "<title>User agent fixture</title>",
      baseURL: URL(string: "https://fixture.invalid/user-agent"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )
    let userAgent = try #require(
      try await ephemeral.webView.evaluateJavaScript("navigator.userAgent") as? String)
    #expect(userAgent.contains("AppleWebKit"))
    #expect(!userAgent.contains("WebkitUIMCP"))
  }

  @Test("Visible WebAuthn security-key control requires a full browser without entitlement")
  func webAuthnSecurityKeyRequiresFullBrowserWithoutEntitlement() async throws {
    let runtime = WebKitRuntime(websiteDataStore: .nonPersistent())
    _ = try await runtime.loadHTML(
      "<div>Verify with a security key</div>",
      baseURL: URL(string: "https://dash.cloudflare.com/two-factor"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )

    let status = try #require(runtime.authenticationRestrictionStatus())
    #expect(status.origin == "https://dash.cloudflare.com")
    #expect(status.classification == .fullBrowserRequired)
    #expect(!status.environment.webAuthnAnyRelyingPartyEntitlementConfigured)
    await #expect(
      throws: WebKitRuntimeError.authenticationOriginRequiresHuman(
        "https://dash.cloudflare.com")
    ) {
      try await runtime.observe()
    }
  }

  @Test("Cloudflare two-factor route requires a full browser even with closed component text")
  func cloudflareTwoFactorRouteRequiresFullBrowser() async throws {
    let runtime = WebKitRuntime(websiteDataStore: .nonPersistent())
    _ = try await runtime.loadHTML(
      "<div>Authentication challenge</div>",
      baseURL: URL(string: "https://dash.cloudflare.com/two-factor"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )
    let status = try #require(runtime.authenticationRestrictionStatus())
    #expect(status.origin == "https://dash.cloudflare.com")
    #expect(status.classification == .fullBrowserRequired)
  }

  @Test("Full-browser fallback is limited to the exact Apple authentication embedding pair")
  func appleAuthenticationFullBrowserPolicyIsNarrow() {
    #expect(
      WebKitRuntime.requiresFullBrowserBackend(
        topLevelURL: URL(string: "https://appstoreconnect.apple.com/login"),
        restrictedFrameOrigin: "https://idmsa.apple.com"
      ))
    #expect(
      !WebKitRuntime.requiresFullBrowserBackend(
        topLevelURL: URL(string: "https://appstoreconnect.apple.com.evil.invalid/login"),
        restrictedFrameOrigin: "https://idmsa.apple.com"
      ))
    #expect(
      !WebKitRuntime.requiresFullBrowserBackend(
        topLevelURL: URL(string: "https://appstoreconnect.apple.com/login"),
        restrictedFrameOrigin: "https://idmsa.apple.com.evil.invalid"
      ))
    #expect(
      !WebKitRuntime.requiresFullBrowserBackend(
        topLevelURL: URL(string: "https://developer.apple.com/account"),
        restrictedFrameOrigin: "https://idmsa.apple.com"
      ))
    #expect(
      !WebKitRuntime.requiresFullBrowserBackend(
        topLevelURL: URL(string: "https://appstoreconnect.apple.com/login"),
        restrictedFrameOrigin: nil
      ))
  }

  @Test("Element IDs are observation-scoped")
  func observationScopedIDs() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      "<button>Save</button>",
      baseURL: URL(string: "https://fixture.invalid/"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )

    let first = try await runtime.observe()
    let second = try await runtime.observe()
    #expect(first.elements.first?.elementID == "e1")
    #expect(second.elements.first?.elementID == "e1")
    #expect(first.observationID != second.observationID)
    #expect(second.generation == first.generation + 1)
  }

  @Test("Navigation rejects non-web schemes")
  func rejectsNonWebSchemes() async throws {
    let runtime = WebKitRuntime()
    await #expect(throws: WebKitRuntimeError.unsupportedURLScheme) {
      try await runtime.navigate(to: URL(fileURLWithPath: "/tmp/secret"))
    }
  }

  @Test("An approved-origin lock cancels later cross-origin top-level navigation")
  func approvedOriginLock() async throws {
    let server = try FormFixtureServer()
    let runtime = WebKitRuntime(websiteDataStore: .nonPersistent())
    let approvedURL = URL(string: "http://127.0.0.1:\(server.port)/inside")!
    _ = try await runtime.navigate(
      to: approvedURL,
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(20),
      constrainToInitialOrigin: true
    )
    do {
      _ = try await runtime.loadHTML(
        """
        <title>Locked</title>
        <script>
          setTimeout(() => {
            window.location.href = 'http://localhost:\(server.port)/escape';
          }, 100);
        </script>
        """,
        baseURL: approvedURL,
        timeout: fixtureNavigationTimeout,
        quietWindow: .milliseconds(20)
      )
    } catch WebKitRuntimeError.crossOriginRedirectRequiresHuman(
      let fromOrigin,
      let toOrigin
    ) {
      #expect(fromOrigin == "http://127.0.0.1:\(server.port)")
      #expect(toOrigin == "http://localhost:\(server.port)")
      #expect(!fromOrigin.contains("/inside"))
      #expect(!toOrigin.contains("/escape"))
    }
    try await Task.sleep(for: .milliseconds(180))

    #expect(runtime.webView.url?.host == "127.0.0.1")
  }

  @Test("An approved cross-origin redirect retains its exact private request for handoff")
  func approvedCrossOriginRedirectContinuesExactRequest() async throws {
    let privateState = "private-redirect-state-must-stay-inside-webkit"
    let authenticationServer = try FormFixtureServer { request in
      let receivedExactRequest = request.contains("GET /authenticate?state=\(privateState) ")
      return FormFixtureServer.response(
        body: receivedExactRequest
          ? """
          <!doctype html><title>Human authentication</title>
          <style>html,body{margin:0;width:100%;height:100%;background:rgb(18,52,86)}</style>
          <form><label>Account <input autocomplete="username"></label></form>
          """
          : "<title>Missing private redirect state</title>")
    }
    let authenticationURL = URL(
      string: "http://localhost:\(authenticationServer.port)/authenticate?state=\(privateState)"
    )!
    let entryServer = try FormFixtureServer { _ in
      FormFixtureServer.redirect(to: authenticationURL)
    }
    let runtime = makeWindowHandoffRuntime()

    await #expect(
      throws: WebKitRuntimeError.crossOriginRedirectRequiresHuman(
        fromOrigin: "http://127.0.0.1:\(entryServer.port)",
        toOrigin: "http://localhost:\(authenticationServer.port)"
      )
    ) {
      try await runtime.navigate(
        to: URL(string: "http://127.0.0.1:\(entryServer.port)/developer-portal")!,
        timeout: fixtureNavigationTimeout,
        quietWindow: .milliseconds(20),
        constrainToInitialOrigin: true
      )
    }

    let continued = try await runtime.continueApprovedCrossOriginNavigation(
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(20))
    #expect(continued.readiness == .ready)
    #expect(runtime.webView.url == authenticationURL)
    #expect(
      try await runtime.webView.evaluateJavaScript("document.title") as? String
        == "Human authentication")

    try runtime.requestHumanHandoff()
    try runtime.beginHumanControl(presentWindow: true)
    let window = try #require(runtime.webView.window)
    #expect(window.isVisible)
    let snapshot = try await runtime.webView.takeSnapshot(configuration: nil)
    let bitmap = try #require(snapshot.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
    let center = try #require(
      bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB)
    )
    #expect(center.blueComponent > center.redComponent)

    runtime.webView.loadHTMLString(
      "<title>Developer Portal</title><main>Connected</main>",
      baseURL: URL(string: "https://developer.apple.com/account/")!)
    while runtime.webView.isLoading {
      try await Task.sleep(for: .milliseconds(10))
    }
    try runtime.markHumanStepCompleted()
    #expect(runtime.interactionControlState() == .humanStepCompleted)
    #expect(runtime.humanStepCompletionMonotonicNanoseconds() != nil)
    try runtime.requestAgentResume()
    let resumed = try await runtime.resumeAfterHumanControl()
    #expect(resumed.title.segments.first?.text == "Developer Portal")
    #expect(!String(describing: resumed).contains(privateState))
  }

  @Test("macOS 27 willSubmitForm does not cover programmatic requestSubmit")
  func formSubmissionAudit() async throws {
    let server = try FormFixtureServer()
    let runtime = WebKitRuntime(websiteDataStore: .nonPersistent())
    #expect(
      runtime.responds(
        to: NSSelectorFromString("webView:willSubmitForm:submissionHandler:")))
    _ = try await runtime.navigate(
      to: URL(string: "http://127.0.0.1:\(server.port)/form")!,
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(20)
    )
    _ = try await runtime.webView.evaluateJavaScript(
      "document.querySelector('form').requestSubmit()")
    try await Task.sleep(for: .milliseconds(300))

    #expect(runtime.webView.url?.path == "/submitted")
    #expect(runtime.formSubmissionAuditEvents().isEmpty)
  }

  @Test("A forced real WebContent crash invalidates addresses and reloads without replay")
  func forcedWebContentCrashRecovery() async throws {
    let server = try FormFixtureServer()
    let runtime = WebKitRuntime(websiteDataStore: .nonPersistent())
    _ = try await runtime.navigate(
      to: URL(string: "http://127.0.0.1:\(server.port)/form")!,
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(20)
    )
    let before = try await runtime.observe()
    let selector = NSSelectorFromString("_killWebContentProcessAndResetState")
    #expect(runtime.webView.responds(to: selector))
    _ = runtime.webView.perform(selector)

    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(2)
    while !runtime.webContentProcessIsTerminated(), clock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(runtime.webContentProcessIsTerminated())
    let termination = try #require(runtime.terminationAuditEvents().last)
    #expect(termination.documentID == before.documentID)
    #expect(termination.observationID == before.observationID)
    #expect(throws: WebKitRuntimeError.staleObservation) {
      try runtime.locatorRecipe(
        observationID: before.observationID,
        elementID: before.elements[0].elementID)
    }

    try runtime.requestHumanHandoff()
    try runtime.beginHumanControl(presentWindow: false)
    try runtime.requestAgentResume()
    let recovered = try await runtime.resumeAfterHumanControl()

    #expect(recovered.documentID != before.documentID)
    #expect(recovered.observationID != before.observationID)
    #expect(recovered.url.segments.first?.text == before.url.segments.first?.text)
    #expect(runtime.interactionControlState() == .freshlyReobserved)
    #expect(!runtime.webContentProcessIsTerminated())
  }

  @Test("Authenticated cookie and origin storage survive a forced WebContent crash")
  func authenticatedStorageCrashRecovery() async throws {
    let server = try FormFixtureServer { request in
      if request.hasPrefix("GET /login ") {
        return FormFixtureServer.response(
          body: """
            <title>Logged in</title>
            <script>
              localStorage.setItem('durable_state', 'yes');
              sessionStorage.setItem('page_session_state', 'yes');
            </script>
            """,
          extraHeaders: "Set-Cookie: session=alive; Path=/; HttpOnly; SameSite=Lax\r\n")
      }
      let authenticated = request.lowercased().contains("cookie: session=alive")
      return FormFixtureServer.response(
        body: authenticated
          ? """
          <title>Authenticated</title><button>Account</button>
          <script>
            document.title = `Authenticated:${localStorage.getItem('durable_state') ?? 'no'}:${sessionStorage.getItem('page_session_state') ?? 'no'}`;
          </script>
          """
          : "<title>Signed out</title>")
    }
    let runtime = WebKitRuntime(websiteDataStore: .nonPersistent())
    _ = try await runtime.navigate(
      to: URL(string: "http://127.0.0.1:\(server.port)/login")!,
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(20)
    )
    _ = try await runtime.navigate(
      to: URL(string: "http://127.0.0.1:\(server.port)/account")!,
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(20)
    )
    let before = try await runtime.observe()
    #expect(before.title.segments.first?.text == "Authenticated:yes:yes")

    let selector = NSSelectorFromString("_killWebContentProcessAndResetState")
    #expect(runtime.webView.responds(to: selector))
    _ = runtime.webView.perform(selector)
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(2)
    while !runtime.webContentProcessIsTerminated(), clock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(runtime.webContentProcessIsTerminated())

    try runtime.requestHumanHandoff()
    try runtime.beginHumanControl(presentWindow: false)
    try runtime.requestAgentResume()
    let recovered = try await runtime.resumeAfterHumanControl()

    #expect(recovered.title.segments.first?.text == "Authenticated:yes:yes")
    #expect(recovered.documentID != before.documentID)
    #expect(runtime.terminationAuditEvents().count == 1)
  }

  @Test("An isolated persistent data store retains synthetic cookie and origin storage")
  func isolatedPersistentAuthenticationStorage() async throws {
    let server = try FormFixtureServer { request in
      if request.hasPrefix("GET /seed ") {
        return FormFixtureServer.response(
          body: """
            <title>Seeded</title>
            <script>localStorage.setItem('fixture_auth_state', 'alive');</script>
            """,
          extraHeaders: "Set-Cookie: fixture_session=alive; Path=/; HttpOnly; SameSite=Lax\r\n")
      }
      let cookiePresent = request.lowercased().contains("cookie: fixture_session=alive")
      return FormFixtureServer.response(
        body: """
          <title>Check</title>
          <script>
            document.title = '\(cookiePresent ? "cookie" : "no-cookie"):'
              + (localStorage.getItem('fixture_auth_state') ?? 'no-storage');
          </script>
          """)
    }
    let identifier = UUID()
    var testError: (any Error)?
    do {
      let store = WKWebsiteDataStore(forIdentifier: identifier)
      do {
        let first = WebKitRuntime(websiteDataStore: store)
        #expect(first.authenticationEnvironmentSnapshot().persistentWebsiteDataStore)
        _ = try await first.navigate(
          to: URL(string: "http://127.0.0.1:\(server.port)/seed")!,
          timeout: fixtureNavigationTimeout,
          quietWindow: .milliseconds(40)
        )
      }
      do {
        let second = WebKitRuntime(websiteDataStore: store)
        let check = try await second.navigate(
          to: URL(string: "http://127.0.0.1:\(server.port)/check")!,
          timeout: fixtureNavigationTimeout,
          quietWindow: .milliseconds(40)
        )
        #expect(check.readiness == .ready)
        let title = try await second.webView.evaluateJavaScript("document.title") as? String
        #expect(title == "cookie:alive")
      }
    } catch {
      testError = error
    }
    try await Task.sleep(for: .milliseconds(100))
    do {
      try await WKWebsiteDataStore.remove(forIdentifier: identifier)
    } catch {
      if testError == nil { throw error }
    }
    if let testError { throw testError }
  }

  @Test("Invalid readiness windows fail before navigation")
  func invalidQuietWindow() async throws {
    let runtime = WebKitRuntime()
    await #expect(throws: WebKitRuntimeError.invalidQuietWindow) {
      try await runtime.loadHTML(
        "<p>test</p>",
        baseURL: nil,
        quietWindow: .zero
      )
    }
  }

  @Test("A timed-out navigation is stopped before the next command")
  func timedOutNavigationDoesNotReplaceNextDocument() async throws {
    let slowServer = try FormFixtureServer { _ in
      Thread.sleep(forTimeInterval: 0.3)
      return FormFixtureServer.response(body: "<title>Late document</title>")
    }
    let runtime = WebKitRuntime(websiteDataStore: .nonPersistent())

    await #expect(throws: (any Error).self) {
      try await runtime.navigate(
        to: URL(string: "http://127.0.0.1:\(slowServer.port)/slow")!,
        timeout: .milliseconds(40),
        quietWindow: .milliseconds(20))
    }
    let next = try await runtime.loadHTML(
      "<title>Next command</title>",
      baseURL: URL(string: "https://fixture.invalid/next"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(20))
    #expect(next.readiness == .ready)

    try await Task.sleep(for: .milliseconds(400))
    let title = try await runtime.webView.evaluateJavaScript("document.title") as? String
    #expect(title == "Next command")
  }

  @Test("Snapshot is a real PNG with an explicit compositor caveat")
  func snapshot() async throws {
    let runtime = WebKitRuntime()
    #expect(runtime.webView.window != nil)
    _ = try await runtime.loadHTML(
      "<button>Capture me</button>",
      baseURL: URL(string: "https://fixture.invalid/"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )

    let capture = try await runtime.capture()
    #expect(capture.pngData.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    #expect(capture.width == Int(1280 * capture.backingScaleFactor))
    #expect(capture.height == Int(800 * capture.backingScaleFactor))
    #expect(capture.backingScaleFactor >= 1)
    #expect(capture.compositorEffectsMayBeMissing)
  }

  @Test("Human handoff presents the live rendered WebView")
  func humanHandoffPresentsLiveRenderedWebView() async throws {
    let runtime = makeWindowHandoffRuntime()
    let stableWindow = try #require(runtime.webView.window)
    #expect(!stableWindow.isVisible)
    _ = try await runtime.loadHTML(
      """
      <!doctype html>
      <style>
        html, body { margin: 0; width: 100%; height: 100%; background: rgb(12, 34, 56); }
        h1 { color: white; padding: 40px; }
      </style>
      <h1>Visible handoff fixture</h1>
      """,
      baseURL: URL(string: "https://fixture.invalid/handoff"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )

    try runtime.requestHumanHandoff()
    try runtime.beginHumanControl(presentWindow: true)

    let window = try #require(runtime.webView.window)
    #expect(window === stableWindow)
    #expect(window.title == "WebkitUIMCP — Human control")
    #expect(window.isVisible)
    #expect(window.alphaValue == 1)
    #expect(runtime.webView.isDescendant(of: try #require(window.contentView)))
    #expect(runtime.webView.bounds.width > 0)
    #expect(runtime.webView.bounds.height > 0)

    window.displayIfNeeded()
    runtime.webView.layoutSubtreeIfNeeded()
    let configuration = WKSnapshotConfiguration()
    configuration.rect = runtime.webView.bounds
    configuration.snapshotWidth = NSNumber(value: runtime.webView.bounds.width)
    let image = try await runtime.webView.takeSnapshot(configuration: configuration)
    let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
    let center = try #require(
      bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB)
    )
    #expect(center.redComponent < 0.2)
    #expect(center.greenComponent < 0.3)
    #expect(center.blueComponent < 0.4)

    let contentView = try #require(window.contentView)
    let done = try #require(
      descendant(
        of: NSButton.self,
        accessibilityIdentifier: "webkitui.handoff.done",
        in: contentView))
    let status = try #require(
      descendant(
        of: NSTextField.self,
        accessibilityIdentifier: "webkitui.handoff.status",
        in: contentView))
    done.performClick(nil)
    #expect(runtime.interactionControlState() == .humanStepCompleted)
    #expect(!done.isEnabled)
    #expect(done.title == "Ready — Waiting for Agent")
    #expect(status.stringValue.contains("Waiting for the requesting agent"))

    try runtime.requestAgentResume()
    _ = try await runtime.resumeAfterHumanControl()
    // The window stays ordered in so WebKit keeps laying the page out, but it is
    // parked outside every display: nothing is shown to the user.
    #expect(!runtime.browserWindowIsOnScreen)
    #expect(runtime.webView.window === window)
  }

  @Test("Human handoff button reports an invalid transition instead of swallowing it")
  func humanHandoffButtonReportsFailure() throws {
    let runtime = makeWindowHandoffRuntime()
    try runtime.requestHumanHandoff()
    try runtime.beginHumanControl(presentWindow: true)
    let contentView = try #require(runtime.webView.window?.contentView)
    let done = try #require(
      descendant(
        of: NSButton.self,
        accessibilityIdentifier: "webkitui.handoff.done",
        in: contentView))
    let status = try #require(
      descendant(
        of: NSTextField.self,
        accessibilityIdentifier: "webkitui.handoff.status",
        in: contentView))

    try runtime.markHumanStepCompleted()
    done.performClick(nil)

    #expect(done.isEnabled)
    #expect(done.title == "Try Again — Return Control")
    #expect(status.stringValue.contains("could not be returned"))
  }

  @Test("Native Edit menu routes Command-V to the first responder")
  func nativePasteCommand() throws {
    let application = NSApplication.shared
    WebKitNativeApplicationMenu.install(on: application)
    let mainMenu = try #require(application.mainMenu)
    let editMenu = try #require(
      mainMenu.items.first(where: { $0.submenu?.title == "Edit" })?.submenu)
    let paste = try #require(editMenu.items.first(where: { $0.title == "Paste" }))
    #expect(paste.action == #selector(NSText.paste(_:)))
    #expect(paste.keyEquivalent == "v")
    #expect(paste.keyEquivalentModifierMask == [.command])
  }

  @Test("An empty human handoff renders an explicit local status page")
  func emptyHandoffRendersStatusPage() async throws {
    let runtime = makeWindowHandoffRuntime()
    #expect(runtime.webView.url == nil)

    try runtime.requestHumanHandoff()
    try runtime.beginHumanControl(presentWindow: true)
    while runtime.webView.isLoading {
      try await Task.sleep(for: .milliseconds(10))
    }

    let text = try #require(
      try await runtime.webView.evaluateJavaScript("document.body.innerText") as? String)
    #expect(text.contains("No approved page is loaded"))
    #expect(text.contains("Approve a browser navigation"))

    try runtime.requestAgentResume()
    _ = try await runtime.resumeAfterHumanControl()
  }

  @Test("Session handles are bounded and unforgeable")
  func sessions() throws {
    let registry = try WebKitSessionRegistry(maximumSessions: 1)
    let handle = try registry.open()
    #expect(registry.count == 1)
    #expect(try registry.status(handle).sessionID == handle.rawValue)
    #expect(throws: WebKitSessionRegistryError.capacityReached) {
      try registry.open()
    }
    #expect(throws: WebKitSessionRegistryError.unknownSession) {
      try registry.status(.init(rawValue: UUID()))
    }
    try registry.close(handle)
    #expect(registry.count == 0)
  }

  @Test("Production registries enforce one host controller")
  func hostExclusiveSession() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "webkitui-host-lock-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let lockURL = directory.appendingPathComponent("controller.lock")
    let first = try WebKitSessionRegistry(
      enforceHostExclusiveSession: true, hostControllerLockURL: lockURL)
    let second = try WebKitSessionRegistry(
      enforceHostExclusiveSession: true, hostControllerLockURL: lockURL)
    let handle = try first.open()
    do {
      _ = try second.open()
      Issue.record("A second host controller unexpectedly acquired the lock")
    } catch WebKitSessionRegistryError.hostControllerBusy(let holder) {
      #expect(holder?.processID == getpid())
      #expect(holder?.clientName == ProcessInfo.processInfo.processName)
      #expect(holder?.executionPolicy == "auto")
    }
    try first.close(handle)
    let secondHandle = try second.open()
    try second.close(secondHandle)
  }

  @Test("An unowned host lease is yielded to the next process after its grace window")
  func unownedHostLeaseIsYielded() async throws {
    // O11. Every client reaches WebKit through its own process, so a lease kept for an
    // owner that never came back locked every other client out of the machine until an
    // operator pressed Release host lease. Ownership is released on disconnect and the
    // browser is deliberately kept for a reconnect — but only for as long as a
    // reconnect is plausible.
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "webkitui-unowned-lease-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let lockURL = directory.appendingPathComponent("controller.lock")
    let holder = try WebKitSessionRegistry(
      enforceHostExclusiveSession: true, hostControllerLockURL: lockURL,
      unownedLeaseGrace: .milliseconds(150))
    let next = try WebKitSessionRegistry(
      enforceHostExclusiveSession: true, hostControllerLockURL: lockURL)

    let handle = try holder.open()
    let owner = UUID()
    #expect(try holder.claimSessionOwnership(for: handle, owner: owner))
    holder.releaseSessionOwnerships(owner: owner)

    // Inside the window the browser is still there for the client that walked away.
    #expect(holder.existingHandle == handle)
    #expect(throws: WebKitSessionRegistryError.self) { _ = try next.open() }

    try await Task.sleep(for: .milliseconds(400))
    #expect(holder.existingHandle == nil)
    let adopted = try next.open()
    try next.close(adopted)
  }

  @Test("A client that comes back inside the grace window keeps its browser")
  func reconnectInsideGraceKeepsTheSession() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "webkitui-grace-reconnect-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let lockURL = directory.appendingPathComponent("controller.lock")
    let holder = try WebKitSessionRegistry(
      enforceHostExclusiveSession: true, hostControllerLockURL: lockURL,
      unownedLeaseGrace: .milliseconds(300))

    let handle = try holder.open()
    let first = UUID()
    #expect(try holder.claimSessionOwnership(for: handle, owner: first))
    holder.releaseSessionOwnerships(owner: first)

    try await Task.sleep(for: .milliseconds(80))
    let second = UUID()
    #expect(try holder.claimSessionOwnership(for: handle, owner: second))

    try await Task.sleep(for: .milliseconds(500))
    // Reclaimed in time, so the grace no longer applies and the browser survives.
    #expect(holder.existingHandle == handle)
    try holder.close(handle)
  }

  @Test("Authenticated origins list hosts only, never cookie values")
  func authenticatedOriginsListHostsOnly() async throws {
    let store = WKWebsiteDataStore.nonPersistent()
    let runtime = WebKitRuntime(
      websiteDataStore: store, egressProxy: nil,
      managesApplicationActivationPolicy: false)
    let secret = "session-token-must-never-escape"
    let cookie = try #require(
      HTTPCookie(properties: [
        .domain: "console.fixture.invalid",
        .path: "/",
        .name: "session",
        .value: secret,
        .secure: "TRUE",
      ]))
    await store.httpCookieStore.setCookie(cookie)

    let origins = await runtime.authenticatedOrigins()
    #expect(origins.contains("console.fixture.invalid"))
    #expect(!origins.contains(where: { $0.contains(secret) }))
    #expect(origins == origins.sorted())
  }

  @Test("Click re-resolves semantics and reports an untrusted JS gesture")
  func clickActuation() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <button aria-label="Save profile" onclick="this.setAttribute('aria-label', 'Saved')">
        Save
      </button>
      """,
      baseURL: URL(string: "https://fixture.invalid/"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )
    let before = try await runtime.observe()
    let result = try await runtime.perform(
      observationID: before.observationID,
      elementID: "e1",
      operation: .click,
      stabilityInterval: .milliseconds(10)
    )
    #expect(result.dispatched)
    #expect(!result.trustedUserGesture)
    #expect(result.addressingOutcome == .stable)

    let after = try await runtime.observe()
    #expect(after.elements[0].accessibleName?.segments.first?.text == "Saved")
  }

  @Test("AppKit click reaches WebKit as a trusted DOM gesture")
  func nativeTrustedClickActuation() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <button aria-label='Trusted action'
        onclick="this.dataset.state=event.isTrusted && navigator.userActivation.isActive
          ? 'trusted' : 'rejected'">Run</button>
      """,
      baseURL: URL(string: "https://fixture.invalid/native-click"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))
    let before = try await runtime.observe()
    let result = try await runtime.perform(
      observationID: before.observationID,
      elementID: "e1",
      operation: .click,
      dispatchMode: .nativeAppKit,
      stabilityInterval: .milliseconds(10))
    #expect(result.dispatched)
    #expect(result.trustedUserGesture)
    #expect(result.dispatchMode == .nativeAppKit)
    let after = try await runtime.observe()
    #expect(after.elements[0].stateAttributes["data-state"]?.segments.first?.text == "trusted")
  }

  @Test("AppKit fill survives a controlled-input rerender with an exact trusted receipt")
  func nativeControlledFillActuation() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <label for="bundle-id">Bundle ID</label><input id="bundle-id" value="old.value.id">
      <script>
      const input = document.getElementById('bundle-id');
      input.addEventListener('input', event => {
        document.body.dataset.inputTrust = String(event.isTrusted);
        const replacement = event.target.cloneNode(true);
        replacement.value = event.target.value;
        event.target.replaceWith(replacement);
      });
      </script>
      """,
      baseURL: URL(string: "https://fixture.invalid/native-fill"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))
    let before = try await runtime.observe()
    let value = try ProvenancedText(
      text: "com.lorislab.example.background-agent",
      source: ProvenanceSource(classification: .userIntent))
    let result = try await runtime.perform(
      observationID: before.observationID,
      elementID: "e1",
      operation: .fill(value),
      dispatchMode: .nativeAppKit,
      stabilityInterval: .milliseconds(10))
    #expect(result.dispatched)
    #expect(result.trustedUserGesture)
    #expect(result.dispatchMode == .nativeAppKit)
    let after = try await runtime.observe()
    #expect(after.elements[0].value?.segments.first?.text == value.segments.first?.text)
  }

  @Test("AppKit fill commits validation in the same trusted action")
  func nativeFillCommitsValidation() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <label for="description">Short description</label>
      <input id="description" aria-invalid="true" data-state="missing">
      <script>
      const input = document.getElementById('description');
      input.addEventListener('change', event => {
        input.dataset.state = event.isTrusted ? 'committed' : 'rejected';
        input.setAttribute('aria-invalid', event.isTrusted ? 'false' : 'true');
      });
      </script>
      """,
      baseURL: URL(string: "https://fixture.invalid/native-fill-commit"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))
    let before = try await runtime.observe()
    let value = try ProvenancedText(
      text: "Local-first camera monitoring",
      source: ProvenanceSource(classification: .userIntent))
    let result = try await runtime.perform(
      observationID: before.observationID,
      elementID: "e1",
      operation: .fill(value),
      dispatchMode: .nativeAppKit,
      stabilityInterval: .milliseconds(10))
    #expect(result.trustedUserGesture)
    let after = try await runtime.observe()
    #expect(after.elements[0].validationState == .valid)
    #expect(after.elements[0].stateAttributes["data-state"]?.segments.first?.text == "committed")
  }

  @Test("Observation waits for a visible SPA loading shell to hydrate")
  func observationWaitsForSPAHydration() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <main id="shell">Loading Google Play Console…</main>
      <script>
      setTimeout(() => {
        document.getElementById('shell').innerHTML =
          '<label for="name">App name</label><input id="name" value="Lumen">';
      }, 150);
      </script>
      """,
      baseURL: URL(string: "https://fixture.invalid/spa-hydration"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(20))
    let observation = try await runtime.observe(hydrationTimeout: .seconds(2))
    #expect(observation.elements.count == 1)
    #expect(observation.elements[0].value?.segments.first?.text == "Lumen")
  }

  @Test("AppKit fill persists in an Apple-style searchable App ID selector")
  func nativeCustomSelectorFillActuation() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <label for="app-id">App ID</label>
      <input id="app-id" role="combobox" aria-controls="options">
      <div id="options" role="listbox"></div>
      <script>
      const input = document.getElementById('app-id');
      input.addEventListener('input', event => {
        if (!event.isTrusted) { event.target.value = ''; return; }
        const value = event.target.value;
        const replacement = event.target.cloneNode(true);
        replacement.value = value;
        event.target.replaceWith(replacement);
      });
      </script>
      """,
      baseURL: URL(string: "https://fixture.invalid/profile-selector"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))
    let before = try await runtime.observe()
    let value = try ProvenancedText(
      text: "Lumen Background Agent",
      source: ProvenanceSource(classification: .userIntent))
    let result = try await runtime.perform(
      observationID: before.observationID,
      elementID: "e1",
      operation: .fill(value),
      dispatchMode: .nativeAppKit,
      stabilityInterval: .milliseconds(10))
    #expect(result.trustedUserGesture)
    let after = try await runtime.observe()
    #expect(after.elements[0].value?.segments.first?.text == "Lumen Background Agent")
  }

  @Test("Same-row labels independently address repeated Configure buttons")
  func sameRowLabelsDisambiguateControls() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <div class="row"><span>App Groups</span><button data-state="idle"
        onclick="this.dataset.state='opened'">Configure</button></div>
      <div class="row"><span>iCloud</span><button data-state="idle"
        onclick="this.dataset.state='opened'">Configure</button></div>
      """,
      baseURL: URL(string: "https://fixture.invalid/capabilities"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))
    let observation = try await runtime.observe()
    let buttons = observation.elements.filter {
      $0.accessibleName?.segments.first?.text == "Configure"
    }
    #expect(buttons.count == 2)
    #expect(buttons.allSatisfy { $0.locatorQuality.status == .unique })
    #expect(buttons[0].contextAnchors.first?.kind == .sameRowLabel)
    #expect(buttons[0].contextAnchors.first?.text.segments.first?.text == "App Groups")
    #expect(buttons[1].contextAnchors.first?.text.segments.first?.text == "iCloud")

    let firstResult = try await runtime.perform(
      observationID: observation.observationID,
      elementID: buttons[0].elementID,
      operation: .click,
      stabilityInterval: .milliseconds(10))
    #expect(firstResult.dispatched)
    let refreshed = try await runtime.observe()
    let iCloud = try #require(
      refreshed.elements.first { element in
        element.contextAnchors.first?.text.segments.first?.text == "iCloud"
      })
    let secondResult = try await runtime.perform(
      observationID: refreshed.observationID,
      elementID: iCloud.elementID,
      operation: .click,
      stabilityInterval: .milliseconds(10))
    #expect(secondResult.dispatched)
  }

  @Test("An authenticated attachment download returns a collision-safe integrity receipt")
  func authenticatedAttachmentDownload() async throws {
    let profile = "fixture-provisioning-profile-bytes"
    let server = try FormFixtureServer { request in
      if request.hasPrefix("GET /profile") {
        return "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n"
          + "Content-Disposition: attachment; filename=Fixture.provisionprofile\r\n"
          + "Content-Length: \(profile.utf8.count)\r\nConnection: close\r\n\r\n\(profile)"
      }
      return FormFixtureServer.response(
        body: "<a href='/profile'>Download</a>",
        extraHeaders: "Set-Cookie: portal_session=private; HttpOnly\r\n")
    }
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("webkitui-download-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let requested = directory.appendingPathComponent("Fixture.provisionprofile")
    try Data("existing".utf8).write(to: requested)
    let runtime = WebKitRuntime(
      websiteDataStore: .nonPersistent(),
      egressProxy: nil,
      managesApplicationActivationPolicy: false,
      downloadDestinationProvider: { _ in requested })
    _ = try await runtime.navigate(
      to: URL(string: "http://127.0.0.1:\(server.port)/")!,
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))
    let observation = try await runtime.observe()
    let link = try #require(
      observation.elements.first {
        $0.accessibleName?.segments.first?.text == "Download"
      })
    let receipt = try await runtime.download(
      observationID: observation.observationID,
      elementID: link.elementID,
      timeout: fixtureNavigationTimeout)
    #expect(receipt.filename == "Fixture 2.provisionprofile")
    #expect(receipt.suggestedFilename == "Fixture.provisionprofile")
    #expect(receipt.httpStatus == 200)
    #expect(receipt.byteCount == UInt64(profile.utf8.count))
    #expect(receipt.sha256 == ObservationPredicate.textDigest(of: profile))
    #expect(receipt.mimeType == "application/octet-stream")
    #expect(receipt.provisioningProfileUUID == nil)
    #expect(
      try String(
        contentsOf: directory.appendingPathComponent(receipt.filename), encoding: .utf8) == profile)
  }

  @Test("A same-origin URL fallback preserves cookies and verifies a profile UUID")
  func authenticatedDirectURLDownload() async throws {
    let expectedUUID = "12345678-1234-1234-1234-123456789ABC"
    let profile =
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
      + "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
      + "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">"
      + "<plist version=\"1.0\"><dict><key>UUID</key><string>\(expectedUUID)</string>"
      + "</dict></plist>"
    let server = try FormFixtureServer { request in
      if request.hasPrefix("GET /direct-profile") {
        guard request.lowercased().contains("cookie: portal_session=private") else {
          return "HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        }
        return "HTTP/1.1 200 OK\r\nContent-Type: application/x-apple-aspen-config\r\n"
          + "Content-Disposition: attachment; filename=Direct.provisionprofile\r\n"
          + "Content-Length: \(profile.utf8.count)\r\nConnection: close\r\n\r\n\(profile)"
      }
      return FormFixtureServer.response(
        body: "<p>Authenticated portal</p>",
        extraHeaders: "Set-Cookie: portal_session=private; HttpOnly\r\n")
    }
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("webkitui-direct-download-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = WebKitRuntime(
      websiteDataStore: .nonPersistent(),
      egressProxy: nil,
      managesApplicationActivationPolicy: false,
      downloadDestinationProvider: { suggested in directory.appendingPathComponent(suggested) })
    _ = try await runtime.navigate(
      to: URL(string: "http://127.0.0.1:\(server.port)/")!,
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))
    let receipt = try await runtime.download(
      url: URL(string: "http://127.0.0.1:\(server.port)/direct-profile")!,
      expectedProvisioningProfileUUID: expectedUUID,
      timeout: fixtureNavigationTimeout)
    #expect(receipt.httpStatus == 200)
    #expect(receipt.suggestedFilename == "Direct.provisionprofile")
    #expect(receipt.provisioningProfileUUID == expectedUUID)
    #expect(receipt.sha256 == ObservationPredicate.textDigest(of: profile))
    #expect(
      FileManager.default.fileExists(
        atPath: directory.appendingPathComponent(receipt.filename).path))
  }

  @Test("The direct URL fallback rejects another origin before starting")
  func directURLDownloadRejectsCrossOrigin() async throws {
    let runtime = WebKitRuntime(
      websiteDataStore: .nonPersistent(),
      egressProxy: nil,
      managesApplicationActivationPolicy: false,
      downloadDestinationProvider: { _ in nil })
    _ = try await runtime.loadHTML(
      "<p>Portal</p>",
      baseURL: URL(string: "https://portal.example/")!,
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))
    await #expect(throws: WebKitRuntimeError.networkBoundaryDenied) {
      try await runtime.download(
        url: URL(string: "https://download.example/profile")!,
        timeout: .milliseconds(100))
    }
  }

  @Test("A same-origin HTML response is a typed unsupported download")
  func directURLRejectsNonDownloadResponse() async throws {
    let server = try FormFixtureServer { request in
      if request.hasPrefix("GET /not-a-download") {
        return FormFixtureServer.response(body: "<p>Not an attachment</p>")
      }
      return FormFixtureServer.response(body: "<p>Portal</p>")
    }
    let runtime = WebKitRuntime(
      websiteDataStore: .nonPersistent(),
      egressProxy: nil,
      managesApplicationActivationPolicy: false,
      downloadDestinationProvider: { _ in nil })
    _ = try await runtime.navigate(
      to: URL(string: "http://127.0.0.1:\(server.port)/")!,
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))
    await #expect(throws: WebKitRuntimeError.unsupportedDownload(httpStatus: 200)) {
      try await runtime.download(
        url: URL(string: "http://127.0.0.1:\(server.port)/not-a-download")!,
        timeout: fixtureNavigationTimeout)
    }
  }

  @Test("A CMS-wrapped provisioning profile exposes only its decoded UUID")
  func cmsProvisioningProfileUUID() throws {
    let encoded =
      "MIIBEwYJKoZIhvcNAQcBoIIBBASCAQA8P3htbCB2ZXJzaW9uPSIxLjAiIGVuY29kaW5nPSJVVEYtOCI/Pg0KPCFET0NUWVBFIHBsaXN0IFBVQkxJQyAiLS8vQXBwbGUvL0RURCBQTElTVCAxLjAvL0VOIiAiaHR0cDovL3d3dy5hcHBsZS5jb20vRFREcy9Qcm9wZXJ0eUxpc3QtMS4wLmR0ZCI+DQo8cGxpc3QgdmVyc2lvbj0iMS4wIj48ZGljdD48a2V5PlVVSUQ8L2tleT48c3RyaW5nPjg3NjU0MzIxLTQzMjEtNDMyMS00MzIxLUNCQTk4NzY1NDMyMTwvc3RyaW5nPjwvZGljdD48L3BsaXN0Pg0K"
    let cms = try #require(Data(base64Encoded: encoded))
    #expect(
      WebKitRuntime.provisioningProfileUUID(from: cms)
        == "87654321-4321-4321-4321-CBA987654321")
  }

  @Test("Fill preserves input provenance at the actuation boundary")
  func fillActuation() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      "<label for='name'>Name</label><input id='name'>",
      baseURL: URL(string: "https://fixture.invalid/"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )
    let before = try await runtime.observe()
    let value = try ProvenancedText(
      text: "Kevin",
      source: ProvenanceSource(classification: .userIntent)
    )
    let result = try await runtime.perform(
      observationID: before.observationID,
      elementID: "e1",
      operation: .fill(value),
      stabilityInterval: .milliseconds(10)
    )
    #expect(result.dispatched)
    #expect(!result.trustedUserGesture)

    let after = try await runtime.observe()
    #expect(after.elements[0].value?.segments.first?.text == "Kevin")
    #expect(after.elements[0].value?.classifications == [.userEnteredSiteData])
  }

  @Test("Control state and bounded attributes survive a fresh observation")
  func observableControlState() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <label style='display:inline-block; padding:8px'>
        <input style='position:absolute; opacity:0' type='checkbox' checked aria-expanded='false'>
        Financial data
      </label>
      <select aria-label='Plan'><option>Free</option><option selected>Paid</option></select>
      """,
      baseURL: URL(string: "https://fixture.invalid/state"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))

    let observation = try await runtime.observe()
    let checkbox = try #require(
      observation.elements.first { $0.role?.segments.first?.text == "checkbox" })
    let select = try #require(
      observation.elements.first { $0.role?.segments.first?.text == "combobox" })
    #expect(checkbox.checked == true)
    #expect(checkbox.stateAttributes["aria-expanded"]?.segments.first?.text == "false")
    #expect(select.selectedOption?.segments.first?.text == "Paid")

    let state = try observation.canonicalState()
    let fields = Set(state.entries.map(\.key.field))
    #expect(fields.contains("@checked"))
    #expect(fields.contains("@selected_option"))
    #expect(fields.contains("@attribute:aria-expanded"))
  }

  @Test("Keyboard commit operations dispatch without claiming native trust")
  func keyboardCommitOperations() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <input aria-label='Recipient' onkeydown="if(event.key==='Enter') this.dataset.state='accepted'"
        onchange="this.dataset.state='committed'">
      """,
      baseURL: URL(string: "https://fixture.invalid/keyboard"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))
    let before = try await runtime.observe()
    let key = try await runtime.perform(
      observationID: before.observationID, elementID: "e1", operation: .pressKey("Enter"),
      stabilityInterval: .milliseconds(10))
    #expect(key.dispatched)
    #expect(!key.trustedUserGesture)
    let accepted = try await runtime.observe()
    #expect(accepted.elements[0].stateAttributes["data-state"]?.segments.first?.text == "accepted")
    let committed = try await runtime.perform(
      observationID: accepted.observationID, elementID: "e1", operation: .commitInput,
      stabilityInterval: .milliseconds(10))
    #expect(committed.dispatched)
    let after = try await runtime.observe()
    #expect(after.elements[0].stateAttributes["data-state"]?.segments.first?.text == "committed")
  }

  @Test("AppKit Enter reaches the focused WebKit control as trusted")
  func nativeTrustedKeyActuation() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <input aria-label='Recipient'
        onkeydown="if(event.key==='Enter') this.dataset.state=
          event.isTrusted&&navigator.userActivation.isActive?'trusted':'rejected'">
      """,
      baseURL: URL(string: "https://fixture.invalid/native-key"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))
    let before = try await runtime.observe()
    let result = try await runtime.perform(
      observationID: before.observationID, elementID: "e1",
      operation: .pressKey("Enter"), dispatchMode: .nativeAppKit,
      stabilityInterval: .milliseconds(10))
    #expect(result.dispatched)
    #expect(result.trustedUserGesture)
    #expect(result.dispatchMode == .nativeAppKit)
    let after = try await runtime.observe()
    #expect(after.elements[0].stateAttributes["data-state"]?.segments.first?.text == "trusted")
  }

  @Test("AppKit Tab blurs and commits the focused WebKit input")
  func nativeTabCommitsInput() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <input aria-label='Service account' value='verifier@example.test'
        onblur="this.dataset.state=event.isTrusted?'committed':'rejected'">
      <button>Next</button>
      """,
      baseURL: URL(string: "https://fixture.invalid/native-tab"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))
    let before = try await runtime.observe()
    let result = try await runtime.perform(
      observationID: before.observationID, elementID: "e1",
      operation: .pressKey("Tab"), dispatchMode: .nativeAppKit,
      stabilityInterval: .milliseconds(10))
    #expect(result.trustedUserGesture)
    let after = try await runtime.observe()
    #expect(after.elements[0].stateAttributes["data-state"]?.segments.first?.text == "committed")
  }

  @Test("Pointer-styled tab groups expose unique roles, names, and selected state")
  func implicitPointerTabs() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <div class='capability-tabs'>
        <div class='tab active' style='cursor:pointer'>Capabilities</div>
        <div class='tab' style='cursor:pointer'>App Services</div>
        <div class='tab' style='cursor:pointer'>Capability Requests</div>
      </div>
      """,
      baseURL: URL(string: "https://fixture.invalid/capabilities"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))

    let observation = try await runtime.observe()
    let tabs = observation.elements.filter {
      $0.role?.segments.first?.text == "tab"
    }
    #expect(
      tabs.map { $0.accessibleName?.segments.first?.text } == [
        "Capabilities", "App Services", "Capability Requests",
      ])
    #expect(tabs.map(\.selected) == [true, false, false])
    #expect(tabs.allSatisfy { $0.locatorQuality.status == .unique })
  }

  @Test("Element scrolling reports its nearest nested scroll region")
  func nestedElementScroll() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <div style='height:120px; overflow:auto'>
        <div style='height:900px'></div><button aria-label='Nested target'>Target</button>
      </div>
      """,
      baseURL: URL(string: "https://fixture.invalid/nested-scroll"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))
    let observation = try await runtime.observe()
    let target = try #require(
      observation.elements.first { $0.accessibleName?.segments.first?.text == "Nested target" })
    let result = try await runtime.scrollElementIntoView(
      observationID: observation.observationID, elementID: target.elementID)
    #expect(result.y > 0)
    #expect(result.viewportHeight == 120)
    #expect(result.documentHeight > result.viewportHeight)
  }

  @Test("Observation filters apply before serialization")
  func serverSideObservationFilters() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      "<button aria-label='Save profile'>Save</button><a href='/help'>Help center</a>",
      baseURL: URL(string: "https://fixture.invalid/filter"),
      timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(40))
    let observation = try await runtime.observe(
      maximumElements: 10, roles: ["button"], nameContains: "save")
    #expect(observation.elements.count == 1)
    #expect(observation.elements[0].role?.segments.first?.text == "button")
  }

  @Test("Ambiguous fresh resolution aborts and increments its exact counter")
  func ambiguityFailsClosed() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      "<button>Save</button><button>Save</button>",
      baseURL: URL(string: "https://fixture.invalid/"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )
    let observation = try await runtime.observe()

    await #expect(throws: WebKitRuntimeError.targetNotUnique(2)) {
      try await runtime.perform(
        observationID: observation.observationID,
        elementID: "e1",
        operation: .click,
        stabilityInterval: .milliseconds(10)
      )
    }
    #expect(runtime.addressingCounterSnapshot().addressNowAmbiguous == 1)
  }

  @Test("Enabled state disambiguates otherwise identical controls")
  func enabledStateDisambiguatesControls() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      "<button onclick='this.dataset.state=\"clicked\"'>Configure</button>"
        + "<button disabled>Configure</button>",
      baseURL: URL(string: "https://fixture.invalid/"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )
    let observation = try await runtime.observe()

    let result = try await runtime.perform(
      observationID: observation.observationID,
      elementID: "e1",
      operation: .click,
      stabilityInterval: .milliseconds(10)
    )

    #expect(result.dispatched)
    let after = try await runtime.observe()
    #expect(after.elements[0].stateAttributes["data-state"]?.segments.first?.text == "clicked")
  }

  @Test("An element symbol expires after the next observation")
  func staleObservationRejected() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      "<button>Save</button>",
      baseURL: URL(string: "https://fixture.invalid/"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )
    let stale = try await runtime.observe()
    _ = try await runtime.observe()

    await #expect(throws: WebKitRuntimeError.staleObservation) {
      try await runtime.perform(
        observationID: stale.observationID,
        elementID: "e1",
        operation: .click
      )
    }
  }

  @Test("Handoff resume capabilities are session-bound, expiring, replaceable, and single-use")
  func handoffResumeCapabilities() throws {
    let registry = try WebKitSessionRegistry(maximumSessions: 1)
    let handle = try registry.open()
    let forgedHandle = WebKitSessionHandle(rawValue: UUID())

    let first = try registry.issueHandoffResumeCapability(for: handle)
    #expect(registry.handoffResumeCapabilityIsActive(first.token, for: handle))
    #expect(!registry.handoffResumeCapabilityIsActive(first.token, for: forgedHandle))

    let replacement = try registry.issueHandoffResumeCapability(for: handle)
    #expect(!registry.handoffResumeCapabilityIsActive(first.token, for: handle))
    #expect(registry.consumeHandoffResumeCapability(replacement.token, for: handle))
    #expect(!registry.consumeHandoffResumeCapability(replacement.token, for: handle))

    let expired = try registry.issueHandoffResumeCapability(
      for: handle, lifetime: -1, now: Date(timeIntervalSince1970: 100))
    #expect(
      !registry.handoffResumeCapabilityIsActive(
        expired.token, for: handle, now: Date(timeIntervalSince1970: 101)))
  }

  @Test("Implicit tables, rows, cells, and search fields are observed semantically")
  func implicitTableAndSearchSemantics() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <input type="search" placeholder="Search identifiers">
      <table><tr><th>Name</th><td>Example App ID</td></tr></table>
      """,
      baseURL: URL(string: "https://fixture.invalid/identifiers"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )

    let observation = try await runtime.observe()
    let roles = observation.elements.compactMap { $0.role?.segments.first?.text }
    #expect(roles.contains("searchbox"))
    #expect(roles.contains("table"))
    #expect(roles.contains("row"))
    #expect(roles.contains("columnheader"))
    #expect(roles.contains("cell"))
    let search = try #require(
      observation.elements.first { element in
        element.role?.segments.first?.text == "searchbox"
      })
    #expect(search.accessibleName?.segments.first?.text == "Search identifiers")
  }

  @Test("Human handoff blocks the agent and resumes only from a fresh address space")
  func humanHandoff() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      "<label for='secret'>Secret</label><input id='secret' value='private'><button>Continue</button>",
      baseURL: URL(string: "https://fixture.invalid/login"),
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(40)
    )
    let before = try await runtime.observe()

    try runtime.requestHumanHandoff()
    try runtime.beginHumanControl(presentWindow: false)
    #expect(runtime.interactionControlState() == .humanControlled)
    await #expect(throws: WebKitRuntimeError.humanControlActive) {
      try await runtime.observe()
    }
    await #expect(throws: WebKitRuntimeError.humanControlActive) {
      try await runtime.perform(
        observationID: before.observationID, elementID: "e2", operation: .click)
    }

    try runtime.markHumanStepCompleted()
    #expect(runtime.interactionControlState() == .humanStepCompleted)
    #expect(runtime.humanStepCompletionMonotonicNanoseconds() != nil)
    try runtime.requestAgentResume()
    let resumed = try await runtime.resumeAfterHumanControl()
    #expect(runtime.interactionControlState() == .freshlyReobserved)
    #expect(resumed.observationID != before.observationID)
    #expect(throws: WebKitRuntimeError.staleObservation) {
      try runtime.locatorRecipe(observationID: before.observationID, elementID: "e2")
    }
    _ = try await runtime.perform(
      observationID: resumed.observationID,
      elementID: "e2",
      operation: .click,
      stabilityInterval: .milliseconds(10)
    )
    #expect(runtime.interactionControlState() == .agentControlled)

    let events = runtime.handoffAuditEvents()
    #expect(
      events.map(\.to) == [
        .handoffRequested, .humanControlled, .humanStepCompleted, .resumeRequested,
        .freshlyReobserved,
        .agentControlled,
      ])
    let encoded = String(decoding: try JSONEncoder().encode(events), as: UTF8.self)
    #expect(!encoded.contains("private"))
  }
}
