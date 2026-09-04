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

/// Who currently holds the single host controller. Written into the lock file by
/// the holder so a blocked client can say what it is waiting for. It carries
/// identity and timing only, never any browsing state.
public struct HostControllerHolder: Codable, Equatable, Sendable {
  public let processIdentifier: Int32
  public let processName: String
  public let clientName: String?
  public let acquiredAtEpochSeconds: Double
  public let lastActivityEpochSeconds: Double

  public func idleSeconds(now: Date) -> Double {
    max(0, now.timeIntervalSince1970 - lastActivityEpochSeconds)
  }

  public func heldSeconds(now: Date) -> Double {
    max(0, now.timeIntervalSince1970 - acquiredAtEpochSeconds)
  }
}

public enum WebKitSessionRegistryError: Error, Equatable, Sendable {
  case invalidMaximumSessions
  case capacityReached
  case hostControllerBusy(HostControllerHolder?)
  case hostControllerLockUnavailable
  case unknownSession
  case networkBoundaryUnavailable
}

private final class HostControllerLease {
  private let descriptor: Int32

  /// Reads the holder record without taking the lock. `flock` is advisory, so this
  /// never blocks and never disturbs the holder.
  static func currentHolder(lockFileURL: URL?) -> HostControllerHolder? {
    guard let path = try? resolvedPath(lockFileURL: lockFileURL, creatingDirectory: false)
    else { return nil }
    let opened = Darwin.open(path, O_RDONLY | O_NOFOLLOW)
    guard opened >= 0 else { return nil }
    defer { Darwin.close(opened) }
    var bytes = [UInt8](repeating: 0, count: 4_096)
    let read = Darwin.read(opened, &bytes, bytes.count)
    guard read > 0 else { return nil }
    return try? JSONDecoder().decode(
      HostControllerHolder.self, from: Data(bytes[0..<read]))
  }

  private static func resolvedPath(lockFileURL: URL?, creatingDirectory: Bool) throws -> String {
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
    guard creatingDirectory else { return path }
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
    return path
  }

  /// Rewrites the holder record. Called on acquisition and on every recorded call,
  /// so a blocked client can tell a working host from an idle one.
  func record(clientName: String?, acquiredAt: Date, lastActivityAt: Date) {
    let holder = HostControllerHolder(
      processIdentifier: ProcessInfo.processInfo.processIdentifier,
      processName: ProcessInfo.processInfo.processName,
      clientName: clientName,
      acquiredAtEpochSeconds: acquiredAt.timeIntervalSince1970,
      lastActivityEpochSeconds: lastActivityAt.timeIntervalSince1970)
    guard let data = try? JSONEncoder().encode(holder) else { return }
    guard ftruncate(descriptor, 0) == 0, lseek(descriptor, 0, SEEK_SET) == 0 else { return }
    _ = data.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
  }

  init(lockFileURL: URL? = nil) throws {
    let path = try Self.resolvedPath(lockFileURL: lockFileURL, creatingDirectory: true)
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
        throw WebKitSessionRegistryError.hostControllerBusy(
          Self.currentHolder(lockFileURL: lockFileURL))
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
  private var clientName: String?
  private var hostControllerAcquiredAt: Date?
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
    hostControllerLockURL: URL? = nil,
    clientName: String? = nil
  ) throws {
    guard maximumSessions > 0 else { throw WebKitSessionRegistryError.invalidMaximumSessions }
    self.maximumSessions = maximumSessions
    self.enforceHostExclusiveSession = enforceHostExclusiveSession
    self.hostControllerLockURL = hostControllerLockURL
    self.clientName = clientName
  }

  /// Adopts the name a connected client declared at initialize, so a blocked client
  /// reads "claude-code" rather than a bare process name. Identity only.
  public func adoptClientName(_ name: String) {
    guard !name.isEmpty else { return }
    clientName = String(name.prefix(64))
    recordHostActivity()
  }

  /// Who holds the host controller right now, whether this process or another.
  /// Returns nil when the host is free or the record is unreadable.
  public func hostControllerHolder() -> HostControllerHolder? {
    HostControllerLease.currentHolder(lockFileURL: hostControllerLockURL)
  }

  public func holdsHostController() -> Bool { hostControllerLease != nil }

  /// Refreshes this holder's last-activity stamp. A blocked client reads it to tell
  /// a working host from an abandoned one.
  public func recordHostActivity() {
    guard let hostControllerLease, let hostControllerAcquiredAt else { return }
    hostControllerLease.record(
      clientName: clientName, acquiredAt: hostControllerAcquiredAt, lastActivityAt: Date())
  }

  /// Opens a session, waiting up to `waitTimeout` for a busy host controller to be
  /// released instead of failing on the first attempt.
  public func open(
    profileIdentifier: UUID? = nil,
    waitTimeout: Duration,
    pollInterval: Duration = .milliseconds(50)
  ) async throws -> WebKitSessionHandle {
    let deadline = ContinuousClock.now + waitTimeout
    while true {
      do {
        return try open(profileIdentifier: profileIdentifier)
      } catch WebKitSessionRegistryError.hostControllerBusy(let holder) {
        guard ContinuousClock.now < deadline else {
          throw WebKitSessionRegistryError.hostControllerBusy(holder)
        }
        try await Task.sleep(for: pollInterval)
      }
    }
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
      if let lease {
        let acquiredAt = Date()
        hostControllerLease = lease
        hostControllerAcquiredAt = acquiredAt
        lease.record(clientName: clientName, acquiredAt: acquiredAt, lastActivityAt: acquiredAt)
      }
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
    if sessions.isEmpty {
      hostControllerLease = nil
      hostControllerAcquiredAt = nil
    }
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
