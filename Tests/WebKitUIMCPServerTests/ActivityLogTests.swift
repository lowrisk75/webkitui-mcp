import CoreGraphics
import Foundation
import ImageIO
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

  @Test("A returned call records what it achieved, from a closed vocabulary only")
  func resultStateIsAllowlisted() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let log = try WebKitActivityLog(directoryURL: directory)
    await log.record(
      method: "tools/call", toolName: "browser_session", outcome: .succeeded,
      durationMilliseconds: 30_013, resultState: "deadline_reached")
    await log.record(
      method: "tools/call", toolName: "browser_act", outcome: .succeeded,
      durationMilliseconds: 5, resultState: "https://private.example/")
    let states = try await log.events().map(\.resultState)
    #expect(states.contains("deadline_reached"))
    #expect(states.contains(nil))
    #expect(!states.contains("https://private.example/"))
    let exported = String(decoding: try await log.exportData(), as: UTF8.self)
    #expect(exported.contains("\"result_state\" : \"deadline_reached\""))
  }

  @Test("The server maps results to journal labels without copying their content")
  func serverJournalLabels() {
    #expect(
      WebKitMCPServer.activityResultState(["readiness": .string("deadline_reached")])
        == "deadline_reached")
    #expect(WebKitMCPServer.activityResultState(["readiness": .string("ready")]) == nil)
    #expect(
      WebKitMCPServer.activityResultState(["verification": .object(["indeterminate": .null])])
        == "indeterminate")
    #expect(WebKitMCPServer.activityResultState(["image_uniform": .bool(true)]) == "blank_capture")
    #expect(
      WebKitMCPServer.activityErrorType([
        "code": .string("tool_error"),
        "message": .string("targetNotFound([\"context_anchor:previous_sibling\"])"),
      ]) == "targetNotFound")
    #expect(
      WebKitMCPServer.activityErrorType(["code": .string("session_busy")]) == "session_busy")
  }

  @Test("A colon inside an error message is not mistaken for a remediation")
  func toolErrorKeepsColonInMessage() {
    let fields = WebKitMCPServer.toolErrorFields(
      "targetNotFound([\"context_anchor:previous_sibling\"])")
    #expect(fields.code == "tool_error")
    #expect(!fields.remediation.contains("previous_sibling"))
    #expect(fields.remediation.hasPrefix("No element matches"))
    #expect(
      WebKitMCPServer.toolErrorFields("preconditionUnsatisfied").remediation
        .contains("nothing was dispatched"))
    #expect(
      WebKitMCPServer.toolErrorFields(
        #"privateNetworkDestination(origin: "https://homeassistant.example.ts.net")"#
      ).remediation.contains("Retrying will not change that"))
    let coded = WebKitMCPServer.toolErrorFields("session_busy: Close the other session first.")
    #expect(coded.code == "session_busy")
    #expect(coded.remediation == "Close the other session first.")
  }

  @Test("A flat capture is flagged and a varied one is not")
  func uniformCaptureDetection() throws {
    #expect(WebKitMCPServer.isUniformImage(try png(split: false)))
    #expect(!WebKitMCPServer.isUniformImage(try png(split: true)))
    #expect(!WebKitMCPServer.isUniformImage(Data("not an image".utf8)))
  }

  private func png(split: Bool) throws -> Data {
    let side = 64
    let context = try #require(
      CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    if split {
      context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: side, height: side / 2))
    }
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(
      CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(
      path: "webkitui-activity-log-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
  }
}
