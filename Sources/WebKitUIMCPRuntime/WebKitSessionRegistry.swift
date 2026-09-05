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

public struct WebKitControllerHolder: Codable, Equatable, Sendable {
  public let clientName: String
  public let clientVersion: String?
  public let processID: Int32
  public let acquiredAt: Date
  public let lastActivityAt: Date
  public let executionPolicy: String
  /// True when the host wrote this record for itself because no client owns a session.
  /// A client reading only the pid cannot tell that apart from a peer at work, and the
  /// two call for opposite reactions: wait, or take the host.
  public let isHostPlaceholder: Bool

  public init(
    clientName: String,
    clientVersion: String? = nil,
    processID: Int32 = getpid(),
    acquiredAt: Date = Date(),
    lastActivityAt: Date = Date(),
    executionPolicy: String = "auto",
    isHostPlaceholder: Bool = false
  ) {
    self.clientName = String(clientName.prefix(128))
    self.clientVersion = clientVersion.map { String($0.prefix(64)) }
    self.processID = processID
    self.acquiredAt = acquiredAt
    self.lastActivityAt = lastActivityAt
    self.executionPolicy = String(executionPolicy.prefix(64))
    self.isHostPlaceholder = isHostPlaceholder
  }

  /// A lock file written by an earlier build has no such field, and failing to decode
  /// it would leave a client unable to read the lease at all. Absent means a peer,
  /// which is the safe reading: wait rather than take.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    clientName = try container.decode(String.self, forKey: .clientName)
    clientVersion = try container.decodeIfPresent(String.self, forKey: .clientVersion)
    processID = try container.decode(Int32.self, forKey: .processID)
    acquiredAt = try container.decode(Date.self, forKey: .acquiredAt)
    lastActivityAt = try container.decode(Date.self, forKey: .lastActivityAt)
    executionPolicy = try container.decode(String.self, forKey: .executionPolicy)
    isHostPlaceholder =
      try container.decodeIfPresent(Bool.self, forKey: .isHostPlaceholder) ?? false
  }
}

extension WebKitControllerHolder {
  /// The lock record is written by whoever last acquired the lease, not by whoever
  /// holds it now. A client that took the lock afterwards without rewriting it leaves
  /// a record naming a process that no longer exists, which misdirects the operator.
  /// Liveness is what tells the two apart.
  public static func isProcessRunning(_ processID: Int32) -> Bool {
    guard processID > 0 else { return false }
    if kill(processID, 0) == 0 { return true }
    return errno == EPERM
  }

  public var processIsRunning: Bool { Self.isProcessRunning(processID) }
}

public enum WebKitSessionRegistryError: Error, Equatable, Sendable {
  case invalidMaximumSessions
  case capacityReached
  case hostControllerBusy(WebKitControllerHolder?)
  case hostControllerLockUnavailable
  case unknownSession
  case networkBoundaryUnavailable
}

private final class HostControllerLease {
  private let descriptor: Int32
  private var holder: WebKitControllerHolder

  init(lockFileURL: URL? = nil, holder: WebKitControllerHolder) throws {
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
      let lockError = errno
      let currentHolder = Self.readHolder(from: opened)
      Darwin.close(opened)
      if lockError == EWOULDBLOCK {
        throw WebKitSessionRegistryError.hostControllerBusy(currentHolder)
      }
      throw WebKitSessionRegistryError.hostControllerLockUnavailable
    }
    descriptor = opened
    self.holder = holder
    writeHolder()
  }

  func recordActivity(at now: Date) {
    holder = WebKitControllerHolder(
      clientName: holder.clientName,
      clientVersion: holder.clientVersion,
      processID: holder.processID,
      acquiredAt: holder.acquiredAt,
      lastActivityAt: now,
      executionPolicy: holder.executionPolicy)
    writeHolder()
  }

  func recordHolder(_ newHolder: WebKitControllerHolder, at now: Date) {
    holder = WebKitControllerHolder(
      clientName: newHolder.clientName,
      clientVersion: newHolder.clientVersion,
      processID: newHolder.processID,
      acquiredAt: newHolder.acquiredAt,
      lastActivityAt: now,
      executionPolicy: newHolder.executionPolicy)
    writeHolder()
  }

  private func writeHolder() {
    guard let data = try? JSONEncoder().encode(holder), data.count <= 4_096 else { return }
    guard ftruncate(descriptor, 0) == 0, lseek(descriptor, 0, SEEK_SET) >= 0 else { return }
    data.withUnsafeBytes { bytes in
      guard let baseAddress = bytes.baseAddress else { return }
      _ = Darwin.write(descriptor, baseAddress, bytes.count)
    }
    _ = fsync(descriptor)
  }

  private static func readHolder(from descriptor: Int32) -> WebKitControllerHolder? {
    guard lseek(descriptor, 0, SEEK_SET) >= 0 else { return nil }
    var bytes = [UInt8](repeating: 0, count: 4_096)
    let count = Darwin.read(descriptor, &bytes, bytes.count)
    guard count > 0 else { return nil }
    return try? JSONDecoder().decode(
      WebKitControllerHolder.self, from: Data(bytes.prefix(Int(count))))
  }

  static func existingHolderIfBusy(lockFileURL: URL?) -> WebKitControllerHolder? {
    let fileManager = FileManager.default
    let url: URL
    if let lockFileURL {
      url = lockFileURL
    } else {
      guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
        return nil
      }
      url = caches.appendingPathComponent(
        "com.lorislab.webkitui-mcp/controller.lock", isDirectory: false)
    }
    let opened = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
    guard opened >= 0 else { return nil }
    defer { Darwin.close(opened) }
    if flock(opened, LOCK_EX | LOCK_NB) == 0 {
      flock(opened, LOCK_UN)
      return nil
    }
    guard errno == EWOULDBLOCK else { return nil }
    return readHolder(from: opened)
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
  private struct SessionOwner {
    let authorityID: UUID
    var holder: WebKitControllerHolder
  }

  private var sessionOwners: [WebKitSessionHandle: SessionOwner] = [:]
  private var activeClientCalls: [UUID: Int] = [:]
  private var hostControllerLease: HostControllerLease?
  private let unownedLeaseGrace: Duration
  private var unownedLeaseYield: Task<Void, Never>?

  public init(
    maximumSessions: Int = 1,
    enforceHostExclusiveSession: Bool = false,
    hostControllerLockURL: URL? = nil,
    unownedLeaseGrace: Duration = .seconds(120)
  ) throws {
    guard maximumSessions > 0 else { throw WebKitSessionRegistryError.invalidMaximumSessions }
    self.maximumSessions = maximumSessions
    self.enforceHostExclusiveSession = enforceHostExclusiveSession
    self.hostControllerLockURL = hostControllerLockURL
    self.unownedLeaseGrace = unownedLeaseGrace
  }

  /// The browser is deliberately kept across a client reconnect, so releasing ownership
  /// must not close it. But every client reaches WebKit through its own process, and a
  /// lease held for an owner that never comes back locks the whole machine out until an
  /// operator presses Release host lease. So the session waits exactly as long as a
  /// reconnect is plausible, then yields. The profile is persistent: whoever opens next
  /// is still signed in, and only the page position is lost — once nobody is left to
  /// lose it.
  private func scheduleUnownedLeaseYield() {
    unownedLeaseYield?.cancel()
    guard enforceHostExclusiveSession, hostControllerLease != nil, sessionOwners.isEmpty else {
      unownedLeaseYield = nil
      return
    }
    let grace = unownedLeaseGrace
    unownedLeaseYield = Task { @MainActor [weak self] in
      try? await Task.sleep(for: grace)
      guard !Task.isCancelled else { return }
      self?.yieldUnownedHostLease()
    }
  }

  private func yieldUnownedHostLease() {
    guard sessionOwners.isEmpty, hostControllerLease != nil else { return }
    for handle in sessions.keys {
      revokeHandoffResumeCapabilities(for: handle)
      handoffOwners.removeValue(forKey: handle)
    }
    sessions.removeAll()
    hostControllerLease = nil
    unownedLeaseYield = nil
  }

  private func cancelUnownedLeaseYield() {
    unownedLeaseYield?.cancel()
    unownedLeaseYield = nil
  }

  public var count: Int { sessions.count }

  /// Every open session, so an operator can close them all and free the host lease.
  public func openSessionHandles() -> [WebKitSessionHandle] { Array(sessions.keys) }

  public var existingHandle: WebKitSessionHandle? {
    sessions.keys.first
  }

  public func externalHostControllerHolder() -> WebKitControllerHolder? {
    guard enforceHostExclusiveSession else { return nil }
    return HostControllerLease.existingHolderIfBusy(lockFileURL: hostControllerLockURL)
  }

  public func open(
    profileIdentifier: UUID? = nil,
    holder: WebKitControllerHolder? = nil
  ) throws -> WebKitSessionHandle {
    guard sessions.count < maximumSessions else {
      throw WebKitSessionRegistryError.capacityReached
    }
    let lease =
      try enforceHostExclusiveSession
      ? HostControllerLease(
        lockFileURL: hostControllerLockURL,
        holder: holder ?? WebKitControllerHolder(clientName: ProcessInfo.processInfo.processName))
      : nil
    let handle = WebKitSessionHandle(rawValue: UUID())
    do {
      let dataStore = profileIdentifier.map(WKWebsiteDataStore.init(forIdentifier:)) ?? .default()
      sessions[handle] = try WebKitRuntime(protectedWebsiteDataStore: dataStore)
      hostControllerLease = lease
      // A session opened but not yet owned must not be swept by a yield armed for the
      // previous client.
      cancelUnownedLeaseYield()
    } catch {
      throw WebKitSessionRegistryError.networkBoundaryUnavailable
    }
    return handle
  }

  public func open(
    profileIdentifier: UUID? = nil,
    holder: WebKitControllerHolder? = nil,
    waitTimeoutMilliseconds: Int
  ) async throws -> WebKitSessionHandle {
    let timeout = max(0, waitTimeoutMilliseconds)
    let deadline = Date().addingTimeInterval(Double(timeout) / 1_000)
    while true {
      do {
        return try open(profileIdentifier: profileIdentifier, holder: holder)
      } catch let error as WebKitSessionRegistryError {
        guard case .hostControllerBusy = error else { throw error }
        guard timeout > 0, Date() < deadline else { throw error }
        try await Task.sleep(for: .milliseconds(100))
      }
    }
  }

  /// Reuses the host-owned browser when a durable broker reconnects. The
  /// session handle remains process-private and no observation or action
  /// authority is carried by this operation.
  public func openOrReuse(
    profileIdentifier: UUID? = nil,
    holder: WebKitControllerHolder? = nil
  ) throws -> (handle: WebKitSessionHandle, reused: Bool) {
    if let existingHandle {
      let currentIdentifier = try runtime(for: existingHandle).webView.configuration
        .websiteDataStore.identifier
      guard currentIdentifier == profileIdentifier else {
        throw WebKitSessionRegistryError.capacityReached
      }
      return (existingHandle, true)
    }
    return (try open(profileIdentifier: profileIdentifier, holder: holder), false)
  }

  public func openOrReuse(
    profileIdentifier: UUID? = nil,
    holder: WebKitControllerHolder? = nil,
    waitTimeoutMilliseconds: Int
  ) async throws -> (handle: WebKitSessionHandle, reused: Bool) {
    if let existingHandle {
      let currentIdentifier = try runtime(for: existingHandle).webView.configuration
        .websiteDataStore.identifier
      guard currentIdentifier == profileIdentifier else {
        throw WebKitSessionRegistryError.capacityReached
      }
      return (existingHandle, true)
    }
    return (
      try await open(
        profileIdentifier: profileIdentifier,
        holder: holder,
        waitTimeoutMilliseconds: waitTimeoutMilliseconds),
      false
    )
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
      cancelUnownedLeaseYield()
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
    owner: UUID,
    holder: WebKitControllerHolder? = nil,
    now: Date = Date()
  ) throws -> Bool {
    _ = try runtime(for: handle)
    if var existing = sessionOwners[handle] {
      guard existing.authorityID == owner else { return false }
      existing.holder = WebKitControllerHolder(
        clientName: existing.holder.clientName,
        clientVersion: existing.holder.clientVersion,
        processID: existing.holder.processID,
        acquiredAt: existing.holder.acquiredAt,
        lastActivityAt: now,
        executionPolicy: existing.holder.executionPolicy)
      sessionOwners[handle] = existing
      hostControllerLease?.recordActivity(at: now)
      cancelUnownedLeaseYield()
      return true
    }
    sessionOwners[handle] = SessionOwner(
      authorityID: owner,
      holder: holder
        ?? WebKitControllerHolder(
          clientName: ProcessInfo.processInfo.processName, lastActivityAt: now))
    if let newHolder = sessionOwners[handle]?.holder {
      hostControllerLease?.recordHolder(newHolder, at: now)
    }
    cancelUnownedLeaseYield()
    return true
  }

  public func sessionOwnershipState(
    for handle: WebKitSessionHandle,
    owner: UUID
  ) throws -> String {
    _ = try runtime(for: handle)
    guard let existing = sessionOwners[handle] else { return "inactive" }
    return existing.authorityID == owner ? "owned_by_this_client" : "owned_elsewhere"
  }

  public func sessionOwner(for handle: WebKitSessionHandle) throws -> WebKitControllerHolder? {
    _ = try runtime(for: handle)
    return sessionOwners[handle]?.holder
  }

  public func releaseSessionOwnerships(owner: UUID) {
    let previousCount = sessionOwners.count
    sessionOwners = sessionOwners.filter { $0.value.authorityID != owner }
    if previousCount != sessionOwners.count, sessionOwners.isEmpty {
      hostControllerLease?.recordHolder(
        WebKitControllerHolder(
          clientName: "WebKitUI MCP host", executionPolicy: "unowned",
          isHostPlaceholder: true),
        at: Date())
      scheduleUnownedLeaseYield()
    }
  }

  public func beginClientCall(owner: UUID) {
    activeClientCalls[owner, default: 0] += 1
    let now = Date()
    let ownedHandles = sessionOwners.compactMap { handle, sessionOwner in
      sessionOwner.authorityID == owner ? handle : nil
    }
    for handle in ownedHandles {
      guard var sessionOwner = sessionOwners[handle] else { continue }
      sessionOwner.holder = WebKitControllerHolder(
        clientName: sessionOwner.holder.clientName,
        clientVersion: sessionOwner.holder.clientVersion,
        processID: sessionOwner.holder.processID,
        acquiredAt: sessionOwner.holder.acquiredAt,
        lastActivityAt: now,
        executionPolicy: sessionOwner.holder.executionPolicy)
      sessionOwners[handle] = sessionOwner
      hostControllerLease?.recordHolder(sessionOwner.holder, at: now)
    }
  }

  public func endClientCall(owner: UUID) {
    let remaining = max(0, activeClientCalls[owner, default: 0] - 1)
    if remaining == 0 {
      activeClientCalls.removeValue(forKey: owner)
    } else {
      activeClientCalls[owner] = remaining
    }
  }

  public func transferSessionOwnership(
    for handle: WebKitSessionHandle,
    to owner: UUID,
    holder: WebKitControllerHolder,
    now: Date = Date()
  ) throws -> Bool {
    _ = try runtime(for: handle)
    if let existing = sessionOwners[handle], existing.authorityID != owner,
      activeClientCalls[existing.authorityID, default: 0] > 0
    {
      return false
    }
    sessionOwners[handle] = SessionOwner(
      authorityID: owner,
      holder: WebKitControllerHolder(
        clientName: holder.clientName,
        clientVersion: holder.clientVersion,
        processID: holder.processID,
        acquiredAt: now,
        lastActivityAt: now,
        executionPolicy: holder.executionPolicy))
    if let newHolder = sessionOwners[handle]?.holder {
      hostControllerLease?.recordHolder(newHolder, at: now)
    }
    return true
  }

  @discardableResult
  public func releaseSessionOwnership(
    for handle: WebKitSessionHandle,
    owner: UUID? = nil
  ) -> Bool {
    guard let existing = sessionOwners[handle] else { return false }
    if let owner, existing.authorityID != owner { return false }
    sessionOwners.removeValue(forKey: handle)
    if sessionOwners.isEmpty {
      hostControllerLease?.recordHolder(
        WebKitControllerHolder(
          clientName: "WebKitUI MCP host", executionPolicy: "unowned",
          isHostPlaceholder: true),
        at: Date())
      scheduleUnownedLeaseYield()
    }
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
