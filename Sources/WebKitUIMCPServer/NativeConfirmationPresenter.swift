import Darwin
import Foundation

@MainActor
protocol BrowserConfirmationPresenting: AnyObject {
  func confirm(title: String, message: String, approveLabel: String) -> Bool
}

@MainActor
final class NativeBrowserConfirmationPresenter: BrowserConfirmationPresenting {
  private let helperURL: URL
  private let helperArguments: [String]

  init(helperURL: URL? = nil, helperArguments: [String] = []) {
    self.helperURL = helperURL ?? Self.defaultHelperURL()
    self.helperArguments = helperArguments
  }

  func confirm(title: String, message: String, approveLabel: String) -> Bool {
    let payload: Data
    do {
      payload = try JSONEncoder().encode(
        NativeConfirmationRequest(
          title: title,
          message: message,
          approveLabel: approveLabel
        ))
    } catch {
      return false
    }
    let process = Process()
    let input = Pipe()
    process.executableURL = helperURL
    process.arguments = helperArguments
    process.standardInput = input
    guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
      return false
    }
    do {
      try process.run()
      try input.fileHandleForWriting.write(contentsOf: payload)
      try input.fileHandleForWriting.close()
      process.waitUntilExit()
    } catch {
      try? input.fileHandleForWriting.close()
      if process.isRunning { process.terminate() }
      return false
    }
    return process.terminationReason == .exit && process.terminationStatus == EXIT_SUCCESS
  }

  private static func defaultHelperURL() -> URL {
    let executable =
      Bundle.main.executableURL
      ?? URL(fileURLWithPath: CommandLine.arguments[0])
    return executable.deletingLastPathComponent().appendingPathComponent("webkitui-mcp-confirm")
  }
}

private struct NativeConfirmationRequest: Encodable {
  let title: String
  let message: String
  let approveLabel: String
}
