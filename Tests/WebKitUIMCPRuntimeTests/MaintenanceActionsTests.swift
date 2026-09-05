import Foundation
import Testing
import WebKit

@testable import WebKitUIMCPRuntime

@Suite("Operator maintenance actions", .serialized)
@MainActor
struct MaintenanceActionsTests {
  @Test("Forcing a render restores a laid-out viewport")
  func forcingARenderRestoresTheViewport() async throws {
    let runtime = WebKitRuntime(
      websiteDataStore: .nonPersistent(), egressProxy: nil,
      managesApplicationActivationPolicy: false)
    _ = try await runtime.loadHTML(
      "<button aria-label='Go'>Go</button>",
      baseURL: URL(string: "https://fixture.invalid/render"),
      timeout: .seconds(15), quietWindow: .milliseconds(20))
    runtime.forceRender()
    let observation = try await runtime.observe(hydrationTimeout: .zero)
    #expect(observation.elements.count == 1)
  }

  @Test("Clearing browsing data removes the profile's cookies")
  func clearingBrowsingDataRemovesCookies() async throws {
    let store = WKWebsiteDataStore.nonPersistent()
    let runtime = WebKitRuntime(
      websiteDataStore: store, egressProxy: nil,
      managesApplicationActivationPolicy: false)
    let cookie = try #require(
      HTTPCookie(properties: [
        .domain: "clear.fixture.invalid", .path: "/", .name: "session",
        .value: "value-to-remove", .secure: "TRUE",
      ]))
    await store.httpCookieStore.setCookie(cookie)
    #expect(await runtime.authenticatedOrigins().contains("clear.fixture.invalid"))

    await runtime.clearBrowsingData()
    #expect(await runtime.authenticatedOrigins().isEmpty)
  }
}
