import Darwin
import Foundation
import Testing

@testable import WebKitUIMCPRuntime

@Suite("Host lease eviction")
struct HostLeaseEvictionTests {
  private func holder(pid: Int32) -> WebKitControllerHolder {
    WebKitControllerHolder(clientName: "peer", processID: pid)
  }

  @Test("No holder means nothing to evict")
  func noHolder() {
    #expect(
      HostLeaseEviction.decide(
        holder: nil, selfProcessID: 10, executablePath: nil, processIsRunning: false)
        == .noHolder)
  }

  @Test("The host never signals itself")
  func refusesSelf() {
    // The operator is looking at this very process. Terminating it would take the
    // Status window down with it.
    #expect(
      HostLeaseEviction.decide(
        holder: holder(pid: 42), selfProcessID: 42,
        executablePath: "/usr/local/bin/webkitui-mcp", processIsRunning: true)
        == .refusedSelf(42))
  }

  @Test("A recorded process that is gone is not signalled")
  func refusesDeadProcess() {
    #expect(
      HostLeaseEviction.decide(
        holder: holder(pid: 42), selfProcessID: 10,
        executablePath: "/usr/local/bin/webkitui-mcp", processIsRunning: false)
        == .refusedNotRunning(42))
  }

  @Test("A pid recycled onto an unrelated process is left alone")
  func refusesUnrecognisedExecutable() {
    // This is the whole reason the executable is checked: the lock file records a pid,
    // the kernel hands that number to somebody else, and the record alone would have us
    // signal a stranger.
    let decision = HostLeaseEviction.decide(
      holder: holder(pid: 42), selfProcessID: 10,
      executablePath: "/usr/bin/ssh", processIsRunning: true)
    #expect(decision == .refusedUnrecognisedExecutable(42, "/usr/bin/ssh"))
  }

  @Test("An unreadable executable path is refused rather than assumed")
  func refusesUnknownExecutable() {
    #expect(
      HostLeaseEviction.decide(
        holder: holder(pid: 42), selfProcessID: 10,
        executablePath: nil, processIsRunning: true)
        == .refusedUnrecognisedExecutable(42, nil))
  }

  @Test("A live peer client is the one case that is terminated")
  func terminatesLivePeer() {
    #expect(
      HostLeaseEviction.decide(
        holder: holder(pid: 42), selfProcessID: 10,
        executablePath: "/Users/someone/.local/bin/webkitui-mcp", processIsRunning: true)
        == .terminate(42))
  }

  @Test("The broker executable is recognised too")
  func recognisesBrokerExecutable() {
    #expect(
      HostLeaseEviction.decide(
        holder: holder(pid: 42), selfProcessID: 10,
        executablePath: "/Applications/X.app/Contents/MacOS/webkitui-mcp-aqua-broker",
        processIsRunning: true)
        == .terminate(42))
  }

  @Test("Eviction reports success once the lock comes free")
  func evictReportsRelease() {
    var signalled: [Int32] = []
    var lookups = 0
    let outcome = HostLeaseEviction.evict(
      graceSeconds: 1,
      selfProcessID: 10,
      holderLookup: { _ in
        lookups += 1
        return lookups == 1 ? WebKitControllerHolder(clientName: "peer", processID: 42) : nil
      },
      executablePathLookup: { _ in "/x/webkitui-mcp" },
      processIsRunning: { _ in true },
      terminate: { signalled.append($0) },
      sleep: { _ in })
    #expect(outcome == .evicted(42))
    #expect(signalled == [42])
  }

  @Test("A holder that ignores the signal is reported, not killed harder")
  func evictReportsStillHeld() {
    // Losing a peer's unsaved work is the operator's call. The button says what happened
    // instead of escalating to SIGKILL on its own.
    var signalled: [Int32] = []
    let outcome = HostLeaseEviction.evict(
      graceSeconds: 0.3,
      selfProcessID: 10,
      holderLookup: { _ in WebKitControllerHolder(clientName: "peer", processID: 42) },
      executablePathLookup: { _ in "/x/webkitui-mcp" },
      processIsRunning: { _ in true },
      terminate: { signalled.append($0) },
      sleep: { _ in })
    #expect(outcome == .stillHeld(42))
    #expect(signalled == [42])
  }

  @Test("A refusal never signals anything")
  func refusalDoesNotSignal() {
    var signalled: [Int32] = []
    let outcome = HostLeaseEviction.evict(
      selfProcessID: 10,
      holderLookup: { _ in WebKitControllerHolder(clientName: "peer", processID: 42) },
      executablePathLookup: { _ in "/usr/bin/ssh" },
      processIsRunning: { _ in true },
      terminate: { signalled.append($0) },
      sleep: { _ in })
    #expect(outcome == .refused(.refusedUnrecognisedExecutable(42, "/usr/bin/ssh")))
    #expect(signalled.isEmpty)
  }
}
