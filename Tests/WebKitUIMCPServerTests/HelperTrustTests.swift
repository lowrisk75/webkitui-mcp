import Foundation
import Testing

@testable import WebKitUIMCPServer

/// Whether the confirmation helper beside the server may be run. Demanding the release
/// team and the release identifier from every installation made the documented source
/// install refuse to present a confirmation at all: a `swift build` product is ad-hoc
/// signed, carries no team, and is identified by its own file name. Every installation
/// but the release signer's was inert, and the failure looked like a missing helper.
@Suite("Confirmation helper trust")
struct HelperTrustTests {
  private let release = NativeBrowserConfirmationPresenter.releaseHelperIdentifier
  private let sourceBuild = NativeBrowserConfirmationPresenter.sourceBuildHelperIdentifier

  private func trusted(_ helperTeam: String?, _ identifier: String, _ serverTeam: String?)
    -> Bool
  {
    NativeBrowserConfirmationPresenter.helperIsTrusted(
      helperTeam: helperTeam, helperIdentifier: identifier, serverTeam: serverTeam)
  }

  @Test("A notarized server runs its own packaged helper")
  func signedPairMatches() {
    #expect(trusted("TDV6D5L785", release, "TDV6D5L785"))
  }

  @Test("A notarized server refuses a helper from another team")
  func signedServerRefusesForeignTeam() {
    #expect(!trusted("AAAAAAAAAA", release, "TDV6D5L785"))
  }

  @Test("A notarized server refuses an unsigned helper")
  func signedServerRefusesUnsignedHelper() {
    // The dangerous direction: the helper decides what the human is shown before they
    // approve, so a notarized server must never run one that is not its own.
    #expect(!trusted(nil, sourceBuild, "TDV6D5L785"))
    #expect(!trusted(nil, release, "TDV6D5L785"))
  }

  @Test("A notarized server refuses its own team under a different identifier")
  func signedServerPinsTheIdentifier() {
    #expect(!trusted("TDV6D5L785", "com.example.something", "TDV6D5L785"))
  }

  @Test("An unsigned server refuses a signed helper")
  func unsignedServerRefusesSignedHelper() {
    #expect(!trusted("TDV6D5L785", release, nil))
  }

  @Test("A source build runs the helper it was built with")
  func sourceBuildPairMatches() {
    // Nothing is given away: whoever can write a helper beside an unsigned server can
    // replace that server too, so the check can only assert co-location and the name.
    #expect(trusted(nil, sourceBuild, nil))
  }

  @Test("An unsigned server still refuses an unrelated executable")
  func unsignedServerRefusesUnrelatedName() {
    #expect(!trusted(nil, "curl", nil))
  }
}
