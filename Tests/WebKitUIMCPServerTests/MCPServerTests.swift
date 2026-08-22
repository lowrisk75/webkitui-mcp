import Foundation
import Testing
import WebKitUIMCPRuntime

@testable import WebKitUIMCPServer

@MainActor
private final class InProcessSyntheticBrokerStub: CredentialBrokerFilling {
  static let username = "synthetic-user@example.test"
  static let password = "SP-MVP0-synthetic-only-7f3a"

  func fill(
    binding: CredentialSinkFormBinding,
    runtime: WebKitRuntime
  ) async throws -> CredentialBrokerWireReceipt {
    _ = try await runtime.performCredentialFill(
      binding: binding,
      username: CredentialSecretBuffer(copying: Array(Self.username.utf8)),
      password: CredentialSecretBuffer(copying: Array(Self.password.utf8))
    )
    return CredentialBrokerWireReceipt(status: .filled)
  }
}

@MainActor
private final class ConfirmationPresenterStub: BrowserConfirmationPresenting {
  private(set) var requests: [(title: String, message: String, approveLabel: String)] = []
  private var responses: [Bool]

  init(responses: [Bool]) {
    self.responses = responses
  }

  func confirm(title: String, message: String, approveLabel: String) -> Bool {
    requests.append((title, message, approveLabel))
    return responses.isEmpty ? false : responses.removeFirst()
  }
}

@Suite("MCP 2026-07-28 wire server", .serialized)
@MainActor
struct MCPServerTests {
  @Test("Confirmation helpers fail closed and closed pipes cannot terminate the server")
  func nativeConfirmationHelperFailClosed() {
    let accepts = NativeBrowserConfirmationPresenter(
      helperURL: URL(fileURLWithPath: "/usr/bin/sed"),
      helperArguments: ["-n", ""])
    let rejects = NativeBrowserConfirmationPresenter(
      helperURL: URL(fileURLWithPath: "/usr/bin/false"))
    let closesInput = NativeBrowserConfirmationPresenter(
      helperURL: URL(fileURLWithPath: "/bin/sh"),
      helperArguments: ["-c", "exec 0<&-; sleep 0.1; exit 0"])
    let missing = NativeBrowserConfirmationPresenter(
      helperURL: URL(fileURLWithPath: "/path/does/not/exist"))

    #expect(accepts.confirm(title: "Title", message: "Message", approveLabel: "Approve"))
    #expect(!rejects.confirm(title: "Title", message: "Message", approveLabel: "Approve"))
    _ = closesInput.confirm(title: "Title", message: "Message", approveLabel: "Approve")
    #expect(!missing.confirm(title: "Title", message: "Message", approveLabel: "Approve"))
  }

  @Test("Discovery advertises stateless modern protocol metadata")
  func discovery() async throws {
    let server = try WebKitMCPServer()
    let response = try await call(
      server,
      id: 1,
      method: "server/discover",
      params: .object([:]),
      modern: true
    )

    let result = try object(response["result"])
    #expect(result["resultType"] == .string("complete"))
    #expect(
      result["supportedVersions"]
        == .array([.string("2026-07-28")])
    )
    #expect(try object(result["_meta"])["io.modelcontextprotocol/serverInfo"] != nil)
  }

  @Test("Modern requests require metadata and reject unsupported revisions")
  func modernMetadataValidation() async throws {
    let server = try WebKitMCPServer()
    let missing = try await call(
      server,
      id: 1,
      method: "server/discover",
      params: .object([:]),
      modern: false
    )
    #expect(try object(missing["error"])["code"] == .int(-32602))

    let unsupported = try await rawCall(
      server,
      id: 2,
      method: "tools/list",
      params: .object([
        "_meta": .object([
          "io.modelcontextprotocol/protocolVersion": .string("2026-08-01"),
          "io.modelcontextprotocol/clientCapabilities": .object([:]),
        ])
      ])
    )
    let error = try object(unsupported["error"])
    #expect(error["code"] == .int(-32022))
    let data = try object(error["data"])
    #expect(data["supported"] == .array([.string("2026-07-28")]))
    #expect(data["requested"] == .string("2026-08-01"))
  }

  @Test("Tool list is deterministic, bounded and cacheable")
  func toolList() async throws {
    let server = try WebKitMCPServer()
    let first = try await call(
      server,
      id: 1,
      method: "tools/list",
      params: .object([:]),
      modern: true
    )
    let second = try await call(
      server,
      id: 2,
      method: "tools/list",
      params: .object([:]),
      modern: true
    )
    let firstResult = try object(first["result"])
    let secondResult = try object(second["result"])
    #expect(firstResult["tools"] == secondResult["tools"])
    #expect(firstResult["ttlMs"] == .int(300_000))

    let names = try array(firstResult["tools"]).map {
      try string(object($0)["name"])
    }
    #expect(
      names == [
        "browser_authorization",
        "browser_act",
        "browser_capture",
        "browser_fill_siliconpass",
        "browser_navigate",
        "browser_observe",
        "browser_session",
        "browser_transaction",
      ]
    )
  }

  @Test("Session state travels through an explicit tool argument")
  func explicitSessionHandle() async throws {
    let server = try WebKitMCPServer()
    let opened = try await toolCall(
      server, id: 1, name: "browser_session", arguments: ["operation": .string("open")])
    let openResult = try object(try object(opened["result"])["structuredContent"])
    let sessionID = try string(openResult["session_id"])
    #expect(UUID(uuidString: sessionID) != nil)

    let status = try await toolCall(
      server,
      id: 2,
      name: "browser_session",
      arguments: ["operation": .string("status"), "session_id": .string(sessionID)]
    )
    let statusResult = try object(try object(status["result"])["structuredContent"])
    #expect(statusResult["sessionID"] == .string(sessionID))

    _ = try await toolCall(
      server,
      id: 3,
      name: "browser_session",
      arguments: ["operation": .string("close"), "session_id": .string(sessionID)]
    )
    let afterClose = try await toolCall(
      server,
      id: 4,
      name: "browser_session",
      arguments: ["operation": .string("status"), "session_id": .string(sessionID)]
    )
    #expect(try object(afterClose["result"])["isError"] == .bool(true))
  }

  @Test("Legacy initialize remains available without contaminating modern results")
  func legacyCompatibility() async throws {
    let server = try WebKitMCPServer()
    let response = try await call(
      server,
      id: 1,
      method: "initialize",
      params: .object(["protocolVersion": .string("2025-11-25")]),
      modern: false
    )
    let result = try object(response["result"])
    #expect(result["protocolVersion"] == .string("2025-11-25"))
    #expect(try object(result["serverInfo"])["version"] == .string(WebKitMCPServer.version))
    #expect(result["resultType"] == nil)
    #expect(result["_meta"] == nil)

    let fallback = try await call(
      server,
      id: 2,
      method: "initialize",
      params: .object(["protocolVersion": .string("2026-07-28")]),
      modern: false
    )
    #expect(try object(fallback["result"])["protocolVersion"] == .string("2025-11-25"))

    let older = try await call(
      server,
      id: 3,
      method: "initialize",
      params: .object(["protocolVersion": .string("2025-06-18")]),
      modern: false
    )
    #expect(try object(older["result"])["protocolVersion"] == .string("2025-06-18"))

    let progressMetadata = try await rawCall(
      server,
      id: 4,
      method: "tools/list",
      params: .object([
        "_meta": .object(["progressToken": .string("legacy-progress")])
      ])
    )
    let progressResult = try object(progressMetadata["result"])
    #expect(progressResult["tools"] != nil)
    #expect(progressResult["resultType"] == nil)
    #expect(progressResult["_meta"] == nil)
  }

  @Test("Modern ping is not part of the stateless protocol")
  func modernPingRejected() async throws {
    let server = try WebKitMCPServer()
    let response = try await call(
      server, id: 1, method: "ping", params: .object([:]), modern: true)
    #expect(try object(response["error"])["code"] == .int(-32601))
  }

  @Test("Multi-round tools require the elicitation capability")
  func modernElicitationCapabilityRequired() async throws {
    let server = try WebKitMCPServer()
    let opened = try await toolCall(
      server, id: 1, name: "browser_session", arguments: ["operation": .string("open")])
    let sessionID = try string(
      try object(try object(opened["result"])["structuredContent"])["session_id"])
    let response = try await rawCall(
      server,
      id: 2,
      method: "tools/call",
      params: .object([
        "name": .string("browser_navigate"),
        "arguments": .object([
          "session_id": .string(sessionID), "url": .string("https://example.test"),
        ]),
        "_meta": .object([
          "io.modelcontextprotocol/protocolVersion": .string("2026-07-28"),
          "io.modelcontextprotocol/clientCapabilities": .object([:]),
        ]),
      ])
    )
    let error = try object(response["error"])
    #expect(error["code"] == .int(-32021))
    #expect(try object(error["data"])["requiredCapabilities"] != nil)
  }

  @Test("Actuation requires one bound, single-use human confirmation")
  func actuationConfirmation() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      "<button>Save</button>", baseURL: URL(string: "https://example.test/start"))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let server = WebKitMCPServer(registry: registry)
    let observed = try await toolCall(
      server,
      id: 1,
      name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)]
    )
    let observation = try object(try object(observed["result"])["structuredContent"])
    let observationID = try string(observation["observationID"])
    let firstElement = try object(try array(observation["elements"]).first)
    let arguments: [String: JSONValue] = [
      "session_id": .string(handle.rawValue.uuidString),
      "observation_id": .string(observationID),
      "element_id": try firstElement["elementID"].map { .string(try string($0)) } ?? .null,
      "operation": .string("click"),
      "idempotency_key": .string("confirm-once"),
      "postcondition": .object([
        "type": .string("url_equals"),
        "value": .string("https://example.test/done"),
      ]),
    ]
    let first = try await toolCall(server, id: 2, name: "browser_act", arguments: arguments)
    let required = try object(first["result"])
    #expect(required["resultType"] == .string("input_required"))
    let requestState = try string(required["requestState"])
    let inputRequests = try object(required["inputRequests"])
    #expect(try object(inputRequests["confirmation"])["method"] == .string("elicitation/create"))

    let declined = try await call(
      server,
      id: 3,
      method: "tools/call",
      params: .object([
        "name": .string("browser_act"),
        "arguments": .object(arguments),
        "requestState": .string(requestState),
        "inputResponses": .object([
          "confirmation": .object(["action": .string("decline")])
        ]),
      ]),
      modern: true
    )
    #expect(try object(declined["result"])["isError"] == .bool(true))

    let replay = try await call(
      server,
      id: 4,
      method: "tools/call",
      params: .object([
        "name": .string("browser_act"),
        "arguments": .object(arguments),
        "requestState": .string(requestState),
        "inputResponses": .object([
          "confirmation": .object([
            "action": .string("accept"), "content": .object(["confirm": .bool(true)]),
          ])
        ]),
      ]),
      modern: true
    )
    #expect(try object(replay["error"])["code"] == .int(-32602))
  }

  @Test("A confirmed fill verifies the same semantic target's exact value")
  func verifiedFill() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      """
      <label for='name'>Name</label><input id='name'>
      <script>
        const input = document.getElementById('name');
        input.addEventListener('input', () => {
          const marker = document.createElement('button');
          marker.textContent = 'Inserted by framework';
          document.body.prepend(marker);
          const replacement = input.cloneNode();
          replacement.value = input.value;
          input.replaceWith(replacement);
        }, { once: true });
      </script>
      """,
      baseURL: URL(string: "https://example.test/profile"))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let server = WebKitMCPServer(registry: registry)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let element = try object(try array(observation["elements"]).first)
    let arguments: [String: JSONValue] = [
      "session_id": .string(handle.rawValue.uuidString),
      "observation_id": .string(try string(observation["observationID"])),
      "element_id": .string(try string(element["elementID"])),
      "operation": .string("fill"),
      "value": .string("Ada"),
      "idempotency_key": .string("fill-name-once"),
    ]
    var newlineArguments = arguments
    newlineArguments["value"] = .string("Ada\nSubmit")
    newlineArguments["idempotency_key"] = .string("blocked-input-newline")
    let newline = try await toolCall(
      server, id: 2, name: "browser_act", arguments: newlineArguments)
    #expect(try object(newline["error"])["code"] == .int(-32602))

    let prepared = try await toolCall(server, id: 3, name: "browser_act", arguments: arguments)
    let required = try object(prepared["result"])
    let completed = try await roundTripToolCall(
      server,
      id: 4,
      name: "browser_act",
      arguments: arguments,
      requestState: try string(required["requestState"]),
      action: "accept",
      confirm: true
    )

    let structured = try object(try object(completed["result"])["structuredContent"])
    #expect(try object(structured["verification"])["verified"] != nil)
    let after = try await runtime.observe()
    let input = after.elements.first { $0.tag.segments.first?.text == "input" }
    #expect(input?.elementID == "e2")
    #expect(input?.value?.segments.first?.text == "Ada")
  }

  @Test("A native submit control requires submit and verifies its postcondition")
  func verifiedSubmit() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      """
      <form onsubmit="event.preventDefault(); const s=document.createElement('div');
        s.setAttribute('role','status'); s.textContent='Submitted once'; document.body.appendChild(s)">
        <button>Send</button>
      </form>
      """,
      baseURL: URL(string: "https://example.test/form"))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let server = WebKitMCPServer(registry: registry)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let target = try object(try array(observation["elements"]).first)
    let arguments: [String: JSONValue] = [
      "session_id": .string(handle.rawValue.uuidString),
      "observation_id": .string(try string(observation["observationID"])),
      "element_id": .string(try string(target["elementID"])),
      "operation": .string("submit"),
      "idempotency_key": .string("submit-form-once"),
      "postcondition": .object([
        "type": .string("semantic_text_appears"), "value": .string("Submitted once"),
      ]),
    ]
    let prepared = try await toolCall(server, id: 2, name: "browser_act", arguments: arguments)
    let required = try object(prepared["result"])
    let completed = try await roundTripToolCall(
      server,
      id: 3,
      name: "browser_act",
      arguments: arguments,
      requestState: try string(required["requestState"]),
      action: "accept",
      confirm: true
    )

    let structured = try object(try object(completed["result"])["structuredContent"])
    #expect(try object(structured["verification"])["verified"] != nil)
  }

  @Test("Password fill and submit-as-click fail before confirmation")
  func formAuthoritySeparation() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      "<form><input type='password' aria-label='Password'><button>Send</button></form>",
      baseURL: URL(string: "https://example.test/account"))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let server = WebKitMCPServer(registry: registry)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let elements = try array(observation["elements"])
    let observationID = try string(observation["observationID"])

    let password = try await toolCall(
      server,
      id: 2,
      name: "browser_act",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": .string(observationID),
        "element_id": .string(try string(try object(elements[0])["elementID"])),
        "operation": .string("fill"),
        "value": .string("secret"),
        "idempotency_key": .string("blocked-password"),
      ])
    #expect(try object(password["error"])["code"] == .int(-32602))

    let submitAsClick = try await toolCall(
      server,
      id: 3,
      name: "browser_act",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": .string(observationID),
        "element_id": .string(try string(try object(elements[1])["elementID"])),
        "operation": .string("click"),
        "idempotency_key": .string("wrong-capability"),
        "postcondition": .object([
          "type": .string("url_equals"), "value": .string("https://example.test/done"),
        ]),
      ])
    #expect(try object(submitAsClick["error"])["code"] == .int(-32602))
  }

  @Test("A confirmed MCP click verifies newly appearing same-page semantic text")
  func semanticPostconditionActuation() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      """
      <button aria-label="Save" onclick="
        const status = document.createElement('div');
        status.setAttribute('role', 'status');
        status.textContent = 'Saved locally';
        document.body.appendChild(status);
      ">Save</button>
      """,
      baseURL: URL(string: "https://example.test/settings")
    )
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let server = WebKitMCPServer(registry: registry)
    let observed = try await toolCall(
      server,
      id: 1,
      name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)]
    )
    let observation = try object(try object(observed["result"])["structuredContent"])
    let element = try object(try array(observation["elements"]).first)
    let arguments: [String: JSONValue] = [
      "session_id": .string(handle.rawValue.uuidString),
      "observation_id": .string(try string(observation["observationID"])),
      "element_id": .string(try string(element["elementID"])),
      "operation": .string("click"),
      "idempotency_key": .string("semantic-save-once"),
      "postcondition": .object([
        "type": .string("semantic_text_appears"),
        "value": .string("Saved locally"),
      ]),
    ]
    let prepared = try await toolCall(
      server, id: 2, name: "browser_act", arguments: arguments)
    let requestState = try string(try object(prepared["result"])["requestState"])
    let accepted = try await call(
      server,
      id: 3,
      method: "tools/call",
      params: .object([
        "name": .string("browser_act"),
        "arguments": .object(arguments),
        "requestState": .string(requestState),
        "inputResponses": .object([
          "confirmation": .object([
            "action": .string("accept"),
            "content": .object(["confirm": .bool(true)]),
          ])
        ]),
      ]),
      modern: true
    )

    let result = try object(accepted["result"])
    #expect(result["resultType"] == .string("complete"))
    let structured = try object(result["structuredContent"])
    #expect(structured["verification"] != nil)
  }

  @Test("Navigation approval is exact-argument-bound and unsafe URL forms fail closed")
  func navigationApprovalBoundary() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let confirmationPresenter = ConfirmationPresenterStub(responses: [false])
    let server = WebKitMCPServer(
      registry: registry,
      confirmationPresenter: confirmationPresenter
    )
    let sessionID = handle.rawValue.uuidString
    let arguments: [String: JSONValue] = [
      "session_id": .string(sessionID),
      "url": .string("https://example.com/account"),
    ]
    let prepared = try await toolCall(
      server, id: 2, name: "browser_navigate", arguments: arguments)
    let required = try object(prepared["result"])
    #expect(required["resultType"] == .string("input_required"))
    let supersededState = try string(required["requestState"])

    let preparedAgain = try await toolCall(
      server, id: 3, name: "browser_navigate", arguments: arguments)
    let requestState = try string(try object(preparedAgain["result"])["requestState"])
    let supersededAttempt = try await roundTripToolCall(
      server,
      id: 4,
      name: "browser_navigate",
      arguments: arguments,
      requestState: supersededState,
      action: "accept",
      confirm: true
    )
    #expect(try object(supersededAttempt["error"])["code"] == .int(-32602))

    var changed = arguments
    changed["url"] = .string("https://example.org/account")
    let mutationAttempt = try await call(
      server,
      id: 5,
      method: "tools/call",
      params: .object([
        "name": .string("browser_navigate"),
        "arguments": .object(changed),
        "requestState": .string(requestState),
        "inputResponses": .object([
          "confirmation": .object([
            "action": .string("accept"),
            "content": .object(["confirm": .bool(true)]),
          ])
        ]),
      ]),
      modern: true
    )
    #expect(try object(mutationAttempt["error"])["code"] == .int(-32602))

    for blockedURL in [
      "https://example.com:password@localhost/private",
      "http://127.0.0.1:8080/private",
      "http://2130706433/private",
      "http://0x7f000001/private",
      "http://service.local/private",
      "file:///etc/passwd",
    ] {
      let blocked = try await toolCall(
        server,
        id: 6,
        name: "browser_navigate",
        arguments: ["session_id": .string(sessionID), "url": .string(blockedURL)]
      )
      #expect(try object(blocked["error"])["code"] == .int(-32602))
    }

    let legacy = try await call(
      server,
      id: 7,
      method: "tools/call",
      params: .object([
        "name": .string("browser_navigate"), "arguments": .object(arguments),
      ]),
      modern: false
    )
    #expect(try object(legacy["result"])["isError"] == .bool(true))
    #expect(confirmationPresenter.requests.count == 1)
    #expect(confirmationPresenter.requests.first?.title == "Approve Web Navigation")
    #expect(
      confirmationPresenter.requests.first?.message.contains("https://example.com/account") == true)
  }

  @Test("Legacy actuation uses one native exact-action confirmation")
  func legacyNativeActuationFallback() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      """
      <button aria-label="Save" onclick="
        const status = document.createElement('div');
        status.textContent = 'Saved by legacy fallback';
        document.body.appendChild(status);
      ">Save</button>
      """,
      baseURL: URL(string: "https://example.test/settings")
    )
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let confirmationPresenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(
      registry: registry,
      confirmationPresenter: confirmationPresenter
    )
    let observed = try await legacyToolCall(
      server,
      id: 1,
      name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)]
    )
    let observation = try object(try object(observed["result"])["structuredContent"])
    let target = try object(try array(observation["elements"]).first)
    let acted = try await legacyToolCall(
      server,
      id: 2,
      name: "browser_act",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try string(target["elementID"])),
        "operation": .string("click"),
        "idempotency_key": .string("legacy-save-once"),
        "postcondition": .object([
          "type": .string("semantic_text_appears"),
          "value": .string("Saved by legacy fallback"),
        ]),
      ]
    )
    #expect(try object(acted["result"])["structuredContent"] != nil)
    #expect(confirmationPresenter.requests.count == 1)
    #expect(confirmationPresenter.requests.first?.message.contains("legacy-save-once") == false)
    #expect(confirmationPresenter.requests.first?.message.contains("Save") == true)
  }

  @Test("Legacy handoff remains human-controlled until native resume approval")
  func legacyNativeHandoffFallback() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<button>Continue</button>",
      baseURL: URL(string: "https://example.test/login"),
      timeout: .seconds(2),
      quietWindow: .milliseconds(40)
    )
    let confirmationPresenter = ConfirmationPresenterStub(responses: [false, true])
    let server = WebKitMCPServer(
      registry: registry,
      presentHumanWindows: false,
      confirmationPresenter: confirmationPresenter
    )
    let arguments: [String: JSONValue] = [
      "operation": .string("handoff"),
      "session_id": .string(handle.rawValue.uuidString),
    ]

    let handedOff = try await legacyToolCall(
      server, id: 1, name: "browser_session", arguments: arguments)
    let handoffResult = try object(try object(handedOff["result"])["structuredContent"])
    #expect(handoffResult["control_state"] == .string("human_controlled"))

    let declined = try await legacyToolCall(
      server, id: 2, name: "browser_session", arguments: arguments)
    #expect(try object(declined["result"])["isError"] == .bool(true))
    #expect(runtime.interactionControlState() == .humanControlled)

    let resumed = try await legacyToolCall(
      server, id: 3, name: "browser_session", arguments: arguments)
    let resumedResult = try object(try object(resumed["result"])["structuredContent"])
    #expect(resumedResult["control_state"] == .string("freshly_reobserved"))
    #expect(resumedResult["observation"] != nil)
    #expect(confirmationPresenter.requests.count == 2)
  }

  @Test("Human handoff keeps control until an accepted resume and returns a fresh observation")
  func humanHandoff() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<button>Continue</button>",
      baseURL: URL(string: "https://example.test/login"),
      timeout: .seconds(2),
      quietWindow: .milliseconds(40)
    )
    let before = try await runtime.observe()
    let server = WebKitMCPServer(registry: registry)
    let arguments: [String: JSONValue] = [
      "operation": .string("handoff"), "session_id": .string(handle.rawValue.uuidString),
    ]
    let requested = try await toolCall(
      server, id: 1, name: "browser_session", arguments: arguments)
    let firstResult = try object(requested["result"])
    let firstState = try string(firstResult["requestState"])
    #expect(runtime.interactionControlState() == .humanControlled)

    let declined = try await roundTripToolCall(
      server, id: 2, name: "browser_session", arguments: arguments,
      requestState: firstState, action: "decline", confirm: nil)
    #expect(try object(declined["result"])["isError"] == .bool(true))
    #expect(runtime.interactionControlState() == .humanControlled)

    let requestedAgain = try await toolCall(
      server, id: 3, name: "browser_session", arguments: arguments)
    let secondState = try string(try object(requestedAgain["result"])["requestState"])
    let resumed = try await roundTripToolCall(
      server, id: 4, name: "browser_session", arguments: arguments,
      requestState: secondState, action: "accept", confirm: true)
    let structured = try object(try object(resumed["result"])["structuredContent"])
    let observation = try object(structured["observation"])
    #expect(structured["control_state"] == .string("freshly_reobserved"))
    #expect(try string(observation["observationID"]) != before.observationID)
  }

  @Test("The SiliconPass MCP shim is secretless and never submits")
  func siliconPassShim() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      """
      <form>
        <label for='username'>Username</label><input id='username'>
        <label for='password'>Password</label><input id='password' type='password'>
        <button type='submit'>Sign in</button>
      </form>
      <script>
        globalThis.submitCount = 0;
        document.querySelector('form').addEventListener('submit', event => {
          globalThis.submitCount += 1; event.preventDefault();
        });
      </script>
      """,
      baseURL: URL(string: "https://fixture.invalid/login"),
      timeout: .seconds(2),
      quietWindow: .milliseconds(40)
    )
    let server = WebKitMCPServer(
      registry: registry,
      credentialBroker: InProcessSyntheticBrokerStub()
    )
    let observed = try await toolCall(
      server,
      id: 1,
      name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)]
    )
    let structured = try object(try object(observed["result"])["structuredContent"])
    let observationID = try string(structured["observationID"])
    let filled = try await toolCall(
      server,
      id: 2,
      name: "browser_fill_siliconpass",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": .string(observationID),
        "username_element_id": .string("e1"),
        "password_element_id": .string("e2"),
      ]
    )
    let result = try object(filled["result"])
    #expect(try object(result["structuredContent"])["status"] == .string("filled"))

    let wire = String(decoding: try JSONEncoder().encode(JSONValue.object(filled)), as: UTF8.self)
    #expect(!wire.contains(InProcessSyntheticBrokerStub.username))
    #expect(!wire.contains(InProcessSyntheticBrokerStub.password))
    let page = try #require(
      await runtime.webView.evaluateJavaScript(
        "JSON.stringify([username.value,password.value,globalThis.submitCount])") as? String
    )
    #expect(
      page
        == "[\"\(InProcessSyntheticBrokerStub.username)\",\"\(InProcessSyntheticBrokerStub.password)\",0]"
    )
  }

  @Test("Malformed requests and tool arguments fail at the right boundary")
  func failures() async throws {
    let server = try WebKitMCPServer()
    let parse = try decode(await server.handle(Data("not-json".utf8)))
    #expect(try object(parse["error"])["code"] == .int(-32700))

    let invalid = try await call(
      server,
      id: 1,
      method: "tools/call",
      params: .object([
        "name": .string("browser_session"),
        "arguments": .object([
          "operation": .string("status"), "session_id": .string("not-a-uuid"),
        ]),
      ]),
      modern: true
    )
    #expect(try object(invalid["error"])["code"] == .int(-32602))
  }

  private func toolCall(
    _ server: WebKitMCPServer,
    id: Int64,
    name: String,
    arguments: [String: JSONValue]
  ) async throws -> [String: JSONValue] {
    try await call(
      server,
      id: id,
      method: "tools/call",
      params: .object([
        "name": .string(name),
        "arguments": .object(arguments),
      ]),
      modern: true
    )
  }

  private func legacyToolCall(
    _ server: WebKitMCPServer,
    id: Int64,
    name: String,
    arguments: [String: JSONValue]
  ) async throws -> [String: JSONValue] {
    try await call(
      server,
      id: id,
      method: "tools/call",
      params: .object([
        "name": .string(name),
        "arguments": .object(arguments),
      ]),
      modern: false
    )
  }

  private func roundTripToolCall(
    _ server: WebKitMCPServer,
    id: Int64,
    name: String,
    arguments: [String: JSONValue],
    requestState: String,
    action: String,
    confirm: Bool?
  ) async throws -> [String: JSONValue] {
    var response: [String: JSONValue] = ["action": .string(action)]
    if let confirm { response["content"] = .object(["confirm": .bool(confirm)]) }
    return try await call(
      server,
      id: id,
      method: "tools/call",
      params: .object([
        "name": .string(name),
        "arguments": .object(arguments),
        "requestState": .string(requestState),
        "inputResponses": .object(["confirmation": .object(response)]),
      ]),
      modern: true
    )
  }

  private func call(
    _ server: WebKitMCPServer,
    id: Int64,
    method: String,
    params: JSONValue,
    modern: Bool
  ) async throws -> [String: JSONValue] {
    var request: [String: JSONValue] = [
      "jsonrpc": .string("2.0"),
      "id": .int(id),
      "method": .string(method),
      "params": params,
    ]
    if modern {
      var parameterObject = try object(request["params"])
      parameterObject["_meta"] = .object([
        "io.modelcontextprotocol/protocolVersion": .string("2026-07-28"),
        "io.modelcontextprotocol/clientInfo": .object([
          "name": .string("tests"), "version": .string("1"),
        ]),
        "io.modelcontextprotocol/clientCapabilities": .object([
          "elicitation": .object([:])
        ]),
      ])
      request["params"] = .object(parameterObject)
    }
    let data = try JSONEncoder().encode(JSONValue.object(request))
    return try decode(await server.handle(data))
  }

  private func rawCall(
    _ server: WebKitMCPServer,
    id: Int64,
    method: String,
    params: JSONValue
  ) async throws -> [String: JSONValue] {
    let request: JSONValue = .object([
      "jsonrpc": .string("2.0"),
      "id": .int(id),
      "method": .string(method),
      "params": params,
    ])
    return try decode(await server.handle(try JSONEncoder().encode(request)))
  }

  private func decode(_ data: Data?) throws -> [String: JSONValue] {
    guard let data else { throw TestError.missingResponse }
    return try object(try JSONDecoder().decode(JSONValue.self, from: data))
  }

  private func object(_ value: JSONValue?) throws -> [String: JSONValue] {
    guard case .object(let object) = value else { throw TestError.wrongType }
    return object
  }

  private func array(_ value: JSONValue?) throws -> [JSONValue] {
    guard case .array(let array) = value else { throw TestError.wrongType }
    return array
  }

  private func string(_ value: JSONValue?) throws -> String {
    guard case .string(let string) = value else { throw TestError.wrongType }
    return string
  }

  private enum TestError: Error {
    case missingResponse
    case wrongType
  }
}
