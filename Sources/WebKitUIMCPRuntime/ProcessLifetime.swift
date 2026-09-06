import Darwin
import Foundation

/// Detects that the MCP client which spawned this server is gone.
///
/// A client that dies without closing its end of the pipe leaves the server running
/// and holding the single host lease indefinitely, which starves every other client.
/// Reparenting to launchd, or a parent that no longer exists, is the signal.
public enum WebKitUIProcessLifetime {
  public static func isOrphaned(parentProcessIdentifier: Int32) -> Bool {
    if parentProcessIdentifier <= 1 { return true }
    if kill(parentProcessIdentifier, 0) == 0 { return false }
    return errno != EPERM
  }

  /// Exits once the spawning client is gone, releasing the host lease on the way out.
  /// The interval is a liveness check, not a timeout: a working client is never
  /// disturbed.
  public static func exitWhenOrphaned(
    interval: Duration = .seconds(5),
    onExit: @escaping @Sendable () -> Void = {}
  ) -> Task<Void, Never> {
    Task.detached {
      while !Task.isCancelled {
        try? await Task.sleep(for: interval)
        if isOrphaned(parentProcessIdentifier: getppid()) {
          onExit()
          Foundation.exit(EXIT_SUCCESS)
        }
      }
    }
  }
}

/// The exact file that is running, so a rebuild at the same path is detectable.
public struct WebKitUIExecutableIdentity: Equatable, Sendable {
  public let device: UInt64
  public let inode: UInt64

  public init?(at url: URL) {
    var status = stat()
    guard stat(url.path, &status) == 0 else { return nil }
    device = UInt64(status.st_dev)
    inode = UInt64(status.st_ino)
  }
}

extension WebKitUIProcessLifetime {
  /// Why this server is going away. A client that only sees the transport die cannot
  /// tell a deliberate replacement from a crash, and the Play campaign lost a session
  /// to exactly that ambiguity.
  public enum ShutdownReason: String, Sendable {
    case executableReplaced = "executable_replaced"
    case clientGone = "client_gone"
    case terminated
  }

  public static func executableWasReplaced(
    since identity: WebKitUIExecutableIdentity,
    at url: URL
  ) -> Bool {
    guard let current = WebKitUIExecutableIdentity(at: url) else { return true }
    return current != identity
  }

  /// One JSON-RPC line, because the transport is newline delimited and a notice that
  /// cannot be read as one message is no notice at all.
  public static func shutdownNotice(reason: ShutdownReason) -> Data {
    let payload: [String: Any] = [
      "jsonrpc": "2.0",
      "method": "notifications/message",
      "params": [
        "level": "warning",
        "logger": "webkitui-mcp",
        "data": [
          "event": "server_shutdown",
          "reason": reason.rawValue,
        ],
      ],
    ]
    guard
      let data = try? JSONSerialization.data(
        withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
    else {
      return Data(#"{"jsonrpc":"2.0","method":"notifications/message"}"#.utf8)
    }
    return data
  }
}
