import Foundation
import Network
import Testing
import WebKitUIMCPCore

@testable import WebKitUIMCPRuntime

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
}

@Suite("Native WebKit runtime", .serialized)
@MainActor
struct WebKitRuntimeTests {
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
      timeout: .seconds(2),
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
      <input id="email" value="ada@example.test">
      <button aria-label="Save profile">Save</button>
      """,
      baseURL: URL(string: "https://fixture.invalid/settings"),
      timeout: .seconds(2),
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
      timeout: .seconds(2),
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

  @Test("Element IDs are observation-scoped")
  func observationScopedIDs() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      "<button>Save</button>",
      baseURL: URL(string: "https://fixture.invalid/"),
      timeout: .seconds(2),
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
    let runtime = WebKitRuntime(websiteDataStore: .nonPersistent())
    do {
      _ = try await runtime.navigate(
        to: URL(string: "https://fixture.invalid/")!,
        timeout: .milliseconds(60),
        quietWindow: .milliseconds(20),
        constrainToInitialOrigin: true
      )
    } catch {
      // The synthetic host need not resolve; the origin lock is installed first.
    }
    do {
      _ = try await runtime.loadHTML(
        """
        <title>Locked</title>
        <script>
          setTimeout(() => { window.location.href = 'https://attacker.invalid/escape'; }, 100);
        </script>
        """,
        baseURL: URL(string: "https://fixture.invalid/inside"),
        timeout: .seconds(2),
        quietWindow: .milliseconds(20)
      )
    } catch WebKitRuntimeError.navigationFailed(let reason) {
      #expect(reason.contains("approved origin"))
    }
    try await Task.sleep(for: .milliseconds(180))

    #expect(runtime.webView.url?.host == "fixture.invalid")
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
      timeout: .seconds(2),
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
      timeout: .seconds(2),
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
      timeout: .seconds(2),
      quietWindow: .milliseconds(20)
    )
    _ = try await runtime.navigate(
      to: URL(string: "http://127.0.0.1:\(server.port)/account")!,
      timeout: .seconds(2),
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

  @Test("Snapshot is a real PNG with an explicit compositor caveat")
  func snapshot() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      "<button>Capture me</button>",
      baseURL: URL(string: "https://fixture.invalid/"),
      timeout: .seconds(2),
      quietWindow: .milliseconds(40)
    )

    let capture = try await runtime.capture()
    #expect(capture.pngData.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    #expect(capture.width == Int(1280 * capture.backingScaleFactor))
    #expect(capture.height == Int(800 * capture.backingScaleFactor))
    #expect(capture.backingScaleFactor >= 1)
    #expect(capture.compositorEffectsMayBeMissing)
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
      timeout: .seconds(2),
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

  @Test("Fill preserves input provenance at the actuation boundary")
  func fillActuation() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      "<label for='name'>Name</label><input id='name'>",
      baseURL: URL(string: "https://fixture.invalid/"),
      timeout: .seconds(2),
      quietWindow: .milliseconds(40)
    )
    let before = try await runtime.observe()
    let value = try ProvenancedText(
      text: "Ada",
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
    #expect(after.elements[0].value?.segments.first?.text == "Ada")
    #expect(after.elements[0].value?.classifications == [.userEnteredSiteData])
  }

  @Test("Ambiguous fresh resolution aborts and increments its exact counter")
  func ambiguityFailsClosed() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      "<button>Save</button><button>Save</button>",
      baseURL: URL(string: "https://fixture.invalid/"),
      timeout: .seconds(2),
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

  @Test("An element symbol expires after the next observation")
  func staleObservationRejected() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      "<button>Save</button>",
      baseURL: URL(string: "https://fixture.invalid/"),
      timeout: .seconds(2),
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

  @Test("Human handoff blocks the agent and resumes only from a fresh address space")
  func humanHandoff() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      "<label for='secret'>Secret</label><input id='secret' value='private'><button>Continue</button>",
      baseURL: URL(string: "https://fixture.invalid/login"),
      timeout: .seconds(2),
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
        .handoffRequested, .humanControlled, .resumeRequested, .freshlyReobserved,
        .agentControlled,
      ])
    let encoded = String(decoding: try JSONEncoder().encode(events), as: UTF8.self)
    #expect(!encoded.contains("private"))
  }
}
