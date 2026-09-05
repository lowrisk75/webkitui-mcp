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

  @Test("A record the host wrote for itself is distinguishable from a peer at work")
  func hostPlaceholderIsDistinguishable() throws {
    // pid_is_this_broker is asked of whichever process answers, so it is false for
    // every holder a client can see — including the host's own leftover record. A
    // client read that as "another session is working" and waited on a lease nobody
    // owned. The two call for opposite reactions and now differ on the record itself.
    let peer = WebKitControllerHolder(clientName: "claude-code", executionPolicy: "trusted_local")
    let placeholder = WebKitControllerHolder(
      clientName: "WebKitUI MCP host", executionPolicy: "unowned", isHostPlaceholder: true)
    #expect(peer.isHostPlaceholder == false)
    #expect(placeholder.isHostPlaceholder)

    // Records written before this field existed decode as a peer, which is the safe
    // reading: it means wait rather than take.
    let legacy = Data(
      #"{"clientName":"old","processID":1,"acquiredAt":0,"lastActivityAt":0,"executionPolicy":"auto"}"#
        .utf8)
    let decoded = try JSONDecoder().decode(WebKitControllerHolder.self, from: legacy)
    #expect(decoded.isHostPlaceholder == false)
  }
}
