import CryptoKit
import Foundation
import Security
import WebKitUIMCPConfirmPolicy

struct SiteApprovalContext: Equatable {
  let origin: String
  let profile: String
  let persistent: Bool
  var key: String { profile + "|" + origin }

  init?(url: URL, profile: String, persistent: Bool) {
    guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = url.host?.lowercased(), !host.isEmpty,
      url.user == nil, url.password == nil,
      !profile.isEmpty, profile.count <= 128,
      profile.unicodeScalars.allSatisfy({
        CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).contains($0)
      })
    else { return nil }
    var origin = URLComponents()
    origin.scheme = scheme
    origin.host = host
    let defaultPort = scheme == "https" ? 443 : 80
    origin.port = url.port == defaultPort ? nil : url.port
    guard let text = origin.string else { return nil }
    self.origin = text
    self.profile = profile
    self.persistent = persistent
  }
}

/// Persistent grants are explicitly profile-wide, not authenticated by a client name.
/// All production servers share this store so native revocation reaches every client.
///
/// The archive lives in a preferences domain any same-user process can write with
/// `defaults write`. A grant is authority to navigate, click and type on a site without
/// a panel, so the archive alone cannot be the proof that a person chose it. Every
/// archive carries an HMAC over its entries under a key that only this product's own
/// signed binaries can read back silently (a Keychain item with the default
/// creator-only access list). A forged or edited archive fails that check and is
/// treated as empty: no grant, and a diagnostic naming why.
@MainActor
final class SiteApprovalStore {
  static let shared: SiteApprovalStore = {
    let defaults = UserDefaults(suiteName: "com.lorislab.webkitui-mcp.permissions")
    return SiteApprovalStore(
      load: { defaults?.data(forKey: "siteApprovalsV2") },
      save: { data in
        guard let defaults else { throw StoreError.persistenceUnavailable }
        if let data {
          defaults.set(data, forKey: "siteApprovalsV2")
        } else {
          defaults.removeObject(forKey: "siteApprovalsV2")
        }
        // The unauthenticated archive from earlier builds is never read again.
        defaults.removeObject(forKey: "siteApprovalsV1")
      },
      integrityKey: SiteApprovalIntegrityKey.keychainBacked)
  }()

  private struct Entry: Codable {
    let origin: String
    let profile: String
    let interactions: Bool
    var key: String { profile + "|" + origin }
  }
  private struct Archive: Codable {
    let version: Int
    var entries: [Entry]
    /// Hex HMAC-SHA256 over the canonical JSON of `entries` under the integrity key.
    var mac: String
  }
  private struct SessionKey: Hashable {
    let client: UUID
    let session: UUID
    let site: String
  }
  private enum StoreError: Error { case persistenceUnavailable, invalidScope, capacity }
  private let load: () -> Data?
  private let save: (Data?) throws -> Void
  private let integrityKey: () throws -> Data
  private var sessions: [SessionKey: Bool] = [:]
  private var reportedIntegrityFailure = false

  // Tests default to an ephemeral, non-writing store with a process-local key. No user
  // preferences and no Keychain are read.
  init(
    load: @escaping () -> Data? = { nil },
    save: @escaping (Data?) throws -> Void = { _ in throw StoreError.persistenceUnavailable },
    integrityKey: @escaping () throws -> Data = SiteApprovalIntegrityKey.processLocal
  ) {
    self.load = load
    self.save = save
    self.integrityKey = integrityKey
  }

  func authorize(_ context: SiteApprovalContext, client: UUID, session: UUID, interaction: Bool)
    -> String?
  {
    if let interactions = sessions[SessionKey(client: client, session: session, site: context.key)],
      !interaction || interactions
    {
      return "remembered_session"
    }
    guard context.persistent, let entry = entries().first(where: { $0.key == context.key }),
      !interaction || entry.interactions
    else { return nil }
    return "remembered_persistent"
  }

  func grant(
    _ choice: RememberedApprovalChoice, context: SiteApprovalContext, client: UUID, session: UUID
  ) throws {
    if choice.persistent {
      guard context.persistent else { throw StoreError.invalidScope }
      var values = entries().filter { $0.key != context.key }
      guard values.count < 256 else { throw StoreError.capacity }
      values.append(
        Entry(origin: context.origin, profile: context.profile, interactions: choice.interactions))
      let mac = try Self.mac(of: values, key: try integrityKey())
      try save(JSONEncoder().encode(Archive(version: 2, entries: values, mac: mac)))
    } else {
      guard sessions.count < 1_024 else { throw StoreError.capacity }
      sessions[SessionKey(client: client, session: session, site: context.key)] =
        choice.interactions
    }
  }

  func revoke(client: UUID, session: UUID? = nil) {
    sessions = sessions.filter {
      $0.key.client != client || (session != nil && $0.key.session != session)
    }
  }

  func revokeAll() throws {
    sessions.removeAll()
    try save(nil)
  }

  private static func mac(of entries: [Entry], key: Data) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let canonical = try encoder.encode(entries)
    let digest = HMAC<SHA256>.authenticationCode(for: canonical, using: SymmetricKey(data: key))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
    let left = Array(lhs.utf8)
    let right = Array(rhs.utf8)
    guard left.count == right.count else { return false }
    var difference: UInt8 = 0
    for index in left.indices { difference |= left[index] ^ right[index] }
    return difference == 0
  }

  private func entries() -> [Entry] {
    guard let data = load(), data.count <= 65_536,
      let archive = try? JSONDecoder().decode(Archive.self, from: data),
      archive.version == 2, archive.entries.count <= 256,
      Set(archive.entries.map(\.key)).count == archive.entries.count,
      archive.entries.allSatisfy({ entry in
        guard let url = URL(string: entry.origin),
          let scope = SiteApprovalContext(url: url, profile: entry.profile, persistent: true)
        else { return false }
        return scope.origin == entry.origin
      })
    else { return [] }
    guard let key = try? integrityKey(),
      let expected = try? Self.mac(of: archive.entries, key: key),
      Self.constantTimeEqual(expected, archive.mac)
    else {
      // An archive that does not verify under this product's key was written by
      // something else — or the key is unreadable. Either way no grant stands, and the
      // person is told once per process rather than silently left with a panel they
      // expected to be remembered.
      if !reportedIntegrityFailure {
        reportedIntegrityFailure = true
        FileHandle.standardError.write(
          Data(
            "webkitui-mcp: remembered site permissions ignored: archive integrity check failed\n"
              .utf8))
      }
      return []
    }
    return archive.entries
  }
}

/// Where the archive's HMAC key comes from.
enum SiteApprovalIntegrityKey {
  private static let service = "com.lorislab.webkitui-mcp.permissions"
  private static let account = "site-approval-integrity"
  private static let processKey: Data = {
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return Data(bytes)
  }()

  enum KeyError: Error {
    case keychainUnavailable(OSStatus)
    case randomUnavailable
  }

  /// One random key for the life of this process. Tests and ephemeral stores use it;
  /// nothing written under it is readable by a later process, which is the point.
  static func processLocal() throws -> Data { processKey }

  /// A 32-byte random key in the login Keychain, created on first use. The item keeps
  /// the default access list, so only the application that created it reads it without
  /// a system prompt; a `defaults write` from a shell has no silent route to it.
  static func keychainBacked() throws -> Data {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecSuccess, let data = item as? Data, data.count == 32 { return data }
    guard status == errSecItemNotFound else { throw KeyError.keychainUnavailable(status) }
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw KeyError.randomUnavailable
    }
    let fresh = Data(bytes)
    let attributes: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrLabel as String: "WebKitUI MCP remembered site permissions",
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      kSecValueData as String: fresh,
    ]
    let added = SecItemAdd(attributes as CFDictionary, nil)
    if added == errSecDuplicateItem {
      // Another of this product's processes created it first; read theirs.
      var again: CFTypeRef?
      let reread = SecItemCopyMatching(query as CFDictionary, &again)
      guard reread == errSecSuccess, let data = again as? Data, data.count == 32 else {
        throw KeyError.keychainUnavailable(reread)
      }
      return data
    }
    guard added == errSecSuccess else { throw KeyError.keychainUnavailable(added) }
    return fresh
  }
}
