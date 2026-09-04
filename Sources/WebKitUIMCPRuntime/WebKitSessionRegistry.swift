import CryptoKit
import Darwin
import Foundation
import WebKit

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
  public let profileID: String
  public let controlState: InteractionControlState
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

  init(lockFileURL: URL? = nil) throws {
    let fileManager = FileManager.default
    let directory: URL
    let path: String
    if let lockFileURL {
      directory = lockFileURL.deletingLastPathComponent()
      path = lockFileURL.path
    } else {
      guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
        throw WebKitSessionRegistryError.hostControllerLockUnavailable
      }
      directory = caches.appendingPathComponent(
        "com.lorislab.webkitui-mcp", isDirectory: true)
      path = directory.appendingPathComponent("controller.lock").path
    }
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
  private struct HandoffResumeCapability {
    let session: WebKitSessionHandle
    let expiresAt: Date
  }

  public let maximumSessions: Int
  private let enforceHostExclusiveSession: Bool
  private let hostControllerLockURL: URL?
  private var sessions: [WebKitSessionHandle: WebKitRuntime] = [:]
  // Resume capabilities belong to the host-owned browser authority, not to a
  // transient MCP transport. Only a one-way digest is retained in memory.
  private var handoffResumeCapabilities: [Data: HandoffResumeCapability] = [:]
  private var handoffOwners: [WebKitSessionHandle: UUID] = [:]
  private var sessionOwners: [WebKitSessionHandle: UUID] = [:]
  private var hostControllerLease: HostControllerLease?

  public init(
    maximumSessions: Int = 1,
    enforceHostExclusiveSession: Bool = false,
    hostControllerLockURL: URL? = nil
  ) throws {
    guard maximumSessions > 0 else { throw WebKitSessionRegistryError.invalidMaximumSessions }
    self.maximumSessions = maximumSessions
    self.enforceHostExclusiveSession = enforceHostExclusiveSession
    self.hostControllerLockURL = hostControllerLockURL
  }

  public var count: Int { sessions.count }

  public var existingHandle: WebKitSessionHandle? {
    sessions.keys.first
  }

  public func open(profileIdentifier: UUID? = nil) throws -> WebKitSessionHandle {
    guard sessions.count < maximumSessions else {
      throw WebKitSessionRegistryError.capacityReached
    }
    let lease =
      try enforceHostExclusiveSession
      ? HostControllerLease(lockFileURL: hostControllerLockURL) : nil
    let handle = WebKitSessionHandle(rawValue: UUID())
    do {
      let dataStore = profileIdentifier.map(WKWebsiteDataStore.init(forIdentifier:)) ?? .default()
      sessions[handle] = try WebKitRuntime(protectedWebsiteDataStore: dataStore)
      hostControllerLease = lease
    } catch {
      throw WebKitSessionRegistryError.networkBoundaryUnavailable
    }
    return handle
  }

  /// Reuses the host-owned browser when a durable broker reconnects. The
  /// session handle remains process-private and no observation or action
  /// authority is carried by this operation.
  public func openOrReuse(
    profileIdentifier: UUID? = nil
  ) throws -> (handle: WebKitSessionHandle, reused: Bool) {
    if let existingHandle {
      let currentIdentifier = try runtime(for: existingHandle).webView.configuration
        .websiteDataStore.identifier
      guard currentIdentifier == profileIdentifier else {
        throw WebKitSessionRegistryError.capacityReached
      }
      return (existingHandle, true)
    }
    return (try open(profileIdentifier: profileIdentifier), false)
  }

  public func availableProfileIDs() async -> [String] {
    // macOS 27 (26A5416b) crashes inside
    // WebsiteDataStore::fetchAllDataStoreIdentifiers. Keep the only profile
    // whose persistence is proven and whose identity is stable for this host.
    ["default"]
  }

  public func close(_ handle: WebKitSessionHandle) throws {
    guard sessions.removeValue(forKey: handle) != nil else {
      throw WebKitSessionRegistryError.unknownSession
    }
    revokeHandoffResumeCapabilities(for: handle)
    handoffOwners.removeValue(forKey: handle)
    sessionOwners.removeValue(forKey: handle)
    if sessions.isEmpty { hostControllerLease = nil }
  }

  public func issueHandoffResumeCapability(
    for handle: WebKitSessionHandle,
    lifetime: TimeInterval = 3_600,
    now: Date = Date()
  ) throws -> (token: String, expiresAt: Date) {
    _ = try runtime(for: handle)
    purgeExpiredHandoffResumeCapabilities(now: now)
    revokeHandoffResumeCapabilities(for: handle)
    let token = SymmetricKey(size: .bits256).withUnsafeBytes {
      $0.map { String(format: "%02x", $0) }.joined()
    }
    let expiresAt = now.addingTimeInterval(lifetime)
    handoffResumeCapabilities[handoffResumeDigest(token)] = .init(
      session: handle, expiresAt: expiresAt)
    return (token, expiresAt)
  }

  public func handoffResumeCapabilityIsActive(
    _ token: String,
    for handle: WebKitSessionHandle,
    now: Date = Date()
  ) -> Bool {
    purgeExpiredHandoffResumeCapabilities(now: now)
    guard let capability = handoffResumeCapabilities[handoffResumeDigest(token)] else {
      return false
    }
    return capability.session == handle
  }

  public func hasActiveHandoffResumeCapability(
    for handle: WebKitSessionHandle,
    now: Date = Date()
  ) -> Bool {
    purgeExpiredHandoffResumeCapabilities(now: now)
    return handoffResumeCapabilities.values.contains { $0.session == handle }
  }

  public func claimHandoffOwnership(
    for handle: WebKitSessionHandle,
    owner: UUID
  ) throws -> Bool {
    _ = try runtime(for: handle)
    if let existing = handoffOwners[handle] { return existing == owner }
    handoffOwners[handle] = owner
    return true
  }

  public func handoffOwnershipState(
    for handle: WebKitSessionHandle,
    owner: UUID
  ) throws -> String {
    _ = try runtime(for: handle)
    guard let existing = handoffOwners[handle] else { return "inactive" }
    return existing == owner ? "owned_by_this_client" : "owned_elsewhere"
  }

  @discardableResult
  public func releaseHandoffOwnership(
    for handle: WebKitSessionHandle,
    owner: UUID? = nil
  ) -> Bool {
    guard let existing = handoffOwners[handle] else { return false }
    if let owner, existing != owner { return false }
    handoffOwners.removeValue(forKey: handle)
    return true
  }

  public func releaseHandoffOwnerships(owner: UUID) {
    handoffOwners = handoffOwners.filter { $0.value != owner }
  }

  public func claimSessionOwnership(
    for handle: WebKitSessionHandle,
    owner: UUID
  ) throws -> Bool {
    _ = try runtime(for: handle)
    if let existing = sessionOwners[handle] { return existing == owner }
    sessionOwners[handle] = owner
    return true
  }

  public func sessionOwnershipState(
    for handle: WebKitSessionHandle,
    owner: UUID
  ) throws -> String {
    _ = try runtime(for: handle)
    guard let existing = sessionOwners[handle] else { return "inactive" }
    return existing == owner ? "owned_by_this_client" : "owned_elsewhere"
  }

  public func releaseSessionOwnerships(owner: UUID) {
    sessionOwners = sessionOwners.filter { $0.value != owner }
  }

  @discardableResult
  public func releaseSessionOwnership(
    for handle: WebKitSessionHandle,
    owner: UUID? = nil
  ) -> Bool {
    guard let existing = sessionOwners[handle] else { return false }
    if let owner, existing != owner { return false }
    sessionOwners.removeValue(forKey: handle)
    return true
  }

  @discardableResult
  public func consumeHandoffResumeCapability(
    _ token: String,
    for handle: WebKitSessionHandle,
    now: Date = Date()
  ) -> Bool {
    purgeExpiredHandoffResumeCapabilities(now: now)
    let digest = handoffResumeDigest(token)
    guard handoffResumeCapabilities[digest]?.session == handle else { return false }
    handoffResumeCapabilities.removeValue(forKey: digest)
    return true
  }

  public func revokeHandoffResumeCapabilities(for handle: WebKitSessionHandle) {
    handoffResumeCapabilities = handoffResumeCapabilities.filter { $0.value.session != handle }
  }

  private func purgeExpiredHandoffResumeCapabilities(now: Date) {
    handoffResumeCapabilities = handoffResumeCapabilities.filter { $0.value.expiresAt > now }
  }

  private func handoffResumeDigest(_ token: String) -> Data {
    Data(SHA256.hash(data: Data(token.utf8)))
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
      currentURL: runtime.agentSafeCurrentURL(),
      isLoading: runtime.webView.isLoading,
      profileID: runtime.webView.configuration.websiteDataStore.identifier?.uuidString ?? "default",
      controlState: runtime.interactionControlState()
    )
  }
}
