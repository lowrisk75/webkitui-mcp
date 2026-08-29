import Foundation

public enum WebKitUILicenseProduct {
  public static let id = "webkitui-mcp.team"
  public static let issuer = "lorislabs-license"
}

public struct WebKitUILicenseClaims: Codable, Equatable, Sendable {
  public let iss: String
  public let sub: String
  public let machineId: String
  public let email: String
  public let product: String
  public let plan: String
  public let organization: String?
  public let seatLimit: Int
  public let machineLimit: Int
  public let appVersion: String
  public let iat: TimeInterval
  public let exp: TimeInterval
  public let nbf: TimeInterval
  public let jti: String?
  public let licenseVersion: Int?
  public let subscriptionStatus: String?
  public let paidThrough: String?
  public let serverTime: TimeInterval?

  public init(
    iss: String,
    sub: String,
    machineId: String,
    email: String,
    product: String,
    plan: String,
    organization: String?,
    seatLimit: Int,
    machineLimit: Int,
    appVersion: String,
    iat: TimeInterval,
    exp: TimeInterval,
    nbf: TimeInterval,
    jti: String? = nil,
    licenseVersion: Int? = nil,
    subscriptionStatus: String? = nil,
    paidThrough: String? = nil,
    serverTime: TimeInterval? = nil
  ) {
    self.iss = iss
    self.sub = sub
    self.machineId = machineId
    self.email = email
    self.product = product
    self.plan = plan
    self.organization = organization
    self.seatLimit = seatLimit
    self.machineLimit = machineLimit
    self.appVersion = appVersion
    self.iat = iat
    self.exp = exp
    self.nbf = nbf
    self.jti = jti
    self.licenseVersion = licenseVersion
    self.subscriptionStatus = subscriptionStatus
    self.paidThrough = paidThrough
    self.serverTime = serverTime
  }
}

public struct StoredWebKitUILicense: Codable, Equatable, Sendable {
  public let licenseKey: String
  public let token: String
  public let activatedAt: Date
  public let lastServerSuccessAt: Date?
  public let maximumObservedAt: Date?

  public init(
    licenseKey: String,
    token: String,
    activatedAt: Date,
    lastServerSuccessAt: Date? = nil,
    maximumObservedAt: Date? = nil
  ) {
    self.licenseKey = licenseKey
    self.token = token
    self.activatedAt = activatedAt
    self.lastServerSuccessAt = lastServerSuccessAt
    self.maximumObservedAt = maximumObservedAt
  }
}

public enum WebKitUILicenseState: String, Codable, Equatable, Sendable {
  case none
  case active
  case grace
  case expired
  case invalid
}

public struct WebKitUILicenseStatus: Equatable, Sendable {
  public let state: WebKitUILicenseState
  public let maskedKey: String?
  public let organization: String?
  public let plan: String?
  public let seatLimit: Int?
  public let machineLimit: Int?
  public let expiresAt: Date?

  public init(
    state: WebKitUILicenseState,
    maskedKey: String? = nil,
    organization: String? = nil,
    plan: String? = nil,
    seatLimit: Int? = nil,
    machineLimit: Int? = nil,
    expiresAt: Date? = nil
  ) {
    self.state = state
    self.maskedKey = maskedKey
    self.organization = organization
    self.plan = plan
    self.seatLimit = seatLimit
    self.machineLimit = machineLimit
    self.expiresAt = expiresAt
  }
}

public enum WebKitUILicenseError: Error, Equatable, Sendable {
  case invalidKey
  case machineLimitReached(maximum: Int?)
  case inactiveSubscription
  case revoked
  case invalidServerResponse
  case tokenVerificationFailed
  case machineIdentityUnavailable
  case clockRollbackDetected
  case transport(String)
  case server(status: Int, code: String?)
  case secureStorage(status: Int32)
}

public protocol WebKitUILicenseStoring: Sendable {
  func load() throws -> StoredWebKitUILicense?
  func save(_ license: StoredWebKitUILicense) throws
  func clear() throws
}

public protocol WebKitUILicenseTokenVerifying: Sendable {
  func verify(
    _ token: String,
    machineID: String,
    now: Date
  ) -> WebKitUILicenseTokenVerification
}

public enum WebKitUILicenseTokenVerification: Equatable, Sendable {
  case valid(WebKitUILicenseClaims)
  case expired(WebKitUILicenseClaims)
  case invalid
}

public struct WebKitUIActivationReceipt: Equatable, Sendable {
  public let token: String
  public let activeMachines: Int
  public let maximumMachines: Int

  public init(token: String, activeMachines: Int, maximumMachines: Int) {
    self.token = token
    self.activeMachines = activeMachines
    self.maximumMachines = maximumMachines
  }
}

public protocol WebKitUILicenseAPI: Sendable {
  func activate(licenseKey: String, machineID: String, appVersion: String) async throws
    -> WebKitUIActivationReceipt
  func deactivate(licenseKey: String, machineID: String) async throws
  func refresh(licenseKey: String, machineID: String, appVersion: String) async throws
    -> WebKitUIActivationReceipt
}

extension String {
  var webKitUILicenseMasked: String {
    let suffix = self.suffix(4)
    return suffix.isEmpty ? "••••" : "••••-\(suffix)"
  }
}
