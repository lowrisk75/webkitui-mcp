import AppKit
import Foundation
import WebKit
import WebKitUIMCPRuntime
import WebKitUIMCPServer

@main
@MainActor
struct CredentialBrokerPhysicalValidation {
  static func main() async {
    NSApplication.shared.setActivationPolicy(.accessory)

    do {
      let mode = try parseArguments()
      let registry = try WebKitSessionRegistry()
      let session = try registry.open()
      let runtime = try registry.runtime(for: session)
      _ = try await runtime.loadHTML(
        mode.html,
        baseURL: URL(string: "https://fixture.invalid/login"),
        timeout: .seconds(5),
        quietWindow: .milliseconds(80)
      )

      let server = WebKitMCPServer(durableRegistry: registry)
      let observation = try await callTool(
        server,
        id: 1,
        name: "browser_observe",
        arguments: ["session_id": session.rawValue.uuidString]
      )
      guard
        let observationID = observation["observationID"] as? String,
        let elements = observation["elements"] as? [[String: Any]]
      else {
        throw ValidationError.expectedFieldsMissing
      }
      let sensitiveElementIDs = elements.compactMap { element -> String? in
        guard element["sensitive"] as? Bool == true else { return nil }
        return element["elementID"] as? String
      }
      guard !sensitiveElementIDs.isEmpty else { throw ValidationError.expectedFieldsMissing }

      if mode == .rotation {
        guard sensitiveElementIDs.count == 3 else {
          throw ValidationError.expectedFieldsMissing
        }
        let rotation = try await callTool(
          server,
          id: 2,
          name: "browser_rotate_siliconpass_password",
          arguments: [
            "session_id": session.rawValue.uuidString,
            "observation_id": observationID,
            "current_password_element_id": sensitiveElementIDs[0],
            "new_password_element_id": sensitiveElementIDs[1],
            "confirmation_element_id": sensitiveElementIDs[2],
          ]
        )
        guard rotation["status"] as? String == "changed",
          rotation["secret_released_to_mcp"] as? Bool == false,
          rotation["submitted"] as? Bool == false
        else { throw ValidationError.invalidMCPResponse }
        try await verifyRotation(in: runtime)
        print(
          "{\"brokerReceipt\":\"changed\",\"mcpTool\":\"browser_rotate_siliconpass_password\",\"newPasswordGenerated\":true,\"secretReleasedToMCP\":false,\"submissionCount\":0,\"syntheticOnly\":true}"
        )
        exit(EXIT_SUCCESS)
      }

      guard
        let usernameElementID = elements.first(where: {
          ($0["sensitive"] as? Bool) == false
            && (($0["tag"] as? [String: Any])?["segments"] as? [[String: Any]])?.first?["text"]
              as? String == "input"
        })?["elementID"] as? String,
        let passwordElementID = sensitiveElementIDs.first
      else {
        throw ValidationError.expectedFieldsMissing
      }
      let fill = try await callTool(
        server,
        id: 2,
        name: "browser_fill_siliconpass",
        arguments: [
          "session_id": session.rawValue.uuidString,
          "observation_id": observationID,
          "username_element_id": usernameElementID,
          "password_element_id": passwordElementID,
        ]
      )
      guard let status = fill["status"] as? String else {
        throw ValidationError.invalidMCPResponse
      }
      if mode == .expectUserPresenceUnavailable {
        guard
          status == "user_presence_unavailable",
          fill["requires_user_presence"] as? Bool == true,
          fill["retryable"] as? Bool == true,
          fill["automatic_retry"] as? Bool == false,
          fill["secret_released"] as? Bool == false,
          fill["authentication_policy"] as? String == "device_owner_authentication",
          (fill["recovery"] as? String)?.isEmpty == false
        else {
          throw ValidationError.invalidUserPresenceFeedback
        }
        print(
          "{\"mcpFeedback\":\"user_presence_unavailable\",\"requiresUserPresence\":true,\"retryable\":true,\"secretMaterial\":false}"
        )
        exit(EXIT_SUCCESS)
      }
      guard status == "filled" else { throw ValidationError.terminalStatus(status) }

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
        "{\"brokerReceipt\":\"filled\",\"mcpTool\":\"browser_fill_siliconpass\",\"passwordCanaryMatched\":true,\"submissionCount\":0,\"usernameCanaryMatched\":true}"
      )
      exit(EXIT_SUCCESS)
    } catch {
      let reason = (error as? ValidationError)?.reason ?? "unexpected"
      fputs(
        "{\"validation\":\"failed\",\"reason\":\"\(reason)\",\"secretMaterial\":false}\n",
        stderr
      )
      exit(EXIT_FAILURE)
    }
  }

  private static func verifyRotation(in runtime: WebKitRuntime) async throws {
    let verification = try await runtime.webView.callAsyncJavaScript(
      """
      const current = document.getElementById('current-password').value;
      const next = document.getElementById('new-password').value;
      const confirmation = document.getElementById('confirm-password').value;
      return JSON.stringify({
        currentMatchesSyntheticCanary: current === 'SP-MVP0-synthetic-only-7f3a',
        newPasswordIsDistinct: next.length === 24 && next !== current,
        confirmationMatches: confirmation === next,
        submissionCount: window.submitCount,
        inputEventCount: window.inputEventCount
      });
      """,
      arguments: [:],
      in: nil,
      contentWorld: .page
    )
    guard let verificationJSON = verification as? String,
      let verificationData = verificationJSON.data(using: .utf8),
      let result = try? JSONDecoder().decode(
        RotationVerificationResult.self, from: verificationData),
      result.currentMatchesSyntheticCanary,
      result.newPasswordIsDistinct,
      result.confirmationMatches,
      result.submissionCount == 0,
      result.inputEventCount == 0
    else { throw ValidationError.postRotationVerificationFailed }
  }

  private static func parseArguments() throws -> ValidationMode {
    switch Array(CommandLine.arguments.dropFirst()) {
    case []:
      .fill
    case ["--expect-user-presence-unavailable"]:
      .expectUserPresenceUnavailable
    case ["--rotation"]:
      .rotation
    default:
      throw ValidationError.invalidArguments
    }
  }

  private static func callTool(
    _ server: WebKitMCPServer,
    id: Int,
    name: String,
    arguments: [String: Any]
  ) async throws -> [String: Any] {
    let request: [String: Any] = [
      "jsonrpc": "2.0",
      "id": id,
      "method": "tools/call",
      "params": [
        "name": name,
        "arguments": arguments,
        "_meta": [
          "io.modelcontextprotocol/protocolVersion": "2026-07-28",
          "io.modelcontextprotocol/clientInfo": [
            "name": "credential-broker-physical-validation",
            "version": "1",
          ],
          "io.modelcontextprotocol/clientCapabilities": ["elicitation": [:]],
        ],
      ],
    ]
    let requestData = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
    guard let responseData = await server.handle(requestData),
      let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
    else { throw ValidationError.invalidMCPResponse }
    let wire = String(decoding: responseData, as: UTF8.self)
    guard
      !wire.contains("synthetic-user@example.test"),
      !wire.contains("SP-MVP0-synthetic-only-7f3a")
    else {
      throw ValidationError.secretCrossedMCP
    }
    guard response["error"] == nil,
      let result = response["result"] as? [String: Any],
      result["isError"] as? Bool != true,
      let content = result["structuredContent"] as? [String: Any]
    else {
      let result = response["result"] as? [String: Any]
      let diagnostic: [String: Any] = [
        "error": response["error"] ?? NSNull(),
        "isError": result?["isError"] ?? NSNull(),
        "structuredContent": result?["structuredContent"] ?? NSNull(),
      ]
      if let data = try? JSONSerialization.data(withJSONObject: diagnostic, options: [.sortedKeys])
      {
        fputs("mcp-structural-diagnostic: \(String(decoding: data, as: UTF8.self))\n", stderr)
      }
      throw ValidationError.invalidMCPResponse
    }
    return content
  }
}

private enum ValidationMode: Equatable {
  case fill
  case expectUserPresenceUnavailable
  case rotation

  var html: String {
    switch self {
    case .fill, .expectUserPresenceUnavailable:
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
      """
    case .rotation:
      """
      <!doctype html>
      <title>SiliconPass synthetic password rotation</title>
      <form id="rotation">
        <label for="current-password">Current password</label>
        <input id="current-password" type="password" autocomplete="current-password">
        <label for="new-password">New password</label>
        <input id="new-password" type="password" autocomplete="new-password">
        <label for="confirm-password">Confirm new password</label>
        <input id="confirm-password" type="password" autocomplete="new-password">
        <button type="submit">Change password</button>
      </form>
      <script>
        window.submitCount = 0;
        window.inputEventCount = 0;
        document.getElementById('rotation').addEventListener('submit', event => {
          event.preventDefault();
          window.submitCount += 1;
        });
        document.getElementById('rotation').addEventListener('input', () => {
          window.inputEventCount += 1;
        });
        document.getElementById('rotation').addEventListener('change', () => {
          window.inputEventCount += 1;
        });
      </script>
      """
    }
  }
}

private struct VerificationResult: Decodable {
  let usernameMatchesSyntheticCanary: Bool
  let passwordMatchesSyntheticCanary: Bool
  let submissionCount: Int
}

private struct RotationVerificationResult: Decodable {
  let currentMatchesSyntheticCanary: Bool
  let newPasswordIsDistinct: Bool
  let confirmationMatches: Bool
  let submissionCount: Int
  let inputEventCount: Int
}

private enum ValidationError: Error {
  case expectedFieldsMissing
  case invalidArguments
  case invalidMCPResponse
  case invalidUserPresenceFeedback
  case postFillVerificationFailed
  case postRotationVerificationFailed
  case secretCrossedMCP
  case terminalStatus(String)

  var reason: String {
    switch self {
    case .expectedFieldsMissing: "expected_fields_missing"
    case .invalidArguments: "invalid_arguments"
    case .invalidMCPResponse: "invalid_mcp_response"
    case .invalidUserPresenceFeedback: "invalid_user_presence_feedback"
    case .postFillVerificationFailed: "post_fill_verification_failed"
    case .postRotationVerificationFailed: "post_rotation_verification_failed"
    case .secretCrossedMCP: "secret_crossed_mcp"
    case .terminalStatus(let status):
      "terminal_status_\(status.filter { $0.isASCII && ($0.isLetter || $0 == "_") })"
    }
  }
}
