import Foundation
import Testing

@testable import WebKitUIMCPLicensing

@Suite("WebKitUI commercial licensing")
struct LicenseManagerTests {
  @Test("activation stores only a verified product-bound token")
  func activationStoresVerifiedToken() async throws {
    let store = MemoryStore()
    let claims = fixtureClaims()
    let manager = WebKitUILicenseManager(
      store: store,
      api: StubAPI(token: "signed-token"),
      verifier: StubVerifier(result: .valid(claims)),
      machineID: { "machine-1" },
      now: { Date(timeIntervalSince1970: 1_000) },
      appVersion: { "0.6.0" }
    )

    let status = try await manager.activate(licenseKey: "webkitui-abcd-efgh-2345-6789")

    #expect(status.state == .active)
    #expect(status.plan == "team-annual")
    #expect(status.seatLimit == 5)
    #expect(status.machineLimit == 10)
    #expect(try store.load()?.licenseKey == "WEBKITUI-ABCD-EFGH-2345-6789")
  }

  @Test("an unverified token never reaches secure storage")
  func rejectsUnverifiedToken() async {
    let store = MemoryStore()
    let manager = WebKitUILicenseManager(
      store: store,
      api: StubAPI(token: "forged"),
      verifier: StubVerifier(result: .invalid),
      machineID: { "machine-1" }
    )

    await #expect(throws: WebKitUILicenseError.tokenVerificationFailed) {
      try await manager.activate(licenseKey: "WEBKITUI-ABCD-EFGH-2345-6789")
    }
    let stored = try? store.load()
    #expect(stored == nil)
  }

  @Test("activation fails closed when no stable machine identity is available")
  func rejectsUnavailableMachineIdentity() async {
    let manager = WebKitUILicenseManager(
      store: MemoryStore(),
      api: StubAPI(token: "unused"),
      verifier: StubVerifier(result: .invalid),
      machineID: { "" }
    )

    await #expect(throws: WebKitUILicenseError.machineIdentityUnavailable) {
      try await manager.activate(licenseKey: "WEBKITUI-ABCD-EFGH-2345-6789")
    }
  }

  @Test("status masks the license key")
  func statusMasksKey() async throws {
    let store = MemoryStore()
    try store.save(
      StoredWebKitUILicense(
        licenseKey: "WEBKITUI-ABCD-EFGH-2345-6789",
        token: "signed-token",
        activatedAt: Date(timeIntervalSince1970: 900)
      ))
    let manager = WebKitUILicenseManager(
      store: store,
      api: StubAPI(token: "signed-token"),
      verifier: StubVerifier(result: .valid(fixtureClaims())),
      machineID: { "machine-1" },
      now: { Date(timeIntervalSince1970: 1_000) }
    )

    let status = try await manager.status()

    #expect(status.maskedKey == "••••-6789")
  }

  @Test("invalid stored tokens never receive offline grace")
  func invalidTokenNeverReceivesGrace() async throws {
    let store = MemoryStore()
    try store.save(
      StoredWebKitUILicense(
        licenseKey: "WEBKITUI-ABCD-EFGH-2345-6789",
        token: "forged",
        activatedAt: Date(timeIntervalSince1970: 900),
        lastServerSuccessAt: Date(timeIntervalSince1970: 900),
        maximumObservedAt: Date(timeIntervalSince1970: 900)
      ))
    let manager = WebKitUILicenseManager(
      store: store,
      api: StubAPI(token: "unused"),
      verifier: StubVerifier(result: .invalid),
      machineID: { "machine-1" },
      now: { Date(timeIntervalSince1970: 1_000) }
    )

    #expect(try await manager.status().state == .invalid)
  }

  @Test("a previously validated expired lease receives only bounded offline grace")
  func expiredValidatedLeaseReceivesBoundedGrace() async throws {
    let store = MemoryStore()
    let claims = fixtureClaims(expiration: 2_000)
    try store.save(
      StoredWebKitUILicense(
        licenseKey: claims.sub,
        token: "expired-signed-token",
        activatedAt: Date(timeIntervalSince1970: 900),
        lastServerSuccessAt: Date(timeIntervalSince1970: 1_900),
        maximumObservedAt: Date(timeIntervalSince1970: 1_900)
      ))
    let manager = WebKitUILicenseManager(
      store: store,
      api: StubAPI(token: "unused"),
      verifier: StubVerifier(result: .expired(claims)),
      machineID: { "machine-1" },
      now: { Date(timeIntervalSince1970: 2_100) }
    )

    #expect(try await manager.status().state == .grace)
  }

  @Test("clock rollback fails closed before local grace")
  func clockRollbackFailsClosed() async throws {
    let store = MemoryStore()
    try store.save(
      StoredWebKitUILicense(
        licenseKey: "WEBKITUI-ABCD-EFGH-2345-6789",
        token: "signed-token",
        activatedAt: Date(timeIntervalSince1970: 900),
        lastServerSuccessAt: Date(timeIntervalSince1970: 2_000),
        maximumObservedAt: Date(timeIntervalSince1970: 2_000)
      ))
    let manager = WebKitUILicenseManager(
      store: store,
      api: StubAPI(token: "unused"),
      verifier: StubVerifier(result: .valid(fixtureClaims())),
      machineID: { "machine-1" },
      now: { Date(timeIntervalSince1970: 1_000) }
    )

    #expect(try await manager.status().state == .invalid)
  }

  @Test("refresh atomically replaces a lease only after verification")
  func refreshStoresVerifiedLease() async throws {
    let store = MemoryStore()
    try store.save(
      StoredWebKitUILicense(
        licenseKey: "WEBKITUI-ABCD-EFGH-2345-6789",
        token: "old-token",
        activatedAt: Date(timeIntervalSince1970: 900),
        lastServerSuccessAt: Date(timeIntervalSince1970: 900),
        maximumObservedAt: Date(timeIntervalSince1970: 900)
      ))
    let manager = WebKitUILicenseManager(
      store: store,
      api: StubAPI(token: "new-token"),
      verifier: StubVerifier(result: .valid(fixtureClaims(expiration: 4_000))),
      machineID: { "machine-1" },
      now: { Date(timeIntervalSince1970: 2_000) }
    )

    #expect(try await manager.refresh().state == .active)
    #expect(try store.load()?.token == "new-token")
    #expect(try store.load()?.lastServerSuccessAt == Date(timeIntervalSince1970: 2_000))
  }

  @Test("signed leases require explicit lifecycle claims")
  func lifecycleClaimsAreMandatory() {
    #expect(
      WebKitUIRS256TokenVerifier.lifecycleClaimsAreValid(
        fixtureClaims(licenseVersion: 1, subscriptionStatus: "active")))
    #expect(
      !WebKitUIRS256TokenVerifier.lifecycleClaimsAreValid(
        fixtureClaims(licenseVersion: nil, subscriptionStatus: "active")))
    #expect(
      !WebKitUIRS256TokenVerifier.lifecycleClaimsAreValid(
        fixtureClaims(licenseVersion: 1, subscriptionStatus: nil)))
    #expect(
      !WebKitUIRS256TokenVerifier.lifecycleClaimsAreValid(
        fixtureClaims(licenseVersion: 1, subscriptionStatus: "canceled")))
  }

  @Test("SPKI extraction validates the RSA algorithm structure")
  func spkiExtractionValidatesRSAOID() {
    let rsaEncryptionOID: [UInt8] = [
      0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01,
    ]
    let algorithm = [0x30, 0x0D, 0x06, 0x09] + rsaEncryptionOID + [0x05, 0x00]
    let bitString: [UInt8] = [0x03, 0x04, 0x00, 0x30, 0x01, 0x00]
    let valid = Data([0x30, UInt8(algorithm.count + bitString.count)] + algorithm + bitString)
    #expect(WebKitUIRS256TokenVerifier.stripSPKI(valid) == Data([0x30, 0x01, 0x00]))

    var wrongOID = valid
    wrongOID[wrongOID.index(wrongOID.startIndex, offsetBy: 14)] = 0x02
    #expect(WebKitUIRS256TokenVerifier.stripSPKI(wrongOID) == nil)
    #expect(WebKitUIRS256TokenVerifier.stripSPKI(valid.dropLast()) == nil)
  }

  @Test("status checkpoints secure storage only at the rollback interval")
  func statusThrottlesMaximumObservedCheckpoint() async throws {
    let store = MemoryStore()
    try store.save(
      StoredWebKitUILicense(
        licenseKey: "WEBKITUI-ABCD-EFGH-2345-6789",
        token: "signed-token",
        activatedAt: Date(timeIntervalSince1970: 900),
        maximumObservedAt: Date(timeIntervalSince1970: 1_000)
      ))
    let withinInterval = WebKitUILicenseManager(
      store: store,
      api: StubAPI(token: "unused"),
      verifier: StubVerifier(result: .valid(fixtureClaims(expiration: 4_000))),
      machineID: { "machine-1" },
      now: { Date(timeIntervalSince1970: 1_100) }
    )
    #expect(try await withinInterval.status().state == .active)
    #expect(store.saveCount() == 1)

    let afterInterval = WebKitUILicenseManager(
      store: store,
      api: StubAPI(token: "unused"),
      verifier: StubVerifier(result: .valid(fixtureClaims(expiration: 4_000))),
      machineID: { "machine-1" },
      now: { Date(timeIntervalSince1970: 1_301) }
    )
    #expect(try await afterInterval.status().state == .active)
    #expect(store.saveCount() == 2)
  }

  private func fixtureClaims(
    expiration: TimeInterval = 2_000,
    licenseVersion: Int? = 1,
    subscriptionStatus: String? = "active"
  ) -> WebKitUILicenseClaims {
    WebKitUILicenseClaims(
      iss: WebKitUILicenseProduct.issuer,
      sub: "WEBKITUI-ABCD-EFGH-2345-6789",
      machineId: "machine-1",
      email: "buyer@example.com",
      product: WebKitUILicenseProduct.id,
      plan: "team-annual",
      organization: "Example SAS",
      seatLimit: 5,
      machineLimit: 10,
      appVersion: "0.6.0",
      iat: 900,
      exp: expiration,
      nbf: 850,
      licenseVersion: licenseVersion,
      subscriptionStatus: subscriptionStatus
    )
  }
}

private final class MemoryStore: WebKitUILicenseStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var value: StoredWebKitUILicense?
  private var saves = 0

  func load() throws -> StoredWebKitUILicense? { lock.withLock { value } }
  func save(_ license: StoredWebKitUILicense) throws {
    lock.withLock {
      value = license
      saves += 1
    }
  }
  func clear() throws { lock.withLock { value = nil } }
  func saveCount() -> Int { lock.withLock { saves } }
}

private struct StubVerifier: WebKitUILicenseTokenVerifying {
  let result: WebKitUILicenseTokenVerification

  func verify(
    _ token: String,
    machineID: String,
    now: Date
  ) -> WebKitUILicenseTokenVerification { result }
}

private struct StubAPI: WebKitUILicenseAPI {
  let token: String
  func activate(licenseKey: String, machineID: String, appVersion: String) async throws
    -> WebKitUIActivationReceipt
  {
    WebKitUIActivationReceipt(token: token, activeMachines: 1, maximumMachines: 10)
  }
  func deactivate(licenseKey: String, machineID: String) async throws {}
  func refresh(licenseKey: String, machineID: String, appVersion: String) async throws
    -> WebKitUIActivationReceipt
  {
    WebKitUIActivationReceipt(token: token, activeMachines: 1, maximumMachines: 10)
  }
}
