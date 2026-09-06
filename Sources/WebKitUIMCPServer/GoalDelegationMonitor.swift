import Foundation

public struct GoalDelegationSnapshot: Equatable, Sendable {
  public let identifier: String
  public let goalDisplay: String
  public let origin: String
  public let expiresAt: Date
  public let remainingNavigations: Int

  public init(
    identifier: String,
    goalDisplay: String,
    origin: String,
    expiresAt: Date,
    remainingNavigations: Int
  ) {
    self.identifier = identifier
    self.goalDisplay = goalDisplay
    self.origin = origin
    self.expiresAt = expiresAt
    self.remainingNavigations = remainingNavigations
  }
}

/// Process-local bridge between the MCP authority and the companion UI. It
/// exposes only the user-approved scope summary, never page data or URLs.
public actor GoalDelegationMonitor {
  private var active: GoalDelegationSnapshot?
  private var revokedIdentifiers: Set<String> = []

  public init() {}

  public func publish(_ snapshot: GoalDelegationSnapshot) {
    revokedIdentifiers.remove(snapshot.identifier)
    active = snapshot
  }

  public func snapshot(now: Date = Date()) -> GoalDelegationSnapshot? {
    guard let active, active.expiresAt > now, active.remainingNavigations > 0 else {
      self.active = nil
      return nil
    }
    return active
  }

  public func requestImmediateRevocation() -> Bool {
    guard let active else { return false }
    revokedIdentifiers.insert(active.identifier)
    self.active = nil
    return true
  }

  func isRevoked(_ identifier: String) -> Bool {
    revokedIdentifiers.contains(identifier)
  }

  func clear(identifier: String? = nil) {
    guard identifier == nil || active?.identifier == identifier else { return }
    active = nil
  }
}
