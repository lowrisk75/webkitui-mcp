import Darwin
import Foundation

public struct WebKitSessionHandle: Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }
}

public struct WebKitSessionStatus: Codable, Equatable, Sendable {
  public let sessionID: UUID
  public let currentURL: String?
  public let isLoading: Bool
}

public enum WebKitSessionRegistryError: Error, Equatable, Sendable {
  case invalidMaximumSessions
  case capacityReached
  case hostControllerBusy
  case hostControllerLockUnavailable
  case unknownSession
  case networkBoundaryUnavailable
}

private final class HostControllerLease {
  private let descriptor: Int32

  init() throws {
    let fileManager = FileManager.default
    guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
      throw WebKitSessionRegistryError.hostControllerLockUnavailable
    }
    let directory = caches.appendingPathComponent(
      "com.lorislab.webkitui-mcp", isDirectory: true)
    do {
      try fileManager.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
    } catch {
      throw WebKitSessionRegistryError.hostControllerLockUnavailable
    }
    guard chmod(directory.path, S_IRWXU) == 0 else {
      throw WebKitSessionRegistryError.hostControllerLockUnavailable
    }
    let path = directory.appendingPathComponent("controller.lock").path
    let opened = Darwin.open(path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard opened >= 0 else {
      throw WebKitSessionRegistryError.hostControllerLockUnavailable
    }
    guard fchmod(opened, S_IRUSR | S_IWUSR) == 0 else {
      Darwin.close(opened)
      throw WebKitSessionRegistryError.hostControllerLockUnavailable
    }
    guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
      Darwin.close(opened)
      if errno == EWOULDBLOCK {
        throw WebKitSessionRegistryError.hostControllerBusy
      }
      throw WebKitSessionRegistryError.hostControllerLockUnavailable
    }
    descriptor = opened
  }

  deinit {
    flock(descriptor, LOCK_UN)
    Darwin.close(descriptor)
  }
}

@MainActor
public final class WebKitSessionRegistry {
  public let maximumSessions: Int
  private let enforceHostExclusiveSession: Bool
  private var sessions: [WebKitSessionHandle: WebKitRuntime] = [:]
  private var hostControllerLease: HostControllerLease?

  public init(maximumSessions: Int = 1, enforceHostExclusiveSession: Bool = false) throws {
    guard maximumSessions > 0 else { throw WebKitSessionRegistryError.invalidMaximumSessions }
    self.maximumSessions = maximumSessions
    self.enforceHostExclusiveSession = enforceHostExclusiveSession
  }

  public var count: Int { sessions.count }

  public func open() throws -> WebKitSessionHandle {
    guard sessions.count < maximumSessions else {
      throw WebKitSessionRegistryError.capacityReached
    }
    let lease = try enforceHostExclusiveSession ? HostControllerLease() : nil
    let handle = WebKitSessionHandle(rawValue: UUID())
    do {
      sessions[handle] = try WebKitRuntime(protectedWebsiteDataStore: .default())
      hostControllerLease = lease
    } catch {
      throw WebKitSessionRegistryError.networkBoundaryUnavailable
    }
    return handle
  }

  public func close(_ handle: WebKitSessionHandle) throws {
    guard sessions.removeValue(forKey: handle) != nil else {
      throw WebKitSessionRegistryError.unknownSession
    }
    if sessions.isEmpty { hostControllerLease = nil }
  }

  public func runtime(for handle: WebKitSessionHandle) throws -> WebKitRuntime {
    guard let runtime = sessions[handle] else {
      throw WebKitSessionRegistryError.unknownSession
    }
    return runtime
  }

  public func status(_ handle: WebKitSessionHandle) throws -> WebKitSessionStatus {
    let runtime = try runtime(for: handle)
    return WebKitSessionStatus(
      sessionID: handle.rawValue,
      currentURL: runtime.webView.url?.absoluteString,
      isLoading: runtime.webView.isLoading
    )
  }
}
