import XCTest

@testable import WebKitUIMCPConfirmPolicy

final class ConfirmationKeyboardPolicyTests: XCTestCase {
  func testMissingPreferencesFallBackToCancelAfterOneSecond() {
    let policy = ConfirmationKeyboardPolicy(preferences: [:])
    XCTAssertEqual(policy.keyboardDefault, .cancel)
    XCTAssertEqual(policy.armingDelaySeconds, 1.0)
  }

  func testNonePreferenceRemovesEveryKeyboardDefault() {
    let policy = ConfirmationKeyboardPolicy(
      preferences: [ConfirmationKeyboardPolicy.keyboardDefaultKey: "none"])
    XCTAssertEqual(policy.keyboardDefault, .none)
  }

  func testPreferenceValueIsCaseAndWhitespaceInsensitive() {
    let policy = ConfirmationKeyboardPolicy(
      preferences: [ConfirmationKeyboardPolicy.keyboardDefaultKey: "  None \n"])
    XCTAssertEqual(policy.keyboardDefault, .none)
  }

  func testApproveCanNeverBecomeTheKeyboardDefault() {
    let policy = ConfirmationKeyboardPolicy(
      preferences: [ConfirmationKeyboardPolicy.keyboardDefaultKey: "approve"])
    XCTAssertEqual(policy.keyboardDefault, .cancel)
  }

  func testUnknownPreferenceFallsBackToCancel() {
    let policy = ConfirmationKeyboardPolicy(
      preferences: [ConfirmationKeyboardPolicy.keyboardDefaultKey: "yolo"])
    XCTAssertEqual(policy.keyboardDefault, .cancel)
  }

  func testArmingDelayReadsANumberAndClampsItToFiveSeconds() {
    XCTAssertEqual(
      ConfirmationKeyboardPolicy(
        preferences: [ConfirmationKeyboardPolicy.armingDelayKey: 2.5]
      ).armingDelaySeconds, 2.5)
    XCTAssertEqual(
      ConfirmationKeyboardPolicy(
        preferences: [ConfirmationKeyboardPolicy.armingDelayKey: 30]
      ).armingDelaySeconds, 5.0)
    XCTAssertEqual(
      ConfirmationKeyboardPolicy(
        preferences: [ConfirmationKeyboardPolicy.armingDelayKey: 0]
      ).armingDelaySeconds, 0.0)
  }

  func testArmingDelayRejectsNegativeNaNAndNonNumbers() {
    for value: Any in [-1.0, Double.nan, "soon", true] {
      XCTAssertEqual(
        ConfirmationKeyboardPolicy(
          preferences: [ConfirmationKeyboardPolicy.armingDelayKey: value]
        ).armingDelaySeconds, 1.0, "\(value)")
    }
  }

  func testCancelKeysArmOnlyOnceTheArmingDelayHasPassed() {
    let policy = ConfirmationKeyboardPolicy(preferences: [:])
    XCTAssertFalse(policy.cancelKeysAreArmed(elapsedSeconds: 0))
    XCTAssertFalse(policy.cancelKeysAreArmed(elapsedSeconds: 0.99))
    XCTAssertTrue(policy.cancelKeysAreArmed(elapsedSeconds: 1.0))
  }

  func testCancelKeysNeverArmInNoneMode() {
    let policy = ConfirmationKeyboardPolicy(
      preferences: [ConfirmationKeyboardPolicy.keyboardDefaultKey: "none"])
    XCTAssertFalse(policy.cancelKeysAreArmed(elapsedSeconds: 60))
  }

  func testZeroDelayArmsImmediately() {
    let policy = ConfirmationKeyboardPolicy(
      preferences: [ConfirmationKeyboardPolicy.armingDelayKey: 0])
    XCTAssertTrue(policy.cancelKeysAreArmed(elapsedSeconds: 0))
  }

  func testCustomDelayAndNoneModeRespectTheBoundary() {
    let delayed = ConfirmationKeyboardPolicy(
      preferences: [ConfirmationKeyboardPolicy.armingDelayKey: 2.5])
    XCTAssertFalse(delayed.cancelKeysAreArmed(elapsedSeconds: 2.499))
    XCTAssertTrue(delayed.cancelKeysAreArmed(elapsedSeconds: 2.5))
    XCTAssertTrue(delayed.cancelKeysAreArmed(elapsedSeconds: 3))
    let disabled = ConfirmationKeyboardPolicy(preferences: [
      ConfirmationKeyboardPolicy.keyboardDefaultKey: "none",
      ConfirmationKeyboardPolicy.armingDelayKey: 0,
    ])
    XCTAssertFalse(disabled.cancelKeysAreArmed(elapsedSeconds: 0))
    XCTAssertFalse(disabled.cancelKeysAreArmed(elapsedSeconds: 10))
  }

  func testPreferenceDomainIsSharedBetweenSourceAndNotarizedInstalls() {
    XCTAssertEqual(ConfirmationKeyboardPolicy.suiteName, "com.lorislab.webkitui-mcp")
    XCTAssertEqual(ConfirmationKeyboardPolicy.keyboardDefaultKey, "ConfirmationKeyboardDefault")
    XCTAssertEqual(ConfirmationKeyboardPolicy.armingDelayKey, "ConfirmationArmingDelaySeconds")
  }

  func testQueuedInputUsesItsOriginalTimestamp() {
    let policy = ConfirmationKeyboardPolicy(preferences: [:])
    // The UI may handle this early input several seconds later; its timestamp stays early.
    XCTAssertFalse(policy.cancelKeysAreArmed(eventTimestamp: 100.2, presentedAt: 100))
    XCTAssertFalse(policy.cancelKeysAreArmed(eventTimestamp: 99, presentedAt: 100))
    XCTAssertTrue(policy.cancelKeysAreArmed(eventTimestamp: 101, presentedAt: 100))
    XCTAssertFalse(policy.cancelKeysAreArmed(eventTimestamp: .infinity, presentedAt: 100))
    XCTAssertFalse(policy.cancelKeysAreArmed(eventTimestamp: 101, presentedAt: .nan))
    let disabled = ConfirmationKeyboardPolicy(preferences: [
      ConfirmationKeyboardPolicy.keyboardDefaultKey: "none"
    ])
    XCTAssertFalse(disabled.cancelKeysAreArmed(eventTimestamp: 110, presentedAt: 100))
  }
}
