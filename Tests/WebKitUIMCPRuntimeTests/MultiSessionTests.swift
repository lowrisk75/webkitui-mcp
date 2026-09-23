import Foundation
import Testing
import WebKit

@testable import WebKitUIMCPRuntime

@Suite("Several sessions in one process", .serialized)
@MainActor
struct MultiSessionTests {
  private func lockURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("webkitui-multi-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("controller.lock")
  }

  @Test("A second session in the holding process reuses its host lease")
  func secondSessionReusesTheLease() throws {
    let url = lockURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = WKWebsiteDataStore.nonPersistent()
    let registry = try WebKitSessionRegistry(
      maximumSessions: 2, enforceHostExclusiveSession: true, hostControllerLockURL: url,
      runtimeFactory: { _ in try WebKitRuntime(protectedWebsiteDataStore: store) })
    let first = try registry.open()
    let second = try registry.open()
    #expect(first != second)
    #expect(registry.count == 2)
    // Another process is still refused.
    let other = try WebKitSessionRegistry(
      enforceHostExclusiveSession: true, hostControllerLockURL: url)
    #expect(throws: WebKitSessionRegistryError.self) { _ = try other.open() }
    // The lease outlives the first close and goes with the last.
    try registry.close(first)
    #expect(throws: WebKitSessionRegistryError.self) { _ = try other.open() }
    try registry.close(second)
    let reopened = try other.open()
    try other.close(reopened)
  }

  @Test("Two sessions on one profile share one egress proxy")
  func sessionsOnOneStoreShareTheProxy() throws {
    let store = WKWebsiteDataStore.nonPersistent()
    let first = try WebKitRuntime(protectedWebsiteDataStore: store)
    let second = try WebKitRuntime(protectedWebsiteDataStore: store)
    #expect(first.egressProxyIdentity != nil)
    #expect(first.egressProxyIdentity == second.egressProxyIdentity)
    let other = try WebKitRuntime(protectedWebsiteDataStore: .nonPersistent())
    #expect(other.egressProxyIdentity != first.egressProxyIdentity)
  }

  @Test("A reconnecting client gets a free session, then a new one, then waits")
  func reuseRespectsOwnership() throws {
    let registry = try WebKitSessionRegistry(
      maximumSessions: 2,
      runtimeFactory: { _ in try WebKitRuntime(protectedWebsiteDataStore: .nonPersistent()) })
    let alice = UUID()
    let bob = UUID()
    let first = try registry.openOrReuse()
    #expect(!first.reused)
    _ = try registry.claimSessionOwnership(for: first.handle, owner: alice)
    // Owned elsewhere and there is room: a new session, not Alice's.
    let second = try registry.openOrReuse()
    #expect(!second.reused)
    #expect(second.handle != first.handle)
    _ = try registry.claimSessionOwnership(for: second.handle, owner: bob)
    // Full: handed an owned session, which the caller cannot claim.
    let third = try registry.openOrReuse()
    #expect(third.reused)
    #expect(try registry.claimSessionOwnership(for: third.handle, owner: UUID()) == false)
    // Released by its owner: handed back first.
    registry.releaseSessionOwnerships(owner: bob)
    #expect(try registry.openOrReuse().handle == second.handle)
  }
}
