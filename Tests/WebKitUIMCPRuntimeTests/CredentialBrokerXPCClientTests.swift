import Foundation
import Testing

@testable import WebKitUIMCPRuntime

@Suite("Credential broker XPC peer isolation")
struct CredentialBrokerXPCClientTests {
  @Test("Human delivery uses the provider budget, not the control-request timeout")
  func timeoutBudgetsAreSeparated() {
    #expect(CredentialBrokerTimeoutPolicy.request == .seconds(15))
    #expect(CredentialBrokerTimeoutPolicy.delivery > .seconds(300))
    #expect(CredentialBrokerTimeoutPolicy.delivery <= .seconds(360))
  }

  @Test("Reply gates finish once, ignore late replies, and bound missing replies")
  func replyGateIsOneShotAndBounded() async {
    let gate = DataReplyGate()
    let result = await gate.wait(timeout: .milliseconds(30)) { _ in }
    #expect(result.0 == nil)
    #expect(result.1 == "timeout")
    gate.finish(data: Data([42]), error: nil)
    let late = await gate.wait(timeout: .seconds(1)) { reply in reply(Data([7]), nil) }
    #expect(late.0 == nil)
    #expect(late.1 == "timeout")

    let immediate = await DataReplyGate().wait(timeout: .seconds(1)) { reply in
      reply(Data([1]), nil)
      reply(Data([2]), "invalid")
    }
    #expect(immediate.0 == Data([1]))
    #expect(immediate.1 == nil)
  }

  @Test("Cancelling an XPC wait closes its one-shot gate promptly")
  func replyGateCancellationIsPrompt() async throws {
    let gate = DataReplyGate()
    let operation = Task { await gate.wait(timeout: .seconds(330)) { _ in } }
    try await Task.sleep(for: .milliseconds(10))
    let start = ContinuousClock.now
    operation.cancel()
    let result = await operation.value
    #expect(result.1 == "cancelled")
    #expect(start.duration(to: .now) < .seconds(1))
  }

  @MainActor
  @Test("A credential callback arriving after the request ends cannot fill")
  func invalidatedSinkRejectsLateFill() async throws {
    let runtime = WebKitRuntime(websiteDataStore: .nonPersistent())
    _ = try await runtime.loadHTML(
      "<input id='u' autocomplete='username'><input id='p' type='password' autocomplete='current-password'>",
      baseURL: URL(string: "https://fixture.invalid/login"),
      timeout: .seconds(2), quietWindow: .milliseconds(40))
    let observation = try await runtime.observe()
    let binding = try runtime.credentialFormBinding(
      observationID: observation.observationID, usernameElementID: "e1", passwordElementID: "e2")
    let lifetime = CredentialSinkLifetime()
    let sink = CredentialSinkExport(runtime: runtime, expectedBinding: binding, lifetime: lifetime)
    lifetime.invalidate()
    let encoded = try JSONEncoder().encode(binding)
    let result: String? = await withCheckedContinuation { continuation in
      sink.fillSyntheticCredential(
        encoded, username: Data("synthetic-user".utf8), password: Data("synthetic-password".utf8)
      ) { continuation.resume(returning: $0) }
    }
    #expect(result == "stale")
    let values = try await runtime.webView.evaluateJavaScript("JSON.stringify([u.value,p.value])")
    #expect(values as? String == "[\"\",\"\"]")
  }

  @Test("Production peers are independently and exactly pinned")
  func productionPeersAreIndependentlyPinned() {
    let requirements = CredentialBrokerXPCPeerRequirements()
    let controlIdentifier =
      "identifier \"com.lorislab.siliconpass.credential-broker-service\""
    let providerIdentifier = "identifier \"com.lorislab.siliconpass\""

    #expect(requirements.controlService.contains(controlIdentifier))
    #expect(!requirements.controlService.contains(providerIdentifier))
    #expect(requirements.secretProvider.contains(providerIdentifier))
    #expect(!requirements.secretProvider.contains(controlIdentifier))

    for requirement in [requirements.controlService, requirements.secretProvider] {
      #expect(requirement.contains("anchor apple generic"))
      #expect(requirement.contains("certificate leaf[subject.OU] = \"TDV6D5L785\""))
      #expect(
        requirement.contains(
          "entitlement[\"com.apple.security.get-task-allow\"] absent"
        ))
    }
  }

  @Test("Custom peers remain separated without weakening the signing policy")
  func customPeersRemainSeparated() {
    let requirements = CredentialBrokerXPCPeerRequirements(
      brokerBundleIdentifier: "com.example.control",
      secretProviderBundleIdentifier: "com.example.provider"
    )

    #expect(requirements.controlService.contains("identifier \"com.example.control\""))
    #expect(!requirements.controlService.contains("identifier \"com.example.provider\""))
    #expect(requirements.secretProvider.contains("identifier \"com.example.provider\""))
    #expect(!requirements.secretProvider.contains("identifier \"com.example.control\""))
  }
}
