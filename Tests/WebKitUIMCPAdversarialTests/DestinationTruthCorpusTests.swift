import Foundation
import Testing
import WebKitUIMCPCore

@Suite("Submission destination truth corpus", .serialized)
@MainActor
struct DestinationTruthCorpusTests {
  @Test("A submit control's formaction overrides its form")
  func formActionOverridesForm() async throws {
    let message = try await submitConfirmation(
      """
      <form action='https://form-target.fixture.invalid/collect'>
        <button type='submit' formaction='https://control-target.fixture.invalid/collect'>Send</button>
      </form>
      """, fixture: "formaction-overrides")
    #expect(try destinationValue(in: message).contains("control-target.fixture.invalid"))
    #expect(!message.contains("form-target.fixture.invalid"))
  }

  @Test("The form action is used when the control has no formaction")
  func formActionIsFallback() async throws {
    let message = try await submitConfirmation(
      """
      <form action='https://form-target.fixture.invalid/collect'>
        <button type='submit'>Send</button>
      </form>
      """, fixture: "form-action-fallback")
    #expect(try destinationValue(in: message).contains("form-target.fixture.invalid"))
  }

  @Test("A base URL rewrites a relative form destination")
  func baseRewritesRelativeAction() async throws {
    let message = try await submitConfirmation(
      """
      <base href='https://base-target.fixture.invalid/root/'>
      <form action='collect'><button type='submit'>Send</button></form>
      """, fixture: "base-rewrite")
    #expect(try destinationValue(in: message).contains("base-target.fixture.invalid"))
  }

  @Test("URL userinfo cannot impersonate the destination host")
  func userInfoCannotDisguiseHost() async throws {
    let message = try await submitConfirmation(
      """
      <form action='https://trusted-shop.fixture.invalid@attacker.fixture.invalid/collect'>
        <button type='submit'>Send</button>
      </form>
      """, fixture: "userinfo")
    let destination = try destinationValue(in: message)
    #expect(destination.contains("attacker.fixture.invalid"))
    #expect(!destination.contains("trusted-shop.fixture.invalid"))
  }

  @Test("A Cyrillic homograph is shown in ASCII punycode")
  func cyrillicHomographIsASCII() async throws {
    let message = try await submitConfirmation(
      """
      <form action='https://аррӏе.example/collect'>
        <button type='submit'>Send</button>
      </form>
      """, fixture: "cyrillic-homograph")
    let origin = try firstQuotedOrigin(in: message)
    #expect(origin.contains("xn--"))
    #expect(origin.unicodeScalars.allSatisfy { $0.isASCII })
    #expect(!origin.contains("аррӏе"))
  }

  @Test("A full-width homograph is compatibility-normalized")
  func fullWidthHomographIsNormalized() async throws {
    let message = try await submitConfirmation(
      """
      <form action='https://ａｔｔａｃｋｅｒ.example/collect'>
        <button type='submit'>Send</button>
      </form>
      """, fixture: "fullwidth-homograph")
    #expect(try firstQuotedOrigin(in: message) == "https://attacker.example")
  }

  @Test("A trailing dot remains visible in the destination host")
  func trailingDotRemainsVisible() async throws {
    let message = try await submitConfirmation(
      """
      <form action='https://trailing.fixture.invalid./collect'>
        <button type='submit'>Send</button>
      </form>
      """, fixture: "trailing-dot")
    #expect(try firstQuotedOrigin(in: message) == "https://trailing.fixture.invalid.")
  }

  @Test("An explicit punycode host is shown exactly as ASCII")
  func explicitPunycodeIsShownExactly() async throws {
    let message = try await submitConfirmation(
      """
      <form action='https://xn--pple-43d.example/collect'>
        <button type='submit'>Send</button>
      </form>
      """, fixture: "punycode")
    #expect(try firstQuotedOrigin(in: message) == "https://xn--pple-43d.example")
  }

  @Test("Bidi controls in a host or path never reach the operator")
  func bidiDestinationIsSanitized() async throws {
    let bidi = "\u{202E}"
    let hostileHost = try await submitConfirmation(
      """
      <form action='https://attacker\(bidi).example/collect'>
        <button type='submit'>Send</button>
      </form>
      """, fixture: "bidi-host")
    #expect(!hostileHost.unicodeScalars.contains(where: { $0.value == 0x202E }))
    #expect(try destinationValue(in: hostileHost).contains("UNKNOWN"))

    let hostilePath = try await submitConfirmation(
      """
      <form action='https://attacker.example/collect/\(bidi)elpmaxe.detcurtsid'>
        <button type='submit'>Send</button>
      </form>
      """, fixture: "bidi-path")
    #expect(!hostilePath.unicodeScalars.contains(where: { $0.value == 0x202E }))
    #expect(try firstQuotedOrigin(in: hostilePath) == "https://attacker.example")
  }

  @Test(
    "Non-network schemes are reported as unreadable",
    arguments: [
      "javascript:alert(1)", "data:text/plain,send", "blob:https://example.test/id", "about:blank",
    ]
  )
  func nonNetworkSchemesFailLoud(destination: String) async throws {
    let message = try await submitConfirmation(
      """
      <form action='\(destination)'><button type='submit'>Send</button></form>
      """, fixture: "non-network-scheme")
    #expect(try destinationValue(in: message).contains("UNKNOWN"))
  }

  @Test("A port difference is called a different site")
  func portDifferenceIsVisible() async throws {
    let message = try await submitConfirmation(
      """
      <form action='https://port-difference.fixture.invalid:8443/collect'>
        <button type='submit'>Send</button>
      </form>
      """, fixture: "port-difference")
    #expect(try firstQuotedOrigin(in: message) == "https://port-difference.fixture.invalid:8443")
    #expect(message.contains("A DIFFERENT SITE"))
  }

  @Test("HTTP and HTTPS on one host are different origins")
  func schemeDifferenceIsVisible() async throws {
    let message = try await submitConfirmation(
      """
      <form action='http://scheme-difference.fixture.invalid/collect'>
        <button type='submit'>Send</button>
      </form>
      """, fixture: "scheme-difference")
    #expect(try firstQuotedOrigin(in: message) == "http://scheme-difference.fixture.invalid")
    #expect(message.contains("A DIFFERENT SITE"))
  }

  @Test("A four-kilobyte destination cannot enlarge the confirmation")
  func longDestinationIsBounded() async throws {
    let path = String(repeating: "a", count: 4_096)
    let message = try await submitConfirmation(
      """
      <form action='https://long-destination.fixture.invalid/\(path)'>
        <button type='submit'>Send</button>
      </form>
      """, fixture: "long-destination")
    #expect(try firstQuotedOrigin(in: message) == "https://long-destination.fixture.invalid")
    #expect(message.utf8.count < 2_048)
  }

  @Test("An anchor uses its href, not its enclosing form action")
  func anchorInsideForeignFormUsesHref() async throws {
    let harness = try AdversarialFixtureHarness()
    let requests = try await harness.loadAndRecordActionConfirmations(
      """
      <form action='https://form-attacker.fixture.invalid/collect'>
        <a href='/safe-details'>Read details</a>
      </form>
      """,
      baseURL: try #require(URL(string: "https://anchor.fixture.invalid/start")),
      operation: "click",
      confirmationCount: 1)
    let message = try #require(requests.last?.message)
    #expect(try firstQuotedOrigin(in: message) == "https://anchor.fixture.invalid")
    #expect(!message.contains("form-attacker.fixture.invalid"))
  }

  @Test("A control that sends nothing has no destination section")
  func plainControlHasNoDestination() async throws {
    let harness = try AdversarialFixtureHarness()
    let requests = try await harness.loadAndRecordActionConfirmations(
      "<button type='button'>Expand details</button>",
      baseURL: try #require(URL(string: "https://no-destination.fixture.invalid/start")),
      operation: "click",
      confirmationCount: 1)
    let message = try #require(requests.last?.message)
    #expect(!message.contains("Data would be sent to:"))
  }

  @Test("A destination mutation is re-resolved before confirmation")
  func mutatedFormActionIsFresh() async throws {
    let old = "old-target.fixture.invalid"
    let new = "new-target.fixture.invalid"
    let harness = try AdversarialFixtureHarness()
    let observation = try await harness.loadAndObserve(
      """
      <form action='https://\(old)/collect'>
        <button id='send' type='submit'>Send</button>
      </form>
      """,
      baseURL: try #require(URL(string: "https://mutated-formaction.fixture.invalid/start")))
    try await harness.evaluateFixtureJavaScript(
      "document.getElementById('send').setAttribute('formaction', 'https://\(new)/collect')")
    let requests = try await harness.recordActionConfirmations(
      observation: observation, confirmationCount: 1)
    let message = try #require(requests.last?.message)
    #expect(message.contains(new))
    #expect(!message.contains(old))
  }

  private func submitConfirmation(_ html: String, fixture: String) async throws -> String {
    let harness = try AdversarialFixtureHarness()
    let requests = try await harness.loadAndRecordActionConfirmations(
      html,
      baseURL: try #require(URL(string: "https://\(fixture).fixture.invalid/start")),
      confirmationCount: 1)
    return try #require(requests.last?.message)
  }

  private func destinationValue(in message: String) throws -> String {
    let lines = message.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let heading = try #require(lines.firstIndex(of: "Data would be sent to:"))
    let value = lines.index(after: heading)
    return try #require(value < lines.endIndex ? lines[value] : nil)
  }

  private func firstQuotedOrigin(in message: String) throws -> String {
    let line = try destinationValue(in: message)
    let pieces = line.split(separator: "\"", omittingEmptySubsequences: false)
    return try #require(pieces.count >= 3 ? String(pieces[1]) : nil)
  }
}
