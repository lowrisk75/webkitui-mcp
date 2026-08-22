import Foundation

public enum BrowserCapability: String, Codable, CaseIterable, Hashable, Sendable {
  case readPage = "read_page"
  case navigate
  case activateElement = "activate_element"
  case fillForm = "fill_form"
  case submitForm = "submit_form"
  case download
  case upload
}

public struct CapabilityHandle: Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }
}

public struct CapabilityScope: Sendable {
  public let actions: Set<BrowserCapability>
  public let origins: Set<SecurityOrigin>
  public let acceptedInputProvenance: Set<ProvenanceClass>
  public let expiresAt: Date

  public init(
    actions: Set<BrowserCapability>,
    origins: Set<SecurityOrigin>,
    acceptedInputProvenance: Set<ProvenanceClass>,
    expiresAt: Date
  ) {
    self.actions = actions
    self.origins = origins
    self.acceptedInputProvenance = acceptedInputProvenance
    self.expiresAt = expiresAt
  }
}

public struct CapabilityRequest: Sendable {
  public let action: BrowserCapability
  public let liveOrigin: SecurityOrigin
  public let inputProvenance: Set<ProvenanceClass>

  public init(
    action: BrowserCapability,
    liveOrigin: SecurityOrigin,
    inputProvenance: Set<ProvenanceClass> = []
  ) {
    self.action = action
    self.liveOrigin = liveOrigin
    self.inputProvenance = inputProvenance
  }
}

public enum CapabilityDenial: String, Codable, Equatable, Sendable {
  case unknownHandle = "unknown_handle"
  case expired
  case actionNotGranted = "action_not_granted"
  case originNotGranted = "origin_not_granted"
  case inputProvenanceNotGranted = "input_provenance_not_granted"
}

public enum CapabilityDecision: Equatable, Sendable {
  case allowed
  case denied(CapabilityDenial)
}

/// Serialized names are not authority. Only handles present in this actor's
/// private registry can authorize an action.
public actor CapabilityAuthority {
  private var grants: [CapabilityHandle: CapabilityScope] = [:]

  public init() {}

  public func issue(_ scope: CapabilityScope) -> CapabilityHandle {
    let handle = CapabilityHandle(rawValue: UUID())
    grants[handle] = scope
    return handle
  }

  public func revoke(_ handle: CapabilityHandle) {
    grants.removeValue(forKey: handle)
  }

  /// The caller supplies the current live origin after re-resolution.
  /// Decisions are intentionally not cached across action boundaries.
  public func evaluate(
    _ request: CapabilityRequest,
    using handle: CapabilityHandle,
    now: Date
  ) -> CapabilityDecision {
    guard let scope = grants[handle] else { return .denied(.unknownHandle) }
    guard now < scope.expiresAt else {
      grants.removeValue(forKey: handle)
      return .denied(.expired)
    }
    guard scope.actions.contains(request.action) else {
      return .denied(.actionNotGranted)
    }
    guard scope.origins.contains(request.liveOrigin) else {
      return .denied(.originNotGranted)
    }
    guard request.inputProvenance.isSubset(of: scope.acceptedInputProvenance) else {
      return .denied(.inputProvenanceNotGranted)
    }
    return .allowed
  }
}
