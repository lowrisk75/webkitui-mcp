import CryptoKit
import Foundation
import Security
import WebKitUIMCPCore

public struct WebKitTransactionLedgerFactory: Sendable {
  private let makeLedger: @Sendable (String) throws -> TransactionalWriteLedger

  public init(
    makeLedger: @escaping @Sendable (String) throws -> TransactionalWriteLedger
  ) {
    self.makeLedger = makeLedger
  }

  public func make(scope: String) throws -> TransactionalWriteLedger {
    try makeLedger(scope)
  }

  public static let inMemory = WebKitTransactionLedgerFactory { _ in
    TransactionalWriteLedger()
  }

  public static func shared(
    makeLedger: @escaping @Sendable (String) throws -> TransactionalWriteLedger
  ) -> WebKitTransactionLedgerFactory {
    let pool = SharedTransactionLedgerPool(makeLedger: makeLedger)
    return WebKitTransactionLedgerFactory { scope in
      try pool.ledger(scope: scope)
    }
  }

  public static func durable() throws -> WebKitTransactionLedgerFactory {
    let key = try TransactionLedgerKeychain.loadOrCreate()
    let root = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ).appendingPathComponent("WebkitUIMCP/Receipts", isDirectory: true)
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    return .shared { scope in
      let digest = SHA256.hash(data: Data(scope.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
      let store = try FileTransactionLedgerStore(
        url: root.appendingPathComponent("\(digest).ledger.json"),
        authenticationKey: key,
        anchor: KeychainTransactionLedgerAnchor(account: digest)
      )
      return try TransactionalWriteLedger(persistence: store)
    }
  }
}

private final class SharedTransactionLedgerPool: @unchecked Sendable {
  private let lock = NSLock()
  private let makeLedger: @Sendable (String) throws -> TransactionalWriteLedger
  private var ledgers: [String: TransactionalWriteLedger] = [:]

  init(makeLedger: @escaping @Sendable (String) throws -> TransactionalWriteLedger) {
    self.makeLedger = makeLedger
  }

  func ledger(scope: String) throws -> TransactionalWriteLedger {
    try lock.withLock {
      if let existing = ledgers[scope] { return existing }
      let created = try makeLedger(scope)
      ledgers[scope] = created
      return created
    }
  }
}

private final class KeychainTransactionLedgerAnchor: TransactionLedgerAnchoring,
  @unchecked Sendable
{
  private static let service = "com.lorislab.webkitui-mcp.transaction-ledger-anchor-v2"
  private let account: String

  init(account: String) {
    self.account = account
  }

  func loadAnchorState() throws -> TransactionLedgerAnchorState? {
    var result: CFTypeRef?
    let status = SecItemCopyMatching(
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Self.service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ] as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw TransactionLedgerKeyError.keychain(status)
    }
    do {
      return try JSONDecoder().decode(TransactionLedgerAnchorState.self, from: data)
    } catch {
      throw TransactionLedgerKeyError.invalidAnchor
    }
  }

  func saveAnchorState(_ state: TransactionLedgerAnchorState) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(state)
    let query =
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Self.service,
        kSecAttrAccount as String: account,
      ] as CFDictionary
    let updateStatus = SecItemUpdate(
      query,
      [kSecValueData as String: data] as CFDictionary
    )
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else {
      throw TransactionLedgerKeyError.keychain(updateStatus)
    }
    let addStatus = SecItemAdd(
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Self.service,
        kSecAttrAccount as String: account,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        kSecValueData as String: data,
      ] as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw TransactionLedgerKeyError.keychain(addStatus)
    }
  }
}

private enum TransactionLedgerKeychain {
  private static let service = "com.lorislab.webkitui-mcp.transaction-ledger"
  private static let account = "hmac-v1"

  static func loadOrCreate() throws -> Data {
    if let existing = try load() { return existing }
    var bytes = Data(count: 32)
    let status = bytes.withUnsafeMutableBytes { buffer in
      SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
    }
    guard status == errSecSuccess else {
      throw TransactionLedgerKeyError.secureRandom(status)
    }
    let addStatus = SecItemAdd(
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        kSecValueData as String: bytes,
      ] as CFDictionary, nil)
    if addStatus == errSecDuplicateItem, let existing = try load() { return existing }
    guard addStatus == errSecSuccess else {
      throw TransactionLedgerKeyError.keychain(addStatus)
    }
    return bytes
  }

  private static func load() throws -> Data? {
    var result: CFTypeRef?
    let status = SecItemCopyMatching(
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ] as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data, data.count >= 32 else {
      throw TransactionLedgerKeyError.keychain(status)
    }
    return data
  }
}

private enum TransactionLedgerKeyError: Error {
  case secureRandom(OSStatus)
  case keychain(OSStatus)
  case invalidAnchor
}
