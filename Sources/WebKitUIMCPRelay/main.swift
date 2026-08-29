import Darwin
import Foundation

@main
struct WebKitUIMCPRelay {
  static func main() {
    signal(SIGPIPE, SIG_IGN)
    guard CommandLine.arguments.count == 2 else {
      diagnostic("relay requires one Unix socket path")
    }
    let path = CommandLine.arguments[1]
    var descriptor: Int32?
    var responseBuffer = Data()
    while let line = Swift.readLine() {
      let request = Data((line + "\n").utf8)
      let identifier = requestIdentifier(in: request)
      var dispatched = false

      for attempt in 0..<2 {
        if descriptor == nil {
          descriptor = try? connectWithRetry(to: path)
          responseBuffer.removeAll(keepingCapacity: true)
        }
        guard let liveDescriptor = descriptor else { break }
        do {
          try writeAll(request, to: liveDescriptor)
          dispatched = true
        } catch {
          Darwin.close(liveDescriptor)
          descriptor = nil
          guard attempt == 0 else { break }
          continue
        }
        break
      }

      guard dispatched else {
        emitTransportError(
          id: identifier,
          code: -32_097,
          message: "WebKitUI MCP app unavailable; request not dispatched")
        continue
      }
      guard identifier.present, let liveDescriptor = descriptor else { continue }
      do {
        let response = try readLine(from: liveDescriptor, buffer: &responseBuffer)
        try writeAll(response, to: STDOUT_FILENO)
      } catch {
        Darwin.close(liveDescriptor)
        descriptor = nil
        responseBuffer.removeAll(keepingCapacity: true)
        emitTransportError(
          id: identifier,
          code: -32_098,
          message:
            "WebKitUI MCP app restarted after dispatch; request outcome unknown and was not replayed"
        )
      }
    }
    if let descriptor { Darwin.close(descriptor) }
  }

  private static func connectWithRetry(
    to path: String,
    attempts: Int = 50,
    delayMicroseconds: useconds_t = 100_000
  ) throws -> Int32 {
    precondition(attempts > 0)
    for attempt in 1...attempts {
      do { return try connect(to: path) } catch {
        guard attempt < attempts else { throw error }
        usleep(delayMicroseconds)
      }
    }
    throw RelayError.connectionFailed
  }

  private static func connect(to path: String) throws -> Int32 {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw RelayError.socketCreationFailed }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
    let copied = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
      pointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) {
        strlcpy($0, path, pathCapacity)
      }
    }
    guard copied < pathCapacity else {
      Darwin.close(descriptor)
      throw RelayError.socketPathTooLong
    }
    let result = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard result == 0 else {
      Darwin.close(descriptor)
      throw RelayError.connectionFailed
    }
    return descriptor
  }

  private static func writeAll(_ data: Data, to descriptor: Int32) throws {
    try data.withUnsafeBytes { rawBuffer in
      var offset = 0
      while offset < rawBuffer.count {
        let written = Darwin.write(
          descriptor, rawBuffer.baseAddress?.advanced(by: offset), rawBuffer.count - offset)
        if written < 0, errno == EINTR { continue }
        guard written > 0 else { throw RelayError.connectionLost }
        offset += written
      }
    }
  }

  private static func readLine(from descriptor: Int32, buffer: inout Data) throws -> Data {
    var chunk = [UInt8](repeating: 0, count: 16_384)
    while true {
      if let newline = buffer.firstIndex(of: 0x0A) {
        let line = Data(buffer[...newline])
        buffer.removeSubrange(...newline)
        return line
      }
      let count = chunk.withUnsafeMutableBytes {
        Darwin.read(descriptor, $0.baseAddress, $0.count)
      }
      if count < 0, errno == EINTR { continue }
      guard count > 0 else { throw RelayError.connectionLost }
      buffer.append(contentsOf: chunk.prefix(count))
      guard buffer.count <= 8 * 1_024 * 1_024 else { throw RelayError.frameTooLarge }
    }
  }

  private static func requestIdentifier(in request: Data) -> RequestIdentifier {
    guard
      let object = try? JSONSerialization.jsonObject(with: request) as? [String: Any],
      object.keys.contains("id")
    else { return RequestIdentifier(present: false, value: NSNull()) }
    return RequestIdentifier(present: true, value: object["id"] ?? NSNull())
  }

  private static func emitTransportError(id: RequestIdentifier, code: Int, message: String) {
    guard id.present else { return }
    let object: [String: Any] = [
      "jsonrpc": "2.0",
      "id": id.value,
      "error": ["code": code, "message": message],
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
    try? writeAll(data + Data("\n".utf8), to: STDOUT_FILENO)
  }

  private static func diagnostic(_ message: String) -> Never {
    FileHandle.standardError.write(Data("webkitui-mcp: \(message)\n".utf8))
    Foundation.exit(EXIT_FAILURE)
  }
}

private enum RelayError: Error {
  case connectionLost
  case connectionFailed
  case frameTooLarge
  case socketCreationFailed
  case socketPathTooLong
}

private struct RequestIdentifier {
  let present: Bool
  let value: Any
}
