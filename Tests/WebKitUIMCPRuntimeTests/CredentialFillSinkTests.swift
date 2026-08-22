import Foundation
import Testing

@testable import WebKitUIMCPRuntime

@Suite("Private credential fill sink", .serialized)
@MainActor
struct CredentialFillSinkTests {
  private let usernameCanary = "synthetic-user@example.test"
  private let passwordCanary = "SP-MVP0-synthetic-only-7f3a"

  private func fixture() async throws -> (WebKitRuntime, WebKitPageObservation) {
    let runtime = WebKitRuntime(websiteDataStore: .nonPersistent())
    _ = try await runtime.loadHTML(
      """
      <!doctype html>
      <form id="login">
        <label for="username">Username</label>
        <input id="username" autocomplete="username">
        <label for="password">Password</label>
        <input id="password" type="password" autocomplete="current-password">
        <button type="submit">Sign in</button>
      </form>
      <script>
        globalThis.submitCount = 0;
        document.querySelector('form').addEventListener('submit', event => {
          globalThis.submitCount += 1;
          event.preventDefault();
        });
        for (const input of document.querySelectorAll('input')) {
          input.addEventListener('input', () => document.querySelector('form').requestSubmit());
          input.addEventListener('change', () => document.querySelector('form').requestSubmit());
        }
      </script>
      """,
      baseURL: URL(string: "https://fixture.invalid/login"),
      timeout: .seconds(2),
      quietWindow: .milliseconds(40)
    )
    return (runtime, try await runtime.observe())
  }

  @Test("Synthetic values reach exact fields without submission or receipt leakage")
  func fillsExactFields() async throws {
    let (runtime, observation) = try await fixture()
    let binding = try runtime.credentialFormBinding(
      observationID: observation.observationID,
      usernameElementID: "e1",
      passwordElementID: "e2"
    )
    let username = CredentialSecretBuffer(copying: Array(usernameCanary.utf8))
    let password = CredentialSecretBuffer(copying: Array(passwordCanary.utf8))
    let receipt = try await runtime.performCredentialFill(
      binding: binding,
      username: username,
      password: password
    )

    #expect(receipt.status == .filled)
    #expect(username.isWiped)
    #expect(password.isWiped)
    let values = try #require(
      await runtime.webView.evaluateJavaScript(
        "JSON.stringify([username.value, password.value, globalThis.submitCount])") as? String
    )
    #expect(values == "[\"\(usernameCanary)\",\"\(passwordCanary)\",0]")

    let receiptJSON = String(decoding: try JSONEncoder().encode(receipt), as: UTF8.self)
    #expect(!receiptJSON.contains(usernameCanary))
    #expect(!receiptJSON.contains(passwordCanary))
  }

  @Test("An identical DOM replacement is stale and fills neither field")
  func replacementFailsClosed() async throws {
    let (runtime, observation) = try await fixture()
    let binding = try runtime.credentialFormBinding(
      observationID: observation.observationID,
      usernameElementID: "e1",
      passwordElementID: "e2"
    )
    _ = try await runtime.webView.evaluateJavaScript(
      """
      const old = document.querySelector('#password');
      const replacement = old.cloneNode(true);
      old.replaceWith(replacement);
      """
    )

    let username = CredentialSecretBuffer(copying: Array(usernameCanary.utf8))
    let password = CredentialSecretBuffer(copying: Array(passwordCanary.utf8))
    await #expect(throws: WebKitRuntimeError.invalidCredentialBinding) {
      try await runtime.performCredentialFill(
        binding: binding,
        username: username,
        password: password
      )
    }
    #expect(username.isWiped)
    #expect(password.isWiped)
    let values = try #require(
      await runtime.webView.evaluateJavaScript(
        "JSON.stringify([username.value, password.value])") as? String
    )
    #expect(values == "[\"\",\"\"]")
  }

  @Test("A navigation invalidates the bound document")
  func navigationFailsClosed() async throws {
    let (runtime, observation) = try await fixture()
    let binding = try runtime.credentialFormBinding(
      observationID: observation.observationID,
      usernameElementID: "e1",
      passwordElementID: "e2"
    )
    _ = try await runtime.loadHTML(
      "<input id='username'><input id='password' type='password'>",
      baseURL: URL(string: "https://fixture.invalid/next"),
      timeout: .seconds(2),
      quietWindow: .milliseconds(40)
    )

    await #expect(throws: WebKitRuntimeError.invalidCredentialBinding) {
      try await runtime.performCredentialFill(
        binding: binding,
        username: CredentialSecretBuffer(copying: Array(usernameCanary.utf8)),
        password: CredentialSecretBuffer(copying: Array(passwordCanary.utf8))
      )
    }
  }

  @Test("The sink accepts only strict HTTPS ASCII origins")
  func strictOrigin() throws {
    #expect(throws: CredentialSinkOriginError.httpsRequired) {
      try CredentialSinkOrigin(scheme: "http", asciiHost: "fixture.invalid", effectivePort: 443)
    }
    #expect(throws: CredentialSinkOriginError.nonCanonicalHost) {
      try CredentialSinkOrigin(scheme: "https", asciiHost: "Fixture.Invalid", effectivePort: 443)
    }
    #expect(throws: CredentialSinkOriginError.nonCanonicalHost) {
      try CredentialSinkOrigin(
        scheme: "https", asciiHost: "xn--bcher-kva.invalid", effectivePort: 443)
    }
    #expect(throws: CredentialSinkOriginError.nonCanonicalHost) {
      try CredentialSinkOrigin(scheme: "https", asciiHost: "localhost", effectivePort: 443)
    }
    #expect(throws: CredentialSinkOriginError.nonCanonicalHost) {
      try CredentialSinkOrigin(scheme: "https", asciiHost: "127.0.0.1", effectivePort: 443)
    }
  }
}
