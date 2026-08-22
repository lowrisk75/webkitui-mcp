import AppKit
import Foundation
import WebKit
import WebKitUIMCPRuntime

@main
@MainActor
struct CredentialBrokerPhysicalValidation {
  static func main() async {
    NSApplication.shared.setActivationPolicy(.accessory)

    do {
      let runtime = WebKitRuntime(websiteDataStore: .nonPersistent())
      _ = try await runtime.loadHTML(
        """
        <!doctype html>
        <title>SiliconPass MVP0 physical validation</title>
        <form id="login">
          <label for="username">Username</label>
          <input id="username" name="username" autocomplete="username">
          <label for="password">Password</label>
          <input id="password" name="password" type="password" autocomplete="current-password">
          <button type="submit">Sign in</button>
        </form>
        <script>
          window.submitCount = 0;
          document.getElementById('login').addEventListener('submit', event => {
            event.preventDefault();
            window.submitCount += 1;
          });
        </script>
        """,
        baseURL: URL(string: "https://fixture.invalid/login"),
        timeout: .seconds(5),
        quietWindow: .milliseconds(80)
      )

      let observation = try await runtime.observe()
      guard
        let username = observation.elements.first(where: {
          !$0.sensitive && $0.tag.segments.first?.text == "input"
        }),
        let password = observation.elements.first(where: { $0.sensitive })
      else {
        throw ValidationError.expectedFieldsMissing
      }

      let binding = try runtime.credentialFormBinding(
        observationID: observation.observationID,
        usernameElementID: username.elementID,
        passwordElementID: password.elementID
      )
      let receipt = try await SyntheticCredentialBrokerXPCClient().fill(
        binding: binding,
        runtime: runtime
      )
      guard receipt.status == .filled else { throw ValidationError.notFilled }

      let verification = try await runtime.webView.callAsyncJavaScript(
        """
        return JSON.stringify({
          usernameMatchesSyntheticCanary:
            document.getElementById('username').value === 'synthetic-user@example.test',
          passwordMatchesSyntheticCanary:
            document.getElementById('password').value === 'SP-MVP0-synthetic-only-7f3a',
          submissionCount: window.submitCount
        });
        """,
        arguments: [:],
        in: nil,
        contentWorld: .page
      )
      guard let verificationJSON = verification as? String,
        let verificationData = verificationJSON.data(using: .utf8),
        let result = try? JSONDecoder().decode(VerificationResult.self, from: verificationData),
        result.usernameMatchesSyntheticCanary,
        result.passwordMatchesSyntheticCanary,
        result.submissionCount == 0
      else {
        throw ValidationError.postFillVerificationFailed
      }

      print(
        "{\"brokerReceipt\":\"filled\",\"passwordCanaryMatched\":true,\"submissionCount\":0,\"usernameCanaryMatched\":true}"
      )
      exit(EXIT_SUCCESS)
    } catch {
      fputs("{\"validation\":\"failed\",\"secretMaterial\":false}\n", stderr)
      exit(EXIT_FAILURE)
    }
  }
}

private struct VerificationResult: Decodable {
  let usernameMatchesSyntheticCanary: Bool
  let passwordMatchesSyntheticCanary: Bool
  let submissionCount: Int
}

private enum ValidationError: Error {
  case expectedFieldsMissing
  case notFilled
  case postFillVerificationFailed
}
