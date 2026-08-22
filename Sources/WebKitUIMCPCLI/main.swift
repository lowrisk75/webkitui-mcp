import Foundation
import WebKitUIMCPServer

@main
struct WebKitUIMCPCLI {
  @MainActor
  static func main() async {
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
