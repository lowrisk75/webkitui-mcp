import Foundation
import Testing

@testable import WebKitUIMCPServer

@Suite("Native confirmation helper location")
struct NativeConfirmationHelperLocationTests {
  @Test("The executable is resolved absolutely, never from what the caller typed")
  func executableIsAbsolute() {
    // doctor used CommandLine.arguments[0]. Invoked by bare name through PATH
    // that carries no directory, so the helper was looked for in the working
    // directory and a healthy installation reported action_required.
    let executable = NativeConfirmationHelperLocation.executableURL
    #expect(executable.path.hasPrefix("/"))
    #expect(NativeConfirmationHelperLocation.helperURL.path.hasPrefix("/"))
  }

  @Test("The helper is expected beside the executable, under its exact name")
  func helperSitsBesideTheExecutable() {
    let executable = URL(fileURLWithPath: "/opt/webkitui/bin/webkitui-mcp")
    let helper = NativeConfirmationHelperLocation.helperURL(besideExecutable: executable)
    #expect(helper.path == "/opt/webkitui/bin/webkitui-mcp-confirm")
    #expect(helper.lastPathComponent == NativeConfirmationHelperLocation.helperName)
  }

  @Test("Availability reports the file that is actually there")
  func availabilityFollowsTheFileSystem() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("webkitui-mcp")

    #expect(
      NativeConfirmationHelperLocation.helperIsAvailable(besideExecutable: executable) == false)

    let helper = directory.appendingPathComponent(NativeConfirmationHelperLocation.helperName)
    try Data().write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

    #expect(NativeConfirmationHelperLocation.helperIsAvailable(besideExecutable: executable))
  }
}
