import Foundation

/// Bounded public AppKit facts from the verified helper. Never an approval receipt
/// or proof that a person perceived the window; contains no requested action text.
public struct ConfirmationPresentationReceipt: Codable, Sendable, Equatable {
  public enum Phase: String, Codable, Sendable {
    case ordered, sampled, refocused, decision, finished
  }
  public enum Decision: String, Codable, Sendable { case approve, decline, close, hidden }
  public let requestID: UUID
  public let helperPID: Int32
  public let phase: Phase
  public let monotonicNanoseconds: UInt64
  public let windowNumber: Int
  public let windowVisible: Bool
  public let appKitVisible: Bool
  public let keyWindow: Bool
  public let onActiveSpace: Bool
  public let intersectsScreen: Bool
  public let decision: Decision?

  public init(
    requestID: UUID, helperPID: Int32, phase: Phase,
    monotonicNanoseconds: UInt64, windowNumber: Int, windowVisible: Bool,
    appKitVisible: Bool, keyWindow: Bool, onActiveSpace: Bool, intersectsScreen: Bool,
    decision: Decision? = nil
  ) {
    self.requestID = requestID
    self.helperPID = helperPID
    self.phase = phase
    self.monotonicNanoseconds = monotonicNanoseconds
    self.windowNumber = windowNumber
    self.windowVisible = windowVisible
    self.appKitVisible = appKitVisible
    self.keyWindow = keyWindow
    self.onActiveSpace = onActiveSpace
    self.intersectsScreen = intersectsScreen
    self.decision = decision
  }
}
