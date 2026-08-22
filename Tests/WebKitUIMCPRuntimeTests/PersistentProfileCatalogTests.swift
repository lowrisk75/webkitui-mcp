import Darwin
import Foundation
import Testing
import WebKit

@testable import WebKitUIMCPRuntime

@Suite("Persistent WebKit profiles", .serialized)
@MainActor
struct PersistentProfileCatalogTests {
  @Test("Catalog updates are cross-instance safe and stored owner-only")
  func secureCatalog() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = try PersistentProfileCatalog(directoryURL: directory)
    let second = try PersistentProfileCatalog(directoryURL: directory)
    let firstID = try first.create()
    let secondID = try second.create()

    #expect(try first.contains(firstID))
    #expect(try first.contains(secondID))
    var status = stat()
    let catalogPath = directory.appendingPathComponent("persistent-profiles.json").path
    #expect(lstat(catalogPath, &status) == 0)
    #expect(status.st_mode & (S_IRWXG | S_IRWXO) == 0)
    #expect(status.st_uid == geteuid())

    try second.remove(firstID)
    #expect(try !first.contains(firstID))
    #expect(try first.contains(secondID))
  }

  @Test("Catalog rejects symlinked storage and group-readable metadata")
  func filesystemBoundary() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let target = root.appendingPathComponent("target", isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    let linked = root.appendingPathComponent("linked", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: target)
    #expect(throws: PersistentProfileCatalogError.insecurePermissions) {
      try PersistentProfileCatalog(directoryURL: linked)
    }

    let secure = root.appendingPathComponent("secure", isDirectory: true)
    let catalog = try PersistentProfileCatalog(directoryURL: secure)
    _ = try catalog.create()
    let catalogPath = secure.appendingPathComponent("persistent-profiles.json").path
    #expect(chmod(catalogPath, S_IRUSR | S_IWUSR | S_IRGRP) == 0)
    #expect(throws: PersistentProfileCatalogError.insecurePermissions) {
      try catalog.contains(UUID())
    }
  }

  @Test("A persistent data store survives sessions and remains isolated by profile ID")
  func websiteDataIsolation() async throws {
    let firstID = UUID()
    let secondID = UUID()
    defer {
      Task { @MainActor in
        try? await WKWebsiteDataStore.remove(forIdentifier: firstID)
        try? await WKWebsiteDataStore.remove(forIdentifier: secondID)
      }
    }
    let cookie = try #require(
      HTTPCookie(properties: [
        .domain: "fixture.invalid",
        .path: "/",
        .name: "session-proof",
        .value: "synthetic-only",
        .secure: "TRUE",
        .expires: Date().addingTimeInterval(300),
      ]))

    do {
      let firstRegistry = try WebKitSessionRegistry()
      let firstHandle = try firstRegistry.open(persistentProfileID: firstID)
      let firstRuntime = try firstRegistry.runtime(for: firstHandle)
      await firstRuntime.webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
      #expect(try firstRegistry.status(firstHandle).persistentProfileID == firstID)
      try firstRegistry.close(firstHandle)
    }

    do {
      let reopenedRegistry = try WebKitSessionRegistry(maximumSessions: 2)
      let reopenedHandle = try reopenedRegistry.open(persistentProfileID: firstID)
      let isolatedHandle = try reopenedRegistry.open(persistentProfileID: secondID)
      let reopenedCookies = await (try reopenedRegistry.runtime(for: reopenedHandle)).webView
        .configuration.websiteDataStore.httpCookieStore.allCookies()
      let isolatedCookies = await (try reopenedRegistry.runtime(for: isolatedHandle)).webView
        .configuration.websiteDataStore.httpCookieStore.allCookies()
      #expect(reopenedCookies.contains { $0.name == "session-proof" })
      #expect(!isolatedCookies.contains { $0.name == "session-proof" })
      try reopenedRegistry.close(reopenedHandle)
      try reopenedRegistry.close(isolatedHandle)
    }
    try await removeDataStoreWhenReleased(firstID)
    try await removeDataStoreWhenReleased(secondID)
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "webkitui-profile-catalog-tests-\(UUID().uuidString)", isDirectory: true)
  }

  private func removeDataStoreWhenReleased(_ identifier: UUID) async throws {
    var lastError: Error?
    for _ in 0..<20 {
      do {
        try await WKWebsiteDataStore.remove(forIdentifier: identifier)
        return
      } catch {
        lastError = error
        try await Task.sleep(for: .milliseconds(50))
      }
    }
    if let lastError { throw lastError }
  }
}
