import Foundation
import Testing

@testable import WebKitUIMCPLicensing

@Suite("License HTTP transport", .serialized)
struct LicenseHTTPAPITests {
  @Test("Ephemeral configuration disables cookies and caches")
  func ephemeralConfiguration() {
    let configuration = WebKitUILicenseHTTPAPI.ephemeralConfiguration()

    #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    #expect(configuration.urlCache == nil)
    #expect(configuration.httpCookieStorage == nil)
    #expect(!configuration.httpShouldSetCookies)
    #expect(configuration.timeoutIntervalForRequest == 20)
    #expect(configuration.timeoutIntervalForResource == 20)
  }

  @Test("Redirect delegate refuses every redirected request")
  func redirectsAreRejected() async throws {
    let delegate = WebKitUILicenseNoRedirectDelegate()
    let configuration = URLSessionConfiguration.ephemeral
    let session = URLSession(configuration: configuration)
    let task = session.dataTask(with: URL(string: "https://license.example/original")!)
    let response = HTTPURLResponse(
      url: task.originalRequest!.url!,
      statusCode: 302,
      httpVersion: "HTTP/1.1",
      headerFields: ["Location": "https://elsewhere.example/"]
    )!

    let redirected = await withCheckedContinuation { continuation in
      delegate.urlSession(
        session,
        task: task,
        willPerformHTTPRedirection: response,
        newRequest: URLRequest(url: URL(string: "https://elsewhere.example/")!)
      ) { request in
        continuation.resume(returning: request)
      }
    }
    #expect(redirected == nil)
    session.invalidateAndCancel()
  }

  @Test("Activation accepts only bounded same-origin JSON")
  func responseBoundary() async throws {
    let body = Data(#"{"jwt":"token","activeMachines":1,"max":2}"#.utf8)
    let valid = makeAPI(
      responseURL: URL(string: "https://license.example/api/activate")!, body: body)
    #expect(
      try await valid.activate(licenseKey: "key", machineID: "machine", appVersion: "1.0.0")
        == WebKitUIActivationReceipt(token: "token", activeMachines: 1, maximumMachines: 2))

    let redirected = makeAPI(
      responseURL: URL(string: "https://other.example/api/activate")!, body: body)
    await #expect(throws: WebKitUILicenseError.invalidServerResponse) {
      try await redirected.activate(licenseKey: "key", machineID: "machine", appVersion: "1.0.0")
    }

    let oversized = makeAPI(
      responseURL: URL(string: "https://license.example/api/activate")!,
      body: Data(repeating: 0x20, count: WebKitUILicenseHTTPAPI.maximumResponseBytes + 1))
    await #expect(throws: WebKitUILicenseError.invalidServerResponse) {
      try await oversized.activate(licenseKey: "key", machineID: "machine", appVersion: "1.0.0")
    }
  }

  @Test("A non-HTTPS license endpoint fails before transport")
  func requiresHTTPS() async {
    let api = WebKitUILicenseHTTPAPI(
      baseURL: URL(string: "http://license.example")!,
      session: makeSession(
        responseURL: URL(string: "http://license.example/api/activate")!, body: Data()))

    await #expect(throws: WebKitUILicenseError.transport("license endpoint must use HTTPS")) {
      try await api.activate(licenseKey: "key", machineID: "machine", appVersion: "1.0.0")
    }
  }

  private func makeAPI(responseURL: URL, body: Data) -> WebKitUILicenseHTTPAPI {
    WebKitUILicenseHTTPAPI(
      baseURL: URL(string: "https://license.example")!,
      session: makeSession(responseURL: responseURL, body: body))
  }

  private func makeSession(responseURL: URL, body: Data) -> URLSession {
    LicenseURLProtocol.responseURL = responseURL
    LicenseURLProtocol.body = body
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LicenseURLProtocol.self]
    return URLSession(configuration: configuration)
  }
}

private final class LicenseURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var responseURL = URL(string: "https://license.example")!
  nonisolated(unsafe) static var body = Data()

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let response = HTTPURLResponse(
      url: Self.responseURL,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Self.body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
