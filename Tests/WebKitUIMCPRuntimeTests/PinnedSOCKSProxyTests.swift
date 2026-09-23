import Darwin
import Foundation
import Testing
import WebKit

@testable import WebKitUIMCPRuntime

/// Fixture navigations must not be bound to wall-clock luck. The suite is
/// serialized and launches many WebKit content processes, so a loaded machine can
/// exceed a two-second budget while the behaviour under test is perfectly correct.
/// No test asserts that a navigation times out, so a generous bound weakens nothing
/// and removes the only cause of intermittent failures observed here.
private let fixtureNavigationTimeout: Duration = .seconds(15)

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
  @Test("Connection admission rejects saturation and recovers after release")
  func boundedConnectionAdmission() {
    let admission = BoundedConnectionAdmission(maximum: 2)

    #expect(admission.tryAcquire())
    #expect(admission.tryAcquire())
    #expect(!admission.tryAcquire())
    #expect(admission.activeCount() == 2)

    admission.release()
    #expect(admission.tryAcquire())
    #expect(admission.activeCount() == 2)
    admission.release()
    admission.release()
    #expect(admission.activeCount() == 0)
  }

  @Test("Local socket deadlines are applied to blocking descriptors")
  func localSocketDeadlines() throws {
    var descriptors = [Int32](repeating: -1, count: 2)
    guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
      throw POSIXError(.ENOTCONN)
    }
    defer {
      close(descriptors[0])
      close(descriptors[1])
    }

    try LocalSocketDeadlinePolicy(receiveIdleSeconds: 17, sendSeconds: 9)
      .apply(to: descriptors[0])

    #expect(try socketTimeout(SO_RCVTIMEO, descriptor: descriptors[0]).tv_sec == 17)
    #expect(try socketTimeout(SO_SNDTIMEO, descriptor: descriptors[0]).tv_sec == 9)
  }

  @Test("Proxy rejects connections above its active connection limit")
  func activeConnectionLimit() async throws {
    let resolver = ResolverProbe()
    let proxy = try PinnedSOCKSProxy(
      maximumActiveConnections: 1,
      timeouts: PinnedSOCKSTimeouts(handshake: 2, connect: 2, idle: 2)
    ) { resolver.resolve($0) }
    let first = try openProxyConnection(port: proxy.port.rawValue)
    defer { close(first) }
    try await Task.sleep(for: .milliseconds(50))

    let second = try openProxyConnection(port: proxy.port.rawValue)
    defer { close(second) }

    try await waitUntil { proxy.metricsSnapshot().blockedConnections == 1 }
    #expect(proxy.metricsSnapshot().blockedConnections == 1)
  }

  @Test("Handshake timeout releases capacity for a later valid request")
  func handshakeTimeoutRecovery() async throws {
    let destination = try FormFixtureServer()
    let resolver = ResolverProbe()
    let proxy = try PinnedSOCKSProxy(
      maximumActiveConnections: 1,
      timeouts: PinnedSOCKSTimeouts(handshake: 0.05, connect: 1, idle: 1)
    ) { resolver.resolve($0) }
    let stalled = try openProxyConnection(port: proxy.port.rawValue)
    defer { close(stalled) }

    try await waitUntil { proxy.metricsSnapshot().timedOutConnections == 1 }
    let response = try await Task.detached {
      try socksRequest(
        proxyPort: proxy.port.rawValue,
        host: "rebind.test",
        destinationPort: destination.port)
    }.value

    #expect(String(decoding: response, as: UTF8.self).contains("200 OK"))
    #expect(proxy.metricsSnapshot().timedOutConnections == 1)
  }

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

  @Test("A granted tailnet origin opens one host on one port, and nothing else")
  func tailnetGrantIsExact() async throws {
    let destination = try FormFixtureServer()
    let grants = TailnetOriginGrants()
    // The public resolver refuses, as it does for a 100.64.0.0/10 name; the tailnet
    // resolver stands in for Tailscale by answering with the fixture's loopback.
    let proxy = try PinnedSOCKSProxy(
      tailnetGrants: grants,
      tailnetResolver: { ResolvedPublicAddress(host: $0, address: "127.0.0.1") },
      resolver: { _ in throw PublicNetworkAddressPolicyError.noPublicAddress })
    let request: @Sendable (String, UInt16) async throws -> Data = { host, port in
      try await Task.detached {
        try socksRequest(proxyPort: proxy.port.rawValue, host: host, destinationPort: port)
      }.value
    }

    #expect(try await request("ha.example.ts.net", destination.port) == Data([2]))
    grants.grant(host: "HA.example.ts.net.", port: destination.port)
    let allowed = try await request("ha.example.ts.net", destination.port)
    #expect(String(decoding: allowed, as: UTF8.self).contains("200 OK"))
    // Same name on another port, or another name: still refused.
    #expect(try await request("ha.example.ts.net", destination.port &+ 1) == Data([2]))
    #expect(try await request("nas.example.ts.net", destination.port) == Data([2]))
  }

  @Test("A granted tailnet origin answers its own pages, never another site's")
  @MainActor
  func tailnetOriginIsReachableOnlyFromItself() async throws {
    // Stand-in for the tailnet service, and a foreign page that would reach into it.
    let service = try FormFixtureServer { request in
      FormFixtureServer.response(
        body: request.hasPrefix("GET /data")
          ? "secret-state"
          : "<script>fetch('/data').then(r => r.text())"
            + ".then(t => document.title = 'reached:' + t, () => document.title = 'blocked')"
            + "</script>")
    }
    let foreign = try FormFixtureServer { _ in
      FormFixtureServer.response(
        body: "<script>fetch('http://127.0.0.1:\(service.port)/data', {mode: 'no-cors'})"
          + ".then(() => document.title = 'reached', () => document.title = 'blocked')"
          + "</script>")
    }
    let runtime = WebKitRuntime()
    await runtime.installTailnetRules(for: [(host: "127.0.0.1", port: service.port)])
    func title(after url: String) async throws -> String? {
      _ = try await runtime.navigate(
        to: URL(string: url)!, timeout: .seconds(15), quietWindow: .milliseconds(40))
      for _ in 0..<100 {
        if let title = try await runtime.webView.evaluateJavaScript("document.title") as? String,
          !title.isEmpty
        {
          return title
        }
        try await Task.sleep(for: .milliseconds(20))
      }
      return nil
    }
    #expect(try await title(after: "http://localhost:\(foreign.port)/") == "blocked")
    #expect(try await title(after: "http://127.0.0.1:\(service.port)/") == "reached:secret-state")
  }

  @Test("Only 100.64.0.0/10 counts as a tailnet address")
  func tailnetRange() {
    #expect(PublicNetworkAddressPolicy.isTailnetIPv4(0x6440_0001))  // 100.64.0.1
    #expect(PublicNetworkAddressPolicy.isTailnetIPv4(0x647F_FFFE))  // 100.127.255.254
    #expect(!PublicNetworkAddressPolicy.isTailnetIPv4(0x6480_0000))  // 100.128.0.0
    #expect(!PublicNetworkAddressPolicy.isTailnetIPv4(0xC0A8_0001))  // 192.168.0.1
    #expect(!PublicNetworkAddressPolicy.isTailnetIPv4(0x7F00_0001))  // 127.0.0.1
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
        to: url, timeout: fixtureNavigationTimeout, quietWindow: .milliseconds(20))
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
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(20)
    )
    try await Task.sleep(for: .milliseconds(300))

    #expect(resolver.callCount() == 1)
    #expect(proxy.metricsSnapshot().pinnedHosts == 1)
    #expect(proxy.metricsSnapshot().acceptedConnections >= 1)
  }

  @Test("WKWebView routes an HTTPS TLS attempt through the pinned proxy")
  @MainActor
  func webKitHTTPSAttemptRouting() async throws {
    let destination = try FormFixtureServer()
    let resolver = ResolverProbe()
    let proxy = try PinnedSOCKSProxy { resolver.resolve($0) }
    let store = WKWebsiteDataStore.nonPersistent()
    store.proxyConfigurations = [proxy.proxyConfiguration()]
    let runtime = WebKitRuntime(websiteDataStore: store, egressProxy: proxy)

    _ = try await runtime.loadHTML(
      """
      <img src="https://rebind.test:\(destination.port)/tls-attempt">
      """,
      baseURL: URL(string: "https://fixture.invalid/")!,
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(20)
    )
    try await Task.sleep(for: .milliseconds(300))

    #expect(resolver.callCount() == 1)
    #expect(proxy.metricsSnapshot().pinnedHosts == 1)
    #expect(proxy.metricsSnapshot().acceptedConnections >= 1)
  }

  @Test("WKWebView routes a WebSocket handshake attempt through the pinned proxy")
  @MainActor
  func webKitWebSocketAttemptRouting() async throws {
    let destination = try FormFixtureServer()
    let resolver = ResolverProbe()
    let proxy = try PinnedSOCKSProxy { resolver.resolve($0) }
    let store = WKWebsiteDataStore.nonPersistent()
    store.proxyConfigurations = [proxy.proxyConfiguration()]
    let runtime = WebKitRuntime(websiteDataStore: store, egressProxy: proxy)

    _ = try await runtime.loadHTML(
      """
      <script>
        const socket = new WebSocket('ws://rebind.test:\(destination.port)/socket-attempt');
        socket.onerror = () => { document.title = 'websocket-attempted'; };
      </script>
      """,
      baseURL: URL(string: "http://fixture.invalid/")!,
      timeout: fixtureNavigationTimeout,
      quietWindow: .milliseconds(20)
    )
    try await Task.sleep(for: .milliseconds(300))

    #expect(resolver.callCount() == 1)
    #expect(proxy.metricsSnapshot().pinnedHosts == 1)
    #expect(proxy.metricsSnapshot().acceptedConnections >= 1)
  }
}

private func waitUntil(
  timeout: Duration = .seconds(2),
  condition: @escaping @Sendable () -> Bool
) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while !condition() {
    guard clock.now < deadline else { throw POSIXError(.ETIMEDOUT) }
    try await Task.sleep(for: .milliseconds(10))
  }
}

private func openProxyConnection(port: UInt16) throws -> Int32 {
  let descriptor = socket(AF_INET, SOCK_STREAM, 0)
  guard descriptor >= 0 else { throw POSIXError(.ENOTCONN) }
  var address = sockaddr_in()
  address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
  address.sin_family = sa_family_t(AF_INET)
  address.sin_port = port.bigEndian
  inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)
  let connected = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
  }
  guard connected == 0 else {
    close(descriptor)
    throw POSIXError(.ECONNREFUSED)
  }
  return descriptor
}

private func socketTimeout(_ option: Int32, descriptor: Int32) throws -> timeval {
  var timeout = timeval()
  var length = socklen_t(MemoryLayout<timeval>.size)
  let result = withUnsafeMutablePointer(to: &timeout) {
    getsockopt(descriptor, SOL_SOCKET, option, $0, &length)
  }
  guard result == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
  return timeout
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
