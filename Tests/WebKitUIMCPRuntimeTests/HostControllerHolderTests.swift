import Darwin
import Foundation
import Testing

@testable import WebKitUIMCPRuntime

@Suite("Host controller holder liveness")
struct HostControllerHolderTests {
  @Test("A holder record naming a dead process is reported as stale")
  func staleHolderRecordIsDetected() throws {
    // The record is written by whoever last acquired the lease. A client that took
    // the lock afterwards without rewriting it leaves a record naming a process that
    // no longer exists, which is worse than no record: it misdirects the operator.
    #expect(WebKitControllerHolder.isProcessRunning(getpid()))
    #expect(!WebKitControllerHolder.isProcessRunning(Int32(999_999)))

    let live = WebKitControllerHolder(clientName: "live-client", processID: getpid())
    let dead = WebKitControllerHolder(clientName: "dead-client", processID: Int32(999_999))
    #expect(live.processIsRunning)
    #expect(!dead.processIsRunning)
  }
}
