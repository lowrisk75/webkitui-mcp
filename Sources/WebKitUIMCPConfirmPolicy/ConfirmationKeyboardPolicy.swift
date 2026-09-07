import Foundation

/// What the keyboard does to a native confirmation before the operator has looked at it.
///
/// The helper takes keyboard focus the moment it opens, so whatever the operator was
/// typing in their terminal lands on the panel. With Return bound to Cancel that
/// silently refused actions the operator never saw (reported 2026-09-07). Approve is
/// deliberately not an option: a stray Return must never navigate or fill.
public enum ConfirmationKeyboardDefault: String, Sendable, Equatable {
  /// Return presses Cancel, but only once the arming delay has passed.
  case cancel
  /// No key presses any button; the operator must click, or Tab to a button first.
  case none
}

public struct ConfirmationKeyboardPolicy: Sendable, Equatable {
  /// Preference domain shared by a source build and the notarized app so one
  /// `defaults write` covers both.
  public static let suiteName = "com.lorislab.webkitui-mcp"
  public static let keyboardDefaultKey = "ConfirmationKeyboardDefault"
  public static let armingDelayKey = "ConfirmationArmingDelaySeconds"

  public static let fallbackArmingDelaySeconds = 1.0
  public static let maximumArmingDelaySeconds = 5.0

  public let keyboardDefault: ConfirmationKeyboardDefault
  public let armingDelaySeconds: Double

  public init(preferences: [String: Any]) {
    let rawDefault = (preferences[Self.keyboardDefaultKey] as? String ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    keyboardDefault = ConfirmationKeyboardDefault(rawValue: rawDefault) ?? .cancel

    // Booleans bridge to NSNumber, so a stray `-bool` write would otherwise read as 1 s
    // or 0 s. Only a real number counts.
    if let number = preferences[Self.armingDelayKey] as? NSNumber,
      CFGetTypeID(number) != CFBooleanGetTypeID(),
      number.doubleValue.isFinite, number.doubleValue >= 0
    {
      armingDelaySeconds = min(number.doubleValue, Self.maximumArmingDelaySeconds)
    } else {
      armingDelaySeconds = Self.fallbackArmingDelaySeconds
    }
  }

  public init(userDefaults: UserDefaults) {
    self.init(preferences: userDefaults.dictionaryRepresentation())
  }

  public static func stored() -> ConfirmationKeyboardPolicy {
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      return ConfirmationKeyboardPolicy(preferences: [:])
    }
    return ConfirmationKeyboardPolicy(userDefaults: defaults)
  }

  public func returnCancels(elapsedSeconds: Double) -> Bool {
    keyboardDefault == .cancel && elapsedSeconds >= armingDelaySeconds
  }
}
