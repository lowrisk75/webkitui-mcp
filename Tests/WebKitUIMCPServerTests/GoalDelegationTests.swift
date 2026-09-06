import Foundation
import Testing

@testable import WebKitUIMCPServer

@Suite("Goal delegation policy")
struct GoalDelegationTests {
  @Test("A typed same-origin path grant spends a bounded navigation budget")
  func boundedGrant() throws {
    let now = Date(timeIntervalSince1970: 1_000)
    var grant = try GoalDelegation(
      identifier: "delegation-test",
      goalDisplay: "Inspect account settings",
      origin: try #require(URL(string: "https://example.com")),
      pathPrefixes: ["/account", "/docs/"],
      allowedQueryKeys: ["page", "tab"],
      issuedAt: now,
      expiresAt: now.addingTimeInterval(900),
      maximumNavigations: 2)

    #expect(
      grant.authorizeNavigation(
        to: try #require(URL(string: "https://example.com/account/profile?tab=general")),
        now: now) == .allowed)
    #expect(grant.remainingNavigations == 1)
    #expect(
      grant.authorizeNavigation(
        to: try #require(URL(string: "https://example.com/docs/reference?page=2")),
        now: now) == .allowed)
    #expect(grant.remainingNavigations == 0)
    #expect(
      grant.authorizeNavigation(
        to: try #require(URL(string: "https://example.com/account")),
        now: now) == .denied(.exhausted))
  }

  @Test(
    "Origin, path, query, expiry and consequential destinations fail closed",
    arguments: [
      ("https://other.example/account", GoalDelegationDenial.originMismatch),
      ("https://example.com/accounting", GoalDelegationDenial.pathOutsideScope),
      ("https://example.com/account?next=1", GoalDelegationDenial.queryKeyOutsideScope),
      ("https://example.com/account/newApiKey", GoalDelegationDenial.consequentialDestination),
      (
        "https://example.com/account/%256e%2565%2577%2541%2570%2569%254b%2565%2579",
        GoalDelegationDenial.consequentialDestination
      ),
      ("https://example.com/account?tab=publish", GoalDelegationDenial.consequentialDestination),
    ])
  func hardStops(rawURL: String, expected: GoalDelegationDenial) throws {
    let now = Date(timeIntervalSince1970: 1_000)
    var grant = try GoalDelegation(
      goalDisplay: "Inspect account settings",
      origin: try #require(URL(string: "https://example.com")),
      pathPrefixes: ["/account"],
      allowedQueryKeys: ["tab"],
      issuedAt: now,
      expiresAt: now.addingTimeInterval(900),
      maximumNavigations: 30)
    #expect(
      grant.authorizeNavigation(to: try #require(URL(string: rawURL)), now: now)
        == .denied(expected))
    #expect(grant.remainingNavigations == 30)
  }

  @Test("Unsafe scopes and sensitive query keys are rejected at issuance")
  func issuanceValidation() throws {
    let now = Date(timeIntervalSince1970: 1_000)
    for queryKeys in [Set(["token"]), Set(["newApiKey"])] {
      #expect(throws: GoalDelegationValidationError.invalidScope) {
        _ = try GoalDelegation(
          goalDisplay: "Inspect",
          origin: try #require(URL(string: "https://example.com")),
          pathPrefixes: ["/account"],
          allowedQueryKeys: queryKeys,
          issuedAt: now,
          expiresAt: now.addingTimeInterval(900),
          maximumNavigations: 30)
      }
    }
  }

  @Test("The companion monitor exposes only summary state and revokes immediately")
  func companionMonitorRevocation() async {
    let monitor = GoalDelegationMonitor()
    let snapshot = GoalDelegationSnapshot(
      identifier: "delegation-visible",
      goalDisplay: "Inspect account settings",
      origin: "https://example.com",
      expiresAt: Date().addingTimeInterval(900),
      remainingNavigations: 4)

    await monitor.publish(snapshot)
    #expect(await monitor.snapshot() == snapshot)
    #expect(await monitor.requestImmediateRevocation())
    #expect(await monitor.snapshot() == nil)
    #expect(await monitor.isRevoked(snapshot.identifier))
  }
}
