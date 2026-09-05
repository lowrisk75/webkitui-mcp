import Darwin
import Foundation
import Testing

@testable import WebKitUIMCPRuntime

@Suite("Orphaned server exit")
struct OrphanExitTests {
  @Test("A server reparented to launchd is orphaned and must release its lease")
  func reparentedServerIsOrphaned() {
    // An MCP client that dies without closing the pipe leaves the server alive,
    // holding the single host lease forever. Reparenting to pid 1 is the signal
    // that the client is gone.
    #expect(WebKitUIProcessLifetime.isOrphaned(parentProcessIdentifier: 1))
    #expect(!WebKitUIProcessLifetime.isOrphaned(parentProcessIdentifier: getppid()))
    // A parent that no longer exists counts as gone even before reparenting lands.
    #expect(WebKitUIProcessLifetime.isOrphaned(parentProcessIdentifier: 999_999))
  }
}
