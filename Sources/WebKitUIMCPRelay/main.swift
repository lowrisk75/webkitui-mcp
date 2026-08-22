import Darwin
import Foundation

@main
struct WebKitUIMCPRelay {
  static func main() {
    signal(SIGPIPE, SIG_IGN)
    guard CommandLine.arguments.count == 2 else {
      diagnostic("relay requires one Unix socket path")
    }
    let descriptor: Int32
    do {
      descriptor = try connect(to: CommandLine.arguments[1])
    } catch {
      diagnostic("relay could not connect")
    }

    DispatchQueue.global(qos: .userInitiated).async {
      pump(from: STDIN_FILENO, to: descriptor)
      shutdown(descriptor, SHUT_WR)
    }
    pump(from: descriptor, to: STDOUT_FILENO)
    Darwin.close(descriptor)
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

  private static func pump(from source: Int32, to destination: Int32) {
    var buffer = [UInt8](repeating: 0, count: 16_384)
    while true {
      let count = buffer.withUnsafeMutableBytes {
        Darwin.read(source, $0.baseAddress, $0.count)
      }
      guard count > 0 else { return }
      var offset = 0
      while offset < count {
        let written = buffer.withUnsafeBytes {
          Darwin.write(destination, $0.baseAddress?.advanced(by: offset), count - offset)
        }
        guard written > 0 else { return }
        offset += written
      }
    }
  }

  private static func diagnostic(_ message: String) -> Never {
    FileHandle.standardError.write(Data("webkitui-mcp: \(message)\n".utf8))
    Foundation.exit(EXIT_FAILURE)
  }
}

private enum RelayError: Error {
  case connectionFailed
  case socketCreationFailed
  case socketPathTooLong
}
