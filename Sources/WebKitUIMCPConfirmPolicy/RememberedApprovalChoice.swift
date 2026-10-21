/// Only the verified local helper may return one of these explicit user choices.
/// Exit codes 2/3/4 retain their existing decline/cancel/hidden meanings.
public enum RememberedApprovalChoice: Int32, Sendable, Codable {
  case sessionNavigation = 8
  case persistentNavigation = 9
  case sessionInteractions = 10
  case persistentInteractions = 11

  public var persistent: Bool { self == .persistentNavigation || self == .persistentInteractions }
  public var interactions: Bool { self == .sessionInteractions || self == .persistentInteractions }
}
