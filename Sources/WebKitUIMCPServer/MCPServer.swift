import CryptoKit
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
  private let safariCompatibilityPresenter: any SafariCompatibilityPresenting
  private let preserveBrowserOnClose: Bool
  private let transactionLedgerFactory: WebKitTransactionLedgerFactory
  private let activityLog: WebKitActivityLog?
  private let goalDelegationMonitor: GoalDelegationMonitor
  private let clientAuthorityID = UUID()
  private var clientName = "unknown-client"
  private var clientVersion: String?
  private let capabilityAuthority = CapabilityAuthority()
  private var observations: [WebKitSessionHandle: WebKitPageObservation] = [:]
  private var coordinators: [WebKitSessionHandle: WebKitTransactionCoordinator] = [:]
  private var sessionBackends: [WebKitSessionHandle: String] = [:]
  private var pendingActuations: [String: PendingActuation] = [:]
  private var pendingHandoffs: [String: PendingHandoff] = [:]
  private var pendingNavigations: [String: PendingNavigation] = [:]
  private var safariCompatibilityHandoffs: Set<WebKitSessionHandle> = []
  private var goalDelegations: [WebKitSessionHandle: GoalDelegation] = [:]
  private struct CompletedDownload {
    let arguments: [String: JSONValue]
    let receipt: WebKitDownloadReceipt
  }
  private var completedDownloads: [String: CompletedDownload] = [:]

  private enum ActPostcondition {
    case urlEquals(String)
    case urlPrefix(String)
    case urlChangesFrom(String)
    case urlContains(String)
    case titleEquals(String)
    case titleContains(String)
    case headingEquals(String)
    case headingContains(String)
    case semanticTextAppears(String)
    case semanticTextContains(String)
    case checkedEquals(Bool)
    case selectedEquals(Bool)
    case enabledEquals(Bool)
    case valueEquals(String)
    case validationState(String)
    case characterCountEquals(Int)
    case attributeEquals(name: String, value: String)
    case dialogAppears(String)
    case panelOpen(String)
    case optionSelected(String)

    var confirmationDescription: String {
      switch self {
      case .urlEquals(let value): "URL equals \(value)"
      case .urlPrefix(let value): "URL begins with \(value)"
      case .urlChangesFrom(let value): "URL changes from \(value)"
      case .urlContains(let value): "URL contains \(value)"
      case .titleEquals(let value): "page title equals \(value)"
      case .titleContains(let value): "page title contains \(value)"
      case .headingEquals(let value): "new step heading equals \(value)"
      case .headingContains(let value): "new step heading contains \(value)"
      case .semanticTextAppears(let value): "new semantic text appears: \(value)"
      case .semanticTextContains(let value): "new semantic text contains: \(value)"
      case .checkedEquals(let value): "target checked equals \(value)"
      case .selectedEquals(let value): "target selected equals \(value)"
      case .enabledEquals(let value): "target enabled equals \(value)"
      case .valueEquals(let value): "target value equals \(value)"
      case .validationState(let value): "target validation state equals \(value)"
      case .characterCountEquals(let value): "target character count equals \(value)"
      case .attributeEquals(let name, let value): "target \(name) equals \(value)"
      case .dialogAppears(let value): "dialog appears with accessible name \(value)"
      case .panelOpen(let value): "panel opens with accessible name \(value)"
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
      case .urlPrefix(let value):
        return .entryTextPrefixDigest(
          .init(frameID: "main", elementID: "@page", field: "url"),
          ObservationPredicate.textDigest(of: value), value.utf8.count)
      case .urlChangesFrom(let value):
        return .entryTextNotDigest(
          .init(frameID: "main", elementID: "@page", field: "url"),
          ObservationPredicate.textDigest(of: value)
        )
      case .urlContains(let value):
        let parameters = ObservationPredicate.containsParameters(of: value)
        return .anyEntryTextContainsDigest(
          [.url], parameters.digest, parameters.length, parameters.rolling)
      case .titleEquals(let value):
        return .entryTextDigest(
          .init(frameID: "main", elementID: "@page", field: "title"),
          ObservationPredicate.textDigest(of: value)
        )
      case .titleContains(let value):
        let parameters = ObservationPredicate.containsParameters(of: value)
        return .anyEntryTextContainsDigest(
          [.title], parameters.digest, parameters.length, parameters.rolling)
      case .headingEquals(let value):
        return .anyEntryTextDigest(
          [.heading], ObservationPredicate.textDigest(of: value))
      case .headingContains(let value):
        let parameters = ObservationPredicate.containsParameters(of: value)
        return .anyEntryTextContainsDigest(
          [.heading], parameters.digest, parameters.length, parameters.rolling)
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
      case .validationState(let value): return targetField("@validation_state", value)
      case .characterCountEquals(let value): return targetField("@character_count", String(value))
      case .attributeEquals(let name, let value):
        return targetField("@attribute:\(name)", value)
      case .dialogAppears(let value):
        return .anyEntryTextDigest([.dialogName], ObservationPredicate.textDigest(of: value))
      case .panelOpen(let value):
        return .anyEntryTextDigest([.panelName], ObservationPredicate.textDigest(of: value))
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

  private struct PendingNavigation {
    let arguments: [String: JSONValue]
    let session: WebKitSessionHandle
    let url: URL
    let timeoutMilliseconds: Int64
    let quietWindowMilliseconds: Int64
    let goalDelegationID: String?
    let expiresAt: Date
  }

  public init(
    maximumSessions: Int = 1,
    enforceHostExclusiveSession: Bool = false,
    preserveBrowserOnClose: Bool = false,
    transactionLedgerFactory: WebKitTransactionLedgerFactory = .inMemory,
    activityLog: WebKitActivityLog? = nil,
    goalDelegationMonitor: GoalDelegationMonitor = GoalDelegationMonitor()
  ) throws {
    self.registry = try WebKitSessionRegistry(
      maximumSessions: maximumSessions,
      enforceHostExclusiveSession: enforceHostExclusiveSession)
    self.presentHumanWindows = true
    self.credentialBroker = SyntheticCredentialBrokerXPCClient()
    self.confirmationPresenter = NativeBrowserConfirmationPresenter()
    self.safariCompatibilityPresenter = NativeSafariCompatibilityPresenter()
    self.preserveBrowserOnClose = preserveBrowserOnClose
    self.transactionLedgerFactory = transactionLedgerFactory
    self.activityLog = activityLog
    self.goalDelegationMonitor = goalDelegationMonitor
  }

  /// Creates one client-scoped authority surface over a host-owned durable
  /// browser registry. Multiple transports may discover tools concurrently,
  /// while the shared runtime keeps browser control serialized and stale
  /// observations fail closed.
  public init(
    durableRegistry registry: WebKitSessionRegistry,
    transactionLedgerFactory: WebKitTransactionLedgerFactory = .inMemory,
    activityLog: WebKitActivityLog? = nil,
    goalDelegationMonitor: GoalDelegationMonitor = GoalDelegationMonitor()
  ) {
    self.registry = registry
    self.presentHumanWindows = true
    self.credentialBroker = SyntheticCredentialBrokerXPCClient()
    self.confirmationPresenter = NativeBrowserConfirmationPresenter()
    self.safariCompatibilityPresenter = NativeSafariCompatibilityPresenter()
    self.preserveBrowserOnClose = true
    self.transactionLedgerFactory = transactionLedgerFactory
    self.activityLog = activityLog
    self.goalDelegationMonitor = goalDelegationMonitor
  }

  init(
    registry: WebKitSessionRegistry,
    presentHumanWindows: Bool = false,
    credentialBroker: any CredentialBrokerFilling = SyntheticCredentialBrokerXPCClient(),
    confirmationPresenter: any BrowserConfirmationPresenting =
      NativeBrowserConfirmationPresenter(),
    safariCompatibilityPresenter: any SafariCompatibilityPresenting =
      NativeSafariCompatibilityPresenter(),
    preserveBrowserOnClose: Bool = false,
    transactionLedgerFactory: WebKitTransactionLedgerFactory = .inMemory,
    activityLog: WebKitActivityLog? = nil,
    goalDelegationMonitor: GoalDelegationMonitor = GoalDelegationMonitor()
  ) {
    self.registry = registry
    self.presentHumanWindows = presentHumanWindows
    self.credentialBroker = credentialBroker
    self.confirmationPresenter = confirmationPresenter
    self.safariCompatibilityPresenter = safariCompatibilityPresenter
    self.preserveBrowserOnClose = preserveBrowserOnClose
    self.transactionLedgerFactory = transactionLedgerFactory
    self.activityLog = activityLog
    self.goalDelegationMonitor = goalDelegationMonitor
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
    goalDelegations.removeAll(keepingCapacity: false)
    safariCompatibilityHandoffs.removeAll(keepingCapacity: false)
    registry.releaseHandoffOwnerships(owner: clientAuthorityID)
    registry.releaseSessionOwnerships(owner: clientAuthorityID)
    await capabilityAuthority.revokeAll()
    await goalDelegationMonitor.clear()
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
    let startedAt = Date()
    let rawToolName = params?.objectValue?["name"]?.stringValue
    registry.beginClientCall(owner: clientAuthorityID)
    defer { registry.endClientCall(owner: clientAuthorityID) }
    do {
      let result = try await performToolCall(params: params, modern: modern)
      let failed = result.objectValue?["isError"] == .bool(true)
      await activityLog?.record(
        method: "tools/call",
        toolName: rawToolName,
        outcome: failed ? .failed : .succeeded,
        durationMilliseconds: Self.elapsedMilliseconds(since: startedAt),
        errorType: failed ? "tool_error" : nil
      )
      return result
    } catch {
      await activityLog?.record(
        method: "tools/call",
        toolName: rawToolName,
        outcome: .failed,
        durationMilliseconds: Self.elapsedMilliseconds(since: startedAt),
        errorType: String(describing: type(of: error))
      )
      throw error
    }
  }

  private func performToolCall(params: JSONValue?, modern: Bool) async throws -> JSONValue {
    let params = try requireObject(params, named: "params")
    let name = try requireString(params["name"], named: "name")
    let arguments = params["arguments"]?.objectValue ?? [:]

    if name != "browser_session", arguments["session_id"] != nil {
      let requestedHandle = try sessionHandle(arguments)
      let ownershipState = try registry.sessionOwnershipState(
        for: requestedHandle, owner: clientAuthorityID)
      if ownershipState == "inactive" {
        _ = try registry.claimSessionOwnership(
          for: requestedHandle, owner: clientAuthorityID, holder: clientHolder())
      } else if ownershipState == "owned_elsewhere" {
        return try sessionInUseResult(handle: requestedHandle, modern: modern)
      } else {
        _ = try registry.claimSessionOwnership(
          for: requestedHandle, owner: clientAuthorityID, holder: clientHolder())
      }
    }

    if Self.authenticationRestrictedTools.contains(name) {
      let restrictedHandle = try sessionHandle(arguments)
      let runtime = try registry.runtime(for: restrictedHandle)
      if let restriction = runtime.authenticationRestrictionStatus() {
        observations.removeValue(forKey: restrictedHandle)
        await revokeGoalDelegation(for: restrictedHandle)
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
        let compact: Bool
        switch arguments["compact"] {
        case .bool(let value): compact = value
        case nil: compact = false
        default: throw MCPServerError.invalidParams("compact must be a boolean")
        }
        let compactFields = try boundedStringArray(
          arguments["fields"], named: "fields", maximumCount: 10,
          maximumLength: 32, allowEmpty: true)
        let allowedCompactFields: Set<String> = [
          "tag", "role", "name", "label", "text", "href", "context", "bbox", "state",
          "locator_quality",
        ]
        guard compactFields.allSatisfy(allowedCompactFields.contains) else {
          throw MCPServerError.invalidParams("fields contains an unsupported compact field")
        }
        guard compact || compactFields.isEmpty else {
          throw MCPServerError.invalidParams("fields requires compact=true")
        }
        let observation = try await runtime.observe(
          maximumElements: maximum,
          elementOffset: elementOffset,
          maximumFieldCharacters: maximumFieldCharacters,
          roles: roles,
          nameContains: nameContains)
        observations[handle] = observation
        if compact {
          let selectedFields =
            compactFields.isEmpty
            ? Set(["role", "name", "href", "bbox", "state", "locator_quality"])
            : Set(compactFields)
          return try toolResult(
            structured: compactObservation(observation, fields: selectedFields),
            modern: modern,
            duplicateStructuredInText: !modern)
        }
        var observed = try requireObject(.encoded(observation), named: "browser observation")
        // Locator recipes remain server-private. Clients act through ephemeral element IDs,
        // while locatorQuality exposes the useful uniqueness decision without duplicating
        // every semantic field in the wire payload.
        if case .array(let encodedElements) = observed["elements"] {
          observed["elements"] = .array(
            encodedElements.map { encodedElement in
              guard case .object(var element) = encodedElement else { return encodedElement }
              element.removeValue(forKey: "locatorRecipe")
              return .object(element)
            })
        }
        let dialogs = observation.elements.filter {
          $0.role?.segments.map(\.text).joined().lowercased() == "dialog"
        }
        observed["modal_state"] = .object([
          "active": .bool(!dialogs.isEmpty),
          "dialog_element_ids": .array(dialogs.map { .string($0.elementID) }),
          "safe_next_step": .string(
            dialogs.isEmpty
              ? "none"
              : "Inspect and act on the exact dialog; never replay the preceding write."
          ),
        ])
        observed["file_upload_receipt"] =
          try runtime.latestFileUploadReceipt()
          .map(JSONValue.encoded) ?? .null
        observed["latest_navigation"] =
          try runtime.latestNavigationAuditEvent()
          .map(JSONValue.encoded) ?? .null
        observed["navigation_event_count"] = .int(Int64(runtime.navigationAuditEventCount()))
        observed["file_picker_visible"] = .bool(runtime.isFilePickerVisible())
        return try toolResult(structured: .object(observed), modern: modern)
      case "browser_inspect_element":
        let handle = try sessionHandle(arguments)
        let observationID = try requireString(
          arguments["observation_id"], named: "observation_id")
        guard
          let observation = observations[handle],
          observation.observationID == observationID
        else { throw MCPServerError.invalidParams("observation_id is stale") }
        let elementID = try requireString(arguments["element_id"], named: "element_id")
        guard let element = observation.elements.first(where: { $0.elementID == elementID }) else {
          throw MCPServerError.invalidParams("element_id is not in that observation")
        }
        return try toolResult(
          structured: inspectElement(element, observation: observation), modern: modern)
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
      case "browser_download":
        return try await downloadTool(arguments: arguments, modern: modern)
      case "browser_upload":
        return try await uploadTool(arguments: arguments, modern: modern)
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
    } catch WebKitSessionRegistryError.hostControllerBusy(let holder) {
      return try structuredToolError(
        structured: .object([
          "code": .string("host_controller_busy"),
          "message": .string("Another local client currently holds the WebKitUI host."),
          "remediation": .string(
            "Inspect browser_session operation=status without a session_id, then wait for the holder to disconnect."
          ),
          "holder": holderValue(holder),
          "control_available": .bool(false),
          "wait_only": .bool(true),
        ]),
        modern: modern)
    } catch WebKitRuntimeError.targetNotActionable {
      return try toolError(
        "target_not_actionable: scroll/re-observe first; if the site requires a trusted human gesture, use browser_session operation=handoff",
        modern: modern)
    } catch WebKitRuntimeError.downloadReceiptTimedOut(let started) {
      return try structuredToolError(
        structured: .object([
          "status": .string("download_timeout"),
          "reason": .string("download_receipt_timed_out"),
          "download_started": .bool(started),
          "download_completed": .bool(false),
          "artifact_exists": .bool(false),
        ]),
        modern: modern)
    } catch WebKitRuntimeError.unsupportedDownload(let httpStatus) {
      return try structuredToolError(
        structured: .object([
          "status": .string("unsupported_download"),
          "reason": .string("response_is_not_a_download"),
          "http_status": httpStatus.map { .int(Int64($0)) } ?? .null,
          "download_started": .bool(false),
          "download_completed": .bool(false),
          "artifact_exists": .bool(false),
        ]),
        modern: modern)
    } catch WebKitRuntimeError.downloadHTTPFailure(let status) {
      return try structuredToolError(
        structured: .object([
          "status": .string("download_http_error"),
          "reason": .string("non_success_http_status"),
          "http_status": .int(Int64(status)),
          "download_started": .bool(false),
          "download_completed": .bool(false),
          "artifact_exists": .bool(false),
        ]),
        modern: modern)
    } catch WebKitRuntimeError.downloadFailed(let reason) {
      return try structuredToolError(
        structured: .object([
          "status": .string("download_failed"),
          "reason": .string(reason),
          "download_completed": .bool(false),
          "artifact_exists": .bool(false),
        ]),
        modern: modern)
    } catch {
      return try toolError(String(describing: error), modern: modern)
    }
  }

  nonisolated private static func elapsedMilliseconds(since start: Date) -> Int {
    max(0, Int(Date().timeIntervalSince(start) * 1_000))
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
        "recommended_user_action": .string(
          fullBrowserRequired
            ? "continue_in_safari_or_another_full_browser"
            : "complete_sensitive_step_in_native_handoff"),
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
    if operation != "open", operation != "profiles", operation != "status",
      operation != "client_handoff"
    {
      let handle = try sessionHandle(arguments)
      let ownershipState = try registry.sessionOwnershipState(
        for: handle, owner: clientAuthorityID)
      if ownershipState == "inactive" {
        _ = try registry.claimSessionOwnership(
          for: handle, owner: clientAuthorityID, holder: clientHolder())
      } else if ownershipState == "owned_elsewhere" {
        return try sessionInUseResult(handle: handle, modern: modern)
      } else {
        _ = try registry.claimSessionOwnership(
          for: handle, owner: clientAuthorityID, holder: clientHolder())
      }
    }
    switch operation {
    case "open":
      guard
        arguments.keys.allSatisfy({
          $0 == "operation" || $0 == "profile_id" || $0 == "execution_policy"
            || $0 == "wait_timeout_ms"
        })
      else {
        throw MCPServerError.invalidParams(
          "open accepts only operation, profile_id, execution_policy, and wait_timeout_ms")
      }
      let requestedProfile = arguments["profile_id"]?.stringValue ?? "default"
      let executionPolicy = arguments["execution_policy"]?.stringValue ?? "auto"
      let waitTimeoutMilliseconds = try boundedInteger(
        arguments["wait_timeout_ms"], defaultValue: 0, range: 0...60_000,
        name: "wait_timeout_ms")
      guard
        ["auto", "trusted_local"].contains(executionPolicy)
      else {
        throw MCPServerError.invalidParams(
          "execution_policy must be auto or trusted_local")
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
        ? try await registry.openOrReuse(
          profileIdentifier: profileIdentifier,
          holder: clientHolder(policy: executionPolicy),
          waitTimeoutMilliseconds: waitTimeoutMilliseconds)
        : (
          handle: try await registry.open(
            profileIdentifier: profileIdentifier,
            holder: clientHolder(policy: executionPolicy),
            waitTimeoutMilliseconds: waitTimeoutMilliseconds),
          reused: false
        )
      let handle = opened.handle
      let controlAvailable = try registry.claimSessionOwnership(
        for: handle, owner: clientAuthorityID, holder: clientHolder(policy: executionPolicy))
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
          "client_control_state": .string(
            controlAvailable ? "owned_by_this_client" : "owned_elsewhere"),
          "control_available": .bool(controlAvailable),
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
            .string("auto"), .string("trusted_local"),
          ]),
          "unavailable_execution_policies": .object([
            "compatibility": .string("use operation=compatibility_start after local confirmation"),
            "isolated_read_only": .string("not implemented"),
          ]),
          "authenticated_origins": .array([]),
          "authenticated_origins_status": .string(
            "not_observable_without_inspecting_credentials_or_cookies"),
          "restricted_origins": .array([
            .string("https://idmsa.apple.com")
          ]),
        ]),
        modern: modern)
    case "status":
      guard arguments.keys.allSatisfy({ $0 == "operation" || $0 == "session_id" }) else {
        throw MCPServerError.invalidParams("status accepts only operation and session_id")
      }
      let handle: WebKitSessionHandle
      if arguments["session_id"] != nil {
        handle = try sessionHandle(arguments)
      } else if let existing = registry.existingHandle {
        handle = existing
      } else {
        if let holder = registry.externalHostControllerHolder() {
          return try toolResult(
            structured: .object([
              "status": .string("host_controller_busy"),
              "control_available": .bool(false),
              "wait_only": .bool(true),
              "holder": holderValue(holder),
              "remediation": .string(
                "Retry open with wait_timeout_ms up to 60000, or wait for the holder to disconnect."
              ),
            ]), modern: modern)
        }
        return try toolResult(
          structured: .object([
            "status": .string("no_active_session"),
            "control_available": .bool(true),
            "holder": .null,
          ]), modern: modern)
      }
      let status = try registry.status(handle)
      var statusObject = try requireObject(.encoded(status), named: "session status")
      statusObject["session_id"] = .string(handle.rawValue.uuidString)
      statusObject["control_state"] = .string(status.controlState.rawValue)
      statusObject["human_step_completed"] = .bool(
        status.controlState == .humanStepCompleted)
      statusObject["selected_backend"] = .string(sessionBackends[handle] ?? "native_webkit")
      statusObject["handoff_active"] = .bool(
        registry.hasActiveHandoffResumeCapability(for: handle))
      statusObject["handoff_owner_state"] = .string(
        try registry.handoffOwnershipState(for: handle, owner: clientAuthorityID))
      statusObject["session_owner_state"] = .string(
        try registry.sessionOwnershipState(for: handle, owner: clientAuthorityID))
      statusObject["holder"] = holderValue(try registry.sessionOwner(for: handle))
      statusObject["file_upload_receipt"] =
        try registry.runtime(for: handle)
        .latestFileUploadReceipt().map(JSONValue.encoded) ?? .null
      statusObject["latest_navigation"] =
        try registry.runtime(for: handle)
        .latestNavigationAuditEvent().map(JSONValue.encoded) ?? .null
      statusObject["navigation_event_count"] = .int(
        Int64(try registry.runtime(for: handle).navigationAuditEventCount()))
      // Host names only: a client can tell whether this profile is already signed in
      // to an origin without any cookie ever leaving the store.
      let statusRuntime = try registry.runtime(for: handle)
      statusObject["authenticated_origins"] = .array(
        await statusRuntime.authenticatedOrigins().map(JSONValue.string))
      statusObject["file_picker_visible"] = .bool(
        try registry.runtime(for: handle).isFilePickerVisible())
      statusObject["native_confirmation_state"] = .string(confirmationPresenter.state.rawValue)
      statusObject["native_confirmation_cancel_available"] = .bool(
        confirmationPresenter.state == .pending)
      statusObject["safari_compatibility_handoff_active"] = .bool(
        safariCompatibilityHandoffs.contains(handle))
      if let delegation = await activeGoalDelegation(for: handle) {
        statusObject["goal_delegation"] = goalDelegationStatus(delegation)
      } else {
        statusObject["goal_delegation"] = .object(["state": .string("inactive")])
      }
      return try toolResult(
        structured: .object(statusObject), modern: modern)
    case "confirmation_cancel":
      let handle = try sessionHandle(arguments)
      _ = try registry.status(handle)
      guard arguments.keys.allSatisfy({ $0 == "operation" || $0 == "session_id" }) else {
        throw MCPServerError.invalidParams(
          "confirmation_cancel accepts only operation and session_id")
      }
      let wasPending = confirmationPresenter.state == .pending
      confirmationPresenter.cancel()
      return try toolResult(
        structured: .object([
          "cancel_requested": .bool(wasPending),
          "native_confirmation_state": .string(confirmationPresenter.state.rawValue),
        ]), modern: modern)
    case "close":
      let handle = try sessionHandle(arguments)
      observations.removeValue(forKey: handle)
      coordinators.removeValue(forKey: handle)
      sessionBackends.removeValue(forKey: handle)
      pendingActuations = pendingActuations.filter { $0.value.session != handle }
      pendingHandoffs = pendingHandoffs.filter { $0.value.session != handle }
      let ownsHandoff =
        try registry.handoffOwnershipState(for: handle, owner: clientAuthorityID)
        == "owned_by_this_client"
      if ownsHandoff {
        registry.revokeHandoffResumeCapabilities(for: handle)
        registry.releaseHandoffOwnership(for: handle, owner: clientAuthorityID)
      }
      pendingNavigations = pendingNavigations.filter { $0.value.session != handle }
      await revokeGoalDelegation(for: handle)
      safariCompatibilityHandoffs.remove(handle)
      if !preserveBrowserOnClose {
        try registry.close(handle)
      } else {
        registry.releaseSessionOwnership(for: handle, owner: clientAuthorityID)
      }
      return try toolResult(
        structured: .object([
          "closed": .bool(true),
          "browser_preserved": .bool(preserveBrowserOnClose),
        ]),
        modern: modern)
    case "client_handoff":
      return try await clientHandoff(arguments: arguments, modern: modern)
    case "handoff":
      await revokeGoalDelegation(for: try sessionHandle(arguments))
      return try await handoffTool(params: params, arguments: arguments, modern: modern)
    case "handoff_start":
      await revokeGoalDelegation(for: try sessionHandle(arguments))
      return try asynchronousHandoffStart(arguments: arguments, modern: modern)
    case "handoff_status":
      return try asynchronousHandoffStatus(arguments: arguments, modern: modern)
    case "handoff_resume":
      return try await asynchronousHandoffResume(arguments: arguments, modern: modern)
    case "compatibility_start":
      await revokeGoalDelegation(for: try sessionHandle(arguments))
      return try await safariCompatibilityStart(arguments: arguments, modern: modern)
    case "goal_delegation_start":
      return try await goalDelegationStart(arguments: arguments, modern: modern)
    case "goal_delegation_status":
      return try await goalDelegationStatusTool(arguments: arguments, modern: modern)
    case "goal_delegation_revoke":
      return try await goalDelegationRevoke(arguments: arguments, modern: modern)
    default:
      throw MCPServerError.invalidParams(
        "operation must be open, profiles, status, close, client_handoff, handoff, handoff_start, handoff_status, handoff_resume, compatibility_start, goal_delegation_start, goal_delegation_status, goal_delegation_revoke, or confirmation_cancel"
      )
    }
  }

  private func sessionInUseResult(
    handle: WebKitSessionHandle, modern: Bool
  ) throws -> JSONValue {
    try structuredToolError(
      structured: .object([
        "code": .string("session_in_use"),
        "message": .string("Another local client owns this browser session."),
        "remediation": .string(
          "Wait for the holder to disconnect, or request browser_session operation=client_handoff for local human confirmation."
        ),
        "holder": holderValue(try registry.sessionOwner(for: handle)),
        "status": .string("session_in_use"),
        "control_available": .bool(false),
        "wait_only": .bool(true),
        "safe_next_step": .string(
          "Wait for the current owner to disconnect, or request a local human-confirmed client_handoff; do not navigate or act until transfer succeeds."
        ),
      ]),
      modern: modern)
  }

  private func clientHandoff(
    arguments: [String: JSONValue], modern: Bool
  ) async throws -> JSONValue {
    let handle = try sessionHandle(arguments)
    guard arguments.keys.allSatisfy({ $0 == "operation" || $0 == "session_id" }) else {
      throw MCPServerError.invalidParams(
        "client_handoff accepts only operation and session_id")
    }
    let ownershipState = try registry.sessionOwnershipState(
      for: handle, owner: clientAuthorityID)
    if ownershipState == "owned_by_this_client" {
      return try toolResult(
        structured: .object([
          "status": .string("already_owner"),
          "control_available": .bool(true),
        ]), modern: modern)
    }
    if ownershipState == "inactive" {
      _ = try registry.claimSessionOwnership(
        for: handle, owner: clientAuthorityID, holder: clientHolder())
      return try toolResult(
        structured: .object([
          "status": .string("ownership_claimed"),
          "control_available": .bool(true),
        ]), modern: modern)
    }
    let previousHolder = try registry.sessionOwner(for: handle)
    guard
      await confirmationPresenter.confirm(
        title: "Transfer WebKitUI Control",
        message:
          "Transfer browser control from \(previousHolder?.clientName ?? "another local client") "
          + "(PID \(previousHolder.map { String($0.processID) } ?? "unknown")) to "
          + "\(clientName) (PID \(getpid()))? The previous client will immediately lose "
          + "navigation and action authority. No cookies or credentials are transferred.",
        approveLabel: "Transfer Control"
      ) == .approved
    else {
      return try structuredToolError(
        structured: .object([
          "code": .string("client_handoff_declined"),
          "message": .string("The local user did not approve the client handoff."),
          "remediation": .string("Keep waiting or ask the user to approve a later request."),
          "holder": holderValue(previousHolder),
        ]), modern: modern)
    }
    guard
      try registry.transferSessionOwnership(
        for: handle, to: clientAuthorityID, holder: clientHolder())
    else {
      return try structuredToolError(
        structured: .object([
          "code": .string("client_handoff_owner_active"),
          "message": .string("The current owner is executing a tool call."),
          "remediation": .string("Wait for that call to finish, then request handoff again."),
          "holder": holderValue(try registry.sessionOwner(for: handle)),
        ]), modern: modern)
    }
    sessionBackends[handle] = "native_webkit"
    coordinators[handle] = WebKitTransactionCoordinator(
      runtime: try registry.runtime(for: handle),
      ledger: try transactionLedgerFactory.make(scope: try registry.status(handle).profileID)
    )
    return try toolResult(
      structured: .object([
        "status": .string("ownership_transferred"),
        "control_available": .bool(true),
        "previous_holder": holderValue(previousHolder),
        "holder": holderValue(try registry.sessionOwner(for: handle)),
      ]), modern: modern)
  }

  private func clientHolder(policy: String = "auto") -> WebKitControllerHolder {
    WebKitControllerHolder(
      clientName: clientName,
      clientVersion: clientVersion,
      executionPolicy: policy)
  }

  private func holderValue(_ holder: WebKitControllerHolder?) -> JSONValue {
    guard let holder else { return .null }
    let now = Date()
    return .object([
      "client_name": .string(holder.clientName),
      "client_version": holder.clientVersion.map(JSONValue.string) ?? .null,
      "pid": .int(Int64(holder.processID)),
      "age_ms": .int(Int64(max(0, now.timeIntervalSince(holder.acquiredAt) * 1_000))),
      "inactive_ms": .int(
        Int64(max(0, now.timeIntervalSince(holder.lastActivityAt) * 1_000))),
      "policy": .string(holder.executionPolicy),
      // The record is written on acquisition, not by whoever holds the lock now. A
      // dead pid means the record is stale and its name, age and policy describe a
      // process that is gone: the host is still held, but by someone else.
      "pid_alive": .bool(holder.processIsRunning),
      "record_trustworthy": .bool(holder.processIsRunning),
      // The pid is the broker's, never the MCP client's: clients reach the broker
      // over a socket and their liveness is not tracked. When this is true, pid_alive
      // says nothing about whether the owning client is still there.
      "pid_is_this_broker": .bool(holder.processID == ProcessInfo.processInfo.processIdentifier),
    ])
  }

  private func goalDelegationStart(
    arguments: [String: JSONValue], modern: Bool
  ) async throws -> JSONValue {
    let allowedKeys = Set([
      "operation", "session_id", "goal_display", "origin", "path_prefixes",
      "allowed_query_keys", "duration_seconds", "maximum_navigations",
    ])
    guard Set(arguments.keys).isSubset(of: allowedKeys) else {
      throw MCPServerError.invalidParams("goal_delegation_start received an unknown field")
    }
    let handle = try sessionHandle(arguments)
    let runtime = try registry.runtime(for: handle)
    guard runtime.authenticationRestrictionStatus() == nil else {
      throw MCPServerError.invalidParams(
        "goal delegation cannot start on an authentication-restricted origin")
    }
    let goalDisplay = try requireString(arguments["goal_display"], named: "goal_display")
    guard goalDisplay.count <= 200 else {
      throw MCPServerError.invalidParams("goal_display must contain at most 200 characters")
    }
    let origin = try safeNavigationURL(try requireString(arguments["origin"], named: "origin"))
    let pathPrefixes = try boundedStringArray(
      arguments["path_prefixes"], named: "path_prefixes", maximumCount: 16,
      maximumLength: 1_024, allowEmpty: false)
    let queryKeys = try boundedStringArray(
      arguments["allowed_query_keys"], named: "allowed_query_keys", maximumCount: 16,
      maximumLength: 128, allowEmpty: true)
    let duration = try boundedInteger(
      arguments["duration_seconds"], defaultValue: 900, range: 60...3_600,
      name: "duration_seconds")
    let maximumNavigations = try boundedInteger(
      arguments["maximum_navigations"], defaultValue: 30, range: 1...100,
      name: "maximum_navigations")
    let now = Date()
    let delegation: GoalDelegation
    do {
      delegation = try GoalDelegation(
        goalDisplay: goalDisplay,
        origin: origin,
        pathPrefixes: pathPrefixes,
        allowedQueryKeys: Set(queryKeys),
        issuedAt: now,
        expiresAt: now.addingTimeInterval(TimeInterval(duration)),
        maximumNavigations: maximumNavigations)
    } catch {
      throw MCPServerError.invalidParams("goal delegation scope is invalid or unsafe")
    }

    let pathSummary = delegation.pathPrefixes.joined(separator: ", ")
    let querySummary =
      delegation.allowedQueryKeys.isEmpty
      ? "none" : delegation.allowedQueryKeys.sorted().joined(separator: ", ")
    guard
      await confirmationPresenter.confirm(
        title: "Delegate Browser Goal",
        message:
          "Temporarily auto-authorize navigation only? Goal: \(jsonQuoted(goalDisplay)). "
          + "Origin: \(delegation.originDisplay). Paths: \(jsonQuoted(pathSummary)). "
          + "Allowed query keys: \(jsonQuoted(querySummary)). Duration: \(duration) seconds. "
          + "Budget: \(maximumNavigations) navigations. Authentication, secrets/tokens, "
          + "payments, permissions, sends, deletion, uploads, deployment and publication "
          + "always stop and require an exact confirmation.",
        approveLabel: "Delegate Temporarily"
      ) == .approved
    else {
      return try toolResult(
        structured: .object([
          "state": .string("declined"),
          "automatic_navigation_enabled": .bool(false),
        ]), modern: modern)
    }
    goalDelegations[handle] = delegation
    await goalDelegationMonitor.publish(goalDelegationSnapshot(delegation))
    return try toolResult(
      structured: goalDelegationStatus(delegation), modern: modern)
  }

  private func goalDelegationStatusTool(
    arguments: [String: JSONValue], modern: Bool
  ) async throws -> JSONValue {
    guard arguments.keys.allSatisfy({ $0 == "operation" || $0 == "session_id" }) else {
      throw MCPServerError.invalidParams(
        "goal_delegation_status accepts only operation and session_id")
    }
    let handle = try sessionHandle(arguments)
    _ = try registry.status(handle)
    let structured =
      await activeGoalDelegation(for: handle).map(goalDelegationStatus)
      ?? .object(["state": .string("inactive")])
    return try toolResult(structured: structured, modern: modern)
  }

  private func goalDelegationRevoke(
    arguments: [String: JSONValue], modern: Bool
  ) async throws -> JSONValue {
    guard arguments.keys.allSatisfy({ $0 == "operation" || $0 == "session_id" }) else {
      throw MCPServerError.invalidParams(
        "goal_delegation_revoke accepts only operation and session_id")
    }
    let handle = try sessionHandle(arguments)
    _ = try registry.status(handle)
    let revoked = goalDelegations[handle] != nil
    await revokeGoalDelegation(for: handle)
    return try toolResult(
      structured: .object([
        "state": .string("inactive"),
        "revoked": .bool(revoked),
        "automatic_navigation_enabled": .bool(false),
      ]), modern: modern)
  }

  private func activeGoalDelegation(for handle: WebKitSessionHandle) async -> GoalDelegation? {
    guard let delegation = goalDelegations[handle] else { return nil }
    guard
      delegation.expiresAt > Date(), delegation.remainingNavigations > 0,
      !(await goalDelegationMonitor.isRevoked(delegation.identifier))
    else {
      goalDelegations.removeValue(forKey: handle)
      await goalDelegationMonitor.clear(identifier: delegation.identifier)
      return nil
    }
    return delegation
  }

  private func authorizeGoalDelegatedNavigation(
    session handle: WebKitSessionHandle, url: URL
  ) async -> String? {
    guard var delegation = await activeGoalDelegation(for: handle) else { return nil }
    switch delegation.authorizeNavigation(to: url, now: Date()) {
    case .allowed:
      goalDelegations[handle] = delegation
      await goalDelegationMonitor.publish(goalDelegationSnapshot(delegation))
      return delegation.identifier
    case .denied:
      // Any scope mismatch is a hard stop. The next navigation takes the exact
      // confirmation path and a fresh delegation must be issued deliberately.
      goalDelegations.removeValue(forKey: handle)
      await goalDelegationMonitor.clear(identifier: delegation.identifier)
      return nil
    }
  }

  private func goalDelegationStatus(_ delegation: GoalDelegation) -> JSONValue {
    .object([
      "state": .string("active"),
      "delegation_id": .string(delegation.identifier),
      "goal_display": .string(delegation.goalDisplay),
      "goal_display_is_authority": .bool(false),
      "origin": .string(delegation.originDisplay),
      "path_prefixes": .array(delegation.pathPrefixes.map(JSONValue.string)),
      "allowed_query_keys": .array(delegation.allowedQueryKeys.sorted().map(JSONValue.string)),
      "expires_at": .string(ISO8601DateFormatter().string(from: delegation.expiresAt)),
      "remaining_navigations": .int(Int64(delegation.remainingNavigations)),
      "automatic_navigation_enabled": .bool(true),
      "hard_stops_enforced": .bool(true),
      "revocable": .bool(true),
    ])
  }

  private func goalDelegationSnapshot(_ delegation: GoalDelegation) -> GoalDelegationSnapshot {
    GoalDelegationSnapshot(
      identifier: delegation.identifier,
      goalDisplay: delegation.goalDisplay,
      origin: delegation.originDisplay,
      expiresAt: delegation.expiresAt,
      remainingNavigations: delegation.remainingNavigations)
  }

  private func revokeGoalDelegation(for handle: WebKitSessionHandle) async {
    let identifier = goalDelegations.removeValue(forKey: handle)?.identifier
    await goalDelegationMonitor.clear(identifier: identifier)
  }

  private func safariCompatibilityStart(
    arguments: [String: JSONValue], modern: Bool
  ) async throws -> JSONValue {
    guard arguments.keys.allSatisfy({ $0 == "operation" || $0 == "session_id" }) else {
      throw MCPServerError.invalidParams(
        "compatibility_start accepts only operation and session_id")
    }
    let handle = try sessionHandle(arguments)
    let runtime = try registry.runtime(for: handle)
    guard
      let restriction = runtime.authenticationRestrictionStatus(),
      restriction.classification == .fullBrowserRequired
    else {
      return try structuredToolError(
        structured: .object([
          "status": .string("compatibility_not_required"),
          "selected_backend": .string(sessionBackends[handle] ?? "native_webkit"),
          "opened": .bool(false),
        ]),
        modern: modern)
    }
    guard
      await confirmationPresenter.confirm(
        title: "Continue Authentication in Safari",
        message:
          "Open \(restriction.origin) in Safari for passkey or security-key authentication?\n\n"
          + "Cookies, credentials, MFA codes, paths, and query parameters are not exposed "
          + "through MCP or copied from WebKitUI.",
        approveLabel: "Open in Safari"
      ) == .approved
    else {
      return try toolResult(
        structured: .object([
          "status": .string("compatibility_handoff_declined"),
          "origin": .string(restriction.origin),
          "opened": .bool(false),
          "credentials_exposed_to_mcp": .bool(false),
        ]),
        modern: modern)
    }

    let privateURL = try runtime.privateFullBrowserHandoffURL()
    guard await safariCompatibilityPresenter.openPrivateAuthenticationURL(privateURL) else {
      return try structuredToolError(
        structured: .object([
          "status": .string("safari_compatibility_unavailable"),
          "origin": .string(restriction.origin),
          "opened": .bool(false),
          "credentials_exposed_to_mcp": .bool(false),
        ]),
        modern: modern)
    }
    safariCompatibilityHandoffs.insert(handle)
    return try toolResult(
      structured: .object([
        "status": .string("safari_compatibility_handoff_started"),
        "origin": .string(restriction.origin),
        "selected_backend": .string(sessionBackends[handle] ?? "native_webkit"),
        "handoff_backend": .string("safari"),
        "opened": .bool(true),
        "session_transfer_supported": .bool(false),
        "cookie_transfer_supported": .bool(false),
        "credential_transfer_supported": .bool(false),
        "credentials_exposed_to_mcp": .bool(false),
        "instructions": .string(
          "Complete passkey or security-key authentication in Safari. WebKitUI remains fail-closed on the restricted origin."
        ),
      ]),
      modern: modern)
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

    if params["requestState"] == nil, params["inputResponses"] == nil,
      let delegationID = await authorizeGoalDelegatedNavigation(session: handle, url: url)
    {
      let pending = PendingNavigation(
        arguments: arguments,
        session: handle,
        url: url,
        timeoutMilliseconds: timeout,
        quietWindowMilliseconds: quiet,
        goalDelegationID: delegationID,
        expiresAt: Date().addingTimeInterval(60)
      )
      return try await executeNavigation(pending, runtime: runtime, modern: modern)
    }

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
      goalDelegationID: nil,
      expiresAt: Date().addingTimeInterval(60)
    )
    if !modern || approvalMode == "native" {
      let currentURL = runtime.agentSafeCurrentURL() ?? "no current page"
      guard
        await confirmationPresenter.confirm(
          title: "Approve Web Navigation",
          message: navigationConfirmationMessage(currentURL: currentURL, url: url),
          approveLabel: "Navigate"
        ) == .approved
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
      let accepted =
        await confirmationPresenter.confirm(
          title: "No Saved SiliconPass Credential",
          message:
            "No credential is saved for \(origin). Continue in the visible browser to sign in manually, then add or update this credential in SiliconPass? No password will be sent through MCP.",
          approveLabel: "Continue Securely"
        ) == .approved
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
    guard try registry.claimHandoffOwnership(for: handle, owner: clientAuthorityID) else {
      return try handoffWaitOnlyResult(runtime: runtime, modern: modern)
    }
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
      case .humanControlled, .humanStepCompleted:
        guard
          await confirmationPresenter.confirm(
            title: "Return Browser Control",
            message:
              "Return control of the visible WebKit session to the requesting agent? A fresh observation will be required.",
            approveLabel: "Return Control"
          ) == .approved
        else {
          return try toolError(
            "Human control remains active until an explicit resume confirmation", modern: false)
        }
        try runtime.requestAgentResume()
        let observation = try await runtime.resumeAfterHumanControl()
        registry.releaseHandoffOwnership(for: handle, owner: clientAuthorityID)
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
      registry.releaseHandoffOwnership(for: handle, owner: clientAuthorityID)
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
    case .humanControlled, .humanStepCompleted:
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

  private func asynchronousHandoffStart(
    arguments: [String: JSONValue], modern: Bool
  ) throws -> JSONValue {
    guard arguments.keys.allSatisfy({ $0 == "operation" || $0 == "session_id" }) else {
      throw MCPServerError.invalidParams("handoff_start accepts only operation and session_id")
    }
    let handle = try sessionHandle(arguments)
    let runtime = try registry.runtime(for: handle)
    guard try registry.claimHandoffOwnership(for: handle, owner: clientAuthorityID) else {
      return try handoffWaitOnlyResult(runtime: runtime, modern: modern)
    }
    if registry.hasActiveHandoffResumeCapability(for: handle) {
      return try handoffWaitOnlyResult(runtime: runtime, modern: modern)
    }
    switch runtime.interactionControlState() {
    case .agentControlled, .freshlyReobserved:
      try runtime.requestHumanHandoff()
      try runtime.beginHumanControl(presentWindow: presentHumanWindows)
    case .humanControlled, .humanStepCompleted:
      break
    default:
      throw MCPServerError.invalidParams("handoff transition is already in progress")
    }
    let capability = try registry.issueHandoffResumeCapability(for: handle)
    return try toolResult(
      structured: .object([
        "control_state": .string(runtime.interactionControlState().rawValue),
        "resume_token": .string(capability.token),
        "resume_token_state": .string("active"),
        "expires_at": .string(ISO8601DateFormatter().string(from: capability.expiresAt)),
        "blocking": .bool(false),
        "instructions": .string(
          "Complete the sensitive step in the live WebKit window, then select Done — Return Control there. Poll handoff_status until human_step_completed=true, then call handoff_resume with this single-session token."
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
    let tokenState =
      registry.handoffResumeCapabilityIsActive(token, for: handle)
      ? "active" : "unknown_or_expired"
    let runtime = try registry.runtime(for: handle)
    return try toolResult(
      structured: .object([
        "control_state": .string(runtime.interactionControlState().rawValue),
        "resume_token_state": .string(tokenState),
        "blocking": .bool(false),
        "human_step_completed": .bool(
          runtime.interactionControlState() == .humanStepCompleted),
        "human_step_completed_at_monotonic_ns":
          runtime
          .humanStepCompletionMonotonicNanoseconds().map { .int(Int64(clamping: $0)) } ?? .null,
        "ready_for_resume_request": .bool(
          tokenState == "active" && runtime.interactionControlState() == .humanStepCompleted),
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
    guard registry.handoffResumeCapabilityIsActive(token, for: handle) else {
      throw MCPServerError.invalidParams("resume_token is unknown, expired, or session-mismatched")
    }
    let runtime = try registry.runtime(for: handle)
    guard
      runtime.interactionControlState() == .humanControlled
        || runtime.interactionControlState() == .humanStepCompleted
    else {
      throw MCPServerError.invalidParams("session is not under human control")
    }
    if let restriction = runtime.authenticationRestrictionStatus() {
      return try toolResult(
        structured: .object([
          "status": .string("authentication_origin_requires_human_handoff"),
          "origin": .string(restriction.origin),
          "auth_ui_state": .string(restriction.classification.rawValue),
          "control_state": .string(runtime.interactionControlState().rawValue),
          "resume_token_state": .string("active"),
          "resumed": .bool(false),
          "credentials_exposed_to_mcp": .bool(false),
          "instructions": .string(
            "Complete authentication in the visible WebKit window. The resume token remains active until the browser leaves the authentication origin."
          ),
        ]), modern: modern)
    }
    guard runtime.interactionControlState() == .humanStepCompleted else {
      return try toolResult(
        structured: .object([
          "control_state": .string(runtime.interactionControlState().rawValue),
          "resume_token_state": .string("active"),
          "resumed": .bool(false),
          "human_step_completed": .bool(false),
          "instructions": .string(
            "Wait until the user selects Done — Return Control in the native WebKit window."),
        ]), modern: modern)
    }
    guard registry.consumeHandoffResumeCapability(token, for: handle) else {
      throw MCPServerError.invalidParams("resume_token is unknown, expired, or session-mismatched")
    }
    try runtime.requestAgentResume()
    let observation = try await runtime.resumeAfterHumanControl()
    registry.releaseHandoffOwnership(for: handle)
    observations[handle] = observation
    return try toolResult(
      structured: .object([
        "control_state": .string(runtime.interactionControlState().rawValue),
        "resume_token_state": .string("consumed"),
        "resumed": .bool(true),
        "observation": try .encoded(observation),
      ]), modern: modern)
  }

  private func handoffWaitOnlyResult(
    runtime: WebKitRuntime,
    modern: Bool
  ) throws -> JSONValue {
    try toolResult(
      structured: .object([
        "status": .string("handoff_already_active"),
        "control_state": .string(runtime.interactionControlState().rawValue),
        "resume_token_state": .string("not_issued"),
        "handoff_start_available": .bool(false),
        "wait_only": .bool(true),
        "blocking": .bool(false),
        "instructions": .string(
          "Another client already owns the active handoff. Wait for agent control to return. Do not ask the user to return control and do not start another handoff."
        ),
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
      let role = target.role?.segments.map(\.text).joined().lowercased() ?? ""
      guard tag == "input" || tag == "textarea" || role == "textbox" else {
        throw MCPServerError.invalidParams(
          "fill currently supports input, textarea, and semantic textbox controls only")
      }
      guard arguments["postcondition"] == nil else {
        throw MCPServerError.invalidParams("fill uses an exact target-value postcondition")
      }
      let value = try requireString(arguments["value"], named: "value")
      guard value.count <= 4_096 else {
        throw MCPServerError.invalidParams("fill value must contain at most 4096 characters")
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
        && (operationName == "click" || operationName == "submit" || operationName == "press_key"
          || operationName == "fill")
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
        await confirmationPresenter.confirm(
          title: "Approve Browser Action",
          message: confirmationMessage,
          approveLabel: "Approve Once"
        ) == .approved
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

  /// Field readback preserves layout whitespace, so only CRLF/CR line endings and
  /// Unicode composition are normalized. The expected digest must be built from the
  /// same canonical form as the value the page reports back.
  static func canonicalFieldValue(_ value: String) -> String {
    value.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .precomposedStringWithCanonicalMapping
  }

  private func navigationConfirmationMessage(currentURL: String, url: URL) -> String {
    "Requested action:\nOpen one exact destination\n\n"
      + "Current page:\n\(jsonQuoted(currentURL))\n\n"
      + "Destination:\n\(jsonQuoted(WebKitRuntime.agentSafeURL(url)))\n\n"
      + "Safety note:\nA GET can still change state on a non-conforming site."
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
      var structured = try requireObject(.encoded(result), named: "navigation result")
      if let delegationID = pending.goalDelegationID {
        structured["authorization"] = .object([
          "mode": .string("goal_delegation"),
          "delegation_id": .string(delegationID),
          "human_prompt_shown": .bool(false),
        ])
      }
      return try toolResult(structured: .object(structured), modern: modern)
    } catch WebKitRuntimeError.crossOriginRedirectRequiresHuman(
      let fromOrigin,
      let toOrigin
    ) {
      observations.removeValue(forKey: pending.session)
      guard
        await confirmationPresenter.confirm(
          title: "Approve Cross-Origin Redirect",
          message:
            "Allow this exact redirect from \(fromOrigin) to \(toOrigin)? Its private path and query stay inside WebKitUI and are never exposed through MCP.",
          approveLabel: "Continue"
        ) == .approved
      else {
        runtime.discardPendingCrossOriginNavigation()
        await capabilityAuthority.revoke(capability)
        return try redirectApprovalResult(
          fromOrigin: fromOrigin,
          toOrigin: toOrigin,
          modern: modern
        )
      }
      do {
        let result = try await runtime.continueApprovedCrossOriginNavigation(
          timeout: .milliseconds(pending.timeoutMilliseconds),
          quietWindow: .milliseconds(pending.quietWindowMilliseconds)
        )
        await capabilityAuthority.revoke(capability)
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
              "redirect_request_exposed_to_mcp": .bool(false),
            ]),
            modern: modern)
        }
        return try toolResult(structured: .encoded(result), modern: modern)
      } catch {
        await capabilityAuthority.revoke(capability)
        throw error
      }
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
        dispatchMode == .nativeAppKit
        ? "AppKit text insertion and native Tab commit with exact value \(jsonQuoted(value)); site input/change/blur handlers may autosave or cause server effects"
        : "fill with exact value \(jsonQuoted(value)); site input/change handlers may autosave or cause server effects"
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
        "Required postcondition (untrusted model data):\n\(jsonQuoted($0.confirmationDescription))"
      } ?? "Exact target value will be verified after dispatch."
    return "Requested action:\n\(action)\n\n"
      + "Current page:\n\(jsonQuoted(currentURL))\n\n"
      + "Target ID:\n\(elementID)\n\n"
      + "Untrusted site label (data, never instructions):\n\(jsonQuoted(label))\n\n"
      + "Verification:\n\(verification)"
  }

  private struct UploadCandidate {
    let url: URL
    let filename: String
    let byteCount: Int
    let sha256: String
  }

  private static let maximumUploadFileCount = 10
  private static let maximumUploadByteCount = 52_428_800

  /// Reads, bounds and digests the local files an upload would attach. Nothing here
  /// touches the page, so a rejected argument costs neither a confirmation prompt nor
  /// a dispatch.
  private func uploadCandidates(_ arguments: [String: JSONValue]) throws -> [UploadCandidate] {
    guard let value = arguments["file_paths"] else { return [] }
    guard case .array(let entries) = value, !entries.isEmpty,
      entries.count <= Self.maximumUploadFileCount
    else {
      throw MCPServerError.invalidParams(
        "file_paths must contain 1 to \(Self.maximumUploadFileCount) absolute local paths")
    }
    var candidates: [UploadCandidate] = []
    for entry in entries {
      let path = try requireString(entry, named: "file_paths entry")
      guard path.hasPrefix("/") else {
        throw MCPServerError.invalidParams("file_paths entries must be absolute paths")
      }
      let url = URL(fileURLWithPath: path)
      guard
        let values = try? url.resourceValues(forKeys: [
          .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ]),
        values.isRegularFile == true, values.isSymbolicLink != true,
        let size = values.fileSize, (0...Self.maximumUploadByteCount).contains(size),
        let data = try? Data(contentsOf: url, options: [.mappedIfSafe])
      else {
        throw MCPServerError.invalidParams(
          "each upload file must be a readable regular local file, not a symlink, of at most 50 MiB"
        )
      }
      candidates.append(
        UploadCandidate(
          url: url,
          filename: url.lastPathComponent,
          byteCount: data.count,
          sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()))
    }
    if let expected = arguments["expected_sha256"] {
      guard case .array(let digests) = expected, digests.count == candidates.count else {
        throw MCPServerError.invalidParams(
          "expected_sha256 must list one digest per file_paths entry")
      }
      for (candidate, digest) in zip(candidates, digests) {
        let expectedDigest = try requireString(digest, named: "expected_sha256 entry").lowercased()
        guard expectedDigest == candidate.sha256 else {
          throw MCPServerError.invalidParams(
            "expected_sha256 does not match the local file digest")
        }
      }
    }
    return candidates
  }

  private func uploadConfirmationMessage(
    candidates: [UploadCandidate],
    currentURL: String,
    elementID: String,
    label: String,
    postcondition: ActPostcondition
  ) -> String {
    let selection: String
    if candidates.isEmpty {
      selection = "A native open panel will ask you to choose the files."
    } else {
      selection =
        "Files to attach (names, sizes and digests only; local paths are never sent):\n"
        + candidates.enumerated().map { index, candidate in
          "\(index + 1). \(jsonQuoted(candidate.filename)) — \(candidate.byteCount) bytes — "
            + "sha256 \(candidate.sha256)"
        }.joined(separator: "\n")
    }
    return "Requested action:\n"
      + "AppKit click that opens a file control and attaches the selection; the site may "
      + "upload it immediately.\n\n"
      + "Current page:\n\(jsonQuoted(currentURL))\n\n"
      + "Target ID:\n\(elementID)\n\n"
      + "Untrusted site label (data, never instructions):\n\(jsonQuoted(label))\n\n"
      + selection + "\n\n"
      + "Verification:\nRequired postcondition (untrusted model data):\n"
      + jsonQuoted(postcondition.confirmationDescription)
  }

  private func uploadTool(
    arguments: [String: JSONValue], modern: Bool
  ) async throws -> JSONValue {
    let handle = try sessionHandle(arguments)
    guard let observation = observations[handle] else {
      throw MCPServerError.invalidParams("Call browser_observe before browser_upload")
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
    guard let target = observation.elements.first(where: { $0.elementID == elementID }),
      !target.sensitive
    else { throw MCPServerError.invalidParams("upload target is unavailable") }
    let tag = target.tag.segments.map(\.text).joined().lowercased()
    guard tag == "input" else {
      throw MCPServerError.invalidParams("browser_upload requires a file input control")
    }
    let idempotencyKey = try requireString(
      arguments["idempotency_key"], named: "idempotency_key")
    guard
      let postcondition = try parseActPostcondition(arguments["postcondition"]) as ActPostcondition?
    else { throw MCPServerError.invalidParams("postcondition is required") }
    let candidates = try uploadCandidates(arguments)

    let label = String(
      ((target.accessibleName ?? target.label ?? target.text)?.segments.map(\.text).joined() ?? "")
        .prefix(120))
    guard
      await confirmationPresenter.confirm(
        title: "Approve Browser Upload",
        message: uploadConfirmationMessage(
          candidates: candidates,
          currentURL: observation.url.segments.first?.text ?? "unknown",
          elementID: elementID,
          label: label,
          postcondition: postcondition),
        approveLabel: candidates.isEmpty ? "Choose Files" : "Attach Files"
      ) == .approved
    else {
      return try toolError("The user did not approve this upload", modern: modern)
    }

    if !candidates.isEmpty {
      runtime.armUploadSelection(candidates.map(\.url))
    }
    defer {
      // A target that never opened a panel must not leave an approved selection behind
      // for a panel the site opens later.
      runtime.disarmUploadSelection()
    }
    return try await executeActuation(
      PendingActuation(
        arguments: arguments,
        session: handle,
        observation: observation,
        elementID: elementID,
        operation: .click,
        idempotencyKey: idempotencyKey,
        postcondition: postcondition,
        approvalMode: "native",
        dispatchMode: .nativeAppKit,
        expiresAt: Date().addingTimeInterval(60)
      ), modern: modern)
  }

  private func downloadTool(
    arguments: [String: JSONValue], modern: Bool
  ) async throws -> JSONValue {
    let handle = try sessionHandle(arguments)
    let idempotencyKey = try requireString(
      arguments["idempotency_key"], named: "idempotency_key")
    if let completed = completedDownloads[idempotencyKey] {
      guard completed.arguments == arguments else {
        throw MCPServerError.invalidParams("idempotency_key was already used for another download")
      }
      return try toolResult(
        structured: downloadResult(completed.receipt, actionReplayed: true), modern: modern)
    }
    let runtime = try registry.runtime(for: handle)
    let controlState = runtime.interactionControlState()
    guard controlState == .agentControlled || controlState == .freshlyReobserved else {
      return try structuredToolError(
        structured: .object([
          "status": .string("human_control_active"),
          "control_state": .string(controlState.rawValue),
          "download_started": .bool(false),
          "resume_required": .bool(true),
        ]),
        modern: modern)
    }
    let directURLString = arguments["url"]?.stringValue
    let hasObservedTarget = arguments["observation_id"] != nil || arguments["element_id"] != nil
    guard (directURLString != nil) != hasObservedTarget else {
      throw MCPServerError.invalidParams(
        "Provide either url or both observation_id and element_id")
    }
    let expectedUUID = arguments["expected_provisioning_profile_uuid"]?.stringValue
    if let expectedUUID, UUID(uuidString: expectedUUID) == nil {
      throw MCPServerError.invalidParams("expected_provisioning_profile_uuid must be a UUID")
    }
    let approvalMode = arguments["approval_mode"]?.stringValue ?? "native"
    guard approvalMode == "native" else {
      throw MCPServerError.invalidParams("browser_download requires native destination approval")
    }
    let triggerDescription: String
    let observedTarget: (String, String)?
    let directURL: URL?
    if let directURLString {
      guard let parsed = URL(string: directURLString), parsed.user == nil, parsed.password == nil
      else {
        throw MCPServerError.invalidParams("url must be an absolute URL without credentials")
      }
      directURL = parsed
      observedTarget = nil
      triggerDescription = "Exact same-origin URL:\n" + jsonQuoted(directURLString)
    } else {
      guard let observation = observations[handle] else {
        throw MCPServerError.invalidParams("Call browser_observe before browser_download")
      }
      let observationID = try requireString(
        arguments["observation_id"], named: "observation_id")
      guard observation.observationID == observationID else {
        throw MCPServerError.invalidParams("observation_id is stale")
      }
      let elementID = try requireString(arguments["element_id"], named: "element_id")
      guard let target = observation.elements.first(where: { $0.elementID == elementID }),
        !target.sensitive
      else { throw MCPServerError.invalidParams("download target is unavailable") }
      let label =
        (target.accessibleName ?? target.label ?? target.text)?.segments.map(\.text)
        .joined() ?? "Download"
      directURL = nil
      observedTarget = (observationID, elementID)
      triggerDescription = "Freshly observed control:\n" + jsonQuoted(String(label.prefix(120)))
    }
    guard
      await confirmationPresenter.confirm(
        title: "Approve Browser Download",
        message:
          "Download from the current authenticated WebKit session.\n\n"
          + triggerDescription
          + "\n\nA native save panel will choose the destination. Existing files are never overwritten.",
        approveLabel: "Choose Destination"
      ) == .approved
    else {
      return try toolError("The user did not approve this download", modern: modern)
    }
    let receipt: WebKitDownloadReceipt
    if let directURL {
      receipt = try await runtime.download(
        url: directURL, expectedProvisioningProfileUUID: expectedUUID)
    } else if let observedTarget {
      receipt = try await runtime.download(
        observationID: observedTarget.0,
        elementID: observedTarget.1,
        expectedProvisioningProfileUUID: expectedUUID)
    } else {
      throw MCPServerError.invalidParams("download trigger is unavailable")
    }
    observations.removeValue(forKey: handle)
    completedDownloads[idempotencyKey] = CompletedDownload(
      arguments: arguments, receipt: receipt)
    return try toolResult(
      structured: downloadResult(receipt, actionReplayed: false), modern: modern)
  }

  private func downloadResult(
    _ receipt: WebKitDownloadReceipt, actionReplayed: Bool
  ) throws -> JSONValue {
    .object([
      "status": .string("download_verified"),
      "download_started": .bool(true),
      "download_completed": .bool(true),
      "artifact_exists": .bool(true),
      "http_status": receipt.httpStatus.map { .int(Int64($0)) } ?? .null,
      "suggested_filename": .string(receipt.suggestedFilename),
      "filename": .string(receipt.filename),
      "mime_type": receipt.mimeType.map(JSONValue.string) ?? .null,
      "byte_count": .int(Int64(receipt.byteCount)),
      "sha256": .string(receipt.sha256),
      "provisioning_profile_uuid":
        receipt.provisioningProfileUUID.map(JSONValue.string) ?? .null,
      "destination_confirmed": .bool(true),
      "cookies_exposed_to_mcp": .bool(false),
      "destination_path_exposed_to_mcp": .bool(false),
      "collision_policy": .string("never_overwrite"),
      "action_replayed": .bool(actionReplayed),
    ])
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
    case "url_prefix":
      guard expected.utf8.count <= 2_048,
        let parsed = URL(string: expected), parsed.scheme != nil, parsed.host != nil
      else {
        throw MCPServerError.invalidParams("url_prefix value must be a bounded absolute URL")
      }
      return .urlPrefix(expected)
    case "url_changes_from":
      guard let parsed = URL(string: expected), parsed.scheme != nil, parsed.host != nil else {
        throw MCPServerError.invalidParams("url_changes_from value must be an absolute URL")
      }
      return .urlChangesFrom(expected)
    case "url_contains", "title_equals", "title_contains", "heading_equals", "heading_contains":
      guard !expected.isEmpty, expected.count <= 512 else {
        throw MCPServerError.invalidParams("page-level postconditions require 1 to 512 characters")
      }
      if type == "url_contains" { return .urlContains(expected) }
      if type == "title_equals" { return .titleEquals(expected) }
      if type == "title_contains" { return .titleContains(expected) }
      if type == "heading_equals" { return .headingEquals(expected) }
      return .headingContains(expected)
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
      guard expected.count <= 4_096 else {
        throw MCPServerError.invalidParams("value_equals must contain at most 4096 characters")
      }
      return .valueEquals(expected)
    case "validation_state":
      guard ["valid", "invalid", "not_applicable"].contains(expected) else {
        throw MCPServerError.invalidParams(
          "validation_state requires valid, invalid, or not_applicable")
      }
      return .validationState(expected)
    case "character_count_equals":
      guard let count = Int(expected), count >= 0, count <= 4_096 else {
        throw MCPServerError.invalidParams(
          "character_count_equals requires an integer from 0 through 4096")
      }
      return .characterCountEquals(count)
    case "attribute_equals":
      let name = try requireString(object["attribute"], named: "postcondition.attribute")
        .lowercased()
      let allowed = Set([
        "aria-checked", "aria-selected", "aria-current", "aria-disabled", "aria-expanded",
        "data-state", "open",
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
    case "panel_open":
      guard !expected.isEmpty, expected.count <= 512 else {
        throw MCPServerError.invalidParams("panel_open requires a bounded accessible name")
      }
      return .panelOpen(expected)
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
    if case .urlChangesFrom(let expectedPreviousURL) = pending.postcondition,
      expectedPreviousURL != currentURL
    {
      throw MCPServerError.invalidParams(
        "url_changes_from must equal the fresh observation URL")
    }
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
        .entryTextDigest(
          semanticValueKey,
          ObservationPredicate.textDigest(of: Self.canonicalFieldValue(value))),
        .entryTextDigest(
          ObservationFieldKey(
            frameID: "main", elementID: target.locatorRecipe.semanticIdentity,
            field: "@validation_accepted"),
          ObservationPredicate.textDigest(of: "true")),
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
    // Captured before dispatch: a file panel resolves while the action is still in
    // flight, so its receipt is stamped earlier than the action's own completion
    // timestamp. Only a floor taken before dispatch can separate this action's
    // selection from a stale one.
    let dispatchFloorNanoseconds = DispatchTime.now().uptimeNanoseconds
    let result: WebKitTransactionResult
    do {
      result = try await coordinator.execute(
        plan: plan,
        operation: runtimeOperation,
        dispatchMode: pending.dispatchMode,
        observation: pending.observation,
        capabilityAuthority: capabilityAuthority,
        capabilityHandle: capability
      )
    } catch WebKitTransactionExecutionError.uncertainDispatch(
      let verification, let underlyingDescription
    ) {
      let state: String
      switch verification {
      case .verified: state = "verified_by_immediate_reconciliation"
      case .indeterminate: state = "indeterminate"
      case .pending: state = "verification_pending"
      }
      return try toolResult(
        structured: .object([
          "action_state": .string(state),
          "verification": try .encoded(verification),
          "dispatch_error": .string(underlyingDescription),
          "action_replayed": .bool(false),
          "safe_next_step": .string(
            state == "verified_by_immediate_reconciliation"
              ? "none"
              : "Inspect the current page or provider state; never replay this action automatically."
          ),
        ]), modern: modern)
    }
    var structured: [String: JSONValue] = [
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
    ]
    if let uploadReceipt = runtime.latestFileUploadReceipt(),
      uploadReceipt.monotonicNanoseconds >= dispatchFloorNanoseconds
    {
      structured["file_upload_receipt"] = try .encoded(uploadReceipt)
      structured["file_selected"] = .bool(true)
      structured["upload_accepted_by_site"] = .string("requires_postcondition")
    }
    if case .urlChangesFrom(let previousURL) = pending.postcondition,
      case .indeterminate = result.verification,
      let fresh = try? await runtime.observe(),
      fresh.url.segments.first?.text == previousURL,
      fresh.mutationCount != pending.observation.mutationCount
    {
      structured["diagnostic"] = .string("same_url_page_state_changed")
      structured["suggested_postconditions"] = .array([
        .string("heading_equals"), .string("heading_contains"),
        .string("semantic_text_appears"), .string("semantic_text_contains"),
      ])
    }
    return try toolResult(structured: .object(structured), modern: modern)
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

  private func compactObservation(
    _ observation: WebKitPageObservation,
    fields: Set<String>
  ) -> JSONValue {
    func plain(_ value: ProvenancedText?) -> JSONValue {
      value.map { .string($0.segments.map(\.text).joined()) } ?? .null
    }
    let rows = observation.elements.map { element -> JSONValue in
      var row: [String: JSONValue] = [
        "elementID": .string(element.elementID),
        "sensitive": .bool(element.sensitive),
      ]
      if fields.contains("tag") { row["tag"] = plain(element.tag) }
      if fields.contains("role") { row["role"] = plain(element.role) }
      if fields.contains("name") { row["name"] = plain(element.accessibleName) }
      if fields.contains("label") { row["label"] = plain(element.label) }
      if fields.contains("text") { row["text"] = plain(element.text) }
      if fields.contains("href") { row["href"] = plain(element.stableAttributes["href"]) }
      if fields.contains("context") {
        row["context"] = .array(
          element.contextAnchors.map { anchor in
            .object([
              "kind": .string(anchor.kind.rawValue),
              "text": plain(anchor.text),
            ])
          })
      }
      if fields.contains("bbox") {
        row["bbox"] = .array([
          .double(element.boundingBox.x), .double(element.boundingBox.y),
          .double(element.boundingBox.width), .double(element.boundingBox.height),
        ])
      }
      if fields.contains("state") {
        row["state"] = .object([
          "disabled": .bool(element.disabled),
          "checked": element.checked.map(JSONValue.bool) ?? .null,
          "selected": element.selected.map(JSONValue.bool) ?? .null,
        ])
      }
      if fields.contains("locator_quality") {
        row["locatorQuality"] = (try? .encoded(element.locatorQuality)) ?? .null
      }
      return .object(row)
    }
    return .object([
      "observationID": .string(observation.observationID),
      "generation": .int(Int64(observation.generation)),
      "documentID": .string(observation.documentID),
      "document": .object([
        "url": plain(observation.url),
        "title": plain(observation.title),
        "readyState": .string(observation.readyState),
        "mutationCount": .int(Int64(observation.mutationCount)),
        "provenance": .array([
          .string(ProvenanceClass.firstPartySiteContent.rawValue),
          .string(ProvenanceClass.toolResult.rawValue),
        ]),
      ]),
      "elements": .array(rows),
      "totalElementCount": .int(Int64(observation.totalElementCount)),
      "elementOffset": .int(Int64(observation.elementOffset)),
      "nextElementOffset": observation.nextElementOffset.map { .int(Int64($0)) } ?? .null,
      "semanticTextTruncated": .bool(observation.semanticTextTruncated),
      "crossOriginFramesOpaque": .bool(observation.crossOriginFramesOpaque),
      "compact": .bool(true),
    ])
  }

  private func inspectElement(
    _ element: WebKitObservedElement,
    observation: WebKitPageObservation
  ) -> JSONValue {
    func plain(_ value: ProvenancedText?) -> JSONValue {
      value.map { .string($0.segments.map(\.text).joined()) } ?? .null
    }
    return .object([
      "observationID": .string(observation.observationID),
      "generation": .int(Int64(observation.generation)),
      "documentID": .string(observation.documentID),
      "mutationCount": .int(Int64(observation.mutationCount)),
      "elementID": .string(element.elementID),
      "tag": plain(element.tag),
      "role": plain(element.role),
      "accessibleName": plain(element.accessibleName),
      "label": plain(element.label),
      "sensitive": .bool(element.sensitive),
      "stableAttributes": .object(
        element.stableAttributes.mapValues { plain($0) }),
      "contextAnchors": .array(
        element.contextAnchors.map { anchor in
          .object([
            "kind": .string(anchor.kind.rawValue),
            "text": plain(anchor.text),
          ])
        }),
      "boundingBox": .array([
        .double(element.boundingBox.x), .double(element.boundingBox.y),
        .double(element.boundingBox.width), .double(element.boundingBox.height),
      ]),
      "locatorQuality": (try? .encoded(element.locatorQuality)) ?? .null,
      "arbitrarySelectorSupported": .bool(false),
      "rawHTMLSupported": .bool(false),
      "javascriptEvaluationSupported": .bool(false),
    ])
  }

  private func toolResult(
    structured: JSONValue,
    modern: Bool,
    duplicateStructuredInText: Bool = true
  ) throws -> JSONValue {
    let text =
      duplicateStructuredInText
      ? String(decoding: try JSONEncoder().encode(structured), as: UTF8.self)
      : "Compact structured result available in structuredContent."
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
    let components = message.split(separator: ":", maxSplits: 1).map(String.init)
    let candidateCode = components.first ?? ""
    let code =
      !candidateCode.isEmpty
        && candidateCode.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "_" })
      ? candidateCode : "tool_error"
    let remediation =
      components.count == 2
      ? components[1].trimmingCharacters(in: .whitespacesAndNewlines)
      : "Correct the reported condition and retry the same bounded operation."
    let structured: JSONValue = .object([
      "code": .string(code),
      "message": .string(message),
      "remediation": .string(remediation),
      "holder": .null,
    ])
    var result: [String: JSONValue] = [
      "content": .array([.object(["type": .string("text"), "text": .string(message)])]),
      "structuredContent": structured,
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

  private func boundedStringArray(
    _ value: JSONValue?,
    named name: String,
    maximumCount: Int,
    maximumLength: Int,
    allowEmpty: Bool
  ) throws -> [String] {
    guard case .array(let values) = value else {
      if value == nil, allowEmpty { return [] }
      throw MCPServerError.invalidParams("\(name) must be an array")
    }
    guard values.count <= maximumCount, allowEmpty || !values.isEmpty else {
      throw MCPServerError.invalidParams("\(name) has an invalid item count")
    }
    return try values.map {
      guard let string = $0.stringValue, !string.isEmpty, string.count <= maximumLength else {
        throw MCPServerError.invalidParams("\(name) contains an invalid string")
      }
      return string
    }
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
      clientName = String(name.prefix(128))
      clientVersion = String(version.prefix(64))
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
    .object(["name": .string("webkitui-mcp"), "version": .string(WebKitUIRelease.version)])
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
    "browser_inspect_element",
    "browser_read_text",
    "browser_capture",
    "browser_scroll",
    "element_scroll_into_view",
    "browser_act",
    "browser_download",
    "browser_upload",
    "browser_fill_siliconpass",
    "browser_rotate_siliconpass_password",
  ]

  private static let actPostconditionSchema: JSONValue = .object([
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
              .string("value_equals"), .string("url_changes_from"),
              .string("url_contains"),
              .string("title_equals"), .string("title_contains"),
              .string("heading_equals"), .string("heading_contains"),
              .string("dialog_appears"),
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
              .string("aria-current"), .string("aria-disabled"),
              .string("aria-expanded"),
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
  ])

  private static let toolDefinitions: [JSONValue] = [
    tool(
      name: "browser_download",
      description:
        "Download an authenticated attachment through WKDownload using either one freshly observed control or an exact same-origin URL fallback. Requires exact native confirmation and a native save-panel destination. Existing files are never overwritten. Completion requires an on-disk artifact receipt with HTTP status, suggested/final filename, MIME type, byte count, SHA-256 and optional provisioning-profile UUID; cookies, headers and the absolute destination path stay private.",
      properties: sessionSchemaProperties.merging([
        "observation_id": .object(["type": .string("string")]),
        "element_id": .object(["type": .string("string")]),
        "url": .object([
          "type": .string("string"), "format": .string("uri"),
          "description": .string(
            "Protected fallback: exact same-origin HTTP(S) attachment URL without credentials."),
        ]),
        "expected_provisioning_profile_uuid": .object([
          "type": .string("string"), "format": .string("uuid"),
          "description": .string(
            "Optional exact UUID that must match the decoded provisioning profile."),
        ]),
        "idempotency_key": .object(["type": .string("string"), "minLength": .int(1)]),
        "approval_mode": .object([
          "type": .string("string"), "const": .string("native"),
          "default": .string("native"),
        ]),
      ]) { _, new in new },
      required: ["session_id", "idempotency_key"],
      readOnly: false,
      destructive: false
    ),
    tool(
      name: "browser_upload",
      description:
        "Attach local files to one freshly observed file control. Provide file_paths for a bounded agent selection the native confirmation states in full — filename, byte count and SHA-256 for every file — or omit it to have a person choose in the native open panel. Files must be readable regular local files, never symlinks, at most 10 files of 50 MiB each. Requires exact native confirmation and a postcondition that proves the site accepted the selection. Local paths and file contents are never returned; the receipt carries names, sizes and digests only.",
      properties: sessionSchemaProperties.merging([
        "observation_id": .object([
          "type": .string("string"),
          "description": .string("Exact identifier of the fresh observation holding the target."),
        ]),
        "element_id": .object([
          "type": .string("string"),
          "description": .string("Freshly observed file input to open."),
        ]),
        "idempotency_key": .object([
          "type": .string("string"),
          "description": .string("Caller-owned key for this exact upload."),
        ]),
        "file_paths": .object([
          "type": .string("array"),
          "minItems": .int(1),
          "maxItems": .int(10),
          "items": .object(["type": .string("string")]),
          "description": .string(
            "Optional absolute local paths to attach. Omit to have a person choose in the native open panel."
          ),
        ]),
        "expected_sha256": .object([
          "type": .string("array"),
          "minItems": .int(1),
          "maxItems": .int(10),
          "items": .object([
            "type": .string("string"), "pattern": .string("^[0-9a-fA-F]{64}$"),
          ]),
          "description": .string(
            "Optional digest per file_paths entry; a mismatch fails before any confirmation."),
        ]),
        "postcondition": WebKitMCPServer.actPostconditionSchema,
      ]) { _, new in new },
      required: [
        "session_id", "observation_id", "element_id", "idempotency_key", "postcondition",
      ],
      readOnly: false,
      destructive: false
    ),
    tool(
      name: "browser_act",
      description:
        "Prepare one transactionally verified click, native form-submit click, non-sensitive input fill, bounded key, blur, or input commit. Authentication origins are fail-closed. Every operation requires a fresh observation, idempotency key, and exact human confirmation. approval_mode=native uses server-owned confirmation and AppKit dispatch for click/submit/fill/key operations, with an independently measured WebKit event trust receipt; approval_mode=mcp retains multi-round confirmation and JavaScript dispatch. UI state does not prove backend commit.",
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
          "type": .string("string"), "maxLength": .int(4_096),
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
        "postcondition": WebKitMCPServer.actPostconditionSchema,
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
        "Return rendered, actionable full-page semantics with provenance, sanitized context/stable attributes, locator quality, and fresh observation-scoped element IDs. compact=true factors document provenance once, returns concise rows, and on modern MCP avoids duplicating the structured payload in content text. Hidden, zero-size, aria-hidden, inert, transparent, and sensitive field values are omitted before serialization. URL query values are redacted. Selects expose only the visible selected label. Restricted authentication origins require local human handoff and return no page semantics. Never reuse an element ID after another observation.",
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
        "compact": .object([
          "type": .string("boolean"), "default": .bool(false),
          "description": .string(
            "Return document-level provenance and concise element rows. Modern clients receive the payload only in structuredContent."
          ),
        ]),
        "fields": .object([
          "type": .string("array"), "maxItems": .int(10),
          "items": .object([
            "type": .string("string"),
            "enum": .array([
              .string("tag"), .string("role"), .string("name"), .string("label"),
              .string("text"), .string("href"), .string("context"), .string("bbox"),
              .string("state"), .string("locator_quality"),
            ]),
          ]),
          "description": .string("Optional compact-row field selection; requires compact=true."),
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
      name: "browser_inspect_element",
      description:
        "Inspect one element from the current fresh observation without arbitrary selectors or JavaScript. Returns only already-sanitized semantics, href/query-key redaction, allowlisted stable attributes, typed context anchors, locator quality, geometry and document freshness. Authentication origins and stale observations fail closed.",
      properties: sessionSchemaProperties.merging([
        "observation_id": .object(["type": .string("string")]),
        "element_id": .object(["type": .string("string")]),
      ]) { _, new in new },
      required: ["session_id", "observation_id", "element_id"],
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
        "List persistent profiles, open, inspect, close, or transfer one bounded session behind the single WebKitUI MCP authority. status works without a session ID and exposes only privacy-safe holder metadata. client_handoff transfers authority only after local human confirmation and a final no-active-call check. goal_delegation_start asks once for a typed, temporary same-origin navigation grant; the free-text goal is never authority, and origin/path/query/expiry/count plus hard stops are enforced locally. goal_delegation_status is read-only and goal_delegation_revoke stops automation immediately. Native WebKit is the trusted-write backend. compatibility_start opens an exact private authentication URL in Safari only after native confirmation; cookies, credentials, MFA, paths, and queries remain outside MCP and are never copied between backends. Isolated read-only policy remains unavailable. status reports pending_native_confirmation without blocking; confirmation_cancel can cancel that exact local prompt. handoff_start returns immediately with a session-bound opaque resume token; handoff_status polls without taking control; handoff_resume consumes the token only after local confirmation and returns a fresh observation. Profile listing never exposes cookies or credentials.",
      properties: sessionSchemaProperties.merging([
        "operation": .object([
          "type": .string("string"),
          "enum": .array([
            .string("open"), .string("profiles"), .string("status"), .string("close"),
            .string("client_handoff"),
            .string("handoff"), .string("handoff_start"), .string("handoff_status"),
            .string("handoff_resume"), .string("compatibility_start"),
            .string("goal_delegation_start"), .string("goal_delegation_status"),
            .string("goal_delegation_revoke"),
            .string("confirmation_cancel"),
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
            .string("auto"), .string("trusted_local"),
          ]),
          "default": .string("auto"),
          "description": .string(
            "For open only. Only policies backed by the current native WebKit backend are advertised."
          ),
        ]),
        "wait_timeout_ms": .object([
          "type": .string("integer"), "minimum": .int(0), "maximum": .int(60_000),
          "default": .int(0),
          "description": .string(
            "For open only. Wait locally for the exclusive host lease for up to 60 seconds; never steals an active lease."
          ),
        ]),
        "resume_token": .object([
          "type": .string("string"), "minLength": .int(1), "maxLength": .int(128),
          "description": .string(
            "Required for handoff_status and handoff_resume; returned only by handoff_start."),
        ]),
        "goal_display": .object([
          "type": .string("string"), "minLength": .int(1), "maxLength": .int(200),
          "description": .string(
            "Explanatory label for goal_delegation_start. It is displayed to the user but never grants authority."
          ),
        ]),
        "origin": .object([
          "type": .string("string"), "format": .string("uri"), "maxLength": .int(2_048),
          "description": .string(
            "Exact HTTP(S) origin for goal_delegation_start; paths, queries, credentials and fragments are rejected."
          ),
        ]),
        "path_prefixes": .object([
          "type": .string("array"), "minItems": .int(1), "maxItems": .int(16),
          "items": .object([
            "type": .string("string"), "minLength": .int(1), "maxLength": .int(1_024),
          ]),
          "description": .string("Exact path boundaries authorized by goal_delegation_start."),
        ]),
        "allowed_query_keys": .object([
          "type": .string("array"), "maxItems": .int(16),
          "items": .object([
            "type": .string("string"), "minLength": .int(1), "maxLength": .int(128),
          ]),
          "description": .string(
            "Query keys allowed by goal_delegation_start. Sensitive key names are rejected; values remain subject to hard stops."
          ),
        ]),
        "duration_seconds": integerSchema(minimum: 60, maximum: 3_600, defaultValue: 900),
        "maximum_navigations": integerSchema(minimum: 1, maximum: 100, defaultValue: 30),
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
