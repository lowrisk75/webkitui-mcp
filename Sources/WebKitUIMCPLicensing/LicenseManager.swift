import Foundation

public actor WebKitUILicenseManager {
  public static let offlineGrace: TimeInterval = 14 * 24 * 60 * 60
  public static let maximumClockRollback: TimeInterval = 5 * 60
  public static let observationCheckpointInterval: TimeInterval = 5 * 60

  private let store: any WebKitUILicenseStoring
  private let api: any WebKitUILicenseAPI
  private let verifier: any WebKitUILicenseTokenVerifying
  private let machineID: @Sendable () -> String
  private let now: @Sendable () -> Date
  private let appVersion: @Sendable () -> String

  public init(
    store: any WebKitUILicenseStoring,
    api: any WebKitUILicenseAPI,
    verifier: any WebKitUILicenseTokenVerifying,
    machineID: @escaping @Sendable () -> String = { WebKitUIMachineIdentity.current },
    now: @escaping @Sendable () -> Date = Date.init,
    appVersion: @escaping @Sendable () -> String = { "unknown" }
  ) {
    self.store = store
    self.api = api
    self.verifier = verifier
    self.machineID = machineID
    self.now = now
    self.appVersion = appVersion
  }

  public func status() throws -> WebKitUILicenseStatus {
    guard let stored = try store.load() else {
      return WebKitUILicenseStatus(state: .none)
    }
    let currentDate = now()
    if let maximumObservedAt = stored.maximumObservedAt,
      currentDate.timeIntervalSince(maximumObservedAt) < -Self.maximumClockRollback
    {
      return WebKitUILicenseStatus(
        state: .invalid,
        maskedKey: stored.licenseKey.webKitUILicenseMasked
      )
    }
    switch verifier.verify(stored.token, machineID: try requiredMachineID(), now: currentDate) {
    case .valid(let claims):
      if currentDate.timeIntervalSince(stored.maximumObservedAt ?? .distantPast)
        >= Self.observationCheckpointInterval
      {
        try store.save(
          StoredWebKitUILicense(
            licenseKey: stored.licenseKey,
            token: stored.token,
            activatedAt: stored.activatedAt,
            lastServerSuccessAt: stored.lastServerSuccessAt,
            maximumObservedAt: currentDate
          ))
      }
      return status(state: .active, stored: stored, claims: claims)
    case .expired(let claims):
      guard let lastServerSuccessAt = stored.lastServerSuccessAt,
        lastServerSuccessAt.timeIntervalSince1970 <= claims.exp + Self.maximumClockRollback,
        currentDate.timeIntervalSince1970 <= claims.exp + Self.offlineGrace
      else {
        return status(state: .expired, stored: stored, claims: claims)
      }
      return status(state: .grace, stored: stored, claims: claims)
    case .invalid:
      return WebKitUILicenseStatus(
        state: .invalid,
        maskedKey: stored.licenseKey.webKitUILicenseMasked
      )
    }
  }

  @discardableResult
  public func activate(licenseKey: String) async throws -> WebKitUILicenseStatus {
    let normalized = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard normalized.hasPrefix("WEBKITUI-") else { throw WebKitUILicenseError.invalidKey }
    let id = try requiredMachineID()
    let receipt = try await api.activate(
      licenseKey: normalized,
      machineID: id,
      appVersion: appVersion()
    )
    let activationDate = now()
    guard
      case .valid(let claims) = verifier.verify(
        receipt.token,
        machineID: id,
        now: activationDate
      )
    else {
      throw WebKitUILicenseError.tokenVerificationFailed
    }
    let stored = StoredWebKitUILicense(
      licenseKey: normalized,
      token: receipt.token,
      activatedAt: activationDate,
      lastServerSuccessAt: activationDate,
      maximumObservedAt: activationDate
    )
    try store.save(stored)
    return status(state: .active, stored: stored, claims: claims)
  }

  @discardableResult
  public func refresh() async throws -> WebKitUILicenseStatus {
    guard let stored = try store.load() else {
      return WebKitUILicenseStatus(state: .none)
    }
    let refreshDate = now()
    if let maximumObservedAt = stored.maximumObservedAt,
      refreshDate.timeIntervalSince(maximumObservedAt) < -Self.maximumClockRollback
    {
      throw WebKitUILicenseError.clockRollbackDetected
    }
    let id = try requiredMachineID()
    let receipt = try await api.refresh(
      licenseKey: stored.licenseKey,
      machineID: id,
      appVersion: appVersion()
    )
    guard
      case .valid(let claims) = verifier.verify(
        receipt.token,
        machineID: id,
        now: refreshDate
      )
    else {
      throw WebKitUILicenseError.tokenVerificationFailed
    }
    let refreshed = StoredWebKitUILicense(
      licenseKey: stored.licenseKey,
      token: receipt.token,
      activatedAt: stored.activatedAt,
      lastServerSuccessAt: refreshDate,
      maximumObservedAt: max(stored.maximumObservedAt ?? refreshDate, refreshDate)
    )
    try store.save(refreshed)
    return status(state: .active, stored: refreshed, claims: claims)
  }

  public func deactivate() async throws {
    guard let stored = try store.load() else { return }
    try await api.deactivate(licenseKey: stored.licenseKey, machineID: requiredMachineID())
    try store.clear()
  }

  private func requiredMachineID() throws -> String {
    let id = machineID().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { throw WebKitUILicenseError.machineIdentityUnavailable }
    return id
  }

  private func status(
    state: WebKitUILicenseState,
    stored: StoredWebKitUILicense,
    claims: WebKitUILicenseClaims
  ) -> WebKitUILicenseStatus {
    WebKitUILicenseStatus(
      state: state,
      maskedKey: stored.licenseKey.webKitUILicenseMasked,
      organization: claims.organization,
      plan: claims.plan,
      seatLimit: claims.seatLimit,
      machineLimit: claims.machineLimit,
      expiresAt: Date(timeIntervalSince1970: claims.exp)
    )
  }
}
