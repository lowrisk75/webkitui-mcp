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

  func testReturnCancelsOnlyOnceTheArmingDelayHasPassed() {
    let policy = ConfirmationKeyboardPolicy(preferences: [:])
    XCTAssertFalse(policy.returnCancels(elapsedSeconds: 0))
    XCTAssertFalse(policy.returnCancels(elapsedSeconds: 0.99))
    XCTAssertTrue(policy.returnCancels(elapsedSeconds: 1.0))
  }

  func testReturnNeverCancelsInNoneMode() {
    let policy = ConfirmationKeyboardPolicy(
      preferences: [ConfirmationKeyboardPolicy.keyboardDefaultKey: "none"])
    XCTAssertFalse(policy.returnCancels(elapsedSeconds: 60))
  }

  func testZeroDelayArmsImmediately() {
    let policy = ConfirmationKeyboardPolicy(
      preferences: [ConfirmationKeyboardPolicy.armingDelayKey: 0])
    XCTAssertTrue(policy.returnCancels(elapsedSeconds: 0))
  }

  func testPreferenceDomainIsSharedBetweenSourceAndNotarizedInstalls() {
    XCTAssertEqual(ConfirmationKeyboardPolicy.suiteName, "com.lorislab.webkitui-mcp")
    XCTAssertEqual(ConfirmationKeyboardPolicy.keyboardDefaultKey, "ConfirmationKeyboardDefault")
    XCTAssertEqual(ConfirmationKeyboardPolicy.armingDelayKey, "ConfirmationArmingDelaySeconds")
  }
}
