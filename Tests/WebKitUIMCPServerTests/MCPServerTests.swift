import Foundation
import Testing
import WebKitUIMCPRuntime

@testable import WebKitUIMCPServer

private final class TransactionLedgerFactoryProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var creationCount = 0

  func recordCreation() {
    lock.withLock { creationCount += 1 }
  }

  func count() -> Int {
    lock.withLock { creationCount }
  }
}

@MainActor
private final class InProcessSyntheticBrokerStub: CredentialBrokerFilling {
  static let username = "synthetic-user@example.test"
  static let password = "SP-MVP0-synthetic-only-7f3a"
  static let rotatedPassword = "SP-ROTATION-synthetic-only-8g4b"

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

  func rotatePassword(
    binding: CredentialSinkRotationBinding,
    runtime: WebKitRuntime
  ) async throws -> CredentialBrokerWireReceipt {
    _ = try await runtime.performCredentialRotationFill(
      binding: binding,
      currentPassword: CredentialSecretBuffer(copying: Array(Self.password.utf8)),
      newPassword: CredentialSecretBuffer(copying: Array(Self.rotatedPassword.utf8))
    )
    return CredentialBrokerWireReceipt(status: .changed)
  }
}

@MainActor
private final class FixedStatusCredentialBrokerStub: CredentialBrokerFilling {
  let status: CredentialBrokerWireStatus

  init(status: CredentialBrokerWireStatus) {
    self.status = status
  }

  func fill(
    binding: CredentialSinkFormBinding,
    runtime: WebKitRuntime
  ) async throws -> CredentialBrokerWireReceipt {
    _ = binding
    _ = runtime
    return CredentialBrokerWireReceipt(status: status)
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
  @Test("A shared transaction ledger factory returns one authority per scope")
  func sharedTransactionLedgerFactory() throws {
    let probe = TransactionLedgerFactoryProbe()
    let factory = WebKitTransactionLedgerFactory.shared { _ in
      probe.recordCreation()
      return .init()
    }

    let first = try factory.make(scope: "default")
    let second = try factory.make(scope: "default")
    let other = try factory.make(scope: "other")

    #expect(first === second)
    #expect(first !== other)
    #expect(probe.count() == 2)
  }

  @Test("Native confirmation helper failures deny authority")
  func nativeConfirmationHelperFailClosed() throws {
    let helperDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "webkitui-confirm-test-\(UUID().uuidString)",
      isDirectory: true)
    try FileManager.default.createDirectory(
      at: helperDirectory,
      withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: helperDirectory) }
    let acceptingHelper = helperDirectory.appendingPathComponent("accepting-helper")
    try Data("#!/bin/sh\n/bin/cat >/dev/null\n".utf8).write(to: acceptingHelper)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: acceptingHelper.path)

    let accepts = NativeBrowserConfirmationPresenter(
      helperURL: acceptingHelper,
      helperVerification: { _ in true },
      runningHelperVerification: { _ in true })
    let rejects = NativeBrowserConfirmationPresenter(
      helperURL: URL(fileURLWithPath: "/usr/bin/false"),
      helperVerification: { _ in true },
      runningHelperVerification: { _ in true })
    let missing = NativeBrowserConfirmationPresenter(
      helperURL: URL(fileURLWithPath: "/path/does/not/exist"),
      helperVerification: { _ in true },
      runningHelperVerification: { _ in true })
    let runningSubstitution = NativeBrowserConfirmationPresenter(
      helperURL: acceptingHelper,
      helperVerification: { _ in true },
      runningHelperVerification: { _ in false })
    let foreignSignedHelper = NativeBrowserConfirmationPresenter(
      helperURL: URL(fileURLWithPath: "/usr/bin/true"))

    #expect(accepts.confirm(title: "Title", message: "Message", approveLabel: "Approve"))
    #expect(!rejects.confirm(title: "Title", message: "Message", approveLabel: "Approve"))
    #expect(!missing.confirm(title: "Title", message: "Message", approveLabel: "Approve"))
    #expect(
      !runningSubstitution.confirm(title: "Title", message: "Message", approveLabel: "Approve"))
    #expect(
      !foreignSignedHelper.confirm(title: "Title", message: "Message", approveLabel: "Approve"))
  }

  @Test("A helper closing standard input fails without terminating the server")
  func nativeConfirmationBrokenPipeFailsClosed() throws {
    let pipe = Pipe()
    try pipe.fileHandleForReading.close()
    defer { try? pipe.fileHandleForWriting.close() }

    var rejectedBrokenPipe = false
    do {
      try NativeBrowserConfirmationPresenter.writePayload(
        Data("synthetic request".utf8),
        to: pipe.fileHandleForWriting)
    } catch {
      rejectedBrokenPipe = true
    }

    #expect(rejectedBrokenPipe)
  }

  @Test("Native confirmation arguments never carry the approval payload")
  func nativeConfirmationPayloadUsesStandardInput() {
    #expect(
      NativeBrowserConfirmationPresenter.helperArguments == [
        "--protocol-version", "1", "--request-stdin",
      ])
    #expect(!NativeBrowserConfirmationPresenter.helperArguments.joined().contains("Message"))
  }

  @Test("Native confirmation strips bidirectional and control spoofing")
  func nativeConfirmationSanitizesUntrustedLabels() {
    let spoofed = "safe\u{202E}txt.exe\u{2066}\nnext"
    #expect(WebKitMCPServer.safeConfirmationText(spoofed) == "safetxt.exenext")
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
        "browser_act",
        "browser_capture",
        "browser_fill_siliconpass",
        "browser_rotate_siliconpass_password",
        "browser_navigate",
        "browser_observe",
        "browser_read_text",
        "browser_scroll",
        "element_scroll_into_view",
        "browser_session",
        "browser_transaction",
      ]
    )
  }

  @Test("Page scrolling, element scrolling, and virtual text reads are bounded")
  func scrollingAndTextReading() async throws {
    let registry = try WebKitSessionRegistry()
    let server = WebKitMCPServer(registry: registry)
    let opened = try await toolCall(
      server, id: 1, name: "browser_session", arguments: ["operation": .string("open")])
    let sessionID = try string(
      object(try object(opened["result"])["structuredContent"])["session_id"])
    let runtime = try registry.runtime(
      for: WebKitSessionHandle(rawValue: try #require(UUID(uuidString: sessionID))))
    _ = try await runtime.loadHTML(
      """
      <div role='log' aria-label='Build log' style='height:80px;overflow:auto'>
        <pre>line one\nline two\nline three</pre>
      </div>
      <div style='height:1600px'></div>
      <button aria-label='Bottom action'>Bottom</button>
      """,
      baseURL: URL(string: "https://fixture.invalid/scroll"),
      timeout: .seconds(5), quietWindow: .milliseconds(40))

    let textRead = try await toolCall(
      server, id: 2, name: "browser_read_text",
      arguments: ["session_id": .string(sessionID), "maximum_characters": .int(2_000)])
    let text = try object(try object(textRead["result"])["structuredContent"])
    #expect(try string(text["bodyText"]).contains("line one"))
    #expect(!(try array(text["regions"])).isEmpty)

    let observed = try await toolCall(
      server, id: 3, name: "browser_observe",
      arguments: ["session_id": .string(sessionID)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let elements = try array(observation["elements"])
    let bottom = try #require(elements.last)
    let elementID = try string(try object(bottom)["elementID"])
    let elementScroll = try await toolCall(
      server, id: 4, name: "element_scroll_into_view",
      arguments: [
        "session_id": .string(sessionID),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(elementID),
      ])
    let elementScrollResult = try object(
      try object(elementScroll["result"])["structuredContent"])
    #expect(elementScrollResult["observationInvalidated"] == .bool(true))

    let pageScroll = try await toolCall(
      server, id: 5, name: "browser_scroll",
      arguments: ["session_id": .string(sessionID), "delta_y": .int(-500)])
    let pageScrollResult = try object(try object(pageScroll["result"])["structuredContent"])
    #expect(pageScrollResult["observationInvalidated"] == .bool(true))
  }

  @Test("Observation pagination and semantic field budgets are server enforced")
  func boundedObservationPages() async throws {
    let registry = try WebKitSessionRegistry()
    let server = WebKitMCPServer(registry: registry)
    let opened = try await toolCall(
      server, id: 1, name: "browser_session", arguments: ["operation": .string("open")])
    let sessionID = try string(
      object(try object(opened["result"])["structuredContent"])["session_id"])
    let runtime = try registry.runtime(
      for: WebKitSessionHandle(rawValue: try #require(UUID(uuidString: sessionID))))
    _ = try await runtime.loadHTML(
      """
      <button aria-label="First action with a deliberately long accessible name">First</button>
      <button aria-label="Second action with a deliberately long accessible name">Second</button>
      <button aria-label="Third action with a deliberately long accessible name">Third</button>
      """,
      baseURL: URL(string: "https://fixture.invalid/observation-pages"),
      timeout: .seconds(3), quietWindow: .milliseconds(40))

    let firstPage = try await toolCall(
      server, id: 2, name: "browser_observe",
      arguments: [
        "session_id": .string(sessionID),
        "maximum_elements": .int(1),
        "maximum_field_characters": .int(64),
      ])
    let first = try object(try object(firstPage["result"])["structuredContent"])
    #expect(first["totalElementCount"] == .int(3))
    #expect(first["elementOffset"] == .int(0))
    #expect(first["nextElementOffset"] == .int(1))
    #expect((try array(first["elements"])).count == 1)

    let finalPage = try await toolCall(
      server, id: 3, name: "browser_observe",
      arguments: [
        "session_id": .string(sessionID),
        "maximum_elements": .int(2),
        "element_offset": .int(2),
        "maximum_field_characters": .int(64),
      ])
    let final = try object(try object(finalPage["result"])["structuredContent"])
    #expect(final["elementOffset"] == .int(2))
    #expect(final["nextElementOffset"] == nil)
    #expect((try array(final["elements"])).count == 1)
  }

  @Test("Default observation pages remain within the one mebibyte wire budget")
  func defaultObservationWireBudget() async throws {
    let registry = try WebKitSessionRegistry()
    let server = WebKitMCPServer(registry: registry)
    let opened = try await toolCall(
      server, id: 1, name: "browser_session", arguments: ["operation": .string("open")])
    let sessionID = try string(
      object(try object(opened["result"])["structuredContent"])["session_id"])
    let runtime = try registry.runtime(
      for: WebKitSessionHandle(rawValue: try #require(UUID(uuidString: sessionID))))
    let longName = String(repeating: "bounded semantic field ", count: 40)
    let markup = (0..<300).map { index in
      "<button aria-label='\(longName)\(index)'>Action \(index)</button>"
    }.joined()
    _ = try await runtime.loadHTML(
      markup,
      baseURL: URL(string: "https://fixture.invalid/default-wire-budget"),
      timeout: .seconds(3), quietWindow: .milliseconds(40))

    let response = try await toolCall(
      server, id: 2, name: "browser_observe",
      arguments: ["session_id": .string(sessionID)])
    let structured = try object(try object(response["result"])["structuredContent"])
    let encoded = try JSONEncoder().encode(response)

    #expect(structured["totalElementCount"] == .int(300))
    #expect(structured["nextElementOffset"] == .int(150))
    #expect((try array(structured["elements"])).count == 150)
    #expect(encoded.count <= 1_048_576)
  }

  @Test("Authentication origins expose only a sanitized handoff requirement")
  func authenticationOriginPolicy() async throws {
    let registry = try WebKitSessionRegistry()
    let server = WebKitMCPServer(registry: registry)
    let opened = try await toolCall(
      server, id: 1, name: "browser_session", arguments: ["operation": .string("open")])
    let sessionID = try string(
      object(try object(opened["result"])["structuredContent"])["session_id"])
    let runtime = try registry.runtime(
      for: WebKitSessionHandle(rawValue: try #require(UUID(uuidString: sessionID))))
    let secret = "server-query-state-must-not-escape"
    _ = try await runtime.loadHTML(
      """
      <div role="progressbar"></div>
      <form hidden><input name="csrfToken" value="hidden-server-secret"></form>
      """,
      baseURL: URL(string: "https://idmsa.apple.com/IDMSWebAuth/signin?state=\(secret)"),
      timeout: .seconds(3),
      quietWindow: .milliseconds(40)
    )

    let status = try await toolCall(
      server,
      id: 2,
      name: "browser_session",
      arguments: ["operation": .string("status"), "session_id": .string(sessionID)]
    )
    let statusContent = try object(try object(status["result"])["structuredContent"])
    #expect(statusContent["currentURL"] == .string("https://idmsa.apple.com"))

    for (offset, name) in [
      "browser_observe",
      "browser_read_text",
      "browser_capture",
      "browser_scroll",
      "element_scroll_into_view",
      "browser_act",
      "browser_fill_siliconpass",
    ].enumerated() {
      let response = try await toolCall(
        server,
        id: Int64(3 + offset),
        name: name,
        arguments: ["session_id": .string(sessionID)]
      )
      let result = try object(response["result"])
      #expect(result["isError"] == .bool(true))
      let structured = try object(result["structuredContent"])
      #expect(structured["status"] == .string("authentication_origin_requires_human_handoff"))
      #expect(structured["origin"] == .string("https://idmsa.apple.com"))
      #expect(structured["auth_ui_state"] == .string("auth_ui_not_ready"))
      #expect(structured["control_state"] == .string("human_controlled"))
      #expect(structured["selected_backend"] == .string("native_webkit"))
      #expect(structured["required_internal_backend"] == .string("native_handoff"))
      #expect(structured["backend_transition"] == .string("human_handoff_required"))
      #expect(structured["session_transfer_supported"] == .bool(false))
      #expect(structured["credential_transfer_supported"] == .bool(false))
      let encoded = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
      #expect(!encoded.contains(secret))
      #expect(!encoded.contains("hidden-server-secret"))
      #expect(!encoded.contains("IDMSWebAuth"))
    }
  }

  @Test("Cross-origin redirects return only sanitized origins")
  func redirectRequiresHumanApprovalResult() throws {
    let server = try WebKitMCPServer()
    let result = try object(
      server.redirectApprovalResult(
        fromOrigin: "https://developer.apple.com",
        toOrigin: "https://idmsa.apple.com",
        modern: true
      ))
    #expect(result["isError"] == .bool(true))
    let structured = try object(result["structuredContent"])
    #expect(structured["status"] == .string("redirect_requires_human_approval"))
    #expect(structured["from_origin"] == .string("https://developer.apple.com"))
    #expect(structured["to_origin"] == .string("https://idmsa.apple.com"))
    let encoded = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
    #expect(!encoded.contains("IDMSWebAuth"))
    #expect(!encoded.contains("?"))
  }

  @Test("Authentication navigation approval omits path and query")
  func authenticationNavigationApprovalIsSanitized() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let server = WebKitMCPServer(registry: registry)
    let secret = "approval-query-state-must-not-escape"
    let prepared = try await toolCall(
      server,
      id: 1,
      name: "browser_navigate",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "url": .string(
          "https://idmsa.apple.com/IDMSWebAuth/signin?state=\(secret)"),
        "approval_mode": .string("mcp"),
      ]
    )
    let result = try object(prepared["result"])
    let requests = try object(result["inputRequests"])
    let confirmation = try object(requests["confirmation"])
    let message = try string(try object(confirmation["params"])["message"])
    #expect(message.contains("https://idmsa.apple.com"))
    #expect(!message.contains("IDMSWebAuth"))
    #expect(!message.contains(secret))
    #expect(!message.contains("?state="))
  }

  @Test("Session state travels through an explicit tool argument")
  func explicitSessionHandle() async throws {
    let server = try WebKitMCPServer()
    let profiles = try await toolCall(
      server, id: 0, name: "browser_session", arguments: ["operation": .string("profiles")])
    let profileResult = try object(try object(profiles["result"])["structuredContent"])
    #expect(try array(profileResult["profiles"]).contains(.string("default")))
    #expect(profileResult["contains_credentials"] == .bool(false))
    let opened = try await toolCall(
      server,
      id: 1,
      name: "browser_session",
      arguments: ["operation": .string("open"), "profile_id": .string("default")])
    let openResult = try object(try object(opened["result"])["structuredContent"])
    let sessionID = try string(openResult["session_id"])
    #expect(UUID(uuidString: sessionID) != nil)
    #expect(openResult["profile_id"] == .string("default"))
    #expect(openResult["execution_policy"] == .string("auto"))
    #expect(openResult["selected_backend"] == .string("native_webkit"))

    let status = try await toolCall(
      server,
      id: 2,
      name: "browser_session",
      arguments: ["operation": .string("status"), "session_id": .string(sessionID)]
    )
    let statusResult = try object(try object(status["result"])["structuredContent"])
    #expect(statusResult["sessionID"] == .string(sessionID))
    #expect(statusResult["selected_backend"] == .string("native_webkit"))

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

  @Test("Unavailable internal backends fail closed without recommending another MCP")
  func unavailableInternalBackendFailsClosed() async throws {
    let server = try WebKitMCPServer()
    let response = try await toolCall(
      server,
      id: 1,
      name: "browser_session",
      arguments: [
        "operation": .string("open"),
        "profile_id": .string("default"),
        "execution_policy": .string("compatibility"),
      ]
    )
    let result = try object(response["result"])
    #expect(result["isError"] == .bool(true))
    let structured = try object(result["structuredContent"])
    #expect(structured["status"] == .string("backend_unavailable"))
    #expect(structured["execution_policy"] == .string("compatibility"))
    #expect(structured["available_internal_backends"] == .array([.string("native_webkit")]))
    let encoded = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
    #expect(!encoded.contains("safari_mcp"))
  }

  @Test("A durable host reuses its live browser but invalidates client observations")
  func durableBrowserReconnect() async throws {
    let registry = try WebKitSessionRegistry()
    let server = WebKitMCPServer(
      registry: registry,
      preserveBrowserOnClose: true
    )
    let opened = try await toolCall(
      server, id: 1, name: "browser_session", arguments: ["operation": .string("open")])
    let first = try object(try object(opened["result"])["structuredContent"])
    let sessionID = try string(first["session_id"])
    #expect(first["reused"] == .bool(false))

    let runtime = try registry.runtime(
      for: WebKitSessionHandle(rawValue: try #require(UUID(uuidString: sessionID))))
    _ = try await runtime.loadHTML(
      "<button aria-label='Continue'>Continue</button>",
      baseURL: URL(string: "https://fixture.invalid/session"),
      timeout: .seconds(2),
      quietWindow: .milliseconds(40)
    )
    _ = try await runtime.webView.evaluateJavaScript(
      "sessionStorage.setItem('durable-browser-proof', 'alive')")
    let observed = try await toolCall(
      server,
      id: 2,
      name: "browser_observe",
      arguments: ["session_id": .string(sessionID)]
    )
    let observation = try object(try object(observed["result"])["structuredContent"])

    let closed = try await toolCall(
      server,
      id: 3,
      name: "browser_session",
      arguments: ["operation": .string("close"), "session_id": .string(sessionID)]
    )
    #expect(
      try object(try object(closed["result"])["structuredContent"])["browser_preserved"]
        == .bool(true))
    await server.prepareForClientReconnect()

    let reopened = try await toolCall(
      server, id: 4, name: "browser_session", arguments: ["operation": .string("open")])
    let second = try object(try object(reopened["result"])["structuredContent"])
    #expect(second["session_id"] == .string(sessionID))
    #expect(second["reused"] == .bool(true))
    let durableProof =
      try await runtime.webView.evaluateJavaScript(
        "sessionStorage.getItem('durable-browser-proof')") as? String
    #expect(durableProof == "alive")

    let staleAction = try await toolCall(
      server,
      id: 5,
      name: "browser_act",
      arguments: [
        "session_id": .string(sessionID),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string("e1"),
        "operation": .string("click"),
        "idempotency_key": .string("must-not-cross-reconnect"),
      ]
    )
    #expect(try object(staleAction["error"])["code"] == .int(-32602))
  }

  @Test("Durable clients share one browser with isolated authority state")
  func durableMultiClientAuthorityIsolation() async throws {
    let registry = try WebKitSessionRegistry()
    let firstClient = WebKitMCPServer(durableRegistry: registry)
    let secondClient = WebKitMCPServer(durableRegistry: registry)

    let firstOpen = try await toolCall(
      firstClient, id: 1, name: "browser_session",
      arguments: ["operation": .string("open")])
    let first = try object(try object(firstOpen["result"])["structuredContent"])
    let sessionID = try string(first["session_id"])
    #expect(first["reused"] == .bool(false))

    let runtime = try registry.runtime(
      for: WebKitSessionHandle(rawValue: try #require(UUID(uuidString: sessionID))))
    _ = try await runtime.loadHTML(
      "<button aria-label='Shared browser'>Shared browser</button>",
      baseURL: URL(string: "https://fixture.invalid/shared"),
      timeout: .seconds(2), quietWindow: .milliseconds(40))

    let firstObservation = try await toolCall(
      firstClient, id: 2, name: "browser_observe",
      arguments: ["session_id": .string(sessionID)])
    let firstObservationID = try string(
      object(try object(firstObservation["result"])["structuredContent"])["observationID"])

    let secondOpen = try await toolCall(
      secondClient, id: 3, name: "browser_session",
      arguments: ["operation": .string("open")])
    let second = try object(try object(secondOpen["result"])["structuredContent"])
    #expect(second["session_id"] == .string(sessionID))
    #expect(second["reused"] == .bool(true))

    _ = try await toolCall(
      secondClient, id: 4, name: "browser_observe",
      arguments: ["session_id": .string(sessionID)])
    let staleArguments: [String: JSONValue] = [
      "session_id": .string(sessionID),
      "observation_id": .string(firstObservationID),
      "element_id": .string("e1"),
      "operation": .string("click"),
      "idempotency_key": .string("cross-client-stale-address"),
      "postcondition": .object([
        "type": .string("semantic_text_appears"), "value": .string("Done"),
      ]),
    ]
    let pendingStaleAction = try await toolCall(
      firstClient,
      id: 5,
      name: "browser_act",
      arguments: staleArguments)
    let requestState = try string(try object(pendingStaleAction["result"])["requestState"])
    let staleFirstClientAction = try await roundTripToolCall(
      firstClient,
      id: 6,
      name: "browser_act",
      arguments: staleArguments,
      requestState: requestState,
      action: "accept",
      confirm: true)
    #expect(try object(staleFirstClientAction["result"])["isError"] == .bool(true))

    await firstClient.prepareForClientReconnect()
    let secondStillConnected = try await toolCall(
      secondClient, id: 7, name: "browser_observe",
      arguments: ["session_id": .string(sessionID)])
    #expect(try object(secondStillConnected["result"])["isError"] == nil)
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
    #expect(try object(result["serverInfo"])["version"] == .string("0.6.0"))
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
    let response = try await rawCall(
      server,
      id: 1,
      method: "tools/call",
      params: .object([
        "name": .string("browser_navigate"),
        "arguments": .object(["approval_mode": .string("mcp")]),
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
      "value": .string("Kevin"),
      "idempotency_key": .string("fill-name-once"),
    ]
    var newlineArguments = arguments
    newlineArguments["value"] = .string("Kevin\nSubmit")
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
    #expect(input?.value?.segments.first?.text == "Kevin")
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

  @Test("A confirmed checkbox click verifies semantic checked state")
  func verifiedCheckedState() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      """
      <label style='display:inline-block; padding:8px'>
        <input style='position:absolute; opacity:0' type='checkbox'> View financial data
      </label>
      """,
      baseURL: URL(string: "https://example.test/permissions"))
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
      "operation": .string("click"),
      "idempotency_key": .string("check-financial-data-once"),
      "postcondition": .object([
        "type": .string("checked_equals"), "value": .string("true"),
      ]),
    ]
    let prepared = try await toolCall(server, id: 2, name: "browser_act", arguments: arguments)
    let required = try object(prepared["result"])
    let completed = try await roundTripToolCall(
      server, id: 3, name: "browser_act", arguments: arguments,
      requestState: try string(required["requestState"]), action: "accept", confirm: true)
    let structured = try object(try object(completed["result"])["structuredContent"])
    #expect(try object(structured["verification"])["verified"] != nil)
  }

  @Test("Native approval and AppKit dispatch produce distinct trusted receipts")
  func nativeApprovedTrustedActuation() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      """
      <button aria-label='Create app'
        onclick="this.dataset.state=event.isTrusted ? 'trusted' : 'rejected'">Create app</button>
      """,
      baseURL: URL(string: "https://example.test/apps"))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let presenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let target = try object(try array(observation["elements"]).first)
    let acted = try await toolCall(
      server, id: 2, name: "browser_act",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try string(target["elementID"])),
        "operation": .string("click"),
        "approval_mode": .string("native"),
        "idempotency_key": .string("native-create-once"),
        "postcondition": .object([
          "type": .string("attribute_equals"), "attribute": .string("data-state"),
          "value": .string("trusted"),
        ]),
      ])
    let structured = try object(try object(acted["result"])["structuredContent"])
    #expect(structured["confirmation_mode"] == .string("native"))
    #expect(structured["dispatch_mode"] == .string("native_appkit"))
    #expect(structured["confirmation_and_dispatch_are_distinct"] == .bool(true))
    #expect(structured["trusted_gesture_state"] == .string("trusted"))
    #expect(try object(structured["verification"])["verified"] != nil)
    #expect(presenter.requests.count == 1)
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
      "approval_mode": .string("mcp"),
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

  @Test("Navigation uses native exact-destination confirmation by default")
  func navigationDefaultsToNativeConfirmation() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let confirmationPresenter = ConfirmationPresenterStub(responses: [false])
    let server = WebKitMCPServer(
      registry: registry,
      confirmationPresenter: confirmationPresenter
    )
    let denied = try await toolCall(
      server,
      id: 1,
      name: "browser_navigate",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "url": .string("https://example.com/account"),
      ]
    )

    let result = try object(denied["result"])
    #expect(result["isError"] == .bool(true))
    #expect(confirmationPresenter.requests.count == 1)
    #expect(confirmationPresenter.requests.first?.title == "Approve Web Navigation")
    #expect(
      confirmationPresenter.requests.first?.message.contains("https://example.com/account")
        == true)
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

  @Test("Non-blocking handoff polls and consumes a session-bound resume token")
  func nonBlockingHandoffLifecycle() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<button>Continue</button>", baseURL: URL(string: "https://example.test/handoff"),
      timeout: .seconds(2), quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(responses: [false, true])
    let server = WebKitMCPServer(
      registry: registry, presentHumanWindows: false, confirmationPresenter: presenter)
    let sessionID = handle.rawValue.uuidString

    let started = try await toolCall(
      server, id: 1, name: "browser_session",
      arguments: ["operation": .string("handoff_start"), "session_id": .string(sessionID)])
    let start = try object(try object(started["result"])["structuredContent"])
    let token = try string(start["resume_token"])
    #expect(start["blocking"] == .bool(false))
    #expect(start["control_state"] == .string("human_controlled"))

    let polled = try await toolCall(
      server, id: 2, name: "browser_session",
      arguments: [
        "operation": .string("handoff_status"), "session_id": .string(sessionID),
        "resume_token": .string(token),
      ])
    let poll = try object(try object(polled["result"])["structuredContent"])
    #expect(poll["resume_token_state"] == .string("active"))
    #expect(poll["ready_for_resume_request"] == .bool(true))

    let declined = try await toolCall(
      server, id: 3, name: "browser_session",
      arguments: [
        "operation": .string("handoff_resume"), "session_id": .string(sessionID),
        "resume_token": .string(token),
      ])
    let declinedState = try object(try object(declined["result"])["structuredContent"])
    #expect(declinedState["resumed"] == .bool(false))
    #expect(declinedState["resume_token_state"] == .string("active"))

    let resumed = try await toolCall(
      server, id: 4, name: "browser_session",
      arguments: [
        "operation": .string("handoff_resume"), "session_id": .string(sessionID),
        "resume_token": .string(token),
      ])
    let resumedState = try object(try object(resumed["result"])["structuredContent"])
    #expect(resumedState["resumed"] == .bool(true))
    #expect(resumedState["resume_token_state"] == .string("consumed"))
    #expect(resumedState["control_state"] == .string("freshly_reobserved"))
    #expect(resumedState["observation"] != nil)

    let replay = try await toolCall(
      server, id: 5, name: "browser_session",
      arguments: [
        "operation": .string("handoff_resume"), "session_id": .string(sessionID),
        "resume_token": .string(token),
      ])
    #expect(try object(replay["error"])["code"] == .int(-32602))
    #expect(presenter.requests.count == 2)
  }

  @Test("Authentication keeps the asynchronous handoff token active until the human leaves")
  func authenticationHandoffDoesNotConsumeResumeToken() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<title>Apple ID</title><form><input autocomplete='username'></form>",
      baseURL: URL(string: "https://idmsa.apple.com/IDMSWebAuth/signin?state=private")!,
      timeout: .seconds(2), quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(
      registry: registry, presentHumanWindows: false, confirmationPresenter: presenter)
    let sessionID = handle.rawValue.uuidString

    let started = try await toolCall(
      server, id: 1, name: "browser_session",
      arguments: ["operation": .string("handoff_start"), "session_id": .string(sessionID)])
    let token = try string(
      try object(try object(started["result"])["structuredContent"])["resume_token"])

    let blocked = try await toolCall(
      server, id: 2, name: "browser_session",
      arguments: [
        "operation": .string("handoff_resume"), "session_id": .string(sessionID),
        "resume_token": .string(token),
      ])
    let blockedState = try object(try object(blocked["result"])["structuredContent"])
    #expect(blockedState["status"] == .string("authentication_origin_requires_human_handoff"))
    #expect(blockedState["origin"] == .string("https://idmsa.apple.com"))
    #expect(blockedState["resumed"] == .bool(false))
    #expect(blockedState["resume_token_state"] == .string("active"))
    #expect(runtime.interactionControlState() == .humanControlled)
    #expect(presenter.requests.isEmpty)

    let polled = try await toolCall(
      server, id: 3, name: "browser_session",
      arguments: [
        "operation": .string("handoff_status"), "session_id": .string(sessionID),
        "resume_token": .string(token),
      ])
    #expect(
      try object(try object(polled["result"])["structuredContent"])["resume_token_state"]
        == .string("active"))
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

  @Test("The SiliconPass rotation tool is secretless and never commits the form")
  func siliconPassRotationShim() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      """
      <form>
        <input id='current' type='password' autocomplete='current-password'>
        <input id='next' type='password' autocomplete='new-password'>
        <input id='confirmation' type='password' autocomplete='new-password'>
        <button type='submit'>Change</button>
      </form>
      <script>
        globalThis.submitCount = 0;
        document.querySelector('form').addEventListener('submit', event => {
          globalThis.submitCount += 1; event.preventDefault();
        });
      </script>
      """,
      baseURL: URL(string: "https://fixture.invalid/settings/password"),
      timeout: .seconds(2),
      quietWindow: .milliseconds(40)
    )
    let server = WebKitMCPServer(
      registry: registry,
      credentialBroker: InProcessSyntheticBrokerStub()
    )
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)]
    )
    let observation = try object(try object(observed["result"])["structuredContent"])
    let response = try await toolCall(
      server, id: 2, name: "browser_rotate_siliconpass_password",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": .string(try string(observation["observationID"])),
        "current_password_element_id": .string("e1"),
        "new_password_element_id": .string("e2"),
        "confirmation_element_id": .string("e3"),
      ]
    )
    let structured = try object(try object(response["result"])["structuredContent"])
    #expect(structured["status"] == .string("changed"))
    #expect(structured["secret_released_to_mcp"] == .bool(false))
    #expect(structured["submitted"] == .bool(false))
    let wire = String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
    #expect(!wire.contains(InProcessSyntheticBrokerStub.password))
    #expect(!wire.contains(InProcessSyntheticBrokerStub.rotatedPassword))
    let page = try #require(
      await runtime.webView.evaluateJavaScript(
        "JSON.stringify([current.value,next.value,confirmation.value,globalThis.submitCount])"
      ) as? String
    )
    #expect(
      page
        == "[\"\(InProcessSyntheticBrokerStub.password)\",\"\(InProcessSyntheticBrokerStub.rotatedPassword)\",\"\(InProcessSyntheticBrokerStub.rotatedPassword)\",0]"
    )
  }

  @Test("A missing SiliconPass credential requests only a human handoff")
  func siliconPassCredentialNotFound() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      """
      <label for='username'>Username</label><input id='username'>
      <label for='password'>Password</label><input id='password' type='password'>
      """,
      baseURL: URL(string: "https://fixture.invalid/login"),
      timeout: .seconds(2),
      quietWindow: .milliseconds(40)
    )
    let server = WebKitMCPServer(
      registry: registry,
      presentHumanWindows: false,
      credentialBroker: FixedStatusCredentialBrokerStub(status: .credentialNotFound),
      confirmationPresenter: ConfirmationPresenterStub(responses: [true])
    )
    let observed = try await toolCall(
      server,
      id: 1,
      name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)]
    )
    let observation = try object(try object(observed["result"])["structuredContent"])
    let response = try await toolCall(
      server,
      id: 2,
      name: "browser_fill_siliconpass",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": .string(try string(observation["observationID"])),
        "username_element_id": .string("e1"),
        "password_element_id": .string("e2"),
      ]
    )
    let result = try object(try object(response["result"])["structuredContent"])
    #expect(result["status"] == .string("credential_not_found"))
    #expect(result["add_offered"] == .bool(true))
    #expect(result["human_handoff_started"] == .bool(true))
    #expect(result["control_state"] == .string("human_controlled"))
    let fieldValues =
      try await runtime.webView.evaluateJavaScript(
        "JSON.stringify([username.value,password.value])") as? String
    #expect(fieldValues == "[\"\",\"\"]")
  }

  @Test("Unavailable Mac user presence returns explicit retry guidance")
  func siliconPassUserPresenceUnavailable() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      """
      <form>
        <input id='username' autocomplete='username'>
        <input id='password' type='password' autocomplete='current-password'>
      </form>
      """,
      baseURL: URL(string: "https://fixture.invalid/login"),
      timeout: .seconds(2),
      quietWindow: .milliseconds(40)
    )
    let server = WebKitMCPServer(
      registry: registry,
      credentialBroker: FixedStatusCredentialBrokerStub(status: .userPresenceUnavailable)
    )
    let observed = try await toolCall(
      server,
      id: 1,
      name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)]
    )
    let observation = try object(try object(observed["result"])["structuredContent"])
    let response = try await toolCall(
      server,
      id: 2,
      name: "browser_fill_siliconpass",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": .string(try string(observation["observationID"])),
        "username_element_id": .string("e1"),
        "password_element_id": .string("e2"),
      ]
    )
    let result = try object(try object(response["result"])["structuredContent"])
    #expect(result["status"] == .string("user_presence_unavailable"))
    #expect(result["requires_user_presence"] == .bool(true))
    #expect(result["retryable"] == .bool(true))
    #expect(result["automatic_retry"] == .bool(false))
    #expect(result["secret_released"] == .bool(false))
    #expect(result["authentication_policy"] == .string("device_owner_authentication"))
    #expect(
      result["accepted_methods"]
        == .array([
          .string("system_device_owner_authentication")
        ]))
    #expect(
      result["recovery"]
        == .string(
          "Unlock this Mac and retry from an interactive session using the authentication method offered by macOS. Closed-lid availability is device-specific and is not inferred."
        ))
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
