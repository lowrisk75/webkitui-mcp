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

  @Test("A shutdown announces itself, and says when the binary underneath it changed")
  func shutdownNoticeNamesItsReason() throws {
    // Reported from the Play campaign: the CLI was rebuilt mid-session, the server went
    // away, and the only trace the client had was an Internal error on the next call
    // followed by the tools disappearing — indistinguishable from a crash. A server that
    // is about to exit can say so.
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("webkitui-shutdown-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("webkitui-mcp")
    try Data("first".utf8).write(to: executable)

    let started = try #require(WebKitUIExecutableIdentity(at: executable))
    #expect(WebKitUIProcessLifetime.executableWasReplaced(since: started, at: executable) == false)

    // A rebuild installs a new file at the same path, which is a new inode.
    try FileManager.default.removeItem(at: executable)
    try Data("second".utf8).write(to: executable)
    #expect(WebKitUIProcessLifetime.executableWasReplaced(since: started, at: executable))

    // Removed outright counts too: whatever is there now is not what is running.
    try FileManager.default.removeItem(at: executable)
    #expect(WebKitUIProcessLifetime.executableWasReplaced(since: started, at: executable))

    let notice = WebKitUIProcessLifetime.shutdownNotice(reason: .executableReplaced)
    let decoded = try #require(
      try JSONSerialization.jsonObject(with: notice) as? [String: Any])
    #expect(decoded["jsonrpc"] as? String == "2.0")
    #expect(decoded["method"] as? String == "notifications/message")
    let params = try #require(decoded["params"] as? [String: Any])
    let data = try #require(params["data"] as? [String: Any])
    #expect(data["event"] as? String == "server_shutdown")
    #expect(data["reason"] as? String == "executable_replaced")
    // A notice nobody can parse as one line is no notice at all.
    #expect(!String(decoding: notice, as: UTF8.self).contains("\n"))
  }
}
