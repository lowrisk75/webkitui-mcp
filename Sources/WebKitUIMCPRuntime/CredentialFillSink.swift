import Foundation

public enum CredentialSinkOriginError: Error, Equatable, Sendable {
  case httpsRequired
  case nonCanonicalHost
  case invalidPort
}

/// Narrow origin language shared conceptually with the SiliconPass MVP.
/// It intentionally excludes IDNs, IP literals and implicit ports.
public struct CredentialSinkOrigin: Codable, Hashable, Sendable {
  public let scheme: String
  public let asciiHost: String
  public let effectivePort: UInt16

  public init(scheme: String, asciiHost: String, effectivePort: Int) throws {
    guard scheme == "https" else { throw CredentialSinkOriginError.httpsRequired }
    guard (1...Int(UInt16.max)).contains(effectivePort) else {
      throw CredentialSinkOriginError.invalidPort
    }
    guard Self.isCanonicalASCIIHost(asciiHost) else {
      throw CredentialSinkOriginError.nonCanonicalHost
    }
    self.scheme = scheme
    self.asciiHost = asciiHost
    self.effectivePort = UInt16(effectivePort)
  }

  init(url: URL) throws {
    guard let scheme = url.scheme, let host = url.host else {
      throw CredentialSinkOriginError.nonCanonicalHost
    }
    try self.init(
      scheme: scheme,
      asciiHost: host,
      effectivePort: url.port ?? (scheme == "https" ? 443 : 80)
    )
  }

  private static func isCanonicalASCIIHost(_ host: String) -> Bool {
    guard !host.isEmpty,
      host == host.lowercased(),
      host.utf8.allSatisfy({ $0 < 0x80 }),
      !host.hasSuffix("."),
      host.count <= 253
    else { return false }

    let labels = host.split(separator: ".", omittingEmptySubsequences: false)
    return labels.count >= 2 && !Self.isIPv4Literal(labels)
      && labels.allSatisfy { label in
        guard !label.isEmpty, label.count <= 63,
          label.first != "-", label.last != "-", !label.hasPrefix("xn--")
        else { return false }
        return label.utf8.allSatisfy {
          (0x61...0x7A).contains($0) || (0x30...0x39).contains($0) || $0 == 0x2D
        }
      }
  }

  private static func isIPv4Literal(_ labels: [Substring]) -> Bool {
    guard labels.count == 4 else { return false }
    return labels.allSatisfy { label in
      guard !label.isEmpty, label.allSatisfy(\.isNumber),
        let value = UInt8(label)
      else { return false }
      return String(value) == label
    }
  }
}

public struct CredentialSinkElementBinding: Codable, Hashable, Sendable {
  public let elementID: String
  public let physicalElementIdentity: String

  public init(elementID: String, physicalElementIdentity: String) {
    self.elementID = elementID
    self.physicalElementIdentity = physicalElementIdentity
  }
}

public struct CredentialSinkFormBinding: Codable, Hashable, Sendable {
  public let origin: CredentialSinkOrigin
  public let documentID: String
  public let observationID: String
  public let observationGeneration: UInt64
  public let usernameTarget: CredentialSinkElementBinding
  public let passwordTarget: CredentialSinkElementBinding

  public init(
    origin: CredentialSinkOrigin,
    documentID: String,
    observationID: String,
    observationGeneration: UInt64,
    usernameTarget: CredentialSinkElementBinding,
    passwordTarget: CredentialSinkElementBinding
  ) {
    self.origin = origin
    self.documentID = documentID
    self.observationID = observationID
    self.observationGeneration = observationGeneration
    self.usernameTarget = usernameTarget
    self.passwordTarget = passwordTarget
  }
}

public struct CredentialSinkRotationBinding: Codable, Hashable, Sendable {
  public let origin: CredentialSinkOrigin
  public let documentID: String
  public let observationID: String
  public let observationGeneration: UInt64
  public let currentPasswordTarget: CredentialSinkElementBinding
  public let newPasswordTarget: CredentialSinkElementBinding
  public let confirmationTarget: CredentialSinkElementBinding

  public init(
    origin: CredentialSinkOrigin,
    documentID: String,
    observationID: String,
    observationGeneration: UInt64,
    currentPasswordTarget: CredentialSinkElementBinding,
    newPasswordTarget: CredentialSinkElementBinding,
    confirmationTarget: CredentialSinkElementBinding
  ) {
    self.origin = origin
    self.documentID = documentID
    self.observationID = observationID
    self.observationGeneration = observationGeneration
    self.currentPasswordTarget = currentPasswordTarget
    self.newPasswordTarget = newPasswordTarget
    self.confirmationTarget = confirmationTarget
  }
}

public enum CredentialSinkStatus: String, Codable, Equatable, Sendable {
  case filled
}

/// Deliberately closed receipt: no message/details field can receive a secret.
public struct CredentialSinkReceipt: Codable, Equatable, Sendable {
  public let status: CredentialSinkStatus

  public init(status: CredentialSinkStatus) {
    self.status = status
  }
}

/// Owned byte buffer for the private native sink boundary. Decoding to a Swift
/// String is still a measured copy required by WebKit; this buffer limits and
/// wipes the bytes under our control.
public final class CredentialSecretBuffer: @unchecked Sendable {
  private let storage: UnsafeMutableRawPointer
  private let lock = NSLock()
  private var wiped = false
  public let count: Int

  public init(copying bytes: [UInt8]) {
    precondition(!bytes.isEmpty)
    count = bytes.count
    storage = .allocate(byteCount: bytes.count, alignment: MemoryLayout<UInt64>.alignment)
    bytes.withUnsafeBytes { source in
      _ = memcpy(storage, source.baseAddress!, bytes.count)
    }
  }

  public init(copying data: Data) {
    precondition(!data.isEmpty)
    count = data.count
    storage = .allocate(byteCount: data.count, alignment: MemoryLayout<UInt64>.alignment)
    data.withUnsafeBytes { source in
      _ = memcpy(storage, source.baseAddress!, data.count)
    }
  }

  deinit {
    wipeUnlocked()
    storage.deallocate()
  }

  func asciiString(maximumBytes: Int) throws -> String {
    try lock.withLock {
      guard !wiped, count <= maximumBytes else {
        throw WebKitRuntimeError.invalidCredentialSecret
      }
      let bytes = UnsafeRawBufferPointer(start: storage, count: count)
      guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else {
        throw WebKitRuntimeError.invalidCredentialSecret
      }
      return String(decoding: bytes, as: UTF8.self)
    }
  }

  public func wipe() {
    lock.withLock { wipeUnlocked() }
  }

  private func wipeUnlocked() {
    guard !wiped else { return }
    memset_s(storage, count, 0, count)
    wiped = true
  }

  public var isWiped: Bool {
    lock.withLock { wiped }
  }
}
