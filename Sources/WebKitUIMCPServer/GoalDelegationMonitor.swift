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
  /// Keyed by delegation: with more than one session in the process, a second
  /// client's grant used to replace the first in the companion window, and the stop
  /// button then reached only the last one published.
  private var active: [String: GoalDelegationSnapshot] = [:]
  private var revokedIdentifiers: Set<String> = []

  public init() {}

  public func publish(_ snapshot: GoalDelegationSnapshot) {
    revokedIdentifiers.remove(snapshot.identifier)
    active[snapshot.identifier] = snapshot
  }

  /// Every live delegation, soonest to expire first.
  public func snapshots(now: Date = Date()) -> [GoalDelegationSnapshot] {
    active = active.filter { $0.value.expiresAt > now && $0.value.remainingNavigations > 0 }
    return active.values.sorted { $0.expiresAt < $1.expiresAt }
  }

  public func snapshot(now: Date = Date()) -> GoalDelegationSnapshot? {
    snapshots(now: now).first
  }

  /// The operator's stop button: every delegation in the process ends at once.
  public func requestImmediateRevocation() -> Bool {
    guard !active.isEmpty else { return false }
    revokedIdentifiers.formUnion(active.keys)
    active.removeAll()
    return true
  }

  func isRevoked(_ identifier: String) -> Bool {
    revokedIdentifiers.contains(identifier)
  }

  func clear(identifier: String? = nil) {
    guard let identifier else {
      active.removeAll()
      return
    }
    active.removeValue(forKey: identifier)
  }
}
