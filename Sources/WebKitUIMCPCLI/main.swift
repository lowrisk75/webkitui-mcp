import AppKit
import Foundation
import WebKitUIMCPServer

@main
struct WebKitUIMCPCLI {
  @MainActor
  static func main() async {
    if CommandLine.arguments.dropFirst().contains("--version") {
      FileHandle.standardOutput.write(Data("webkitui-mcp \(WebKitMCPServer.version)\n".utf8))
      return
    }
    if CommandLine.arguments.dropFirst().contains(where: { $0 == "--help" || $0 == "-h" }) {
      FileHandle.standardOutput.write(
        Data(
          """
          Usage: webkitui-mcp [--help | --version]

          Native WebKit MCP server. Reads newline-delimited JSON-RPC from stdin and writes responses to stdout.
          """.utf8))
      FileHandle.standardOutput.write(Data("\n".utf8))
      return
    }
    guard CommandLine.arguments.count == 1 else {
      FileHandle.standardError.write(
        Data("webkitui-mcp: unexpected arguments; use --help\n".utf8))
      Foundation.exit(EX_USAGE)
    }
    do {
      let server = try WebKitMCPServer(maximumSessions: 8, enforceHostExclusiveSession: false)
      let application = NSApplication.shared
      application.setActivationPolicy(.accessory)
      application.finishLaunching()
      Task.detached {
        do {
          for try await line in FileHandle.standardInput.bytes.lines {
            if let response = await server.handle(Data(line.utf8)) {
              FileHandle.standardOutput.write(response)
              FileHandle.standardOutput.write(Data("\n".utf8))
            }
          }
          await MainActor.run { stopApplicationEventLoop() }
        } catch {
          FileHandle.standardError.write(Data("webkitui-mcp stopped: \(error)\n".utf8))
          Foundation.exit(EXIT_FAILURE)
        }
      }
      application.run()
    } catch {
      FileHandle.standardError.write(Data("webkitui-mcp stopped: \(error)\n".utf8))
      Foundation.exit(EXIT_FAILURE)
    }
  }

  @MainActor
  private static func stopApplicationEventLoop() {
    let application = NSApplication.shared
    application.stop(nil)
    if let event = NSEvent.otherEvent(
      with: .applicationDefined,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      subtype: 0,
      data1: 0,
      data2: 0
    ) {
      application.postEvent(event, atStart: false)
    }
  }
}
