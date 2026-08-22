import Darwin
import Foundation
import Network

public struct PinnedProxyMetrics: Codable, Equatable, Sendable {
  public var acceptedConnections = 0
  public var blockedConnections = 0
  public var pinnedHosts = 0
}

public final class PinnedSOCKSProxy: @unchecked Sendable {
  private let queue = DispatchQueue(label: "WebKitUIMCP.PinnedSOCKSProxy")
  private let listener: NWListener
  private let resolver: @Sendable (String) throws -> ResolvedPublicAddress
  private var pins: [String: String] = [:]
  private var metrics = PinnedProxyMetrics()
  private var activeConnections: [ObjectIdentifier: SOCKSConnection] = [:]
  public private(set) var port: NWEndpoint.Port = .any

  public convenience init() throws {
    let policy = PublicNetworkAddressPolicy()
    try self.init { try policy.resolve($0) }
  }

  init(resolver: @escaping @Sendable (String) throws -> ResolvedPublicAddress) throws {
    self.resolver = resolver
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    listener = try NWListener(using: parameters)
    listener.newConnectionHandler = { [weak self] connection in
      guard let self else {
        connection.cancel()
        return
      }
      let handler = SOCKSConnection(client: connection, proxy: self)
      self.activeConnections[ObjectIdentifier(handler)] = handler
      handler.start(on: self.queue)
    }
    let ready = DispatchSemaphore(value: 0)
    listener.stateUpdateHandler = { state in
      switch state {
      case .ready: ready.signal()
      case .failed: ready.signal()
      default: break
      }
    }
    listener.start(queue: queue)
    guard ready.wait(timeout: .now() + 2) == .success, let assignedPort = listener.port
    else {
      listener.cancel()
      throw CocoaError(.coderReadCorrupt)
    }
    port = assignedPort
  }

  deinit { listener.cancel() }

  public func proxyConfiguration() -> ProxyConfiguration {
    var configuration = ProxyConfiguration(
      socksv5Proxy: .hostPort(host: "127.0.0.1", port: port))
    configuration.allowFailover = false
    return configuration
  }

  public func metricsSnapshot() -> PinnedProxyMetrics {
    queue.sync { metrics }
  }

  fileprivate func pinnedAddress(for host: String) throws -> String {
    let normalized = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    if let existing = pins[normalized] { return existing }
    let resolved = try resolver(normalized)
    pins[normalized] = resolved.address
    metrics.pinnedHosts = pins.count
    return resolved.address
  }

  fileprivate func recordAccepted() { metrics.acceptedConnections += 1 }
  fileprivate func recordBlocked() { metrics.blockedConnections += 1 }
  fileprivate func release(_ connection: SOCKSConnection) {
    activeConnections.removeValue(forKey: ObjectIdentifier(connection))
  }
}

private final class SOCKSConnection: @unchecked Sendable {
  private enum State { case greeting, request, connecting, relaying, closed }

  private let client: NWConnection
  private let proxy: PinnedSOCKSProxy
  private var state: State = .greeting
  private var buffer = Data()
  private var queue: DispatchQueue!

  init(client: NWConnection, proxy: PinnedSOCKSProxy) {
    self.client = client
    self.proxy = proxy
  }

  func start(on queue: DispatchQueue) {
    self.queue = queue
    client.stateUpdateHandler = { [weak self] state in
      if case .failed = state { self?.close() }
    }
    client.start(queue: queue)
    receiveHandshake()
  }

  private func receiveHandshake() {
    client.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
      [weak self] data, _, complete, error in
      guard let self else { return }
      if let data { self.buffer.append(data) }
      if error != nil || complete {
        self.close()
        return
      }
      self.consumeHandshake()
    }
  }

  private func consumeHandshake() {
    switch state {
    case .greeting:
      guard buffer.count >= 2 else { return receiveHandshake() }
      let methodCount = Int(buffer[1])
      guard buffer.count >= 2 + methodCount, buffer[0] == 5,
        buffer[2..<(2 + methodCount)].contains(0)
      else { return reject(method: true) }
      buffer = Data(buffer.dropFirst(2 + methodCount))
      state = .request
      client.send(
        content: Data([5, 0]),
        completion: .contentProcessed { [weak self] error in
          guard let self else { return }
          if error == nil { self.consumeHandshake() } else { self.close() }
        })
    case .request:
      guard buffer.count >= 4 else { return receiveHandshake() }
      guard buffer[0] == 5, buffer[1] == 1 else {
        proxy.recordBlocked()
        return reject(method: false)
      }
      guard let request = parseRequest() else { return receiveHandshake() }
      state = .connecting
      connect(host: request.host, port: request.port, trailing: request.trailing)
    default: break
    }
  }

  private func parseRequest() -> (host: String, port: UInt16, trailing: Data)? {
    let addressType = buffer[3]
    let addressStart = 4
    let addressLength: Int
    let host: String
    switch addressType {
    case 1:
      addressLength = 4
      guard buffer.count >= addressStart + addressLength + 2 else { return nil }
      host = buffer[addressStart..<(addressStart + 4)].map(String.init).joined(separator: ".")
    case 3:
      guard buffer.count >= 5 else { return nil }
      addressLength = Int(buffer[4])
      guard buffer.count >= 5 + addressLength + 2 else { return nil }
      host = String(decoding: buffer[5..<(5 + addressLength)], as: UTF8.self)
    case 4:
      addressLength = 16
      guard buffer.count >= addressStart + addressLength + 2 else { return nil }
      var bytes = Array(buffer[addressStart..<(addressStart + 16)])
      var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
      host = bytes.withUnsafeMutableBytes { raw in
        inet_ntop(AF_INET6, raw.baseAddress, &text, socklen_t(text.count))
          .map { _ in
            String(decoding: text.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
          }
          ?? ""
      }
    default:
      reject(method: false)
      return nil
    }
    let portOffset = addressType == 3 ? 5 + addressLength : addressStart + addressLength
    let port = UInt16(buffer[portOffset]) << 8 | UInt16(buffer[portOffset + 1])
    let consumed = portOffset + 2
    let trailing = Data(buffer.dropFirst(consumed))
    buffer.removeAll(keepingCapacity: false)
    return (host, port, trailing)
  }

  private func connect(host: String, port: UInt16, trailing: Data) {
    do {
      let address: String
      if PublicNetworkAddressPolicy().isPublicIPAddress(host) {
        address = host
      } else {
        address = try proxy.pinnedAddress(for: host)
      }
      guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return reject(method: false) }
      let remote = NWConnection(host: NWEndpoint.Host(address), port: endpointPort, using: .tcp)
      remote.stateUpdateHandler = { [weak self, weak remote] remoteState in
        guard let self, let remote else { return }
        switch remoteState {
        case .ready:
          self.proxy.recordAccepted()
          self.state = .relaying
          self.client.send(
            content: Data([5, 0, 0, 1, 0, 0, 0, 0, 0, 0]),
            completion: .contentProcessed { [weak self, weak remote] error in
              guard let self, let remote else { return }
              guard error == nil else { return self.close(remote: remote) }
              if !trailing.isEmpty {
                remote.send(content: trailing, completion: .contentProcessed { _ in })
              }
              self.relay(from: self.client, to: remote, peer: remote)
              self.relay(from: remote, to: self.client, peer: remote)
            })
        case .failed, .cancelled:
          if self.state == .connecting {
            self.reject(method: false, remote: remote)
          } else {
            self.close(remote: remote)
          }
        default: break
        }
      }
      remote.start(queue: queue)
    } catch {
      proxy.recordBlocked()
      reject(method: false)
    }
  }

  private func relay(from source: NWConnection, to destination: NWConnection, peer: NWConnection) {
    source.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
      [weak self] data, _, complete, error in
      guard let self else { return }
      guard error == nil, !complete else { return self.close(remote: peer) }
      guard let data, !data.isEmpty else {
        return self.relay(from: source, to: destination, peer: peer)
      }
      destination.send(
        content: data,
        completion: .contentProcessed { [weak self] sendError in
          guard let self else { return }
          if sendError == nil {
            self.relay(from: source, to: destination, peer: peer)
          } else {
            self.close(remote: peer)
          }
        })
    }
  }

  private func reject(method: Bool, remote: NWConnection? = nil) {
    guard state != .closed else { return }
    let response = method ? Data([5, 0xFF]) : Data([5, 2, 0, 1, 0, 0, 0, 0, 0, 0])
    client.send(
      content: response,
      completion: .contentProcessed { [weak self] _ in
        self?.close(remote: remote)
      })
  }

  private func close(remote: NWConnection? = nil) {
    guard state != .closed else { return }
    state = .closed
    client.cancel()
    remote?.cancel()
    proxy.release(self)
  }
}
