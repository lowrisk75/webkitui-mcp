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
  public static let protocolVersion = "2026-07-28"
  public static let legacyProtocolVersion = "2025-11-25"

  private let registry: WebKitSessionRegistry
  private let presentHumanWindows: Bool
  private let credentialBroker: any CredentialBrokerFilling
  private let confirmationPresenter: any BrowserConfirmationPresenting
  private let preserveBrowserOnClose: Bool
  private let transactionLedgerFactory: WebKitTransactionLedgerFactory
  private let capabilityAuthority = CapabilityAuthority()
  private var observations: [WebKitSessionHandle: WebKitPageObservation] = [:]
  private var coordinators: [WebKitSessionHandle: WebKitTransactionCoordinator] = [:]
  private var sessionBackends: [WebKitSessionHandle: String] = [:]
  private var pendingActuations: [String: PendingActuation] = [:]
  private var pendingHandoffs: [String: PendingHandoff] = [:]
  private var asynchronousHandoffs: [String: AsynchronousHandoff] = [:]
  private var pendingNavigations: [String: PendingNavigation] = [:]

  private enum ActPostcondition {
    case urlEquals(String)
    case semanticTextAppears(String)
    case semanticTextContains(String)
    case checkedEquals(Bool)
    case selectedEquals(Bool)
    case enabledEquals(Bool)
    case valueEquals(String)
    case attributeEquals(name: String, value: String)
    case dialogAppears(String)
    case optionSelected(String)

    var confirmationDescription: String {
      switch self {
      case .urlEquals(let value): "URL equals \(value)"
      case .semanticTextAppears(let value): "new semantic text appears: \(value)"
      case .semanticTextContains(let value): "new semantic text contains: \(value)"
      case .checkedEquals(let value): "target checked equals \(value)"
      case .selectedEquals(let value): "target selected equals \(value)"
      case .enabledEquals(let value): "target enabled equals \(value)"
      case .valueEquals(let value): "target value equals \(value)"
      case .attributeEquals(let name, let value): "target \(name) equals \(value)"
      case .dialogAppears(let value): "dialog appears with accessible name \(value)"
      case .optionSelected(let value): "target selected option equals \(value)"
      }
    }

    func predicate(for target: WebKitObservedElement) -> ObservationPredicate {
      let semanticID = target.locatorRecipe.semanticIdentity
      func targetField(_ field: String, _ value: String) -> ObservationPredicate {
        .entryTextDigest(
          .init(frameID: "main", elementID: semanticID, field: field),
          ObservationPredicate.textDigest(of: value)
        )
      }
      switch self {
      case .urlEquals(let value):
        return .entryTextDigest(
          .init(frameID: "main", elementID: "@page", field: "url"),
          ObservationPredicate.textDigest(of: value)
        )
      case .semanticTextAppears(let value):
        return .anyEntryTextDigest(
          [.accessibleName, .label, .text, .value],
          ObservationPredicate.textDigest(of: value)
        )
      case .semanticTextContains(let value):
        let parameters = ObservationPredicate.containsParameters(of: value)
        return .anyEntryTextContainsDigest(
          [.accessibleName, .label, .text, .value, .dialogName],
          parameters.digest, parameters.length, parameters.rolling)
      case .checkedEquals(let value): return targetField("@checked", String(value))
      case .selectedEquals(let value): return targetField("@selected", String(value))
      case .enabledEquals(let value): return targetField("@enabled", String(value))
      case .valueEquals(let value): return targetField("@value", value)
      case .attributeEquals(let name, let value):
        return targetField("@attribute:\(name)", value)
      case .dialogAppears(let value):
        return .anyEntryTextDigest([.dialogName], ObservationPredicate.textDigest(of: value))
      case .optionSelected(let value): return targetField("@selected_option", value)
      }
    }
  }

  private enum ActOperation {
    case click
    case submit
    case fill(String)
    case pressKey(String)
    case blur
    case commitInput

    var name: String {
      switch self {
      case .click: "click"
      case .submit: "submit"
      case .fill: "fill"
      case .pressKey: "press_key"
      case .blur: "blur"
      case .commitInput: "commit_input"
      }
    }

    var capability: BrowserCapability {
      switch self {
      case .click: .activateElement
      case .submit: .submitForm
      case .fill: .fillForm
      case .pressKey, .blur, .commitInput: .fillForm
      }
    }

    var inputProvenance: Set<ProvenanceClass> {
      switch self {
      case .fill: [.modelGenerated]
      case .click, .submit, .pressKey, .blur, .commitInput: []
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
    let approvalMode: String
    let dispatchMode: WebKitActionDispatchMode
    let expiresAt: Date
  }

  private struct PendingHandoff {
    let arguments: [String: JSONValue]
    let session: WebKitSessionHandle
    let expiresAt: Date
  }

  private struct AsynchronousHandoff {
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

  public init(
    maximumSessions: Int = 1,
    enforceHostExclusiveSession: Bool = false,
    preserveBrowserOnClose: Bool = false,
    transactionLedgerFactory: WebKitTransactionLedgerFactory = .inMemory
  ) throws {
    self.registry = try WebKitSessionRegistry(
      maximumSessions: maximumSessions,
      enforceHostExclusiveSession: enforceHostExclusiveSession)
    self.presentHumanWindows = true
    self.credentialBroker = SyntheticCredentialBrokerXPCClient()
    self.confirmationPresenter = NativeBrowserConfirmationPresenter()
    self.preserveBrowserOnClose = preserveBrowserOnClose
    self.transactionLedgerFactory = transactionLedgerFactory
  }

  /// Creates one client-scoped authority surface over a host-owned durable
  /// browser registry. Multiple transports may discover tools concurrently,
  /// while the shared runtime keeps browser control serialized and stale
  /// observations fail closed.
  public init(
    durableRegistry registry: WebKitSessionRegistry,
    transactionLedgerFactory: WebKitTransactionLedgerFactory = .inMemory
  ) {
    self.registry = registry
    self.presentHumanWindows = true
    self.credentialBroker = SyntheticCredentialBrokerXPCClient()
    self.confirmationPresenter = NativeBrowserConfirmationPresenter()
    self.preserveBrowserOnClose = true
    self.transactionLedgerFactory = transactionLedgerFactory
  }

  init(
    registry: WebKitSessionRegistry,
    presentHumanWindows: Bool = false,
    credentialBroker: any CredentialBrokerFilling = SyntheticCredentialBrokerXPCClient(),
    confirmationPresenter: any BrowserConfirmationPresenting =
      NativeBrowserConfirmationPresenter(),
    preserveBrowserOnClose: Bool = false,
    transactionLedgerFactory: WebKitTransactionLedgerFactory = .inMemory
  ) {
    self.registry = registry
    self.presentHumanWindows = presentHumanWindows
    self.credentialBroker = credentialBroker
    self.confirmationPresenter = confirmationPresenter
    self.preserveBrowserOnClose = preserveBrowserOnClose
    self.transactionLedgerFactory = transactionLedgerFactory
  }

  /// Drops every client-scoped proof while retaining only the host-owned
  /// browser in durable-broker mode. A reconnect must observe the live page
  /// again before it can request a fill or action.
  public func prepareForClientReconnect() async {
    observations.removeAll(keepingCapacity: false)
    coordinators.removeAll(keepingCapacity: false)
    sessionBackends.removeAll(keepingCapacity: false)
    pendingActuations.removeAll(keepingCapacity: false)
    pendingHandoffs.removeAll(keepingCapacity: false)
    pendingNavigations.removeAll(keepingCapacity: false)
    await capabilityAuthority.revokeAll()
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

    if Self.authenticationRestrictedTools.contains(name) {
      let runtime = try registry.runtime(for: sessionHandle(arguments))
      if let restriction = runtime.authenticationRestrictionStatus() {
        observations.removeValue(forKey: try sessionHandle(arguments))
        return try authenticationRestrictionResult(
          restriction,
          runtime: runtime,
          modern: modern
        )
      }
    }

    do {
      switch name {
      case "browser_session":
        return try await sessionTool(params: params, arguments: arguments, modern: modern)
      case "browser_navigate":
        return try await navigateTool(params: params, arguments: arguments, modern: modern)
      case "browser_observe":
        let handle = try sessionHandle(arguments)
        let runtime = try registry.runtime(for: handle)
        let maximum = try boundedInteger(
          arguments["maximum_elements"],
          defaultValue: 150,
          range: 1...2_000,
          name: "maximum_elements"
        )
        let elementOffset = try boundedInteger(
          arguments["element_offset"], defaultValue: 0, range: 0...100_000,
          name: "element_offset")
        let maximumFieldCharacters = try boundedInteger(
          arguments["maximum_field_characters"], defaultValue: 512, range: 64...4_096,
          name: "maximum_field_characters")
        let roles: [String]
        if case .array(let values) = arguments["roles"] {
          roles = try values.map {
            guard let value = $0.stringValue, !value.isEmpty, value.count <= 64 else {
              throw MCPServerError.invalidParams("roles must contain bounded non-empty strings")
            }
            return value
          }
          guard roles.count <= 16 else {
            throw MCPServerError.invalidParams("roles accepts at most 16 values")
          }
        } else if arguments["roles"] == nil {
          roles = []
        } else {
          throw MCPServerError.invalidParams("roles must be an array")
        }
        let nameContains = arguments["name_contains"]?.stringValue
        if let nameContains, nameContains.count > 128 {
          throw MCPServerError.invalidParams("name_contains must contain at most 128 characters")
        }
        let observation = try await runtime.observe(
          maximumElements: maximum,
          elementOffset: elementOffset,
          maximumFieldCharacters: maximumFieldCharacters,
          roles: roles,
          nameContains: nameContains)
        observations[handle] = observation
        return try toolResult(structured: .encoded(observation), modern: modern)
      case "browser_scroll":
        let handle = try sessionHandle(arguments)
        let runtime = try registry.runtime(for: handle)
        let deltaX = try boundedDouble(
          arguments["delta_x"], defaultValue: 0, range: -2_000...2_000, name: "delta_x")
        let deltaY = try boundedDouble(
          arguments["delta_y"], defaultValue: 0, range: -2_000...2_000, name: "delta_y")
        let result = try await runtime.scrollBy(deltaX: deltaX, deltaY: deltaY)
        observations.removeValue(forKey: handle)
        return try toolResult(structured: .encoded(result), modern: modern)
      case "element_scroll_into_view":
        let handle = try sessionHandle(arguments)
        guard let observation = observations[handle] else {
          throw MCPServerError.invalidParams("Call browser_observe first")
        }
        let observationID = try requireString(
          arguments["observation_id"], named: "observation_id")
        guard observation.observationID == observationID else {
          throw MCPServerError.invalidParams("observation_id is stale")
        }
        let elementID = try requireString(arguments["element_id"], named: "element_id")
        let runtime = try registry.runtime(for: handle)
        let result = try await runtime.scrollElementIntoView(
          observationID: observationID, elementID: elementID)
        observations.removeValue(forKey: handle)
        return try toolResult(structured: .encoded(result), modern: modern)
      case "browser_read_text":
        let runtime = try registry.runtime(for: sessionHandle(arguments))
        let maximum = try boundedInteger(
          arguments["maximum_characters"],
          defaultValue: 20_000,
          range: 1...100_000,
          name: "maximum_characters"
        )
        return try toolResult(
          structured: .encoded(try await runtime.readText(maximumCharacters: Int(maximum))),
          modern: modern)
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
      case "browser_rotate_siliconpass_password":
        return try await credentialRotationTool(arguments: arguments, modern: modern)
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
        case "export":
          let receipt = try await coordinator.receipt(idempotencyKey: key)
          let exported = TransactionReceiptExportV1(
            receipt: receipt,
            exportedAt: ISO8601DateFormatter().string(from: Date())
          )
          let canonical = try exported.canonicalJSONData()
          let digest = try exported.canonicalJSONSHA256()
          return try toolResult(
            structured: .object([
              "format": .string("ReceiptV1"),
              "media_type": .string("application/vnd.lorislab.webkitui-receipt+json"),
              "sha256": .string(digest),
              "canonical_json_base64": .string(canonical.base64EncodedString()),
              "markdown": .string(exported.markdown()),
              "receipt": try .encoded(exported),
              "action_replayed": .bool(false),
            ]),
            modern: modern)
        case "reconcile":
          let verification = try await coordinator.reconcile(idempotencyKey: key)
          let state: String
          let nextStep: String
          switch verification {
          case .verified:
            state = "verified_by_postcondition"
            nextStep = "none"
          case .indeterminate:
            state = "real_world_state_unknown"
            nextStep =
              "Inspect an independent backend or provider status before any retry; reconciliation never replays."
          case .pending:
            state = "verification_pending"
            nextStep = "Wait, then reconcile again without replaying the action."
          }
          return try toolResult(
            structured: .object([
              "verification": try .encoded(verification),
              "reconcile_state": .string(state),
              "safe_next_step": .string(nextStep),
              "action_replayed": .bool(false),
            ]),
            modern: modern)
        default:
          throw MCPServerError.invalidParams("operation must be receipt, export, or reconcile")
        }
      default:
        return try toolError("Unknown tool: \(name)", modern: modern)
      }
    } catch let error as MCPServerError {
      throw error
    } catch WebKitRuntimeError.targetNotActionable {
      return try toolError(
        "target_not_actionable: scroll/re-observe first; if the site requires a trusted human gesture, use browser_session operation=handoff",
        modern: modern)
    } catch {
      return try toolError(String(describing: error), modern: modern)
    }
  }

  private func authenticationRestrictionResult(
    _ restriction: AuthenticationRestrictionStatus,
    runtime: WebKitRuntime,
    modern: Bool
  ) throws -> JSONValue {
    let fullBrowserRequired = restriction.classification == .fullBrowserRequired
    if !fullBrowserRequired,
      runtime.interactionControlState() == .agentControlled
        || runtime.interactionControlState() == .freshlyReobserved
    {
      try runtime.requestHumanHandoff()
      try runtime.beginHumanControl(presentWindow: presentHumanWindows)
    }
    return try structuredToolError(
      structured: .object([
        "status": .string(
          fullBrowserRequired
            ? AuthenticationUIClassification.fullBrowserRequired.rawValue
            : "authentication_origin_requires_human_handoff"),
        "origin": .string(restriction.origin),
        "auth_ui_state": .string(restriction.classification.rawValue),
        "environment": try .encoded(restriction.environment),
        "control_state": .string(runtime.interactionControlState().rawValue),
        "selected_backend": .string("native_webkit"),
        "required_internal_backend": .string(
          fullBrowserRequired ? "safari_compatibility" : "native_handoff"),
        "backend_transition": .string(
          fullBrowserRequired ? "internal_backend_required" : "human_handoff_required"),
        "session_transfer_supported": .bool(false),
        "credential_transfer_supported": .bool(false),
      ]),
      modern: modern
    )
  }

  private func sessionTool(
    params: [String: JSONValue], arguments: [String: JSONValue], modern: Bool
  ) async throws -> JSONValue {
    let operation = try requireString(arguments["operation"], named: "operation")
    switch operation {
    case "open":
      guard
        arguments.keys.allSatisfy({
          $0 == "operation" || $0 == "profile_id" || $0 == "execution_policy"
        })
      else {
        throw MCPServerError.invalidParams(
          "open accepts only operation, profile_id, and execution_policy")
      }
      let requestedProfile = arguments["profile_id"]?.stringValue ?? "default"
      let executionPolicy = arguments["execution_policy"]?.stringValue ?? "auto"
      guard
        ["auto", "trusted_local", "compatibility", "isolated_read_only"].contains(
          executionPolicy)
      else {
        throw MCPServerError.invalidParams(
          "execution_policy must be auto, trusted_local, compatibility, or isolated_read_only")
      }
      guard executionPolicy == "auto" || executionPolicy == "trusted_local" else {
        return try structuredToolError(
          structured: .object([
            "status": .string("backend_unavailable"),
            "execution_policy": .string(executionPolicy),
            "available_internal_backends": .array([.string("native_webkit")]),
            "session_transfer_supported": .bool(false),
            "credential_transfer_supported": .bool(false),
          ]),
          modern: modern
        )
      }
      let profileIdentifier: UUID?
      if requestedProfile == "default" {
        profileIdentifier = nil
      } else if let identifier = UUID(uuidString: requestedProfile) {
        guard await registry.availableProfileIDs().contains(identifier.uuidString) else {
          throw MCPServerError.invalidParams("profile_id is not an existing persistent profile")
        }
        profileIdentifier = identifier
      } else {
        throw MCPServerError.invalidParams("profile_id must be default or a listed UUID")
      }
      let opened =
        preserveBrowserOnClose
        ? try registry.openOrReuse(profileIdentifier: profileIdentifier)
        : (handle: try registry.open(profileIdentifier: profileIdentifier), reused: false)
      let handle = opened.handle
      sessionBackends[handle] = "native_webkit"
      coordinators[handle] = WebKitTransactionCoordinator(
        runtime: try registry.runtime(for: handle),
        ledger: try transactionLedgerFactory.make(scope: requestedProfile)
      )
      return try toolResult(
        structured: .object([
          "session_id": .string(handle.rawValue.uuidString),
          "maximum_sessions": .int(Int64(registry.maximumSessions)),
          "reused": .bool(opened.reused),
          "profile_id": .string(requestedProfile),
          "execution_policy": .string(executionPolicy),
          "selected_backend": .string("native_webkit"),
          "capabilities": .array([
            .string("authenticated_read"),
            .string("trusted_local_write"),
            .string("human_handoff"),
          ]),
        ]), modern: modern)
    case "profiles":
      guard arguments.keys.allSatisfy({ $0 == "operation" }) else {
        throw MCPServerError.invalidParams("profiles accepts only operation")
      }
      return try toolResult(
        structured: .object([
          "profiles": .array(
            await registry.availableProfileIDs().map { .string($0) }),
          "contains_credentials": .bool(false),
          "available_execution_policies": .array([
            .string("auto"), .string("trusted_local"), .string("compatibility"),
            .string("isolated_read_only"),
          ]),
        ]),
        modern: modern)
    case "status":
      let handle = try sessionHandle(arguments)
      purgeExpiredAsynchronousHandoffs()
      let status = try registry.status(handle)
      var statusObject = try requireObject(.encoded(status), named: "session status")
      statusObject["control_state"] = .string(status.controlState.rawValue)
      statusObject["selected_backend"] = .string(sessionBackends[handle] ?? "native_webkit")
      statusObject["handoff_active"] = .bool(
        asynchronousHandoffs.values.contains { $0.session == handle })
      return try toolResult(
        structured: .object(statusObject), modern: modern)
    case "close":
      let handle = try sessionHandle(arguments)
      observations.removeValue(forKey: handle)
      coordinators.removeValue(forKey: handle)
      sessionBackends.removeValue(forKey: handle)
      pendingActuations = pendingActuations.filter { $0.value.session != handle }
      pendingHandoffs = pendingHandoffs.filter { $0.value.session != handle }
      asynchronousHandoffs = asynchronousHandoffs.filter { $0.value.session != handle }
      pendingNavigations = pendingNavigations.filter { $0.value.session != handle }
      if !preserveBrowserOnClose {
        try registry.close(handle)
      }
      return try toolResult(
        structured: .object([
          "closed": .bool(true),
          "browser_preserved": .bool(preserveBrowserOnClose),
        ]),
        modern: modern)
    case "handoff":
      return try await handoffTool(params: params, arguments: arguments, modern: modern)
    case "handoff_start":
      return try asynchronousHandoffStart(arguments: arguments, modern: modern)
    case "handoff_status":
      return try asynchronousHandoffStatus(arguments: arguments, modern: modern)
    case "handoff_resume":
      return try await asynchronousHandoffResume(arguments: arguments, modern: modern)
    default:
      throw MCPServerError.invalidParams(
        "operation must be open, profiles, status, close, handoff, handoff_start, handoff_status, or handoff_resume"
      )
    }
  }

  private func navigateTool(
    params: [String: JSONValue], arguments: [String: JSONValue], modern: Bool
  ) async throws -> JSONValue {
    let approvalMode = arguments["approval_mode"]?.stringValue ?? "native"
    guard ["native", "mcp"].contains(approvalMode) else {
      throw MCPServerError.invalidParams("approval_mode must be native or mcp")
    }
    if modern, approvalMode == "mcp" {
      try requireFormElicitationCapability(params)
    }
    let handle = try sessionHandle(arguments)
    let runtime = try registry.runtime(for: handle)
    let url = try safeNavigationURL(try requireString(arguments["url"], named: "url"))
    let timeout = try boundedMilliseconds(
      arguments["timeout_ms"], defaultValue: 30_000, range: 100...120_000, name: "timeout_ms")
    let quiet = try boundedMilliseconds(
      arguments["quiet_window_ms"], defaultValue: 300, range: 20...5_000,
      name: "quiet_window_ms")

    if modern, approvalMode == "mcp", let requestState = params["requestState"]?.stringValue {
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
    if !modern || approvalMode == "native" {
      let currentURL = runtime.agentSafeCurrentURL() ?? "no current page"
      guard
        confirmationPresenter.confirm(
          title: "Approve Web Navigation",
          message: navigationConfirmationMessage(currentURL: currentURL, url: url),
          approveLabel: "Navigate"
        )
      else {
        return try toolError("The user did not approve this navigation", modern: modern)
      }
      return try await executeNavigation(pending, runtime: runtime, modern: modern)
    }
    pendingNavigations = pendingNavigations.filter {
      $0.value.expiresAt > Date() && $0.value.session != handle
    }
    let requestState = UUID().uuidString
    pendingNavigations[requestState] = pending
    let currentURL = runtime.agentSafeCurrentURL() ?? "no current page"
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
    if status == .credentialNotFound {
      let origin =
        "\(binding.origin.scheme)://\(binding.origin.asciiHost):\(binding.origin.effectivePort)"
      let accepted = confirmationPresenter.confirm(
        title: "No Saved SiliconPass Credential",
        message:
          "No credential is saved for \(origin). Continue in the visible browser to sign in manually, then add or update this credential in SiliconPass? No password will be sent through MCP.",
        approveLabel: "Continue Securely"
      )
      if accepted {
        try runtime.requestHumanHandoff()
        try runtime.beginHumanControl(presentWindow: presentHumanWindows)
      }
      return try toolResult(
        structured: .object([
          "status": .string(status.rawValue),
          "add_offered": .bool(true),
          "human_handoff_started": .bool(accepted),
          "control_state": .string(runtime.interactionControlState().rawValue),
        ]),
        modern: modern
      )
    }
    if status == .userPresenceUnavailable {
      return try toolResult(
        structured: .object([
          "status": .string(status.rawValue),
          "requires_user_presence": .bool(true),
          "retryable": .bool(true),
          "automatic_retry": .bool(false),
          "secret_released": .bool(false),
          "authentication_policy": .string("device_owner_authentication"),
          "accepted_methods": .array([
            .string("system_device_owner_authentication")
          ]),
          "recovery": .string(
            "Unlock this Mac and retry from an interactive session using the authentication method offered by macOS. Closed-lid availability is device-specific and is not inferred."
          ),
          "control_state": .string(runtime.interactionControlState().rawValue),
        ]),
        modern: modern
      )
    }
    return try toolResult(
      structured: .object([
        "status": .string(status.rawValue),
        "requires_human_handoff": .bool(false),
      ]),
      modern: modern
    )
  }

  private func credentialRotationTool(
    arguments: [String: JSONValue],
    modern: Bool
  ) async throws -> JSONValue {
    let allowedKeys = Set([
      "session_id", "observation_id", "current_password_element_id",
      "new_password_element_id", "confirmation_element_id",
    ])
    guard Set(arguments.keys).isSubset(of: allowedKeys) else {
      throw MCPServerError.invalidParams(
        "browser_rotate_siliconpass_password accepts only secretless target identifiers"
      )
    }
    let handle = try sessionHandle(arguments)
    let observationID = try requireString(
      arguments["observation_id"], named: "observation_id")
    guard observations[handle]?.observationID == observationID else {
      throw MCPServerError.invalidParams("Call browser_observe and use its fresh observation_id")
    }
    let runtime = try registry.runtime(for: handle)
    let binding = try runtime.credentialRotationBinding(
      observationID: observationID,
      currentPasswordElementID: try requireString(
        arguments["current_password_element_id"], named: "current_password_element_id"),
      newPasswordElementID: try requireString(
        arguments["new_password_element_id"], named: "new_password_element_id"),
      confirmationElementID: try requireString(
        arguments["confirmation_element_id"], named: "confirmation_element_id")
    )
    let status: CredentialBrokerWireStatus
    do {
      status = try await credentialBroker.rotatePassword(
        binding: binding,
        runtime: runtime
      ).status
    } catch {
      status = .failed
    }
    return try toolResult(
      structured: .object([
        "status": .string(status.rawValue),
        "secret_released_to_mcp": .bool(false),
        "submitted": .bool(false),
        "requires_native_confirmation": .bool(status != .changed),
      ]),
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
              "Complete login, MFA, CAPTCHA, or sensitive input in the local WebKit window, then call browser_session operation=handoff again to request agent resume."
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
              "Human control is active in the local WebKit window. Complete login, MFA, CAPTCHA, or sensitive input there. Confirm only when the agent may resume."
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

  private func purgeExpiredAsynchronousHandoffs(now: Date = Date()) {
    asynchronousHandoffs = asynchronousHandoffs.filter { $0.value.expiresAt > now }
  }

  private func asynchronousHandoffStart(
    arguments: [String: JSONValue], modern: Bool
  ) throws -> JSONValue {
    guard arguments.keys.allSatisfy({ $0 == "operation" || $0 == "session_id" }) else {
      throw MCPServerError.invalidParams("handoff_start accepts only operation and session_id")
    }
    let handle = try sessionHandle(arguments)
    let runtime = try registry.runtime(for: handle)
    switch runtime.interactionControlState() {
    case .agentControlled, .freshlyReobserved:
      try runtime.requestHumanHandoff()
      try runtime.beginHumanControl(presentWindow: presentHumanWindows)
    case .humanControlled:
      break
    default:
      throw MCPServerError.invalidParams("handoff transition is already in progress")
    }
    purgeExpiredAsynchronousHandoffs()
    asynchronousHandoffs = asynchronousHandoffs.filter { $0.value.session != handle }
    let token = UUID().uuidString
    let expiresAt = Date().addingTimeInterval(3_600)
    asynchronousHandoffs[token] = AsynchronousHandoff(session: handle, expiresAt: expiresAt)
    return try toolResult(
      structured: .object([
        "control_state": .string(runtime.interactionControlState().rawValue),
        "resume_token": .string(token),
        "resume_token_state": .string("active"),
        "expires_at": .string(ISO8601DateFormatter().string(from: expiresAt)),
        "blocking": .bool(false),
        "instructions": .string(
          "Complete the sensitive step in the live WebKit window. Poll handoff_status, then call handoff_resume with this single-session token; resume still requires local confirmation."
        ),
      ]), modern: modern)
  }

  private func asynchronousHandoffStatus(
    arguments: [String: JSONValue], modern: Bool
  ) throws -> JSONValue {
    guard
      arguments.keys.allSatisfy({
        $0 == "operation" || $0 == "session_id" || $0 == "resume_token"
      })
    else {
      throw MCPServerError.invalidParams(
        "handoff_status accepts only operation, session_id, and resume_token")
    }
    let handle = try sessionHandle(arguments)
    let token = try requireString(arguments["resume_token"], named: "resume_token")
    purgeExpiredAsynchronousHandoffs()
    let tokenState: String
    if let pending = asynchronousHandoffs[token], pending.session == handle {
      tokenState = "active"
    } else {
      tokenState = "unknown_or_expired"
    }
    let runtime = try registry.runtime(for: handle)
    return try toolResult(
      structured: .object([
        "control_state": .string(runtime.interactionControlState().rawValue),
        "resume_token_state": .string(tokenState),
        "blocking": .bool(false),
        "ready_for_resume_request": .bool(
          tokenState == "active" && runtime.interactionControlState() == .humanControlled),
      ]), modern: modern)
  }

  private func asynchronousHandoffResume(
    arguments: [String: JSONValue], modern: Bool
  ) async throws -> JSONValue {
    guard
      arguments.keys.allSatisfy({
        $0 == "operation" || $0 == "session_id" || $0 == "resume_token"
      })
    else {
      throw MCPServerError.invalidParams(
        "handoff_resume accepts only operation, session_id, and resume_token")
    }
    let handle = try sessionHandle(arguments)
    let token = try requireString(arguments["resume_token"], named: "resume_token")
    purgeExpiredAsynchronousHandoffs()
    guard let pending = asynchronousHandoffs[token], pending.session == handle else {
      throw MCPServerError.invalidParams("resume_token is unknown, expired, or session-mismatched")
    }
    let runtime = try registry.runtime(for: handle)
    guard runtime.interactionControlState() == .humanControlled else {
      throw MCPServerError.invalidParams("session is not under human control")
    }
    guard
      confirmationPresenter.confirm(
        title: "Return Browser Control",
        message:
          "Return control of this exact live WebKit session to the requesting agent? The resume token will be consumed and a fresh observation will be required.",
        approveLabel: "Return Control"
      )
    else {
      return try toolResult(
        structured: .object([
          "control_state": .string(runtime.interactionControlState().rawValue),
          "resume_token_state": .string("active"),
          "resumed": .bool(false),
        ]), modern: modern)
    }
    asynchronousHandoffs.removeValue(forKey: token)
    try runtime.requestAgentResume()
    let observation = try await runtime.resumeAfterHumanControl()
    observations[handle] = observation
    return try toolResult(
      structured: .object([
        "control_state": .string(runtime.interactionControlState().rawValue),
        "resume_token_state": .string("consumed"),
        "resumed": .bool(true),
        "observation": try .encoded(observation),
      ]), modern: modern)
  }

  private func actTool(
    params: [String: JSONValue],
    arguments: [String: JSONValue],
    modern: Bool
  ) async throws -> JSONValue {
    let approvalMode = arguments["approval_mode"]?.stringValue ?? (modern ? "mcp" : "native")
    guard ["native", "mcp"].contains(approvalMode) else {
      throw MCPServerError.invalidParams("approval_mode must be native or mcp")
    }
    if modern, approvalMode == "mcp" {
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
    case "press_key":
      guard arguments["value"] == nil else {
        throw MCPServerError.invalidParams("press_key uses key, not value")
      }
      let key = try requireString(arguments["key"], named: "key")
      let normalized = ["enter": "Enter", "tab": "Tab", "escape": "Escape"][key.lowercased()]
      guard let normalized else {
        throw MCPServerError.invalidParams("press_key key must be Enter, Tab, or Escape")
      }
      operation = .pressKey(normalized)
      postcondition = try parseActPostcondition(arguments["postcondition"])
    case "blur", "commit_input":
      guard arguments["value"] == nil, arguments["key"] == nil else {
        throw MCPServerError.invalidParams("blur and commit_input accept neither value nor key")
      }
      operation = operationName == "blur" ? .blur : .commitInput
      postcondition = try parseActPostcondition(arguments["postcondition"])
    default:
      throw MCPServerError.invalidParams(
        "operation must be click, fill, submit, press_key, blur, or commit_input")
    }
    let idempotencyKey = try requireString(
      arguments["idempotency_key"], named: "idempotency_key")

    if modern, approvalMode == "mcp", let requestState = params["requestState"]?.stringValue {
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
      approvalMode: approvalMode,
      dispatchMode: approvalMode == "native"
        && (operationName == "click" || operationName == "submit" || operationName == "press_key")
        ? .nativeAppKit : .javascript,
      expiresAt: Date().addingTimeInterval(60)
    )
    let confirmationMessage = actuationConfirmationMessage(
      operation: operation,
      currentURL: observation.url.segments.first?.text ?? "unknown",
      elementID: elementID,
      label: String(
        ((target.accessibleName ?? target.label ?? target.text)?.segments.map(\.text).joined() ?? "")
          .prefix(120)),
      postcondition: postcondition,
      dispatchMode: pending.dispatchMode
    )
    if !modern || approvalMode == "native" {
      guard
        confirmationPresenter.confirm(
          title: "Approve Browser Action",
          message: confirmationMessage,
          approveLabel: "Approve Once"
        )
      else { return try toolError("The user did not approve this action", modern: modern) }
      return try await executeActuation(pending, modern: modern)
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
    guard let data = try? encoder.encode(Self.safeConfirmationText(value)) else {
      return "\"unavailable\""
    }
    return String(decoding: data, as: UTF8.self)
  }

  static func safeConfirmationText(_ value: String) -> String {
    let bidiControls: Set<UInt32> = [
      0x061C, 0x200E, 0x200F,
      0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
      0x2066, 0x2067, 0x2068, 0x2069,
    ]
    let rejected = CharacterSet.controlCharacters.union(.illegalCharacters)
    var output = ""
    for scalar in value.precomposedStringWithCompatibilityMapping.unicodeScalars
    where !rejected.contains(scalar) && !bidiControls.contains(scalar.value) {
      output.unicodeScalars.append(scalar)
    }
    return output
  }

  private func navigationConfirmationMessage(currentURL: String, url: URL) -> String {
    "Approve one exact open-world navigation? Current page: \(jsonQuoted(currentURL)). "
      + "Destination: \(jsonQuoted(WebKitRuntime.agentSafeURL(url))). "
      + "A GET can still change state on a non-conforming site."
  }

  private func executeNavigation(
    _ pending: PendingNavigation,
    runtime: WebKitRuntime,
    modern: Bool
  ) async throws -> JSONValue {
    guard let scheme = pending.url.scheme, let host = pending.url.host else {
      throw MCPServerError.invalidParams("navigation URL has no security origin")
    }
    let origin = SecurityOrigin(scheme: scheme, host: host, port: pending.url.port)
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
      if let restriction = runtime.authenticationRestrictionStatus() {
        if runtime.interactionControlState() == .agentControlled
          || runtime.interactionControlState() == .freshlyReobserved
        {
          try runtime.requestHumanHandoff()
          try runtime.beginHumanControl(presentWindow: presentHumanWindows)
        }
        return try toolResult(
          structured: .object([
            "status": .string("authentication_origin_requires_human_handoff"),
            "origin": .string(restriction.origin),
            "auth_ui_state": .string(restriction.classification.rawValue),
            "environment": try .encoded(restriction.environment),
            "control_state": .string(runtime.interactionControlState().rawValue),
            "navigation": try .encoded(result),
          ]),
          modern: modern
        )
      }
      return try toolResult(structured: .encoded(result), modern: modern)
    } catch WebKitRuntimeError.crossOriginRedirectRequiresHuman(
      let fromOrigin,
      let toOrigin
    ) {
      await capabilityAuthority.revoke(capability)
      observations.removeValue(forKey: pending.session)
      return try redirectApprovalResult(
        fromOrigin: fromOrigin,
        toOrigin: toOrigin,
        modern: modern
      )
    } catch {
      await capabilityAuthority.revoke(capability)
      throw error
    }
  }

  func redirectApprovalResult(
    fromOrigin: String,
    toOrigin: String,
    modern: Bool
  ) throws -> JSONValue {
    try structuredToolError(
      structured: .object([
        "status": .string("redirect_requires_human_approval"),
        "from_origin": .string(fromOrigin),
        "to_origin": .string(toOrigin),
      ]),
      modern: modern
    )
  }

  private func actuationConfirmationMessage(
    operation: ActOperation,
    currentURL: String,
    elementID: String,
    label: String,
    postcondition: ActPostcondition?,
    dispatchMode: WebKitActionDispatchMode
  ) -> String {
    let action: String
    switch operation {
    case .click:
      action =
        dispatchMode == .nativeAppKit
        ? "AppKit click with a measured WebKit trust receipt" : "untrusted JavaScript click"
    case .submit:
      action =
        dispatchMode == .nativeAppKit
        ? "AppKit form submission click with a measured WebKit trust receipt"
        : "untrusted JavaScript form submission click"
    case .fill(let value):
      action =
        "fill with exact value \(jsonQuoted(value)); site input/change handlers may autosave or cause server effects"
    case .pressKey(let key):
      action =
        dispatchMode == .nativeAppKit
        ? "AppKit key \(jsonQuoted(key)) with a measured WebKit trust receipt"
        : "untrusted JavaScript key \(jsonQuoted(key))"
    case .blur:
      action = "explicitly blur the target"
    case .commitInput:
      action = "dispatch change and blur to commit the target input"
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
    guard value != nil else {
      throw MCPServerError.invalidParams(
        "postcondition is required for click and submit; it must be omitted for fill")
    }
    let object = try requireObject(value, named: "postcondition")
    let type = try requireString(object["type"], named: "postcondition.type")
    let expected = try requireString(object["value"], named: "postcondition.value")
    let ordinaryKeys: Set<String> = ["type", "value"]
    let attributeKeys: Set<String> = ["type", "attribute", "value"]
    guard Set(object.keys) == (type == "attribute_equals" ? attributeKeys : ordinaryKeys) else {
      throw MCPServerError.invalidParams("postcondition contains unsupported fields")
    }
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
    case "semantic_text_contains":
      guard !expected.isEmpty, expected.count <= 512 else {
        throw MCPServerError.invalidParams(
          "semantic_text_contains must contain 1 to 512 characters")
      }
      return .semanticTextContains(expected)
    case "checked_equals", "selected_equals", "enabled_equals":
      guard let boolean = ["true": true, "false": false][expected.lowercased()] else {
        throw MCPServerError.invalidParams("boolean state postconditions require true or false")
      }
      if type == "checked_equals" { return .checkedEquals(boolean) }
      if type == "selected_equals" { return .selectedEquals(boolean) }
      return .enabledEquals(boolean)
    case "value_equals":
      guard expected.count <= 1_024 else {
        throw MCPServerError.invalidParams("value_equals must contain at most 1024 characters")
      }
      return .valueEquals(expected)
    case "attribute_equals":
      let name = try requireString(object["attribute"], named: "postcondition.attribute")
        .lowercased()
      let allowed = Set([
        "aria-checked", "aria-selected", "aria-disabled", "aria-expanded", "data-state", "open",
      ])
      guard allowed.contains(name) else {
        throw MCPServerError.invalidParams(
          "attribute_equals attribute is not an observable state attribute")
      }
      return .attributeEquals(name: name, value: expected)
    case "dialog_appears":
      guard !expected.isEmpty, expected.count <= 512 else {
        throw MCPServerError.invalidParams("dialog_appears requires a bounded accessible name")
      }
      return .dialogAppears(expected)
    case "option_selected":
      guard !expected.isEmpty, expected.count <= 512 else {
        throw MCPServerError.invalidParams(
          "option_selected requires a bounded visible option label")
      }
      return .optionSelected(expected)
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
    case .click, .submit, .pressKey, .blur, .commitInput:
      guard let postcondition = pending.postcondition else {
        throw MCPServerError.invalidParams("postcondition is required")
      }
      switch pending.operation {
      case .click, .submit: runtimeOperation = .click
      case .pressKey(let key): runtimeOperation = .pressKey(key)
      case .blur: runtimeOperation = .blur
      case .commitInput: runtimeOperation = .commitInput
      case .fill:
        throw MCPServerError.invalidParams("internal operation mismatch")
      }
      preconditions = [
        .entryPresent(.init(frameID: "main", elementID: pending.elementID, field: "@tag"))
      ]
      postconditions = [postcondition.predicate(for: target)]
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
      dispatchMode: pending.dispatchMode,
      observation: pending.observation,
      capabilityAuthority: capabilityAuthority,
      capabilityHandle: capability
    )
    return try toolResult(
      structured: .object([
        "action": try .encoded(result.action),
        "verification": try .encoded(result.verification),
        "confirmation_mode": .string(pending.approvalMode),
        "dispatch_mode": .string(result.action.dispatchMode.rawValue),
        "confirmation_and_dispatch_are_distinct": .bool(true),
        "trusted_gesture_state": .string(
          result.action.trustedUserGesture ? "trusted" : "untrusted_javascript"),
        "requires_trusted_human_gesture": .string(
          result.action.trustedUserGesture ? "no" : "unknown_site_requirement"),
        "trusted_human_gesture_handoff_available": .bool(!result.action.trustedUserGesture),
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

  private func structuredToolError(structured: JSONValue, modern: Bool) throws -> JSONValue {
    let text = String(decoding: try JSONEncoder().encode(structured), as: UTF8.self)
    var result: [String: JSONValue] = [
      "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
      "structuredContent": structured,
      "isError": .bool(true),
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

  private func boundedDouble(
    _ value: JSONValue?,
    defaultValue: Double,
    range: ClosedRange<Double>,
    name: String
  ) throws -> Double {
    let number: Double
    switch value {
    case .int(let integer):
      number = Double(integer)
    case .double(let double):
      number = double
    case nil:
      number = defaultValue
    default:
      throw MCPServerError.invalidParams("\(name) must be a number")
    }
    guard number.isFinite, range.contains(number) else {
      throw MCPServerError.invalidParams("\(name) is out of range")
    }
    return number
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
    .object(["name": .string("webkitui-mcp"), "version": .string("0.6.0")])
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

  private static let authenticationRestrictedTools: Set<String> = [
    "browser_observe",
    "browser_read_text",
    "browser_capture",
    "browser_scroll",
    "element_scroll_into_view",
    "browser_act",
    "browser_fill_siliconpass",
    "browser_rotate_siliconpass_password",
  ]

  private static let toolDefinitions: [JSONValue] = [
    tool(
      name: "browser_act",
      description:
        "Prepare one transactionally verified click, native form-submit click, non-sensitive input fill, bounded key, blur, or input commit. Authentication origins are fail-closed. Every operation requires a fresh observation, idempotency key, and exact human confirmation. approval_mode=native uses server-owned confirmation and AppKit dispatch for click/submit, with an independently measured WebKit event trust receipt; approval_mode=mcp retains multi-round confirmation and JavaScript dispatch. UI state does not prove backend commit.",
      properties: sessionSchemaProperties.merging([
        "observation_id": .object(["type": .string("string")]),
        "element_id": .object(["type": .string("string")]),
        "operation": .object([
          "type": .string("string"),
          "enum": .array([
            .string("click"), .string("fill"), .string("submit"),
            .string("press_key"), .string("blur"), .string("commit_input"),
          ]),
        ]),
        "value": .object([
          "type": .string("string"), "maxLength": .int(512),
          "description": .string("Required only for fill; empty string clears the control."),
        ]),
        "key": .object([
          "type": .string("string"),
          "enum": .array([.string("Enter"), .string("Tab"), .string("Escape")]),
          "description": .string("Required only for press_key."),
        ]),
        "idempotency_key": .object(["type": .string("string"), "minLength": .int(1)]),
        "approval_mode": .object([
          "type": .string("string"),
          "enum": .array([.string("native"), .string("mcp")]),
          "default": .string("mcp"),
          "description": .string(
            "native separates exact local confirmation from measured AppKit dispatch; mcp uses multi-round elicitation and JavaScript dispatch."
          ),
        ]),
        "postcondition": .object([
          "type": .string("object"),
          "description": .string(
            "Required for click and submit; forbidden for fill, whose exact value is verified automatically."
          ),
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
            .object([
              "type": .string("object"),
              "properties": .object([
                "type": .object(["const": .string("semantic_text_contains")]),
                "value": .object([
                  "type": .string("string"), "minLength": .int(1), "maxLength": .int(512),
                ]),
              ]),
              "required": .array([.string("type"), .string("value")]),
              "additionalProperties": .bool(false),
            ]),
            .object([
              "type": .string("object"),
              "properties": .object([
                "type": .object([
                  "enum": .array([
                    .string("checked_equals"), .string("selected_equals"),
                    .string("enabled_equals"),
                  ])
                ]),
                "value": .object([
                  "type": .string("string"),
                  "enum": .array([.string("true"), .string("false")]),
                ]),
              ]),
              "required": .array([.string("type"), .string("value")]),
              "additionalProperties": .bool(false),
            ]),
            .object([
              "type": .string("object"),
              "properties": .object([
                "type": .object([
                  "enum": .array([
                    .string("value_equals"), .string("dialog_appears"),
                    .string("option_selected"),
                  ])
                ]),
                "value": .object([
                  "type": .string("string"), "minLength": .int(1), "maxLength": .int(1_024),
                ]),
              ]),
              "required": .array([.string("type"), .string("value")]),
              "additionalProperties": .bool(false),
            ]),
            .object([
              "type": .string("object"),
              "properties": .object([
                "type": .object(["const": .string("attribute_equals")]),
                "attribute": .object([
                  "type": .string("string"),
                  "enum": .array([
                    .string("aria-checked"), .string("aria-selected"),
                    .string("aria-disabled"), .string("aria-expanded"),
                    .string("data-state"), .string("open"),
                  ]),
                ]),
                "value": .object([
                  "type": .string("string"), "maxLength": .int(1_024),
                ]),
              ]),
              "required": .array([
                .string("type"), .string("attribute"), .string("value"),
              ]),
              "additionalProperties": .bool(false),
            ]),
          ]),
        ]),
      ]) { _, new in new },
      required: [
        "session_id", "observation_id", "element_id", "operation", "idempotency_key",
      ],
      schemaExtras: [
        "allOf": .array([
          .object([
            "if": .object([
              "properties": .object([
                "operation": .object([
                  "enum": .array([
                    .string("click"), .string("submit"), .string("press_key"),
                    .string("blur"), .string("commit_input"),
                  ])
                ])
              ]),
              "required": .array([.string("operation")]),
            ]),
            "then": .object(["required": .array([.string("postcondition")])]),
          ]),
          .object([
            "if": .object([
              "properties": .object([
                "operation": .object(["const": .string("fill")])
              ]),
              "required": .array([.string("operation")]),
            ]),
            "then": .object([
              "required": .array([.string("value")]),
              "not": .object(["required": .array([.string("postcondition")])]),
            ]),
          ]),
          .object([
            "if": .object([
              "properties": .object([
                "operation": .object(["const": .string("press_key")])
              ]),
              "required": .array([.string("operation")]),
            ]),
            "then": .object(["required": .array([.string("key")])]),
          ]),
        ])
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
        "Request one native-confirmed SiliconPass credential fill into one fresh HTTPS main-frame username/password pair. If no credential exists, SiliconPass can offer its native create-and-save flow without exposing values to MCP. If the Mac cannot present user authentication, user_presence_unavailable asks the MCP client to unlock the Mac and retry. The tool accepts no credential value, account, provider, submit action, or reusable authorization and returns only a terminal status.",
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
      name: "browser_rotate_siliconpass_password",
      description:
        "Prepare one SiliconPass password rotation in three freshly observed HTTPS password fields. SiliconPass selects the account, generates and durably seals the replacement, fills current/new/confirmation without DOM events or submit, then promotes only after native human confirmation of remote success. MCP receives no credential value.",
      properties: sessionSchemaProperties.merging([
        "observation_id": .object(["type": .string("string")]),
        "current_password_element_id": .object(["type": .string("string")]),
        "new_password_element_id": .object(["type": .string("string")]),
        "confirmation_element_id": .object(["type": .string("string")]),
      ]) { _, new in new },
      required: [
        "session_id", "observation_id", "current_password_element_id",
        "new_password_element_id", "confirmation_element_id",
      ],
      readOnly: false,
      destructive: true
    ),
    tool(
      name: "browser_navigate",
      description:
        "Prepare one exact open-world HTTP(S) navigation for human confirmation. Native local confirmation is the reliable default; MCP multi-round elicitation remains opt-in. Cross-origin redirects return redirect_requires_human_approval with origin-only data. Restricted authentication origins immediately require local human handoff. Then wait for document completion plus mutation quiescence, never network-idle or rAF. URL credentials, local names, and IP literals are blocked.",
      properties: sessionSchemaProperties.merging([
        "url": .object([
          "type": .string("string"), "format": .string("uri"),
          "maxLength": .int(8_192),
        ]),
        "timeout_ms": integerSchema(minimum: 100, maximum: 120_000, defaultValue: 30_000),
        "quiet_window_ms": integerSchema(minimum: 20, maximum: 5_000, defaultValue: 300),
        "approval_mode": .object([
          "type": .string("string"),
          "enum": .array([.string("native"), .string("mcp")]),
          "default": .string("native"),
          "description": .string(
            "native shows a local exact-destination confirmation and is the reliable default; mcp uses a multi-round client elicitation."
          ),
        ]),
      ]) { _, new in new },
      required: ["session_id", "url"],
      readOnly: false,
      destructive: true
    ),
    tool(
      name: "browser_observe",
      description:
        "Return rendered, actionable full-page semantics with provenance and fresh observation-scoped element IDs. Hidden, zero-size, aria-hidden, inert, transparent, and sensitive field values are omitted before serialization. Selects expose only the visible selected label. Restricted authentication origins require local human handoff and return no page semantics. Never reuse an element ID after another observation.",
      properties: sessionSchemaProperties.merging([
        "maximum_elements": integerSchema(minimum: 1, maximum: 2_000, defaultValue: 150),
        "element_offset": integerSchema(minimum: 0, maximum: 100_000, defaultValue: 0),
        "maximum_field_characters": integerSchema(
          minimum: 64, maximum: 4_096, defaultValue: 512),
        "roles": .object([
          "type": .string("array"), "maxItems": .int(16),
          "items": .object([
            "type": .string("string"), "minLength": .int(1), "maxLength": .int(64),
          ]),
          "description": .string("Optional server-side exact semantic-role filter."),
        ]),
        "name_contains": .object([
          "type": .string("string"), "maxLength": .int(128),
          "description": .string(
            "Optional case-insensitive server-side accessible-name substring filter."),
        ]),
      ]) { _, new in new },
      required: ["session_id"],
      readOnly: true
    ),
    tool(
      name: "browser_read_text",
      description:
        "Read bounded visible body text plus rendered log, terminal, preformatted, aria-live, and scrollable text regions. This exposes currently rendered virtualized console lines; scroll and repeat to read other rendered ranges.",
      properties: sessionSchemaProperties.merging([
        "maximum_characters": integerSchema(
          minimum: 1, maximum: 100_000, defaultValue: 20_000)
      ]) { _, new in new },
      required: ["session_id"],
      readOnly: true
    ),
    tool(
      name: "browser_scroll",
      description:
        "Scroll the top-level page by bounded CSS-pixel deltas and return viewport/document bounds. Scrolling invalidates the prior observation, so call browser_observe again.",
      properties: sessionSchemaProperties.merging([
        "delta_x": numberSchema(minimum: -2_000, maximum: 2_000, defaultValue: 0),
        "delta_y": numberSchema(minimum: -2_000, maximum: 2_000, defaultValue: 0),
      ]) { _, new in new },
      required: ["session_id"],
      readOnly: false
    ),
    tool(
      name: "element_scroll_into_view",
      description:
        "Resolve one element from a fresh observation, scroll it to the viewport center, and invalidate that observation. Call browser_observe again before acting.",
      properties: sessionSchemaProperties.merging([
        "observation_id": .object(["type": .string("string")]),
        "element_id": .object(["type": .string("string")]),
      ]) { _, new in new },
      required: ["session_id", "observation_id", "element_id"],
      readOnly: false
    ),
    tool(
      name: "browser_session",
      description:
        "List persistent profiles, open, inspect, close, or transfer one bounded session behind the single WebKitUI MCP authority. Native WebKit is the current trusted-write backend; compatibility and isolated read-only policies fail closed until their internal backends are available. handoff_start returns immediately with a session-bound opaque resume token; handoff_status polls without taking control; handoff_resume consumes the token only after local confirmation and returns a fresh observation. Profile listing never exposes cookies or credentials.",
      properties: sessionSchemaProperties.merging([
        "operation": .object([
          "type": .string("string"),
          "enum": .array([
            .string("open"), .string("profiles"), .string("status"), .string("close"),
            .string("handoff"), .string("handoff_start"), .string("handoff_status"),
            .string("handoff_resume"),
          ]),
        ]),
        "profile_id": .object([
          "type": .string("string"),
          "description": .string(
            "For open only: default or an exact UUID returned by operation=profiles."
          ),
        ]),
        "execution_policy": .object([
          "type": .string("string"),
          "enum": .array([
            .string("auto"), .string("trusted_local"), .string("compatibility"),
            .string("isolated_read_only"),
          ]),
          "default": .string("auto"),
          "description": .string(
            "For open only. Selects an internal backend policy without exposing a second MCP or transferring credentials between backends."
          ),
        ]),
        "resume_token": .object([
          "type": .string("string"), "minLength": .int(1), "maxLength": .int(128),
          "description": .string(
            "Required for handoff_status and handoff_resume; returned only by handoff_start."),
        ]),
      ]) { _, new in new },
      required: ["operation"],
      readOnly: false,
      destructive: true
    ),
    tool(
      name: "browser_transaction",
      description:
        "Read or export a versioned transaction receipt, or reconcile an indeterminate write against a fresh observation. ReceiptV1 is canonical JSON evidence and never authorizes replay. Reconciliation never retries the action.",
      properties: sessionSchemaProperties.merging([
        "operation": .object([
          "type": .string("string"),
          "enum": .array([.string("receipt"), .string("export"), .string("reconcile")]),
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
    schemaExtras: [String: JSONValue] = [:],
    readOnly: Bool,
    destructive: Bool = false
  ) -> JSONValue {
    var inputSchema: [String: JSONValue] = [
      "type": .string("object"),
      "properties": .object(properties),
      "required": .array(required.map(JSONValue.string)),
      "additionalProperties": .bool(false),
    ]
    for (key, value) in schemaExtras { inputSchema[key] = value }
    return .object([
      "name": .string(name),
      "description": .string(description),
      "inputSchema": .object(inputSchema),
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

  private static func numberSchema(
    minimum: Double,
    maximum: Double,
    defaultValue: Double
  ) -> JSONValue {
    .object([
      "type": .string("number"),
      "minimum": .double(minimum),
      "maximum": .double(maximum),
      "default": .double(defaultValue),
    ])
  }
}
