import Foundation

/// How many confirmations have been asked for recently.
///
/// The safety of this product rests on a human reading a dialog. An agent, or an
/// injected page driving one, can ask fifty times in a minute and train the operator to
/// click through; OWASP files that as the clickthrough vulnerability. Refusing outright
/// would break ordinary work, so a burst is named in the dialog and a flood is refused.
public struct ConfirmationRatePolicy: Equatable, Sendable {
  public enum Verdict: Equatable, Sendable {
    case normal
    /// Show the count in the dialog. An operator who is told this is the ninth request
    /// in a minute has the one fact that makes a flood legible.
    case burst(recentCount: Int)
    /// Do not present. Return an error naming the count.
    case refuse(recentCount: Int)
  }

  public static let burstThreshold = 5
  public static let refuseThreshold = 20
  public static let windowNanoseconds: UInt64 = 60_000_000_000

  private var recent: [UInt64] = []

  public init() {}

  public mutating func record(atMonotonicNanoseconds now: UInt64) -> Verdict {
    recent.removeAll { now >= $0 && now - $0 > Self.windowNanoseconds }
    recent.append(now)
    let count = recent.count
    if count >= Self.refuseThreshold { return .refuse(recentCount: count) }
    if count >= Self.burstThreshold { return .burst(recentCount: count) }
    return .normal
  }
}
