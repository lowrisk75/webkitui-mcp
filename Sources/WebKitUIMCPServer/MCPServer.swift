import Darwin
import Foundation
import WebKitUIMCPCore
import WebKitUIMCPRuntime

private struct RPCRequest: Decodable {
  let jsonrpc: String
  let id: JSONValue?
  let method: String
  let params: JSONValue?
}

private enum MCPServerError: Error {
  case invalidParams(String)
  case missingRequiredClientCapability
  case unsupportedProtocolVersion(String)
}

@MainActor
public final class WebKitMCPServer {
  public static let version = "0.4.0"
  public static let protocolVersion = "2026-07-28"
  public static let legacyProtocolVersion = "2025-11-25"

  private let registry: WebKitSessionRegistry
  private let presentHumanWindows: Bool
  private let credentialBroker: any CredentialBrokerFilling
  private let confirmationPresenter: any BrowserConfirmationPresenting
  private let capabilityAuthority = CapabilityAuthority()
  private let sessionAuthorizations = SessionAuthorizationStore()
  private var observations: [WebKitSessionHandle: WebKitPageObservation] = [:]
  private var coordinators: [WebKitSessionHandle: WebKitTransactionCoordinator] = [:]
  private var pendingActuations: [String: PendingActuation] = [:]
  private var pendingHandoffs: [String: PendingHandoff] = [:]
  private var pendingNavigations: [String: PendingNavigation] = [:]
  private var pendingAuthorizations: [String: PendingAuthorization] = [:]

  private enum ActPostcondition {
    case urlEquals(String)
    case semanticTextAppears(String)

    var confirmationDescription: String {
      switch self {
      case .urlEquals(let value): "URL equals \(value)"
      case .semanticTextAppears(let value): "new semantic text appears: \(value)"
      }
    }

    var predicate: ObservationPredicate {
      switch self {
      case .urlEquals(let value):
        .entryTextDigest(
          .init(frameID: "main", elementID: "@page", field: "url"),
          ObservationPredicate.textDigest(of: value)
        )
      case .semanticTextAppears(let value):
        .anyEntryTextDigest(
          [.accessibleName, .label, .text, .value],
          ObservationPredicate.textDigest(of: value)
        )
      }
    }
  }

  private enum ActOperation {
    case click
    case submit
    case fill(String)

    var name: String {
      switch self {
      case .click: "click"
      case .submit: "submit"
      case .fill: "fill"
      }
    }

    var capability: BrowserCapability {
      switch self {
      case .click: .activateElement
      case .submit: .submitForm
      case .fill: .fillForm
      }
    }

    var inputProvenance: Set<ProvenanceClass> {
      switch self {
      case .fill: [.modelGenerated]
      case .click, .submit: []
      }
    }
  }

  private struct PendingActuation {
    let arguments: [String: JSONValue]
    let session: WebKitSessionHandle
    let observation: WebKitPageObservation
    let elementID: String
    let operation: ActOperation
    let idempotencyKey: String
    let postcondition: ActPostcondition?
    let expiresAt: Date
  }

  private struct PendingHandoff {
    let arguments: [String: JSONValue]
    let session: WebKitSessionHandle
    let expiresAt: Date
  }

  private struct PendingNavigation {
    let arguments: [String: JSONValue]
    let session: WebKitSessionHandle
    let url: URL
    let timeoutMilliseconds: Int64
    let quietWindowMilliseconds: Int64
    let expiresAt: Date
  }

  private struct PendingAuthorization {
    let arguments: [String: JSONValue]
    let session: WebKitSessionHandle
    let origin: SecurityOrigin
    let actions: Set<SessionAuthorizationAction>
    let expiresAt: Date
    let maximumUses: Int
    let confirmationExpiresAt: Date
  }

  public init(maximumSessions: Int = 1, enforceHostExclusiveSession: Bool = false) throws {
    self.registry = try WebKitSessionRegistry(
      maximumSessions: maximumSessions,
      enforceHostExclusiveSession: enforceHostExclusiveSession)
    self.presentHumanWindows = true
    self.credentialBroker = SyntheticCredentialBrokerXPCClient()
    self.confirmationPresenter = NativeBrowserConfirmationPresenter()
  }

  init(
    registry: WebKitSessionRegistry,
    presentHumanWindows: Bool = false,
    credentialBroker: any CredentialBrokerFilling = SyntheticCredentialBrokerXPCClient(),
    confirmationPresenter: any BrowserConfirmationPresenting =
      NativeBrowserConfirmationPresenter()
  ) {
    self.registry = registry
    self.presentHumanWindows = presentHumanWindows
    self.credentialBroker = credentialBroker
    self.confirmationPresenter = confirmationPresenter
  }

  public func handle(_ input: Data) async -> Data? {
    let request: RPCRequest
    do {
      request = try JSONDecoder().decode(RPCRequest.self, from: input)
    } catch {
      return encode(errorResponse(id: nil, code: -32700, message: "Parse error"))
    }

    guard request.jsonrpc == "2.0" else {
      return encode(
        errorResponse(id: request.id ?? .null, code: -32600, message: "Invalid request"))
    }
    if request.id == nil {
      return nil
    }

    let modern: Bool
    do {
      modern = try isModern(request)
    } catch let error {
      switch error {
      case .invalidParams(let detail):
        return encode(errorResponse(id: request.id ?? .null, code: -32602, message: detail))
      case .unsupportedProtocolVersion(let requested):
        return encode(
          errorResponse(
            id: request.id ?? .null,
            code: -32022,
            message: "Unsupported protocol version",
            data: .object([
              "supported": .array([.string(Self.protocolVersion)]),
              "requested": .string(requested),
            ])
          ))
      case .missingRequiredClientCapability:
        return encode(
          errorResponse(
            id: request.id ?? .null,
            code: -32021,
            message: "Missing required client capability",
            data: .object([
              "requiredCapabilities": .object(["elicitation": .object([:])])
            ])
          ))
      }
    }
    let result: JSONValue
    do {
      switch request.method {
      case "server/discover":
        result = discoverResult()
      case "initialize":
        result = legacyInitializeResult(request.params)
      case "tools/list":
        result = toolsListResult(modern: modern)
      case "tools/call":
        result = try await callTool(params: request.params, modern: modern)
      case "ping":
        guard !modern else {
          return encode(
            errorResponse(id: request.id ?? .null, code: -32601, message: "Method not found"))
        }
        result = .object([:])
      default:
        return encode(
          errorResponse(id: request.id ?? .null, code: -32601, message: "Method not found")
        )
      }
    } catch let error as MCPServerError {
      let message: String
      switch error {
      case .invalidParams(let detail): message = detail
      case .missingRequiredClientCapability:
        return encode(
          errorResponse(
            id: request.id ?? .null,
            code: -32021,
            message: "Missing required client capability",
            data: .object([
              "requiredCapabilities": .object(["elicitation": .object([:])])
            ])
          ))
      case .unsupportedProtocolVersion(let requested):
        return encode(
          errorResponse(
            id: request.id ?? .null,
            code: -32022,
            message: "Unsupported protocol version",
            data: .object([
              "supported": .array([.string(Self.protocolVersion)]),
              "requested": .string(requested),
            ])
          ))
      }
      return encode(errorResponse(id: request.id ?? .null, code: -32602, message: message))
    } catch {
      return encode(
        errorResponse(
          id: request.id ?? .null,
          code: -32603,
          message: "Internal error",
          data: .object(["type": .string(String(describing: type(of: error)))])
        )
      )
    }

    return encode(successResponse(id: request.id ?? .null, result: result, modern: modern))
  }

  private func callTool(params: JSONValue?, modern: Bool) async throws -> JSONValue {
    let params = try requireObject(params, named: "params")
    let name = try requireString(params["name"], named: "name")
    let arguments = params["arguments"]?.objectValue ?? [:]

    do {
      switch name {
      case "browser_session":
        return try await sessionTool(params: params, arguments: arguments, modern: modern)
      case "browser_navigate":
        return try await navigateTool(params: params, arguments: arguments, modern: modern)
      case "browser_authorization":
        return try await authorizationTool(params: params, arguments: arguments, modern: modern)
      case "browser_observe":
        let handle = try sessionHandle(arguments)
        let runtime = try registry.runtime(for: handle)
        let maximum = try boundedInteger(
          arguments["maximum_elements"],
          defaultValue: 500,
          range: 1...2_000,
          name: "maximum_elements"
        )
        let observation = try await runtime.observe(maximumElements: maximum)
        observations[handle] = observation
        return try toolResult(structured: .encoded(observation), modern: modern)
      case "browser_act":
        return try await actTool(
          params: params,
          arguments: arguments,
          modern: modern
        )
      case "browser_capture":
        let runtime = try registry.runtime(for: sessionHandle(arguments))
        let capture = try await runtime.capture()
        var result: [String: JSONValue] = [
          "content": .array([
            .object([
              "type": .string("image"),
              "data": .string(capture.pngData.base64EncodedString()),
              "mimeType": .string("image/png"),
            ])
          ]),
          "structuredContent": .object([
            "width": .int(Int64(capture.width)),
            "height": .int(Int64(capture.height)),
            "backing_scale_factor": .double(capture.backingScaleFactor),
            "compositor_effects_may_be_missing": .bool(
              capture.compositorEffectsMayBeMissing
            ),
          ]),
        ]
        if modern { result["resultType"] = .string("complete") }
        return .object(result)
      case "browser_fill_siliconpass":
        return try await credentialFillTool(arguments: arguments, modern: modern)
      case "browser_transaction":
        let handle = try sessionHandle(arguments)
        guard let coordinator = coordinators[handle] else {
          throw MCPServerError.invalidParams("session has no transaction ledger")
        }
        let key = try requireString(arguments["idempotency_key"], named: "idempotency_key")
        let operation = arguments["operation"]?.stringValue ?? "receipt"
        switch operation {
        case "receipt":
          return try toolResult(
            structured: .encoded(try await coordinator.receipt(idempotencyKey: key)),
            modern: modern)
        case "reconcile":
          return try toolResult(
            structured: .encoded(try await coordinator.reconcile(idempotencyKey: key)),
            modern: modern)
        default:
          throw MCPServerError.invalidParams("operation must be receipt or reconcile")
        }
      default:
        return try toolError("Unknown tool: \(name)", modern: modern)
      }
    } catch let error as MCPServerError {
      throw error
    } catch {
      return try toolError(String(describing: error), modern: modern)
    }
  }

  private func sessionTool(
    params: [String: JSONValue], arguments: [String: JSONValue], modern: Bool
  ) async throws -> JSONValue {
    let operation = try requireString(arguments["operation"], named: "operation")
    switch operation {
    case "open":
      guard arguments.keys.allSatisfy({ $0 == "operation" }) else {
        throw MCPServerError.invalidParams("open accepts only operation")
      }
      let handle = try registry.open()
      coordinators[handle] = WebKitTransactionCoordinator(
        runtime: try registry.runtime(for: handle))
      return try toolResult(
        structured: .object([
          "session_id": .string(handle.rawValue.uuidString),
          "maximum_sessions": .int(Int64(registry.maximumSessions)),
        ]), modern: modern)
    case "status":
      return try toolResult(
        structured: .encoded(try registry.status(sessionHandle(arguments))), modern: modern)
    case "close":
      let handle = try sessionHandle(arguments)
      try registry.close(handle)
      observations.removeValue(forKey: handle)
      coordinators.removeValue(forKey: handle)
      pendingActuations = pendingActuations.filter { $0.value.session != handle }
      pendingHandoffs = pendingHandoffs.filter { $0.value.session != handle }
      pendingNavigations = pendingNavigations.filter { $0.value.session != handle }
      pendingAuthorizations = pendingAuthorizations.filter { $0.value.session != handle }
      sessionAuthorizations.revoke(session: handle)
      return try toolResult(structured: .object(["closed": .bool(true)]), modern: modern)
    case "handoff":
      return try await handoffTool(params: params, arguments: arguments, modern: modern)
    default:
      throw MCPServerError.invalidParams("operation must be open, status, close, or handoff")
    }
  }

  private func navigateTool(
    params: [String: JSONValue], arguments: [String: JSONValue], modern: Bool
  ) async throws -> JSONValue {
    let handle = try sessionHandle(arguments)
    let runtime = try registry.runtime(for: handle)
    let url = try safeNavigationURL(try requireString(arguments["url"], named: "url"))
    let timeout = try boundedMilliseconds(
      arguments["timeout_ms"], defaultValue: 30_000, range: 100...120_000, name: "timeout_ms")
    let quiet = try boundedMilliseconds(
      arguments["quiet_window_ms"], defaultValue: 300, range: 20...5_000,
      name: "quiet_window_ms")

    if modern, let requestState = params["requestState"]?.stringValue {
      guard let pending = pendingNavigations.removeValue(forKey: requestState) else {
        throw MCPServerError.invalidParams("requestState is unknown or already used")
      }
      guard pending.expiresAt > Date(), pending.arguments == arguments else {
        throw MCPServerError.invalidParams("navigation confirmation expired or arguments changed")
      }
      guard acceptedConfirmation(params["inputResponses"]) else {
        return try toolError("The user did not approve this navigation", modern: true)
      }
      return try await executeNavigation(pending, runtime: runtime, modern: true)
    }

    guard params["inputResponses"] == nil else {
      throw MCPServerError.invalidParams("inputResponses requires requestState")
    }
    guard params["requestState"] == nil else {
      throw MCPServerError.invalidParams("requestState is unavailable without MCP 2026-07-28")
    }
    let pending = PendingNavigation(
      arguments: arguments,
      session: handle,
      url: url,
      timeoutMilliseconds: timeout,
      quietWindowMilliseconds: quiet,
      expiresAt: Date().addingTimeInterval(60)
    )
    let destinationOrigin = try securityOrigin(for: url)
    if case .allowed(let remainingUses) = sessionAuthorizations.consume(
      session: handle,
      origin: destinationOrigin,
      action: .navigate
    ) {
      return try await executeNavigation(
        pending,
        runtime: runtime,
        modern: modern,
        authorization: .object([
          "mode": .string("trusted_session"),
          "origin": .string(SessionAuthorizationStore.originString(destinationOrigin)),
          "remaining_uses": .int(Int64(remainingUses)),
        ])
      )
    }
    if modern {
      try requireFormElicitationCapability(params)
    }
    if !modern {
      let currentURL = runtime.webView.url?.absoluteString ?? "no current page"
      guard
        confirmationPresenter.confirm(
          title: "Approve Web Navigation",
          message: navigationConfirmationMessage(currentURL: currentURL, url: url),
          approveLabel: "Navigate"
        )
      else {
        return try toolError("The user did not approve this navigation", modern: false)
      }
      return try await executeNavigation(pending, runtime: runtime, modern: false)
    }
    pendingNavigations = pendingNavigations.filter {
      $0.value.expiresAt > Date() && $0.value.session != handle
    }
    let requestState = UUID().uuidString
    pendingNavigations[requestState] = pending
    let currentURL = runtime.webView.url?.absoluteString ?? "no current page"
    return .object([
      "resultType": .string("input_required"),
      "requestState": .string(requestState),
      "inputRequests": .object([
        "confirmation": .object([
          "method": .string("elicitation/create"),
          "params": .object([
            "mode": .string("form"),
            "message": .string(navigationConfirmationMessage(currentURL: currentURL, url: url)),
            "requestedSchema": .object([
              "type": .string("object"),
              "properties": .object([
                "confirm": .object([
                  "type": .string("boolean"),
                  "title": .string("Approve this exact navigation"),
                ])
              ]),
              "required": .array([.string("confirm")]),
            ]),
          ]),
        ])
      ]),
    ])
  }

  private func authorizationTool(
    params: [String: JSONValue], arguments: [String: JSONValue], modern: Bool
  ) async throws -> JSONValue {
    let operation = try requireString(arguments["operation"], named: "operation")
    let handle = try sessionHandle(arguments)
    switch operation {
    case "status":
      guard params["requestState"] == nil, params["inputResponses"] == nil else {
        throw MCPServerError.invalidParams("authorization status is not multi-round")
      }
      guard Set(arguments.keys) == Set(["operation", "session_id"]) else {
        throw MCPServerError.invalidParams(
          "authorization status accepts only operation and session_id")
      }
      let grants = sessionAuthorizations.activeGrants(session: handle).map { grant in
        JSONValue.object([
          "origin": .string(SessionAuthorizationStore.originString(grant.origin)),
          "actions": .array(
            grant.actions.sorted { $0.rawValue < $1.rawValue }.map {
              .string($0.rawValue)
            }),
          "expires_at": .string(ISO8601DateFormatter().string(from: grant.expiresAt)),
          "remaining_uses": .int(Int64(grant.remainingUses)),
        ])
      }
      return try toolResult(
        structured: .object([
          "mode": .string(grants.isEmpty ? "strict" : "trusted_session"),
          "grants": .array(grants),
        ]),
        modern: modern)
    case "revoke":
      guard params["requestState"] == nil, params["inputResponses"] == nil else {
        throw MCPServerError.invalidParams("authorization revoke is not multi-round")
      }
      let allowedKeys = Set(["operation", "session_id", "origin"])
      guard Set(arguments.keys).isSubset(of: allowedKeys) else {
        throw MCPServerError.invalidParams("authorization revoke has unsupported fields")
      }
      let origin = try arguments["origin"].map {
        try authorizationOrigin(try requireString($0, named: "origin"))
      }
      sessionAuthorizations.revoke(session: handle, origin: origin)
      return try toolResult(
        structured: .object([
          "revoked": .bool(true),
          "scope": .string(origin == nil ? "session" : "origin"),
        ]), modern: modern)
    case "grant":
      let allowedKeys = Set([
        "operation", "session_id", "origin", "actions", "ttl_seconds", "maximum_uses",
      ])
      guard Set(arguments.keys).isSubset(of: allowedKeys) else {
        throw MCPServerError.invalidParams("authorization grant has unsupported fields")
      }
      let origin = try authorizationOrigin(try requireString(arguments["origin"], named: "origin"))
      let actions = try authorizationActions(arguments["actions"])
      let ttl = try boundedInteger(
        arguments["ttl_seconds"], defaultValue: 900, range: 60...3_600, name: "ttl_seconds")
      let maximumUses = try boundedInteger(
        arguments["maximum_uses"], defaultValue: 20, range: 1...100, name: "maximum_uses")

      if modern, let requestState = params["requestState"]?.stringValue {
        guard let pending = pendingAuthorizations.removeValue(forKey: requestState) else {
          throw MCPServerError.invalidParams("requestState is unknown or already used")
        }
        guard pending.confirmationExpiresAt > Date(), pending.arguments == arguments else {
          throw MCPServerError.invalidParams(
            "authorization confirmation expired or arguments changed")
        }
        guard acceptedConfirmation(params["inputResponses"]) else {
          return try toolError("The user did not approve this session authorization", modern: true)
        }
        return try installAuthorization(pending, modern: true)
      }
      guard params["inputResponses"] == nil else {
        throw MCPServerError.invalidParams("inputResponses requires requestState")
      }
      let pending = PendingAuthorization(
        arguments: arguments,
        session: handle,
        origin: origin,
        actions: actions,
        expiresAt: Date().addingTimeInterval(TimeInterval(ttl)),
        maximumUses: maximumUses,
        confirmationExpiresAt: Date().addingTimeInterval(60)
      )
      let message = authorizationConfirmationMessage(pending)
      if !modern {
        guard
          confirmationPresenter.confirm(
            title: "Authorize Trusted Session Origin",
            message: message,
            approveLabel: "Trust Temporarily"
          )
        else {
          return try toolError("The user did not approve this session authorization", modern: false)
        }
        return try installAuthorization(pending, modern: false)
      }
      try requireFormElicitationCapability(params)
      pendingAuthorizations = pendingAuthorizations.filter {
        $0.value.confirmationExpiresAt > Date() && $0.value.session != handle
      }
      let requestState = UUID().uuidString
      pendingAuthorizations[requestState] = pending
      return .object([
        "resultType": .string("input_required"),
        "requestState": .string(requestState),
        "inputRequests": .object([
          "confirmation": .object([
            "method": .string("elicitation/create"),
            "params": .object([
              "mode": .string("form"),
              "message": .string(message),
              "requestedSchema": .object([
                "type": .string("object"),
                "properties": .object([
                  "confirm": .object([
                    "type": .string("boolean"),
                    "title": .string("Trust this exact origin for this session"),
                  ])
                ]),
                "required": .array([.string("confirm")]),
              ]),
            ]),
          ])
        ]),
      ])
    default:
      throw MCPServerError.invalidParams("authorization operation must be grant, status, or revoke")
    }
  }

  private func credentialFillTool(
    arguments: [String: JSONValue],
    modern: Bool
  ) async throws -> JSONValue {
    let allowedKeys = Set([
      "session_id", "observation_id", "username_element_id", "password_element_id",
    ])
    guard Set(arguments.keys).isSubset(of: allowedKeys) else {
      throw MCPServerError.invalidParams(
        "browser_fill_siliconpass accepts only secretless target identifiers"
      )
    }
    let handle = try sessionHandle(arguments)
    let observationID = try requireString(
      arguments["observation_id"], named: "observation_id")
    guard observations[handle]?.observationID == observationID else {
      throw MCPServerError.invalidParams("Call browser_observe and use its fresh observation_id")
    }
    let runtime = try registry.runtime(for: handle)
    let binding = try runtime.credentialFormBinding(
      observationID: observationID,
      usernameElementID: try requireString(
        arguments["username_element_id"], named: "username_element_id"),
      passwordElementID: try requireString(
        arguments["password_element_id"], named: "password_element_id")
    )
    let status: CredentialBrokerWireStatus
    do {
      status = try await credentialBroker.fill(binding: binding, runtime: runtime).status
    } catch {
      status = .failed
    }
    return try toolResult(
      structured: .object(["status": .string(status.rawValue)]),
      modern: modern
    )
  }

  private func safeNavigationURL(_ rawValue: String) throws -> URL {
    guard rawValue.utf8.count <= 8_192 else {
      throw MCPServerError.invalidParams("url must contain at most 8192 UTF-8 bytes")
    }
    guard
      let components = URLComponents(string: rawValue),
      let scheme = components.scheme?.lowercased(),
      ["http", "https"].contains(scheme),
      components.user == nil,
      components.password == nil,
      let url = components.url,
      let rawHost = url.host
    else {
      throw MCPServerError.invalidParams(
        "url must be absolute HTTP(S) without embedded credentials")
    }
    let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    var ipv4Address = in_addr()
    let isIPv4Literal = inet_aton(host, &ipv4Address) != 0
    let isIPv6Literal = host.contains(":")
    guard
      host != "localhost",
      !host.hasSuffix(".localhost"),
      !host.hasSuffix(".local"),
      !isIPv4Literal,
      !isIPv6Literal
    else {
      throw MCPServerError.invalidParams("local and IP-literal navigation targets are blocked")
    }
    return url
  }

  private func handoffTool(
    params: [String: JSONValue], arguments: [String: JSONValue], modern: Bool
  ) async throws -> JSONValue {
    if modern {
      try requireFormElicitationCapability(params)
    }
    let handle = try sessionHandle(arguments)
    let runtime = try registry.runtime(for: handle)
    if !modern {
      guard params["requestState"] == nil, params["inputResponses"] == nil else {
        throw MCPServerError.invalidParams(
          "multi-round handoff fields require MCP 2026-07-28")
      }
      switch runtime.interactionControlState() {
      case .agentControlled, .freshlyReobserved:
        try runtime.requestHumanHandoff()
        try runtime.beginHumanControl(presentWindow: presentHumanWindows)
        return try toolResult(
          structured: .object([
            "control_state": .string(runtime.interactionControlState().rawValue),
            "instructions": .string(
              "Complete login, MFA, CAPTCHA, sensitive input, and any OAuth or popup-opening click yourself in the local WebKit window. Agent-generated clicks remain untrusted. Then call browser_session operation=handoff again to request agent resume."
            ),
          ]),
          modern: false
        )
      case .humanControlled:
        guard
          confirmationPresenter.confirm(
            title: "Return Browser Control",
            message:
              "Return control of the visible WebKit session to the requesting agent? A fresh observation will be required.",
            approveLabel: "Return Control"
          )
        else {
          return try toolError(
            "Human control remains active until an explicit resume confirmation", modern: false)
        }
        try runtime.requestAgentResume()
        let observation = try await runtime.resumeAfterHumanControl()
        observations[handle] = observation
        return try toolResult(
          structured: .object([
            "control_state": .string(runtime.interactionControlState().rawValue),
            "observation": try .encoded(observation),
          ]),
          modern: false
        )
      default:
        throw MCPServerError.invalidParams("handoff transition is already in progress")
      }
    }
    if let requestState = params["requestState"]?.stringValue {
      guard let pending = pendingHandoffs.removeValue(forKey: requestState) else {
        throw MCPServerError.invalidParams("requestState is unknown or already used")
      }
      guard pending.expiresAt > Date(), pending.arguments == arguments else {
        throw MCPServerError.invalidParams("handoff confirmation expired or arguments changed")
      }
      guard acceptedConfirmation(params["inputResponses"]) else {
        return try toolError(
          "Human control remains active until an explicit resume confirmation", modern: true)
      }
      try runtime.requestAgentResume()
      let observation = try await runtime.resumeAfterHumanControl()
      observations[handle] = observation
      return try toolResult(
        structured: .object([
          "control_state": .string(runtime.interactionControlState().rawValue),
          "observation": try .encoded(observation),
        ]), modern: modern)
    }
    guard params["inputResponses"] == nil else {
      throw MCPServerError.invalidParams("inputResponses requires requestState")
    }
    switch runtime.interactionControlState() {
    case .agentControlled, .freshlyReobserved:
      try runtime.requestHumanHandoff()
      try runtime.beginHumanControl(presentWindow: presentHumanWindows)
    case .humanControlled:
      break
    default:
      throw MCPServerError.invalidParams("handoff transition is already in progress")
    }
    pendingHandoffs = pendingHandoffs.filter {
      $0.value.expiresAt > Date() && $0.value.session != handle
    }
    let requestState = UUID().uuidString
    pendingHandoffs[requestState] = PendingHandoff(
      arguments: arguments,
      session: handle,
      expiresAt: Date().addingTimeInterval(600)
    )
    return .object([
      "resultType": .string("input_required"),
      "requestState": .string(requestState),
      "inputRequests": .object([
        "confirmation": .object([
          "method": .string("elicitation/create"),
          "params": .object([
            "mode": .string("form"),
            "message": .string(
              "Human control is active in the local WebKit window. Complete login, MFA, CAPTCHA, sensitive input, and any OAuth or popup-opening click yourself. Agent-generated clicks remain untrusted. Confirm only when the agent may resume."
            ),
            "requestedSchema": .object([
              "type": .string("object"),
              "properties": .object([
                "confirm": .object([
                  "type": .string("boolean"),
                  "title": .string("Return control to the agent"),
                ])
              ]),
              "required": .array([.string("confirm")]),
            ]),
          ]),
        ])
      ]),
    ])
  }

  private func actTool(
    params: [String: JSONValue],
    arguments: [String: JSONValue],
    modern: Bool
  ) async throws -> JSONValue {
    if modern {
      try requireFormElicitationCapability(params)
    }
    let handle = try sessionHandle(arguments)
    guard let observation = observations[handle] else {
      throw MCPServerError.invalidParams("Call browser_observe before browser_act")
    }
    let runtime = try registry.runtime(for: handle)
    guard
      runtime.interactionControlState() == .agentControlled
        || runtime.interactionControlState() == .freshlyReobserved
    else { throw MCPServerError.invalidParams("human control is active") }
    let observationID = try requireString(arguments["observation_id"], named: "observation_id")
    guard observation.observationID == observationID else {
      throw MCPServerError.invalidParams("observation_id is stale")
    }
    let elementID = try requireString(arguments["element_id"], named: "element_id")
    guard let target = observation.elements.first(where: { $0.elementID == elementID }) else {
      throw MCPServerError.invalidParams("element_id is not in that observation")
    }
    let operationName = try requireString(arguments["operation"], named: "operation")
    let operation: ActOperation
    let postcondition: ActPostcondition?
    switch operationName {
    case "click":
      guard !target.submitsForm else {
        throw MCPServerError.invalidParams("Use operation=submit for a form submit control")
      }
      guard arguments["value"] == nil else {
        throw MCPServerError.invalidParams("click does not accept value")
      }
      operation = .click
      postcondition = try parseActPostcondition(arguments["postcondition"])
    case "submit":
      guard target.submitsForm else {
        throw MCPServerError.invalidParams("submit requires a native form submit control")
      }
      guard arguments["value"] == nil else {
        throw MCPServerError.invalidParams("submit does not accept value")
      }
      operation = .submit
      postcondition = try parseActPostcondition(arguments["postcondition"])
    case "fill":
      guard !target.sensitive else {
        throw MCPServerError.invalidParams("sensitive fields require local human handoff")
      }
      let tag = target.tag.segments.map(\.text).joined().lowercased()
      guard tag == "input" || tag == "textarea" else {
        throw MCPServerError.invalidParams("fill currently supports input and textarea only")
      }
      guard arguments["postcondition"] == nil else {
        throw MCPServerError.invalidParams("fill uses an exact target-value postcondition")
      }
      let value = try requireString(arguments["value"], named: "value")
      guard value.count <= 512 else {
        throw MCPServerError.invalidParams("fill value must contain at most 512 characters")
      }
      guard tag != "input" || !value.contains(where: { $0.isNewline }) else {
        throw MCPServerError.invalidParams("input fill does not accept newline characters")
      }
      operation = .fill(value)
      postcondition = nil
    default:
      throw MCPServerError.invalidParams("operation must be click, fill, or submit")
    }
    let idempotencyKey = try requireString(
      arguments["idempotency_key"], named: "idempotency_key")

    if modern, let requestState = params["requestState"]?.stringValue {
      guard let pending = pendingActuations.removeValue(forKey: requestState) else {
        throw MCPServerError.invalidParams("requestState is unknown or already used")
      }
      guard pending.expiresAt > Date() else {
        throw MCPServerError.invalidParams("requestState expired")
      }
      guard pending.arguments == arguments else {
        throw MCPServerError.invalidParams("arguments changed after confirmation")
      }
      guard acceptedConfirmation(params["inputResponses"]) else {
        return try toolError("The user did not approve this action", modern: true)
      }
      return try await executeActuation(pending, modern: modern)
    }

    guard params["inputResponses"] == nil else {
      throw MCPServerError.invalidParams("inputResponses requires requestState")
    }
    guard params["requestState"] == nil else {
      throw MCPServerError.invalidParams("requestState is unavailable without MCP 2026-07-28")
    }
    let pending = PendingActuation(
      arguments: arguments,
      session: handle,
      observation: observation,
      elementID: elementID,
      operation: operation,
      idempotencyKey: idempotencyKey,
      postcondition: postcondition,
      expiresAt: Date().addingTimeInterval(60)
    )
    let confirmationMessage = actuationConfirmationMessage(
      operation: operation,
      currentURL: observation.url.segments.first?.text ?? "unknown",
      elementID: elementID,
      label: String(
        ((target.accessibleName ?? target.label ?? target.text)?.segments.map(\.text).joined() ?? "")
          .prefix(120)),
      postcondition: postcondition
    )
    if !modern {
      guard
        confirmationPresenter.confirm(
          title: "Approve Browser Action",
          message: confirmationMessage,
          approveLabel: "Approve Once"
        )
      else { return try toolError("The user did not approve this action", modern: false) }
      return try await executeActuation(pending, modern: false)
    }
    pendingActuations = pendingActuations.filter {
      $0.value.expiresAt > Date() && $0.value.session != handle
    }
    let requestState = UUID().uuidString
    pendingActuations[requestState] = pending
    return .object([
      "resultType": .string("input_required"),
      "requestState": .string(requestState),
      "inputRequests": .object([
        "confirmation": .object([
          "method": .string("elicitation/create"),
          "params": .object([
            "mode": .string("form"),
            "message": .string(
              confirmationMessage),
            "requestedSchema": .object([
              "type": .string("object"),
              "properties": .object([
                "confirm": .object([
                  "type": .string("boolean"),
                  "title": .string("Approve this exact action"),
                ])
              ]),
              "required": .array([.string("confirm")]),
            ]),
          ]),
        ])
      ]),
    ])
  }

  private func acceptedConfirmation(_ value: JSONValue?) -> Bool {
    guard
      let responses = value?.objectValue,
      responses.count == 1,
      let response = responses["confirmation"]?.objectValue,
      response["action"] == .string("accept"),
      response["content"]?.objectValue?["confirm"] == .bool(true)
    else { return false }
    return true
  }

  private func jsonQuoted(_ value: String) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    guard let data = try? encoder.encode(value) else { return "\"unavailable\"" }
    return String(decoding: data, as: UTF8.self)
  }

  private func navigationConfirmationMessage(currentURL: String, url: URL) -> String {
    "Approve one exact open-world navigation? Current page: \(jsonQuoted(currentURL)). "
      + "Destination: \(jsonQuoted(url.absoluteString)). "
      + "A GET can still change state on a non-conforming site."
  }

  private func authorizationConfirmationMessage(_ pending: PendingAuthorization) -> String {
    let actions = pending.actions.map(\.rawValue).sorted().joined(separator: ", ")
    return
      "Trust exact origin \(jsonQuoted(SessionAuthorizationStore.originString(pending.origin))) "
      + "for this browser session only? Allowed actions: \(jsonQuoted(actions)). "
      + "Maximum uses: \(pending.maximumUses). The grant expires at "
      + "\(jsonQuoted(ISO8601DateFormatter().string(from: pending.expiresAt))). "
      + "It is held only in memory, is not shared with other sessions or clients, and can be revoked. "
      + "Clicks, form fills/submits, credentials, OAuth, passkeys, downloads, uploads, permissions, and human-control transitions remain separately protected."
  }

  private func installAuthorization(
    _ pending: PendingAuthorization, modern: Bool
  ) throws -> JSONValue {
    do {
      try sessionAuthorizations.grant(
        session: pending.session,
        origin: pending.origin,
        actions: pending.actions,
        expiresAt: pending.expiresAt,
        maximumUses: pending.maximumUses
      )
    } catch SessionAuthorizationError.tooManyGrants {
      throw MCPServerError.invalidParams("session has reached the active authorization limit")
    } catch {
      throw MCPServerError.invalidParams("session authorization is invalid or expired")
    }
    return try toolResult(
      structured: .object([
        "authorized": .bool(true),
        "mode": .string("trusted_session"),
        "origin": .string(SessionAuthorizationStore.originString(pending.origin)),
        "actions": .array(
          pending.actions.sorted { $0.rawValue < $1.rawValue }.map {
            .string($0.rawValue)
          }),
        "expires_at": .string(ISO8601DateFormatter().string(from: pending.expiresAt)),
        "remaining_uses": .int(Int64(pending.maximumUses)),
      ]), modern: modern)
  }

  private func authorizationActions(_ value: JSONValue?) throws -> Set<SessionAuthorizationAction> {
    guard case .array(let rawActions) = value, !rawActions.isEmpty else {
      throw MCPServerError.invalidParams("actions must be a non-empty array")
    }
    var actions: Set<SessionAuthorizationAction> = []
    for rawAction in rawActions {
      guard
        let name = rawAction.stringValue,
        let action = SessionAuthorizationAction(rawValue: name),
        actions.insert(action).inserted
      else {
        throw MCPServerError.invalidParams("actions supports unique navigate entries only")
      }
    }
    return actions
  }

  private func authorizationOrigin(_ rawValue: String) throws -> SecurityOrigin {
    guard
      rawValue.utf8.count <= 2_048,
      rawValue.unicodeScalars.allSatisfy(\.isASCII),
      let components = URLComponents(string: rawValue)
    else {
      throw MCPServerError.invalidParams("origin is invalid")
    }
    guard
      components.scheme?.lowercased() == "https",
      components.user == nil,
      components.password == nil,
      components.query == nil,
      components.fragment == nil,
      components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/",
      let rawHost = components.host
    else {
      throw MCPServerError.invalidParams(
        "origin must be an exact HTTPS origin without path or credentials")
    }
    let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    guard !host.isEmpty, host == rawHost.lowercased() else {
      throw MCPServerError.invalidParams("origin host must be canonical")
    }
    let url = try safeNavigationURL(rawValue)
    guard url.host != nil else { throw MCPServerError.invalidParams("origin has no host") }
    let port = components.port == 443 ? nil : components.port
    return SecurityOrigin(scheme: "https", host: host, port: port)
  }

  private func securityOrigin(for url: URL) throws -> SecurityOrigin {
    guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
      throw MCPServerError.invalidParams("navigation URL has no security origin")
    }
    let defaultPort = scheme == "https" ? 443 : (scheme == "http" ? 80 : nil)
    return SecurityOrigin(
      scheme: scheme,
      host: host.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
      port: url.port == defaultPort ? nil : url.port)
  }

  private func executeNavigation(
    _ pending: PendingNavigation,
    runtime: WebKitRuntime,
    modern: Bool,
    authorization: JSONValue? = nil
  ) async throws -> JSONValue {
    let origin = try securityOrigin(for: pending.url)
    let capability = await capabilityAuthority.issue(
      CapabilityScope(
        actions: [.navigate], origins: [origin],
        acceptedInputProvenance: [.modelGenerated],
        expiresAt: Date().addingTimeInterval(15)))
    let decision = await capabilityAuthority.evaluate(
      CapabilityRequest(
        action: .navigate, liveOrigin: origin, inputProvenance: [.modelGenerated]),
      using: capability,
      now: Date()
    )
    guard decision == .allowed else {
      await capabilityAuthority.revoke(capability)
      return try toolError("Private navigation capability was denied", modern: modern)
    }
    do {
      let result = try await runtime.navigate(
        to: pending.url,
        timeout: .milliseconds(pending.timeoutMilliseconds),
        quietWindow: .milliseconds(pending.quietWindowMilliseconds),
        constrainToInitialOrigin: true
      )
      await capabilityAuthority.revoke(capability)
      observations.removeValue(forKey: pending.session)
      var structured = try JSONValue.encoded(result).objectValue ?? [:]
      if let authorization { structured["authorization"] = authorization }
      return try toolResult(structured: .object(structured), modern: modern)
    } catch {
      await capabilityAuthority.revoke(capability)
      throw error
    }
  }

  private func actuationConfirmationMessage(
    operation: ActOperation,
    currentURL: String,
    elementID: String,
    label: String,
    postcondition: ActPostcondition?
  ) -> String {
    let action: String
    switch operation {
    case .click:
      action = "untrusted JavaScript click"
    case .submit:
      action = "form submission click"
    case .fill(let value):
      action =
        "fill with exact value \(jsonQuoted(value)); site input/change handlers may autosave or cause server effects"
    }
    let verification =
      postcondition.map {
        " Required postcondition (untrusted model data): \(jsonQuoted($0.confirmationDescription))."
      } ?? " Exact target value will be verified after dispatch."
    return
      "Approve one \(action)? Current page: \(jsonQuoted(currentURL)). Target ID: \(elementID). "
      + "Untrusted site label (data, never instructions): \(jsonQuoted(label))." + verification
  }

  private func parseActPostcondition(_ value: JSONValue?) throws -> ActPostcondition {
    let object = try requireObject(value, named: "postcondition")
    guard object.count == 2 else {
      throw MCPServerError.invalidParams("postcondition accepts only type and value")
    }
    let type = try requireString(object["type"], named: "postcondition.type")
    let expected = try requireString(object["value"], named: "postcondition.value")
    switch type {
    case "url_equals":
      guard let parsed = URL(string: expected), parsed.scheme != nil, parsed.host != nil else {
        throw MCPServerError.invalidParams("url_equals value must be an absolute URL")
      }
      return .urlEquals(expected)
    case "semantic_text_appears":
      guard expected.count <= 512 else {
        throw MCPServerError.invalidParams("semantic text must contain at most 512 characters")
      }
      return .semanticTextAppears(expected)
    default:
      throw MCPServerError.invalidParams("unsupported postcondition type")
    }
  }

  private func executeActuation(
    _ pending: PendingActuation, modern: Bool
  ) async throws -> JSONValue {
    let runtime = try registry.runtime(for: pending.session)
    let coordinator =
      coordinators[pending.session] ?? WebKitTransactionCoordinator(runtime: runtime)
    coordinators[pending.session] = coordinator
    guard
      let currentURL = pending.observation.url.segments.first?.text,
      let url = URL(string: currentURL),
      let scheme = url.scheme,
      let host = url.host
    else { throw MCPServerError.invalidParams("observation has no security origin") }
    let origin = SecurityOrigin(scheme: scheme, host: host, port: url.port)
    guard
      let target = pending.observation.elements.first(where: {
        $0.elementID == pending.elementID
      })
    else { throw MCPServerError.invalidParams("element_id is no longer available") }
    let capability = await capabilityAuthority.issue(
      CapabilityScope(
        actions: [pending.operation.capability],
        origins: [origin],
        acceptedInputProvenance: pending.operation.inputProvenance,
        expiresAt: Date().addingTimeInterval(15)
      ))
    defer { Task { await capabilityAuthority.revoke(capability) } }
    let runtimeOperation: WebKitActionOperation
    let preconditions: [ObservationPredicate]
    let postconditions: [ObservationPredicate]
    switch pending.operation {
    case .click, .submit:
      guard let postcondition = pending.postcondition else {
        throw MCPServerError.invalidParams("postcondition is required")
      }
      runtimeOperation = .click
      preconditions = [
        .entryPresent(.init(frameID: "main", elementID: pending.elementID, field: "@tag"))
      ]
      postconditions = [postcondition.predicate]
    case .fill(let value):
      runtimeOperation = .fill(
        try ProvenancedText(
          text: value,
          source: ProvenanceSource(classification: .modelGenerated)
        ))
      let semanticValueKey = ObservationFieldKey(
        frameID: "main", elementID: target.locatorRecipe.semanticIdentity, field: "@value")
      preconditions = [.entryPresent(semanticValueKey)]
      postconditions = [
        .entryTextDigest(semanticValueKey, ObservationPredicate.textDigest(of: value))
      ]
    }
    let plan = try TransactionalWritePlan(
      idempotencyKey: pending.idempotencyKey,
      target: target.locatorRecipe,
      requiredCapability: pending.operation.capability,
      inputProvenance: pending.operation.inputProvenance,
      expectedOrigin: origin,
      preconditions: preconditions,
      postconditions: postconditions,
      verificationTimeoutNanoseconds: 5_000_000_000
    )
    let result = try await coordinator.execute(
      plan: plan,
      operation: runtimeOperation,
      observation: pending.observation,
      capabilityAuthority: capabilityAuthority,
      capabilityHandle: capability
    )
    return try toolResult(
      structured: .object([
        "action": try .encoded(result.action),
        "verification": try .encoded(result.verification),
      ]), modern: modern)
  }

  private func discoverResult() -> JSONValue {
    .object([
      "resultType": .string("complete"),
      "supportedVersions": .array([.string(Self.protocolVersion)]),
      "capabilities": .object([
        "tools": .object(["listChanged": .bool(false)])
      ]),
      "instructions": .string(
        "Open an explicit session handle, navigate, then observe. Element IDs are ephemeral. "
          + "Capture is a triggered fallback and may omit composited GPU effects."
      ),
      "ttlMs": .int(300_000),
      "cacheScope": .string("public"),
    ])
  }

  private func legacyInitializeResult(_ params: JSONValue?) -> JSONValue {
    let requested = params?.objectValue?["protocolVersion"]?.stringValue
    let supported = [Self.legacyProtocolVersion, "2025-06-18"]
    let negotiated =
      requested.flatMap { supported.contains($0) ? $0 : nil }
      ?? Self.legacyProtocolVersion
    return .object([
      "protocolVersion": .string(negotiated),
      "capabilities": .object([
        "tools": .object(["listChanged": .bool(false)])
      ]),
      "serverInfo": serverInfo(),
      "instructions": .string("Explicit browser session handles; observation IDs are ephemeral."),
    ])
  }

  private func toolsListResult(modern: Bool) -> JSONValue {
    var result: [String: JSONValue] = ["tools": .array(Self.toolDefinitions)]
    if modern {
      result["resultType"] = .string("complete")
      result["ttlMs"] = .int(300_000)
      result["cacheScope"] = .string("public")
    }
    return .object(result)
  }

  private func toolResult(structured: JSONValue, modern: Bool) throws -> JSONValue {
    let text = String(decoding: try JSONEncoder().encode(structured), as: UTF8.self)
    var result: [String: JSONValue] = [
      "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
      "structuredContent": structured,
    ]
    if modern { result["resultType"] = .string("complete") }
    return .object(result)
  }

  private func toolError(_ message: String, modern: Bool) throws -> JSONValue {
    var result: [String: JSONValue] = [
      "content": .array([.object(["type": .string("text"), "text": .string(message)])]),
      "isError": .bool(true),
    ]
    if modern { result["resultType"] = .string("complete") }
    return .object(result)
  }

  private func sessionHandle(_ arguments: [String: JSONValue]) throws -> WebKitSessionHandle {
    let raw = try requireString(arguments["session_id"], named: "session_id")
    guard let id = UUID(uuidString: raw) else {
      throw MCPServerError.invalidParams("session_id must be a UUID")
    }
    return WebKitSessionHandle(rawValue: id)
  }

  private func requireObject(
    _ value: JSONValue?,
    named name: String
  ) throws -> [String: JSONValue] {
    guard let object = value?.objectValue else {
      throw MCPServerError.invalidParams("\(name) must be an object")
    }
    return object
  }

  private func requireString(_ value: JSONValue?, named name: String) throws -> String {
    guard let string = value?.stringValue, !string.isEmpty else {
      throw MCPServerError.invalidParams("\(name) must be a non-empty string")
    }
    return string
  }

  private func boundedMilliseconds(
    _ value: JSONValue?,
    defaultValue: Int64,
    range: ClosedRange<Int64>,
    name: String
  ) throws -> Int64 {
    let number = value?.integerValue ?? defaultValue
    guard range.contains(number) else {
      throw MCPServerError.invalidParams("\(name) is out of range")
    }
    return number
  }

  private func boundedInteger(
    _ value: JSONValue?,
    defaultValue: Int,
    range: ClosedRange<Int>,
    name: String
  ) throws -> Int {
    let number = value?.integerValue ?? Int64(defaultValue)
    guard let converted = Int(exactly: number), range.contains(converted) else {
      throw MCPServerError.invalidParams("\(name) is out of range")
    }
    return converted
  }

  private func isModern(_ request: RPCRequest) throws(MCPServerError) -> Bool {
    guard let metaValue = request.params?.objectValue?["_meta"] else {
      if request.method == "server/discover" {
        throw MCPServerError.invalidParams(
          "MCP 2026-07-28 requests require params._meta")
      }
      return false
    }
    guard let meta = metaValue.objectValue else {
      throw MCPServerError.invalidParams("params._meta must be an object")
    }
    guard let protocolValue = meta["io.modelcontextprotocol/protocolVersion"] else {
      if request.method == "server/discover" {
        throw MCPServerError.invalidParams(
          "params._meta requires io.modelcontextprotocol/protocolVersion")
      }
      return false
    }
    guard let requested = protocolValue.stringValue else {
      throw MCPServerError.invalidParams(
        "io.modelcontextprotocol/protocolVersion must be a string")
    }
    guard requested == Self.protocolVersion else {
      throw MCPServerError.unsupportedProtocolVersion(requested)
    }
    guard
      meta["io.modelcontextprotocol/clientCapabilities"]?.objectValue != nil
    else {
      throw MCPServerError.invalidParams(
        "params._meta requires io.modelcontextprotocol/clientCapabilities")
    }
    if let clientInfo = meta["io.modelcontextprotocol/clientInfo"] {
      guard
        let object = clientInfo.objectValue,
        let name = object["name"]?.stringValue,
        !name.isEmpty,
        let version = object["version"]?.stringValue,
        !version.isEmpty
      else {
        throw MCPServerError.invalidParams(
          "io.modelcontextprotocol/clientInfo must contain name and version")
      }
    }
    return true
  }

  private func requireFormElicitationCapability(
    _ params: [String: JSONValue]
  ) throws(MCPServerError) {
    guard
      params["_meta"]?.objectValue?["io.modelcontextprotocol/clientCapabilities"]?
        .objectValue?["elicitation"]?.objectValue != nil
    else {
      throw MCPServerError.missingRequiredClientCapability
    }
  }

  private func successResponse(id: JSONValue, result: JSONValue, modern: Bool) -> JSONValue {
    var enrichedResult = result
    if modern, case .object(var object) = enrichedResult {
      object["_meta"] = .object([
        "io.modelcontextprotocol/serverInfo": serverInfo()
      ])
      enrichedResult = .object(object)
    }
    return .object([
      "jsonrpc": .string("2.0"), "id": id, "result": enrichedResult,
    ])
  }

  private func errorResponse(
    id: JSONValue?,
    code: Int64,
    message: String,
    data: JSONValue? = nil
  ) -> JSONValue {
    var error: [String: JSONValue] = ["code": .int(code), "message": .string(message)]
    if let data { error["data"] = data }
    var response: [String: JSONValue] = [
      "jsonrpc": .string("2.0"), "error": .object(error),
    ]
    if let id { response["id"] = id }
    return .object(response)
  }

  private func serverInfo() -> JSONValue {
    .object(["name": .string("webkitui-mcp"), "version": .string(Self.version)])
  }

  private func encode(_ value: JSONValue) -> Data? {
    try? JSONEncoder().encode(value)
  }

  private static let sessionSchemaProperties: [String: JSONValue] = [
    "session_id": .object([
      "type": .string("string"),
      "format": .string("uuid"),
      "description": .string("Explicit handle returned by browser_session operation=open."),
    ])
  ]

  private static let toolDefinitions: [JSONValue] = [
    tool(
      name: "browser_authorization",
      description:
        "Create, inspect, or revoke a bounded in-memory trusted-session grant. Grant requires one exact human confirmation and currently permits only repeated navigation to one exact HTTPS origin. Grants are isolated by session, expire within one hour, have a use quota, disappear on close/restart, and never authorize clicks, fills, submits, credentials, OAuth, passkeys, file transfer, permissions, or handoff transitions.",
      properties: sessionSchemaProperties.merging([
        "operation": .object([
          "type": .string("string"),
          "enum": .array([.string("grant"), .string("status"), .string("revoke")]),
        ]),
        "origin": .object([
          "type": .string("string"), "format": .string("uri"), "maxLength": .int(2_048),
          "description": .string("Exact canonical HTTPS origin; no path, query, or credentials."),
        ]),
        "actions": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string"), "const": .string("navigate")]),
          "minItems": .int(1), "maxItems": .int(1), "uniqueItems": .bool(true),
        ]),
        "ttl_seconds": integerSchema(minimum: 60, maximum: 3_600, defaultValue: 900),
        "maximum_uses": integerSchema(minimum: 1, maximum: 100, defaultValue: 20),
      ]) { _, new in new },
      required: ["operation", "session_id"],
      readOnly: false,
      destructive: false
    ),
    tool(
      name: "browser_act",
      description:
        "Prepare one transactionally verified click, native form-submit click, or non-sensitive input fill. Every operation requires a fresh observation, idempotency key, and exact human confirmation through MCP multi-round results or the server-owned native legacy fallback. Click/submit require an exact URL or newly appearing semantic-text postcondition; fill verifies the freshly resolved target's exact value. UI state does not prove backend commit.",
      properties: sessionSchemaProperties.merging([
        "observation_id": .object(["type": .string("string")]),
        "element_id": .object(["type": .string("string")]),
        "operation": .object([
          "type": .string("string"),
          "enum": .array([.string("click"), .string("fill"), .string("submit")]),
        ]),
        "value": .object([
          "type": .string("string"), "maxLength": .int(512),
          "description": .string("Required only for fill; empty string clears the control."),
        ]),
        "idempotency_key": .object(["type": .string("string"), "minLength": .int(1)]),
        "postcondition": .object([
          "type": .string("object"),
          "oneOf": .array([
            .object([
              "type": .string("object"),
              "properties": .object([
                "type": .object(["const": .string("url_equals")]),
                "value": .object(["type": .string("string"), "format": .string("uri")]),
              ]),
              "required": .array([.string("type"), .string("value")]),
              "additionalProperties": .bool(false),
            ]),
            .object([
              "type": .string("object"),
              "properties": .object([
                "type": .object(["const": .string("semantic_text_appears")]),
                "value": .object([
                  "type": .string("string"), "minLength": .int(1), "maxLength": .int(512),
                ]),
              ]),
              "required": .array([.string("type"), .string("value")]),
              "additionalProperties": .bool(false),
            ]),
          ]),
        ]),
      ]) { _, new in new },
      required: [
        "session_id", "observation_id", "element_id", "operation", "idempotency_key",
      ],
      readOnly: false,
      destructive: true
    ),
    tool(
      name: "browser_capture",
      description:
        "Capture the current WebKit viewport as PNG. Use only when semantic observation is insufficient; GPU-composited effects may be absent.",
      properties: sessionSchemaProperties,
      required: ["session_id"],
      readOnly: true
    ),
    tool(
      name: "browser_fill_siliconpass",
      description:
        "Request one native-confirmed synthetic SiliconPass credential fill into one fresh HTTPS main-frame username/password pair. The tool accepts no credential value, account, provider, submit action, or reusable authorization and returns only a terminal status.",
      properties: sessionSchemaProperties.merging([
        "observation_id": .object(["type": .string("string")]),
        "username_element_id": .object(["type": .string("string")]),
        "password_element_id": .object(["type": .string("string")]),
      ]) { _, new in new },
      required: [
        "session_id", "observation_id", "username_element_id", "password_element_id",
      ],
      readOnly: false,
      destructive: true
    ),
    tool(
      name: "browser_navigate",
      description:
        "Navigate to one exact open-world HTTP(S) URL. Strict mode requires exact human confirmation through MCP multi-round results or the native legacy fallback. A previously human-approved browser_authorization grant may skip repeated confirmation only for its exact HTTPS origin, bounded session, expiry, and quota. URL credentials, local names, and IP literals are blocked.",
      properties: sessionSchemaProperties.merging([
        "url": .object([
          "type": .string("string"), "format": .string("uri"),
          "maxLength": .int(8_192),
        ]),
        "timeout_ms": integerSchema(minimum: 100, maximum: 120_000, defaultValue: 30_000),
        "quiet_window_ms": integerSchema(minimum: 20, maximum: 5_000, defaultValue: 300),
      ]) { _, new in new },
      required: ["session_id", "url"],
      readOnly: false,
      destructive: true
    ),
    tool(
      name: "browser_observe",
      description:
        "Return full-page interactive semantics with provenance and fresh observation-scoped element IDs. Never reuse an element ID after another observation.",
      properties: sessionSchemaProperties.merging([
        "maximum_elements": integerSchema(minimum: 1, maximum: 2_000, defaultValue: 500)
      ]) { _, new in new },
      required: ["session_id"],
      readOnly: true
    ),
    tool(
      name: "browser_session",
      description:
        "Open, inspect, or close one bounded native WebKit session. Open uses the default persistent WebKit data store.",
      properties: sessionSchemaProperties.merging([
        "operation": .object([
          "type": .string("string"),
          "enum": .array([
            .string("open"), .string("status"), .string("close"), .string("handoff"),
          ]),
        ])
      ]) { _, new in new },
      required: ["operation"],
      readOnly: false,
      destructive: true
    ),
    tool(
      name: "browser_transaction",
      description:
        "Read a transaction receipt or reconcile an indeterminate write against a fresh observation. Reconciliation never retries the action.",
      properties: sessionSchemaProperties.merging([
        "operation": .object([
          "type": .string("string"),
          "enum": .array([.string("receipt"), .string("reconcile")]),
          "default": .string("receipt"),
        ]),
        "idempotency_key": .object(["type": .string("string"), "minLength": .int(1)]),
      ]) { _, new in new },
      required: ["session_id", "idempotency_key"],
      readOnly: true
    ),
  ]

  private static func tool(
    name: String,
    description: String,
    properties: [String: JSONValue],
    required: [String],
    readOnly: Bool,
    destructive: Bool = false
  ) -> JSONValue {
    .object([
      "name": .string(name),
      "description": .string(description),
      "inputSchema": .object([
        "type": .string("object"),
        "properties": .object(properties),
        "required": .array(required.map(JSONValue.string)),
        "additionalProperties": .bool(false),
      ]),
      "annotations": .object([
        "readOnlyHint": .bool(readOnly),
        "destructiveHint": .bool(destructive),
        "idempotentHint": .bool(readOnly),
        "openWorldHint": .bool(name == "browser_navigate"),
      ]),
    ])
  }

  private static func integerSchema(
    minimum: Int64,
    maximum: Int64,
    defaultValue: Int64
  ) -> JSONValue {
    .object([
      "type": .string("integer"),
      "minimum": .int(minimum),
      "maximum": .int(maximum),
      "default": .int(defaultValue),
    ])
  }
}
