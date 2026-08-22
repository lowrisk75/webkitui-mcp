import Foundation
import Testing
import WebKitUIMCPCore
import WebKitUIMCPRuntime

@testable import WebKitUIMCPServer

@MainActor
private final class AuthorizationConfirmationStub: BrowserConfirmationPresenting {
  private(set) var requests: [(String, String, String)] = []
  private let response: Bool

  init(response: Bool) { self.response = response }

  func confirm(title: String, message: String, approveLabel: String) -> Bool {
    requests.append((title, message, approveLabel))
    return response
  }
}

@Suite("Scoped session authorization", .serialized)
@MainActor
struct SessionAuthorizationStoreTests {
  @Test("Grants are exact-origin, quota-bound, expiring, revocable, and session-isolated")
  func grantBoundary() throws {
    let store = SessionAuthorizationStore()
    let first = WebKitSessionHandle(rawValue: UUID())
    let second = WebKitSessionHandle(rawValue: UUID())
    let origin = SecurityOrigin(scheme: "https", host: "example.test")
    let otherPort = SecurityOrigin(scheme: "https", host: "example.test", port: 8443)
    let now = Date(timeIntervalSince1970: 1_000)

    try store.grant(
      session: first,
      origin: origin,
      actions: [.navigate],
      expiresAt: now.addingTimeInterval(60),
      maximumUses: 2,
      now: now)

    #expect(store.consume(session: second, origin: origin, action: .navigate, now: now) == .denied)
    #expect(
      store.consume(session: first, origin: otherPort, action: .navigate, now: now) == .denied)
    #expect(
      store.consume(session: first, origin: origin, action: .navigate, now: now)
        == .allowed(remainingUses: 1))
    #expect(
      store.consume(session: first, origin: origin, action: .navigate, now: now)
        == .allowed(remainingUses: 0))
    #expect(store.consume(session: first, origin: origin, action: .navigate, now: now) == .denied)

    try store.grant(
      session: first,
      origin: origin,
      actions: [.navigate],
      expiresAt: now.addingTimeInterval(1),
      maximumUses: 1,
      now: now)
    #expect(store.activeGrants(session: first, now: now.addingTimeInterval(2)).isEmpty)

    try store.grant(
      session: first,
      origin: origin,
      actions: [.navigate],
      expiresAt: now.addingTimeInterval(60),
      maximumUses: 1,
      now: now)
    store.revoke(session: first)
    #expect(store.activeGrants(session: first, now: now).isEmpty)
  }

  @Test("Wire grants require exact confirmation and remain navigation-only")
  func wireGrant() async throws {
    let registry = try WebKitSessionRegistry(maximumSessions: 2)
    let first = try registry.open()
    let second = try registry.open()
    let server = WebKitMCPServer(registry: registry)
    let grantArguments: [String: JSONValue] = [
      "operation": .string("grant"),
      "session_id": .string(first.rawValue.uuidString),
      "origin": .string("https://example.test"),
      "actions": .array([.string("navigate")]),
      "ttl_seconds": .int(300),
      "maximum_uses": .int(2),
    ]

    let prepared = try await toolCall(
      server, id: 1, name: "browser_authorization", arguments: grantArguments)
    let required = try object(prepared["result"])
    #expect(required["resultType"] == .string("input_required"))
    let granted = try await roundTripToolCall(
      server,
      id: 2,
      name: "browser_authorization",
      arguments: grantArguments,
      requestState: try string(required["requestState"]),
      action: "accept",
      confirm: true)
    let grant = try object(try object(granted["result"])["structuredContent"])
    #expect(grant["authorized"] == .bool(true))
    #expect(grant["mode"] == .string("trusted_session"))

    let status = try await toolCall(
      server,
      id: 3,
      name: "browser_authorization",
      arguments: [
        "operation": .string("status"),
        "session_id": .string(first.rawValue.uuidString),
      ])
    let statusBody = try object(try object(status["result"])["structuredContent"])
    #expect(try array(statusBody["grants"]).count == 1)
    #expect(statusBody["mode"] == .string("trusted_session"))

    let trusted = try await toolCall(
      server,
      id: 4,
      name: "browser_navigate",
      arguments: [
        "session_id": .string(first.rawValue.uuidString),
        "url": .string("https://example.test/trusted"),
        "timeout_ms": .int(100),
        "quiet_window_ms": .int(20),
      ])
    #expect(try object(trusted["result"])["resultType"] != .string("input_required"))

    let isolated = try await toolCall(
      server,
      id: 5,
      name: "browser_navigate",
      arguments: [
        "session_id": .string(second.rawValue.uuidString),
        "url": .string("https://example.test/isolated"),
      ])
    #expect(try object(isolated["result"])["resultType"] == .string("input_required"))

    let otherOrigin = try await toolCall(
      server,
      id: 6,
      name: "browser_navigate",
      arguments: [
        "session_id": .string(first.rawValue.uuidString),
        "url": .string("https://other.example.test/isolated"),
      ])
    #expect(try object(otherOrigin["result"])["resultType"] == .string("input_required"))

    let rejectedClickGrant = try await toolCall(
      server,
      id: 7,
      name: "browser_authorization",
      arguments: [
        "operation": .string("grant"),
        "session_id": .string(first.rawValue.uuidString),
        "origin": .string("https://example.test"),
        "actions": .array([.string("click")]),
      ])
    #expect(try object(rejectedClickGrant["error"])["code"] == .int(-32602))

    let revoked = try await toolCall(
      server,
      id: 8,
      name: "browser_authorization",
      arguments: [
        "operation": .string("revoke"),
        "session_id": .string(first.rawValue.uuidString),
        "origin": .string("https://example.test"),
      ])
    #expect(
      try object(try object(revoked["result"])["structuredContent"])["revoked"] == .bool(true))
  }

  @Test("Grant origins reject downgrade, paths, credentials, local names, and noncanonical hosts")
  func originValidation() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let server = WebKitMCPServer(registry: registry)
    for origin in [
      "http://example.test", "https://example.test/path", "https://user@example.test",
      "https://localhost", "https://service.local", "https://example.test./",
    ] {
      let response = try await toolCall(
        server,
        id: 1,
        name: "browser_authorization",
        arguments: [
          "operation": .string("grant"),
          "session_id": .string(handle.rawValue.uuidString),
          "origin": .string(origin),
          "actions": .array([.string("navigate")]),
        ])
      #expect(try object(response["error"])["code"] == .int(-32602))
    }
  }

  @Test("Authorization state is exact-argument-bound and single-use")
  func confirmationBinding() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let server = WebKitMCPServer(registry: registry)
    let arguments: [String: JSONValue] = [
      "operation": .string("grant"),
      "session_id": .string(handle.rawValue.uuidString),
      "origin": .string("https://example.test"),
      "actions": .array([.string("navigate")]),
      "maximum_uses": .int(2),
    ]
    let prepared = try await toolCall(
      server, id: 1, name: "browser_authorization", arguments: arguments)
    let requestState = try string(try object(prepared["result"])["requestState"])
    var changed = arguments
    changed["maximum_uses"] = .int(3)
    let mutation = try await roundTripToolCall(
      server,
      id: 2,
      name: "browser_authorization",
      arguments: changed,
      requestState: requestState,
      action: "accept",
      confirm: true)
    #expect(try object(mutation["error"])["code"] == .int(-32602))
    let replay = try await roundTripToolCall(
      server,
      id: 3,
      name: "browser_authorization",
      arguments: arguments,
      requestState: requestState,
      action: "accept",
      confirm: true)
    #expect(try object(replay["error"])["code"] == .int(-32602))
  }

  @Test("Legacy clients receive the same server-owned grant confirmation")
  func legacyConfirmation() async throws {
    let registry = try WebKitSessionRegistry()
    let handle = try registry.open()
    let presenter = AuthorizationConfirmationStub(response: true)
    let server = WebKitMCPServer(
      registry: registry,
      confirmationPresenter: presenter)
    let result = try await legacyToolCall(
      server,
      id: 1,
      name: "browser_authorization",
      arguments: [
        "operation": .string("grant"),
        "session_id": .string(handle.rawValue.uuidString),
        "origin": .string("https://example.test"),
        "actions": .array([.string("navigate")]),
        "ttl_seconds": .int(60),
        "maximum_uses": .int(1),
      ])
    #expect(
      try object(try object(result["result"])["structuredContent"])["authorized"] == .bool(true))
    #expect(presenter.requests.count == 1)
    #expect(presenter.requests.first?.0 == "Authorize Trusted Session Origin")
    #expect(presenter.requests.first?.1.contains("example.test") == true)
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
      params: .object(["name": .string(name), "arguments": .object(arguments)]))
  }

  private func roundTripToolCall(
    _ server: WebKitMCPServer,
    id: Int64,
    name: String,
    arguments: [String: JSONValue],
    requestState: String,
    action: String,
    confirm: Bool
  ) async throws -> [String: JSONValue] {
    try await call(
      server,
      id: id,
      params: .object([
        "name": .string(name),
        "arguments": .object(arguments),
        "requestState": .string(requestState),
        "inputResponses": .object([
          "confirmation": .object([
            "action": .string(action), "content": .object(["confirm": .bool(confirm)]),
          ])
        ]),
      ]))
  }

  private func legacyToolCall(
    _ server: WebKitMCPServer,
    id: Int64,
    name: String,
    arguments: [String: JSONValue]
  ) async throws -> [String: JSONValue] {
    let request: JSONValue = .object([
      "jsonrpc": .string("2.0"),
      "id": .int(id),
      "method": .string("tools/call"),
      "params": .object(["name": .string(name), "arguments": .object(arguments)]),
    ])
    guard let data = await server.handle(try JSONEncoder().encode(request)) else {
      throw TestError.missingResponse
    }
    return try object(try JSONDecoder().decode(JSONValue.self, from: data))
  }

  private func call(
    _ server: WebKitMCPServer,
    id: Int64,
    params: JSONValue
  ) async throws -> [String: JSONValue] {
    var parameterObject = try object(params)
    parameterObject["_meta"] = .object([
      "io.modelcontextprotocol/protocolVersion": .string("2026-07-28"),
      "io.modelcontextprotocol/clientInfo": .object([
        "name": .string("authorization-tests"), "version": .string("1"),
      ]),
      "io.modelcontextprotocol/clientCapabilities": .object([
        "elicitation": .object([:])
      ]),
    ])
    let request: JSONValue = .object([
      "jsonrpc": .string("2.0"),
      "id": .int(id),
      "method": .string("tools/call"),
      "params": .object(parameterObject),
    ])
    guard let data = await server.handle(try JSONEncoder().encode(request)) else {
      throw TestError.missingResponse
    }
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
