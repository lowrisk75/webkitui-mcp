import Foundation
import WebKitUIMCPServer

@main
struct WebKitUIMCPCLI {
  @MainActor
  static func main() async {
    if CommandLine.arguments.dropFirst().contains(where: { $0 == "--help" || $0 == "-h" }) {
      FileHandle.standardOutput.write(
        Data(
          """
          Usage: webkitui-mcp

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
      let server = try WebKitMCPServer(maximumSessions: 1, enforceHostExclusiveSession: true)
      for try await line in FileHandle.standardInput.bytes.lines {
        if let response = await server.handle(Data(line.utf8)) {
          FileHandle.standardOutput.write(response)
          FileHandle.standardOutput.write(Data("\n".utf8))
        }
      }
    } catch {
      FileHandle.standardError.write(Data("webkitui-mcp stopped: \(error)\n".utf8))
      Foundation.exit(EXIT_FAILURE)
    }
  }
}
