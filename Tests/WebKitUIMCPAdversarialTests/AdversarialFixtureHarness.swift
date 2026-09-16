import Foundation
import WebKitUIMCPCore
import WebKitUIMCPRuntime

@testable import WebKitUIMCPServer

enum AdversarialFixtureHarnessError: Error, Equatable {
  case fixtureLoadFailed(String)
  case fixtureDidNotLoad(PageReadiness)
  case missingObservationField(String)
  case missingResponse
  case toolCallFailed(String)
  case wrongWireShape(String)
}

/// The exact native confirmation document an operator would have received. Later corpus
/// families assert on these messages rather than on an internal summary assembled before
/// the confirmation boundary.
@MainActor
final class RecordingConfirmationPresenter: BrowserConfirmationPresenting {
  struct Request: Equatable {
    let title: String
    let message: String
    let approveLabel: String
  }

  private(set) var requests: [Request] = []
  private var outcomes: [NativeConfirmationOutcome]
  var state: NativeConfirmationState = .idle

  init(outcomes: [NativeConfirmationOutcome] = [.declined]) {
    self.outcomes = outcomes
  }

  func confirm(title: String, message: String, approveLabel: String) async
    -> NativeConfirmationOutcome
  {
    requests.append(Request(title: title, message: message, approveLabel: approveLabel))
    return outcomes.isEmpty ? .declined : outcomes.removeFirst()
  }

  func cancel() { state = .idle }
}

/// An in-process MCP client around one isolated fixture session. Tests supply only HTML
/// and a reserved base URL; the harness owns readiness, the modern wire envelope and
/// extraction of the same structured observation an actual client receives.
@MainActor
final class AdversarialFixtureHarness {
  let registry: WebKitSessionRegistry
  let session: WebKitSessionHandle
  let runtime: WebKitRuntime
  let confirmationPresenter: RecordingConfirmationPresenter
  let server: WebKitMCPServer

  private var nextRequestID: Int64 = 1

  init(
    confirmationOutcomes: [NativeConfirmationOutcome] = [.declined],
    activityLog: WebKitActivityLog? = nil
  ) throws {
    registry = try WebKitSessionRegistry()
    session = try registry.open()
    runtime = try registry.runtime(for: session)
    confirmationPresenter = RecordingConfirmationPresenter(outcomes: confirmationOutcomes)
    server = WebKitMCPServer(
      registry: registry,
      confirmationPresenter: confirmationPresenter,
      activityLog: activityLog
    )
  }

  func loadAndObserve(
    _ html: String,
    baseURL: URL,
    loadTimeout: Duration = .seconds(5)
  ) async throws -> [String: JSONValue] {
    let navigation: WebKitNavigationResult
    do {
      navigation = try await runtime.loadHTML(
        html,
        baseURL: baseURL,
        timeout: loadTimeout,
        quietWindow: .milliseconds(40)
      )
    } catch {
      throw AdversarialFixtureHarnessError.fixtureLoadFailed(String(describing: error))
    }
    guard navigation.readiness == .ready else {
      throw AdversarialFixtureHarnessError.fixtureDidNotLoad(navigation.readiness)
    }
    return try await callTool(
      "browser_observe",
      arguments: ["session_id": .string(session.rawValue.uuidString)]
    )
  }

  func callTool(
    _ name: String,
    arguments: [String: JSONValue],
    allowToolError: Bool = false
  ) async throws -> [String: JSONValue] {
    let id = nextRequestID
    nextRequestID += 1
    let request: JSONValue = .object([
      "jsonrpc": .string("2.0"),
      "id": .int(id),
      "method": .string("tools/call"),
      "params": .object([
        "name": .string(name),
        "arguments": .object(arguments),
        "_meta": .object([
          "io.modelcontextprotocol/protocolVersion": .string("2026-07-28"),
          "io.modelcontextprotocol/clientInfo": .object([
            "name": .string("adversarial-corpus"),
            "version": .string("1"),
          ]),
          "io.modelcontextprotocol/clientCapabilities": .object([
            "elicitation": .object([:])
          ]),
        ]),
      ]),
    ])
    guard let responseData = await server.handle(try JSONEncoder().encode(request)) else {
      throw AdversarialFixtureHarnessError.missingResponse
    }
    let response = try object(
      JSONDecoder().decode(JSONValue.self, from: responseData), named: "response")
    if let error = response["error"] {
      throw AdversarialFixtureHarnessError.toolCallFailed(String(describing: error))
    }
    let result = try object(response["result"], named: "result")
    if !allowToolError, result["isError"] == .bool(true) {
      throw AdversarialFixtureHarnessError.toolCallFailed(String(describing: result))
    }
    return try object(result["structuredContent"], named: "structuredContent")
  }

  /// Drives the public browser_act boundary but always records a refusal, so the page is
  /// never mutated. Repeating the request exercises the server-owned burst annotation on
  /// the exact same confirmation document.
  func loadAndRecordActionConfirmations(
    _ html: String,
    baseURL: URL,
    operation: String = "submit",
    value: String? = nil,
    postcondition: JSONValue? = nil,
    confirmationCount: Int = 1
  ) async throws -> [RecordingConfirmationPresenter.Request] {
    let observation = try await loadAndObserve(html, baseURL: baseURL)
    return try await recordActionConfirmations(
      observation: observation,
      operation: operation,
      value: value,
      postcondition: postcondition,
      confirmationCount: confirmationCount
    )
  }

  func recordActionConfirmations(
    observation: [String: JSONValue],
    targetIndex: Int = 0,
    operation: String = "submit",
    value: String? = nil,
    postcondition: JSONValue? = nil,
    confirmationCount: Int = 1
  ) async throws -> [RecordingConfirmationPresenter.Request] {
    guard let observationID = observation["observationID"]?.stringValue else {
      throw AdversarialFixtureHarnessError.missingObservationField("observationID")
    }
    guard case .array(let elements) = observation["elements"],
      elements.indices.contains(targetIndex),
      let elementID = elements[targetIndex].objectValue?["elementID"]?.stringValue
    else {
      throw AdversarialFixtureHarnessError.missingObservationField("elements[0].elementID")
    }
    let start = confirmationPresenter.requests.count
    for index in 0..<confirmationCount {
      var arguments: [String: JSONValue] = [
        "session_id": .string(session.rawValue.uuidString),
        "observation_id": .string(observationID),
        "element_id": .string(elementID),
        "operation": .string(operation),
        "approval_mode": .string("native"),
        "idempotency_key": .string("adversarial-confirmation-\(nextRequestID)-\(index)"),
      ]
      if let value { arguments["value"] = .string(value) }
      if let postcondition {
        arguments["postcondition"] = postcondition
      } else if ["click", "submit", "press_key", "blur", "commit_input"].contains(operation) {
        arguments["postcondition"] = .object([
          "type": .string("semantic_text_appears"),
          "value": .string("THIS ACTION WAS NOT DISPATCHED"),
        ])
      }
      _ = try await callTool("browser_act", arguments: arguments, allowToolError: true)
    }
    return Array(confirmationPresenter.requests.dropFirst(start))
  }

  /// A test-only fixture mutation, never an MCP capability. It exists solely to put a
  /// hostile DOM change in the gap between observation and the confirmation request.
  func evaluateFixtureJavaScript(_ source: String) async throws {
    _ = try await runtime.webView.evaluateJavaScript(source)
  }

  private func object(_ value: JSONValue?, named name: String) throws -> [String: JSONValue] {
    guard case .object(let object) = value else {
      throw AdversarialFixtureHarnessError.wrongWireShape(name)
    }
    return object
  }
}
