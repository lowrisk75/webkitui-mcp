import Foundation
import Testing

@testable import WebKitUIMCPServer

@Suite("Private activity log", .serialized)
struct ActivityLogTests {
  @Test("The journal stores only allowlisted metadata and owner-only files")
  func redactionAndPermissions() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let log = try WebKitActivityLog(directoryURL: directory)

    await log.record(
      method: "tools/call",
      toolName: "password=super-secret",
      outcome: .failed,
      durationMilliseconds: 12,
      errorType: "SyntheticError<script>"
    )

    let events = try await log.events()
    let event = try #require(events.first)
    #expect(event.method == "tools/call")
    #expect(event.toolName == "unknown")
    #expect(event.errorType == "SyntheticErrorscript")
    let exported = String(decoding: try await log.exportData(), as: UTF8.self)
    #expect(!exported.contains("super-secret"))
    let permissions =
      try FileManager.default.attributesOfItem(
        atPath: log.activeFileURL.path)[.posixPermissions] as? NSNumber
    #expect(permissions?.intValue == 0o600)
  }

  @Test("The journal rotates and can be cleared without touching receipts")
  func rotationAndClear() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let log = try WebKitActivityLog(
      directoryURL: directory,
      maximumBytes: 256,
      maximumArchives: 2
    )

    for _ in 0..<8 {
      await log.record(
        method: "tools/call",
        toolName: "browser_observe",
        outcome: .succeeded,
        durationMilliseconds: 1
      )
    }

    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    #expect(names.contains("activity.jsonl"))
    #expect(names.contains("activity.jsonl.1"))
    #expect(!names.contains("activity.jsonl.3"))
    #expect(!(try await log.events(limit: 100)).isEmpty)

    try await log.clear()
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
  }

  @Test("A symlinked journal directory is rejected")
  func symlinkDirectoryRejected() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let actual = root.appending(path: "actual", directoryHint: .isDirectory)
    let link = root.appending(path: "link", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: actual)

    #expect(throws: (any Error).self) {
      _ = try WebKitActivityLog(directoryURL: link)
    }
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(
      path: "webkitui-activity-log-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
  }
}
