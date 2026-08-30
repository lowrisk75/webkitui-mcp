import Darwin
import Foundation
import Testing
import WebKit

@testable import WebKitUIMCPRuntime

private final class ResolverProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var calls = 0

  func resolve(_ host: String) -> ResolvedPublicAddress {
    lock.lock()
    calls += 1
    lock.unlock()
    return ResolvedPublicAddress(host: host, address: "127.0.0.1")
  }

  func callCount() -> Int {
    lock.lock()
    defer { lock.unlock() }
    return calls
  }
}

@Suite("Pinned SOCKS egress proxy", .serialized)
struct PinnedSOCKSProxyTests {
  @Test("A hostname is resolved once, pinned, and reused across TCP connections")
  func pinReuse() async throws {
    let destination = try FormFixtureServer()
    let resolver = ResolverProbe()
    let proxy = try PinnedSOCKSProxy { resolver.resolve($0) }

    for _ in 0..<2 {
      let response = try await Task.detached {
        try socksRequest(
          proxyPort: proxy.port.rawValue,
          host: "rebind.test",
          destinationPort: destination.port)
      }.value
      #expect(String(decoding: response, as: UTF8.self).contains("200 OK"))
    }

    #expect(resolver.callCount() == 1)
    #expect(
      proxy.metricsSnapshot()
        == PinnedProxyMetrics(acceptedConnections: 2, blockedConnections: 0, pinnedHosts: 1))
  }

  @Test("Production policy rejects a SOCKS request resolving only to loopback")
  func blocksLoopbackResolution() async throws {
    let proxy = try PinnedSOCKSProxy()
    let reply = try await Task.detached {
      try socksRequest(proxyPort: proxy.port.rawValue, host: "localhost", destinationPort: 80)
    }.value

    #expect(reply == Data([2]))
    #expect(proxy.metricsSnapshot().blockedConnections == 1)
  }

  @Test("UDP ASSOCIATE fails closed")
  func blocksUDPAssociate() async throws {
    let resolver = ResolverProbe()
    let proxy = try PinnedSOCKSProxy { resolver.resolve($0) }
    let reply = try await Task.detached {
      try socksRequest(
        proxyPort: proxy.port.rawValue,
        host: "rebind.test",
        destinationPort: 53,
        command: 3)
    }.value

    #expect(reply == Data([2]))
    #expect(resolver.callCount() == 0)
    #expect(proxy.metricsSnapshot().blockedConnections == 1)
  }

  @Test("Runtime blocks loopback before WebKit can bypass the configured proxy")
  @MainActor
  func webKitRouting() async throws {
    let destination = try FormFixtureServer()
    let runtime = try WebKitRuntime(protectedWebsiteDataStore: .nonPersistent())
    #expect(runtime.authenticationEnvironmentSnapshot().pinnedProxyConfigured)
    #expect(!runtime.authenticationEnvironmentSnapshot().persistentWebsiteDataStore)
    await #expect(throws: WebKitRuntimeError.networkBoundaryDenied) {
      try await runtime.navigate(
        to: URL(string: "http://127.0.0.1:\(destination.port)/")!,
        timeout: .milliseconds(500),
        quietWindow: .milliseconds(20)
      )
    }
    #expect(runtime.egressProxyMetrics()?.blockedConnections == 0)
  }

  @Test("WKWebsiteDataStore routes a public-looking hostname through the proxy")
  @MainActor
  func webKitHostnameRouting() async throws {
    let resolver: @Sendable (String) throws -> ResolvedPublicAddress = { _ in
      throw PublicNetworkAddressPolicyError.noPublicAddress
    }
    let proxy = try PinnedSOCKSProxy(resolver: resolver)
    let store = WKWebsiteDataStore.nonPersistent()
    store.proxyConfigurations = [proxy.proxyConfiguration()]
    let runtime = WebKitRuntime(websiteDataStore: store, egressProxy: proxy)

    await #expect(throws: (any Error).self) {
      try await runtime.navigate(
        to: URL(string: "http://rebind.test/")!,
        timeout: .milliseconds(500),
        quietWindow: .milliseconds(20)
      )
    }
    #expect(proxy.metricsSnapshot().blockedConnections > 0)
  }

  @Test("WKWebView reuses the proxy's pinned address across navigations")
  @MainActor
  func webKitPinReuse() async throws {
    let destination = try FormFixtureServer()
    let resolver = ResolverProbe()
    let proxy = try PinnedSOCKSProxy { resolver.resolve($0) }
    let store = WKWebsiteDataStore.nonPersistent()
    store.proxyConfigurations = [proxy.proxyConfiguration()]
    let runtime = WebKitRuntime(websiteDataStore: store, egressProxy: proxy)
    let url = URL(string: "http://rebind.test:\(destination.port)/form")!

    for _ in 0..<2 {
      let result = try await runtime.navigate(
        to: url, timeout: .seconds(2), quietWindow: .milliseconds(20))
      #expect(result.readiness == .ready)
    }

    #expect(resolver.callCount() == 1)
    #expect(proxy.metricsSnapshot().pinnedHosts == 1)
    #expect(proxy.metricsSnapshot().acceptedConnections >= 2)
  }

  @Test("WKWebView routes an HTTP subresource through the pinned proxy")
  @MainActor
  func webKitSubresourceRouting() async throws {
    let destination = try FormFixtureServer()
    let resolver = ResolverProbe()
    let proxy = try PinnedSOCKSProxy { resolver.resolve($0) }
    let store = WKWebsiteDataStore.nonPersistent()
    store.proxyConfigurations = [proxy.proxyConfiguration()]
    let runtime = WebKitRuntime(websiteDataStore: store, egressProxy: proxy)

    _ = try await runtime.loadHTML(
      """
      <script>
        fetch('/subresource').then(() => { document.title = 'fetched'; });
      </script>
      """,
      baseURL: URL(string: "http://rebind.test:\(destination.port)/")!,
      timeout: .seconds(2),
      quietWindow: .milliseconds(20)
    )
    try await Task.sleep(for: .milliseconds(300))

    #expect(resolver.callCount() == 1)
    #expect(proxy.metricsSnapshot().pinnedHosts == 1)
    #expect(proxy.metricsSnapshot().acceptedConnections >= 1)
  }
}

private func socksRequest(
  proxyPort: UInt16,
  host: String,
  destinationPort: UInt16,
  command: UInt8 = 1
) throws -> Data {
  let descriptor = socket(AF_INET, SOCK_STREAM, 0)
  guard descriptor >= 0 else { throw POSIXError(.ENOTCONN) }
  defer { close(descriptor) }
  var address = sockaddr_in()
  address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
  address.sin_family = sa_family_t(AF_INET)
  address.sin_port = proxyPort.bigEndian
  inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)
  let connected = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
  }
  guard connected == 0 else { throw POSIXError(.ECONNREFUSED) }

  try sendAll(Data([5, 1, 0]), to: descriptor)
  guard try receiveExactly(2, from: descriptor) == Data([5, 0]) else {
    throw POSIXError(.EPROTO)
  }
  let hostBytes = Data(host.utf8)
  var request = Data([5, command, 0, 3, UInt8(hostBytes.count)])
  request.append(hostBytes)
  request.append(UInt8(destinationPort >> 8))
  request.append(UInt8(destinationPort & 0xFF))
  try sendAll(request, to: descriptor)
  let socksReply = try receiveExactly(10, from: descriptor)
  guard socksReply[1] == 0 else { return Data([socksReply[1]]) }

  try sendAll(
    Data("GET / HTTP/1.1\r\nHost: rebind.test\r\nConnection: close\r\n\r\n".utf8), to: descriptor)
  var response = Data()
  var buffer = [UInt8](repeating: 0, count: 4096)
  while true {
    let count = recv(descriptor, &buffer, buffer.count, 0)
    if count <= 0 { break }
    response.append(contentsOf: buffer.prefix(count))
  }
  return response
}

private func sendAll(_ data: Data, to descriptor: Int32) throws {
  try data.withUnsafeBytes { bytes in
    var sent = 0
    while sent < bytes.count {
      let count = Darwin.send(descriptor, bytes.baseAddress! + sent, bytes.count - sent, 0)
      guard count > 0 else { throw POSIXError(.EPIPE) }
      sent += count
    }
  }
}

private func receiveExactly(_ count: Int, from descriptor: Int32) throws -> Data {
  var result = Data()
  var buffer = [UInt8](repeating: 0, count: count)
  while result.count < count {
    let received = recv(descriptor, &buffer, count - result.count, 0)
    guard received > 0 else { throw POSIXError(.ECONNRESET) }
    result.append(contentsOf: buffer.prefix(received))
  }
  return result
}
