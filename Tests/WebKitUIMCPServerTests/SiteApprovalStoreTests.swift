import Foundation
import Testing

@testable import WebKitUIMCPServer

@MainActor
private final class ApprovalStorageFixture {
  var data: Data?
}

@Suite("Remembered site permissions")
@MainActor
struct SiteApprovalStoreTests {
  @Test("Session permission cannot authorize another client, session, origin or profile")
  func sessionIsolation() throws {
    let store = SiteApprovalStore()
    let client = UUID()
    let session = UUID()
    let context = try #require(
      SiteApprovalContext(
        url: URL(string: "https://fixture.invalid/path")!, profile: "default", persistent: true))
    try store.grant(.sessionInteractions, context: context, client: client, session: session)
    #expect(
      store.authorize(context, client: client, session: session, interaction: true)
        == "remembered_session")
    #expect(store.authorize(context, client: UUID(), session: session, interaction: true) == nil)
    #expect(store.authorize(context, client: client, session: UUID(), interaction: true) == nil)
    for url in [
      "http://fixture.invalid/", "https://fixture.invalid:444/", "https://other.invalid/",
    ] {
      let foreign = try #require(
        SiteApprovalContext(url: URL(string: url)!, profile: "default", persistent: true))
      #expect(store.authorize(foreign, client: client, session: session, interaction: true) == nil)
    }
    let otherProfile = try #require(
      SiteApprovalContext(
        url: URL(string: "https://fixture.invalid")!, profile: "other", persistent: true))
    #expect(
      store.authorize(otherProfile, client: client, session: session, interaction: true) == nil)
    store.revoke(client: client)
    #expect(store.authorize(context, client: client, session: session, interaction: true) == nil)
  }

  @Test(
    "Navigation permission is not interaction permission; persistent grants survive reload and revoke"
  )
  func persistenceAndRevocation() throws {
    let storage = ApprovalStorageFixture()
    let store = SiteApprovalStore(load: { storage.data }, save: { storage.data = $0 })
    let context = try #require(
      SiteApprovalContext(
        url: URL(string: "https://fixture.invalid/a")!, profile: "default", persistent: true))
    let client = UUID()
    let session = UUID()
    try store.grant(.persistentNavigation, context: context, client: client, session: session)
    let reopened = SiteApprovalStore(load: { storage.data }, save: { storage.data = $0 })
    #expect(
      reopened.authorize(context, client: UUID(), session: UUID(), interaction: false)
        == "remembered_persistent")
    #expect(reopened.authorize(context, client: client, session: session, interaction: true) == nil)
    try store.grant(.persistentInteractions, context: context, client: client, session: session)
    #expect(reopened.authorize(context, client: client, session: session, interaction: true) != nil)
    try store.revokeAll()
    #expect(
      reopened.authorize(context, client: client, session: session, interaction: false) == nil)
  }

  /// The archive sits in a preferences domain that `defaults write` can edit. A grant
  /// written there by anything but this product must not stand.
  @Test("A persistent grant written without the integrity key is ignored")
  func forgedArchiveIsIgnored() throws {
    let context = try #require(
      SiteApprovalContext(
        url: URL(string: "https://fixture.invalid")!, profile: "default", persistent: true))
    let forged = Data(
      """
      {"version":2,"mac":"00","entries":[{"origin":"https://fixture.invalid","profile":"default","interactions":true}]}
      """.utf8)
    let store = SiteApprovalStore(load: { forged }, save: { _ in })
    #expect(store.authorize(context, client: UUID(), session: UUID(), interaction: false) == nil)
    let legacy = Data(
      """
      {"version":1,"entries":[{"origin":"https://fixture.invalid","profile":"default","interactions":true}]}
      """.utf8)
    let legacyStore = SiteApprovalStore(load: { legacy }, save: { _ in })
    #expect(
      legacyStore.authorize(context, client: UUID(), session: UUID(), interaction: false) == nil)
    // A genuine archive edited afterwards — one more origin appended — fails the same way.
    let storage = ApprovalStorageFixture()
    let genuine = SiteApprovalStore(load: { storage.data }, save: { storage.data = $0 })
    try genuine.grant(.persistentNavigation, context: context, client: UUID(), session: UUID())
    let written = try #require(storage.data)
    var edited = try #require(JSONSerialization.jsonObject(with: written) as? [String: Any])
    var entries = try #require(edited["entries"] as? [[String: Any]])
    entries.append(["origin": "https://other.invalid", "profile": "default", "interactions": true])
    edited["entries"] = entries
    storage.data = try JSONSerialization.data(withJSONObject: edited)
    let other = try #require(
      SiteApprovalContext(
        url: URL(string: "https://other.invalid")!, profile: "default", persistent: true))
    #expect(genuine.authorize(other, client: UUID(), session: UUID(), interaction: false) == nil)
    #expect(genuine.authorize(context, client: UUID(), session: UUID(), interaction: false) == nil)
    // A store that cannot obtain its key refuses to write a grant at all.
    let keyless = SiteApprovalStore(
      load: { storage.data }, save: { storage.data = $0 },
      integrityKey: { throw CocoaError(.fileReadNoPermission) })
    #expect(throws: (any Error).self) {
      try keyless.grant(.persistentNavigation, context: context, client: UUID(), session: UUID())
    }
  }

  @Test("Invalid storage, failed persistence and private profiles fail closed")
  func invalidStorage() throws {
    let context = try #require(
      SiteApprovalContext(
        url: URL(string: "https://fixture.invalid")!, profile: "default", persistent: true))
    let store = SiteApprovalStore(
      load: { Data("untrusted-invalid-json".utf8) },
      save: { _ in throw CocoaError(.fileWriteUnknown) })
    #expect(store.authorize(context, client: UUID(), session: UUID(), interaction: false) == nil)
    #expect(throws: (any Error).self) {
      try store.grant(.persistentInteractions, context: context, client: UUID(), session: UUID())
    }
    let privateContext = try #require(
      SiteApprovalContext(
        url: URL(string: "https://fixture.invalid")!, profile: "private", persistent: false))
    #expect(throws: (any Error).self) {
      try store.grant(
        .persistentNavigation, context: privateContext, client: UUID(), session: UUID())
    }
    #expect(
      SiteApprovalContext(
        url: URL(string: "https://user:password@fixture.invalid")!, profile: "default",
        persistent: true) == nil)
    #expect(
      SiteApprovalContext(
        url: URL(string: "file:///tmp/fixture")!, profile: "default", persistent: true) == nil)
  }
}
