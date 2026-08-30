import Testing

@testable import WebKitUIMCPRuntime

@Suite("Credential broker XPC peer isolation")
struct CredentialBrokerXPCClientTests {
  @Test("Production peers are independently and exactly pinned")
  func productionPeersAreIndependentlyPinned() {
    let requirements = CredentialBrokerXPCPeerRequirements()
    let controlIdentifier =
      "identifier \"com.lorislab.siliconpass.credential-broker-service\""
    let providerIdentifier = "identifier \"com.lorislab.siliconpass\""

    #expect(requirements.controlService.contains(controlIdentifier))
    #expect(!requirements.controlService.contains(providerIdentifier))
    #expect(requirements.secretProvider.contains(providerIdentifier))
    #expect(!requirements.secretProvider.contains(controlIdentifier))

    for requirement in [requirements.controlService, requirements.secretProvider] {
      #expect(requirement.contains("anchor apple generic"))
      #expect(requirement.contains("certificate leaf[subject.OU] = \"TDV6D5L785\""))
      #expect(
        requirement.contains(
          "entitlement[\"com.apple.security.get-task-allow\"] absent"
        ))
    }
  }

  @Test("Custom peers remain separated without weakening the signing policy")
  func customPeersRemainSeparated() {
    let requirements = CredentialBrokerXPCPeerRequirements(
      brokerBundleIdentifier: "com.example.control",
      secretProviderBundleIdentifier: "com.example.provider"
    )

    #expect(requirements.controlService.contains("identifier \"com.example.control\""))
    #expect(!requirements.controlService.contains("identifier \"com.example.provider\""))
    #expect(requirements.secretProvider.contains("identifier \"com.example.provider\""))
    #expect(!requirements.secretProvider.contains("identifier \"com.example.control\""))
  }
}
