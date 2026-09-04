import Foundation
import IOKit
import Security

public struct WebKitUIKeychainLicenseStore: WebKitUILicenseStoring {
  private let service = "com.lorislab.webkitui-mcp.license"
  private let account = "current"

  public init() {}

  public func load() throws -> StoredWebKitUILicense? {
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
    guard status == errSecSuccess, let data = result as? Data else {
      throw WebKitUILicenseError.secureStorage(status: status)
    }
    return try JSONDecoder().decode(StoredWebKitUILicense.self, from: data)
  }

  public func save(_ license: StoredWebKitUILicense) throws {
    let data = try JSONEncoder().encode(license)
    let identity: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let update = SecItemUpdate(
      identity as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if update == errSecSuccess { return }
    guard update == errSecItemNotFound else {
      throw WebKitUILicenseError.secureStorage(status: update)
    }
    var item = identity
    item[kSecValueData as String] = data
    item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw WebKitUILicenseError.secureStorage(status: status)
    }
  }

  public func clear() throws {
    let status = SecItemDelete(
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
      ] as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw WebKitUILicenseError.secureStorage(status: status)
    }
  }
}

public struct WebKitUILicenseHTTPAPI: WebKitUILicenseAPI {
  static let maximumResponseBytes = 64 * 1_024

  private let baseURL: URL
  private let session: URLSession

  public init(
    baseURL: URL = URL(string: "https://license.lorislab.fr")!,
    session: URLSession? = nil
  ) {
    self.baseURL = baseURL
    self.session = session ?? Self.ephemeralSession()
  }

  public func activate(
    licenseKey: String,
    machineID: String,
    appVersion: String
  ) async throws -> WebKitUIActivationReceipt {
    let response = try await post(
      path: "/api/activate",
      body: [
        "licenseKey": licenseKey,
        "machineId": machineID,
        "appVersion": appVersion,
        "product": WebKitUILicenseProduct.id,
      ]
    )
    guard let token = response.body["jwt"] as? String,
      let active = response.body["activeMachines"] as? Int,
      let maximum = response.body["max"] as? Int
    else {
      throw WebKitUILicenseError.invalidServerResponse
    }
    return WebKitUIActivationReceipt(token: token, activeMachines: active, maximumMachines: maximum)
  }

  public func deactivate(licenseKey: String, machineID: String) async throws {
    _ = try await post(
      path: "/api/deactivate",
      body: [
        "licenseKey": licenseKey,
        "machineId": machineID,
        "product": WebKitUILicenseProduct.id,
      ]
    )
  }

  public func refresh(
    licenseKey: String,
    machineID: String,
    appVersion: String
  ) async throws -> WebKitUIActivationReceipt {
    let response = try await post(
      path: "/api/refresh",
      body: [
        "licenseKey": licenseKey,
        "machineId": machineID,
        "appVersion": appVersion,
        "product": WebKitUILicenseProduct.id,
      ]
    )
    guard let token = response.body["jwt"] as? String,
      let active = response.body["activeMachines"] as? Int,
      let maximum = response.body["max"] as? Int
    else {
      throw WebKitUILicenseError.invalidServerResponse
    }
    return WebKitUIActivationReceipt(
      token: token,
      activeMachines: active,
      maximumMachines: maximum
    )
  }

  private func post(path: String, body: [String: String]) async throws
    -> (body: [String: Any], status: Int)
  {
    guard baseURL.scheme?.lowercased() == "https", baseURL.host != nil else {
      throw WebKitUILicenseError.transport("license endpoint must use HTTPS")
    }
    var request = URLRequest(url: baseURL.appending(path: path))
    request.httpMethod = "POST"
    request.timeoutInterval = 20
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    do {
      let (data, rawResponse) = try await session.data(for: request)
      guard let response = rawResponse as? HTTPURLResponse else {
        throw WebKitUILicenseError.invalidServerResponse
      }
      guard Self.sameHTTPSOrigin(response.url, baseURL),
        data.count <= Self.maximumResponseBytes,
        response.mimeType?.lowercased() == "application/json"
      else {
        throw WebKitUILicenseError.invalidServerResponse
      }
      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
      guard (200..<300).contains(response.statusCode) else {
        let code = object["error"] as? String
        switch code {
        case "invalid_license": throw WebKitUILicenseError.invalidKey
        case "machine_limit_reached":
          throw WebKitUILicenseError.machineLimitReached(maximum: object["max"] as? Int)
        case "inactive_subscription": throw WebKitUILicenseError.inactiveSubscription
        case "revoked": throw WebKitUILicenseError.revoked
        default: throw WebKitUILicenseError.server(status: response.statusCode, code: code)
        }
      }
      return (object, response.statusCode)
    } catch let error as WebKitUILicenseError {
      throw error
    } catch {
      throw WebKitUILicenseError.transport(error.localizedDescription)
    }
  }

  private static func ephemeralSession() -> URLSession {
    URLSession(
      configuration: ephemeralConfiguration(),
      delegate: WebKitUILicenseNoRedirectDelegate(),
      delegateQueue: nil)
  }

  static func ephemeralConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 20
    configuration.httpMaximumConnectionsPerHost = 2
    return configuration
  }

  static func sameHTTPSOrigin(_ candidate: URL?, _ expected: URL) -> Bool {
    guard let candidate else { return false }
    return candidate.scheme?.lowercased() == "https"
      && candidate.host?.lowercased() == expected.host?.lowercased()
      && effectivePort(candidate) == effectivePort(expected)
  }

  private static func effectivePort(_ url: URL) -> Int? {
    url.port ?? (url.scheme?.lowercased() == "https" ? 443 : nil)
  }
}

final class WebKitUILicenseNoRedirectDelegate: NSObject, URLSessionTaskDelegate,
  @unchecked Sendable
{
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

public struct WebKitUIRS256TokenVerifier: WebKitUILicenseTokenVerifying, @unchecked Sendable {
  private let publicKey: SecKey?

  public init(pem: String) {
    self.publicKey = Self.makePublicKey(pem: pem)
  }

  static let resourceBundleName = "WebKitUIMCP_WebKitUIMCPLicensing.bundle"
  static let publicKeyResourceName = "lorislabs-license-public.pem"

  /// Locations a packaged licence bundle can sit in, relative to the running
  /// executable. Deliberately does not use `Bundle.module`: SPM's generated accessor
  /// calls `fatalError` when the bundle is missing, and an MCP server that dies on a
  /// licence resource is undiagnosable from the client.
  public static func defaultSearchRoots() -> [URL] {
    var roots: [URL] = []
    if let resources = Bundle.main.resourceURL { roots.append(resources) }
    roots.append(Bundle.main.bundleURL)
    if let executable = Bundle.main.executableURL?.deletingLastPathComponent() {
      roots.append(executable)
      // A CLI installed in bin/ next to an app bundle's Resources/.
      roots.append(executable.deletingLastPathComponent().appending(path: "Resources"))
    }
    return roots
  }

  /// Returns the packaged public key, or an empty string when no bundle is present.
  /// An empty key yields a verifier that rejects every token, which is the correct
  /// fail-closed outcome — and it never traps.
  public static func bundledPublicKeyPEM(searchRoots: [URL] = defaultSearchRoots()) -> String {
    for root in searchRoots {
      let candidate =
        root
        .appending(path: resourceBundleName, directoryHint: .isDirectory)
        .appending(path: publicKeyResourceName)
      if let pem = try? String(contentsOf: candidate, encoding: .utf8), !pem.isEmpty {
        return pem
      }
    }
    return ""
  }

  public static func bundled() -> Self {
    Self(pem: bundledPublicKeyPEM())
  }

  public func verify(
    _ token: String,
    machineID: String,
    now: Date
  ) -> WebKitUILicenseTokenVerification {
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3,
      let key = publicKey,
      let headerData = Self.decode(String(parts[0])),
      let payloadData = Self.decode(String(parts[1])),
      let signature = Self.decode(String(parts[2])),
      let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
      header["alg"] as? String == "RS256",
      header["kid"] as? String == "lorislabs-license-1"
    else { return .invalid }
    let signed = Data("\(parts[0]).\(parts[1])".utf8)
    guard
      SecKeyVerifySignature(
        key, .rsaSignatureMessagePKCS1v15SHA256, signed as CFData, signature as CFData, nil),
      let claims = try? JSONDecoder().decode(WebKitUILicenseClaims.self, from: payloadData)
    else {
      return .invalid
    }
    let timestamp = now.timeIntervalSince1970
    let skew: TimeInterval = 300
    guard claims.iss == WebKitUILicenseProduct.issuer,
      claims.product == WebKitUILicenseProduct.id,
      claims.machineId == machineID,
      Self.lifecycleClaimsAreValid(claims),
      timestamp >= claims.nbf - skew
    else { return .invalid }
    if timestamp < claims.exp { return .valid(claims) }
    return .expired(claims)
  }

  static func lifecycleClaimsAreValid(_ claims: WebKitUILicenseClaims) -> Bool {
    claims.licenseVersion == 1
      && ["active", "trialing"].contains(claims.subscriptionStatus ?? "")
  }

  private static func decode(_ value: String) -> Data? {
    var base64 = value.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    base64.append(String(repeating: "=", count: (4 - base64.count % 4) % 4))
    return Data(base64Encoded: base64)
  }

  private static func makePublicKey(pem: String) -> SecKey? {
    let base64 =
      pem
      .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
      .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
      .filter { !$0.isWhitespace }
    guard let spki = Data(base64Encoded: base64), let rsa = stripSPKI(spki) else { return nil }
    return SecKeyCreateWithData(
      rsa as CFData,
      [
        kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        kSecAttrKeySizeInBits as String: 2048,
      ] as CFDictionary, nil)
  }

  static func stripSPKI(_ spki: Data) -> Data? {
    let rsaEncryptionOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
    var root = DERReader(bytes: Array(spki))
    guard let sequence = root.read(tag: 0x30), root.isAtEnd else { return nil }
    var subjectPublicKeyInfo = DERReader(bytes: sequence)
    guard
      let algorithm = subjectPublicKeyInfo.read(tag: 0x30),
      let bitString = subjectPublicKeyInfo.read(tag: 0x03),
      subjectPublicKeyInfo.isAtEnd,
      bitString.first == 0,
      bitString.count > 1
    else {
      return nil
    }
    var algorithmIdentifier = DERReader(bytes: algorithm)
    guard
      algorithmIdentifier.read(tag: 0x06) == rsaEncryptionOID,
      algorithmIdentifier.read(tag: 0x05) == [],
      algorithmIdentifier.isAtEnd
    else {
      return nil
    }
    let rsa = Array(bitString.dropFirst())
    var rsaReader = DERReader(bytes: rsa)
    guard rsaReader.read(tag: 0x30) != nil, rsaReader.isAtEnd else { return nil }
    return Data(rsa)
  }
}

private struct DERReader {
  let bytes: [UInt8]
  private(set) var index = 0

  var isAtEnd: Bool { index == bytes.count }

  mutating func read(tag expectedTag: UInt8) -> [UInt8]? {
    guard index < bytes.count, bytes[index] == expectedTag else { return nil }
    index += 1
    guard let length = readLength(), length <= bytes.count - index else { return nil }
    let value = Array(bytes[index..<(index + length)])
    index += length
    return value
  }

  private mutating func readLength() -> Int? {
    guard index < bytes.count else { return nil }
    let first = bytes[index]
    index += 1
    if first < 0x80 { return Int(first) }
    let count = Int(first & 0x7F)
    guard count > 0, count <= MemoryLayout<Int>.size, count <= bytes.count - index else {
      return nil
    }
    guard bytes[index] != 0 else { return nil }
    var length = 0
    for _ in 0..<count {
      guard length <= (Int.max - Int(bytes[index])) / 256 else { return nil }
      length = length * 256 + Int(bytes[index])
      index += 1
    }
    guard length >= 0x80 else { return nil }
    return length
  }
}

public enum WebKitUIMachineIdentity {
  private static let fallbackService = "com.lorislab.webkitui-mcp.machine-identity-v1"
  private static let fallbackAccount = "current"

  public static let current: String = {
    let service = IOServiceGetMatchingService(
      kIOMainPortDefault,
      IOServiceMatching("IOPlatformExpertDevice")
    )
    if service != 0 {
      defer { IOObjectRelease(service) }
      if let property = IORegistryEntryCreateCFProperty(
        service,
        kIOPlatformUUIDKey as CFString,
        kCFAllocatorDefault,
        0
      )?.takeRetainedValue() as? String, !property.isEmpty {
        return property
      }
    }
    return keychainFallback() ?? ""
  }()

  private static func keychainFallback() -> String? {
    let identity: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: fallbackService,
      kSecAttrAccount as String: fallbackAccount,
    ]
    var query = identity
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let copyStatus = SecItemCopyMatching(query as CFDictionary, &result)
    if copyStatus == errSecSuccess, let data = result as? Data,
      let value = String(data: data, encoding: .utf8), !value.isEmpty
    {
      return value
    }
    guard copyStatus == errSecItemNotFound else { return nil }

    let generated = "keychain-\(UUID().uuidString)"
    var item = identity
    item[kSecValueData as String] = Data(generated.utf8)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(item as CFDictionary, nil)
    if addStatus == errSecSuccess { return generated }
    guard addStatus == errSecDuplicateItem else { return nil }

    result = nil
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data,
      let value = String(data: data, encoding: .utf8), !value.isEmpty
    else {
      return nil
    }
    return value
  }
}
