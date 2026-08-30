import Foundation
import Network
import Testing
import WebKit
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

  static func redirect(to url: URL) -> String {
    "HTTP/1.1 302 Found\r\nLocation: \(url.absoluteString)\r\n"
      + "Content-Length: 0\r\nConnection: close\r\n\r\n"
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
      <input id="email" value="kevin@example.test">
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
      timeout: .seconds(3),
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
      timeout: .seconds(3),
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
            customProcessPoolConfigured: false
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
    }
    _ = try await ephemeral.loadHTML(
      "<title>User agent fixture</title>",
      baseURL: URL(string: "https://fixture.invalid/user-agent"),
      timeout: .seconds(3),
      quietWindow: .milliseconds(40)
    )
    let userAgent = try #require(
      try await ephemeral.webView.evaluateJavaScript("navigator.userAgent") as? String)
    #expect(userAgent.contains("AppleWebKit"))
    #expect(!userAgent.contains("WebkitUIMCP"))
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
    let server = try FormFixtureServer()
    let runtime = WebKitRuntime(websiteDataStore: .nonPersistent())
    let approvedURL = URL(string: "http://127.0.0.1:\(server.port)/inside")!
    _ = try await runtime.navigate(
      to: approvedURL,
      timeout: .seconds(2),
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
        timeout: .seconds(2),
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
    let runtime = WebKitRuntime(websiteDataStore: .nonPersistent())

    await #expect(
      throws: WebKitRuntimeError.crossOriginRedirectRequiresHuman(
        fromOrigin: "http://127.0.0.1:\(entryServer.port)",
        toOrigin: "http://localhost:\(authenticationServer.port)"
      )
    ) {
      try await runtime.navigate(
        to: URL(string: "http://127.0.0.1:\(entryServer.port)/developer-portal")!,
        timeout: .seconds(3),
        quietWindow: .milliseconds(20),
        constrainToInitialOrigin: true
      )
    }

    let continued = try await runtime.continueApprovedCrossOriginNavigation(
      timeout: .seconds(3), quietWindow: .milliseconds(20))
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
          timeout: .seconds(3),
          quietWindow: .milliseconds(40)
        )
      }
      do {
        let second = WebKitRuntime(websiteDataStore: store)
        let check = try await second.navigate(
          to: URL(string: "http://127.0.0.1:\(server.port)/check")!,
          timeout: .seconds(3),
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

  @Test("Snapshot is a real PNG with an explicit compositor caveat")
  func snapshot() async throws {
    let runtime = WebKitRuntime()
    #expect(runtime.webView.window != nil)
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

  @Test("Human handoff presents the live rendered WebView")
  func humanHandoffPresentsLiveRenderedWebView() async throws {
    let runtime = WebKitRuntime(websiteDataStore: .nonPersistent())
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
      timeout: .seconds(2),
      quietWindow: .milliseconds(40)
    )

    try runtime.requestHumanHandoff()
    try runtime.beginHumanControl(presentWindow: true)

    let window = try #require(runtime.webView.window)
    #expect(window === stableWindow)
    #expect(window.title == "WebkitUIMCP — Human control")
    #expect(window.isVisible)
    #expect(window.alphaValue == 1)
    #expect(window.contentView === runtime.webView)
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

    try runtime.requestAgentResume()
    _ = try await runtime.resumeAfterHumanControl()
    #expect(!window.isVisible)
    #expect(runtime.webView.window === window)
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
    let runtime = WebKitRuntime(websiteDataStore: .nonPersistent())
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
    #expect(throws: WebKitSessionRegistryError.hostControllerBusy) {
      try second.open()
    }
    try first.close(handle)
    let secondHandle = try second.open()
    try second.close(secondHandle)
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
      timeout: .seconds(2), quietWindow: .milliseconds(40))
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
      timeout: .seconds(2), quietWindow: .milliseconds(40))

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
      timeout: .seconds(2), quietWindow: .milliseconds(40))
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
      timeout: .seconds(2), quietWindow: .milliseconds(40))
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
      timeout: .seconds(2), quietWindow: .milliseconds(40))
    let before = try await runtime.observe()
    let result = try await runtime.perform(
      observationID: before.observationID, elementID: "e1",
      operation: .pressKey("Tab"), dispatchMode: .nativeAppKit,
      stabilityInterval: .milliseconds(10))
    #expect(result.trustedUserGesture)
    let after = try await runtime.observe()
    #expect(after.elements[0].stateAttributes["data-state"]?.segments.first?.text == "committed")
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
      timeout: .seconds(2), quietWindow: .milliseconds(40))
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
      timeout: .seconds(2), quietWindow: .milliseconds(40))
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
