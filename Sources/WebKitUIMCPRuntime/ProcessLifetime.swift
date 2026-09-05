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
