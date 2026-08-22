import Testing

@testable import WebKitUIMCPRuntime

@Suite("Public network address policy")
struct PublicNetworkAddressPolicyTests {
  private let policy = PublicNetworkAddressPolicy()

  @Test("Private, local, reserved and documentation literals fail closed")
  func blockedLiterals() {
    let blocked = [
      "0.0.0.0", "10.0.0.1", "100.64.0.1", "127.0.0.1", "169.254.169.254",
      "172.16.0.1", "192.168.1.1", "192.0.2.1", "198.18.0.1", "198.51.100.1",
      "203.0.113.1", "224.0.0.1", "255.255.255.255", "::", "::1", "fe80::1",
      "fc00::1", "ff02::1", "2001:db8::1", "::ffff:127.0.0.1",
    ]
    for address in blocked {
      #expect(!policy.isPublicIPAddress(address))
    }
  }

  @Test("Representative public unicast literals are allowed")
  func publicLiterals() {
    for address in ["1.1.1.1", "8.8.8.8", "2606:4700:4700::1111"] {
      #expect(policy.isPublicIPAddress(address))
    }
  }

  @Test("Local names and DNS answers with no public address are rejected")
  func localResolution() {
    #expect(throws: PublicNetworkAddressPolicyError.localName) {
      try policy.resolve("localhost")
    }
    #expect(throws: PublicNetworkAddressPolicyError.localName) {
      try policy.resolve("service.local.")
    }
    #expect(throws: PublicNetworkAddressPolicyError.noPublicAddress) {
      try policy.resolve("127.0.0.1")
    }
  }
}
