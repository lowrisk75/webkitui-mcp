import Foundation
import Testing

@testable import WebKitUIMCPCore

@Suite("Confirmation rate policy")
struct ConfirmationRatePolicyTests {
  private let second: UInt64 = 1_000_000_000

  @Test("Ordinary work is never slowed")
  func ordinaryWorkIsNormal() {
    var policy = ConfirmationRatePolicy()
    for index in 0..<4 {
      #expect(policy.record(atMonotonicNanoseconds: UInt64(index) * 5 * second) == .normal)
    }
  }

  @Test("A burst is named, with how many confirmations it counted")
  func burstIsNamed() {
    var policy = ConfirmationRatePolicy()
    var verdict = ConfirmationRatePolicy.Verdict.normal
    for index in 0..<ConfirmationRatePolicy.burstThreshold {
      verdict = policy.record(atMonotonicNanoseconds: UInt64(index) * second / 2)
    }
    #expect(verdict == .burst(recentCount: ConfirmationRatePolicy.burstThreshold))
  }

  @Test("A flood is refused rather than shown")
  func floodIsRefused() {
    var policy = ConfirmationRatePolicy()
    var verdict = ConfirmationRatePolicy.Verdict.normal
    for index in 0..<ConfirmationRatePolicy.refuseThreshold {
      verdict = policy.record(atMonotonicNanoseconds: UInt64(index) * second / 10)
    }
    #expect(verdict == .refuse(recentCount: ConfirmationRatePolicy.refuseThreshold))
  }

  @Test("The window forgets, so a long session is not punished for its past")
  func windowForgets() {
    var policy = ConfirmationRatePolicy()
    for index in 0..<ConfirmationRatePolicy.refuseThreshold {
      _ = policy.record(atMonotonicNanoseconds: UInt64(index) * second / 10)
    }
    // Well past the window.
    #expect(policy.record(atMonotonicNanoseconds: 600 * second) == .normal)
  }
}
