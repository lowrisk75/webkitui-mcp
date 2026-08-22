import Foundation
import Testing

@testable import WebKitUIMCPCore

@Suite("Capability authority")
struct CapabilityAuthorityTests {
  private let origin = SecurityOrigin(scheme: "https", host: "example.com")
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  @Test("Knowing a handle value does not create authority")
  func forgedHandleRejected() async {
    let authority = CapabilityAuthority()
    let forged = CapabilityHandle(rawValue: UUID())
    let request = CapabilityRequest(action: .readPage, liveOrigin: origin)

    #expect(await authority.evaluate(request, using: forged, now: now) == .denied(.unknownHandle))
  }

  @Test("Grant is exact in action, origin and input provenance")
  func exactScope() async {
    let authority = CapabilityAuthority()
    let handle = await authority.issue(
      CapabilityScope(
        actions: [.fillForm],
        origins: [origin],
        acceptedInputProvenance: [.userIntent, .userEnteredSiteData],
        expiresAt: now.addingTimeInterval(60)
      )
    )

    let allowed = CapabilityRequest(
      action: .fillForm,
      liveOrigin: origin,
      inputProvenance: [.userEnteredSiteData]
    )
    let wrongAction = CapabilityRequest(action: .submitForm, liveOrigin: origin)
    let wrongOrigin = CapabilityRequest(
      action: .fillForm,
      liveOrigin: .init(scheme: "https", host: "evil-example.com")
    )
    let tainted = CapabilityRequest(
      action: .fillForm,
      liveOrigin: origin,
      inputProvenance: [.thirdPartyEmbed]
    )

    #expect(await authority.evaluate(allowed, using: handle, now: now) == .allowed)
    #expect(
      await authority.evaluate(wrongAction, using: handle, now: now)
        == .denied(.actionNotGranted)
    )
    #expect(
      await authority.evaluate(wrongOrigin, using: handle, now: now)
        == .denied(.originNotGranted)
    )
    #expect(
      await authority.evaluate(tainted, using: handle, now: now)
        == .denied(.inputProvenanceNotGranted)
    )
  }

  @Test("Expired and revoked handles fail closed")
  func lifecycle() async {
    let authority = CapabilityAuthority()
    let expired = await authority.issue(
      CapabilityScope(
        actions: [.readPage],
        origins: [origin],
        acceptedInputProvenance: [],
        expiresAt: now
      )
    )
    let request = CapabilityRequest(action: .readPage, liveOrigin: origin)

    #expect(await authority.evaluate(request, using: expired, now: now) == .denied(.expired))
    #expect(
      await authority.evaluate(request, using: expired, now: now)
        == .denied(.unknownHandle)
    )

    let revoked = await authority.issue(
      CapabilityScope(
        actions: [.readPage],
        origins: [origin],
        acceptedInputProvenance: [],
        expiresAt: now.addingTimeInterval(60)
      )
    )
    await authority.revoke(revoked)
    #expect(await authority.evaluate(request, using: revoked, now: now) == .denied(.unknownHandle))
  }
}
