import Darwin
import Foundation

public enum PublicNetworkAddressPolicyError: Error, Equatable, Sendable {
  case invalidHost
  case localName
  case noPublicAddress
}

public struct ResolvedPublicAddress: Equatable, Sendable {
  public let host: String
  public let address: String

  public init(host: String, address: String) {
    self.host = host
    self.address = address
  }
}

public struct PublicNetworkAddressPolicy: Sendable {
  public init() {}

  public func resolve(_ rawHost: String) throws -> ResolvedPublicAddress {
    let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    guard !host.isEmpty else { throw PublicNetworkAddressPolicyError.invalidHost }
    guard host != "localhost", !host.hasSuffix(".localhost"), !host.hasSuffix(".local") else {
      throw PublicNetworkAddressPolicyError.localName
    }

    var hints = addrinfo()
    hints.ai_flags = AI_ADDRCONFIG
    hints.ai_family = AF_UNSPEC
    hints.ai_socktype = SOCK_STREAM
    var result: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else {
      throw PublicNetworkAddressPolicyError.invalidHost
    }
    defer { freeaddrinfo(first) }

    var cursor: UnsafeMutablePointer<addrinfo>? = first
    while let info = cursor?.pointee {
      defer { cursor = info.ai_next }
      guard let address = info.ai_addr, isPublic(address: address, family: info.ai_family) else {
        continue
      }
      var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      guard
        getnameinfo(
          address, info.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0
      else { continue }
      let end = buffer.firstIndex(of: 0) ?? buffer.endIndex
      return ResolvedPublicAddress(
        host: host,
        address: String(decoding: buffer[..<end].map(UInt8.init(bitPattern:)), as: UTF8.self)
      )
    }
    throw PublicNetworkAddressPolicyError.noPublicAddress
  }

  public func isPublicIPAddress(_ text: String) -> Bool {
    var ipv4 = in_addr()
    if inet_pton(AF_INET, text, &ipv4) == 1 {
      return isPublicIPv4(UInt32(bigEndian: ipv4.s_addr))
    }
    var ipv6 = in6_addr()
    if inet_pton(AF_INET6, text, &ipv6) == 1 {
      return withUnsafeBytes(of: &ipv6) { isPublicIPv6(Array($0)) }
    }
    return false
  }

  public func validateNavigationHost(_ rawHost: String) throws {
    let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    guard !host.isEmpty else { throw PublicNetworkAddressPolicyError.invalidHost }
    guard host != "localhost", !host.hasSuffix(".localhost"), !host.hasSuffix(".local") else {
      throw PublicNetworkAddressPolicyError.localName
    }
    var ipv4 = in_addr()
    if inet_aton(host, &ipv4) != 0 {
      guard isPublicIPv4(UInt32(bigEndian: ipv4.s_addr)) else {
        throw PublicNetworkAddressPolicyError.noPublicAddress
      }
      return
    }
    var ipv6 = in6_addr()
    if inet_pton(AF_INET6, host, &ipv6) == 1 {
      let allowed = withUnsafeBytes(of: &ipv6) { isPublicIPv6(Array($0)) }
      guard allowed else { throw PublicNetworkAddressPolicyError.noPublicAddress }
    }
  }

  private func isPublic(address: UnsafePointer<sockaddr>, family: Int32) -> Bool {
    if family == AF_INET {
      let value = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
        UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
      }
      return isPublicIPv4(value)
    }
    if family == AF_INET6 {
      let value = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
        $0.pointee.sin6_addr
      }
      var copy = value
      return withUnsafeBytes(of: &copy) { isPublicIPv6(Array($0)) }
    }
    return false
  }

  private func isPublicIPv4(_ value: UInt32) -> Bool {
    let blocked: [(UInt32, UInt32)] = [
      (0x0000_0000, 0xFF00_0000), (0x0A00_0000, 0xFF00_0000),
      (0x6440_0000, 0xFFC0_0000), (0x7F00_0000, 0xFF00_0000),
      (0xA9FE_0000, 0xFFFF_0000), (0xAC10_0000, 0xFFF0_0000),
      (0xC000_0000, 0xFFFF_FF00), (0xC000_0200, 0xFFFF_FF00),
      (0xC0A8_0000, 0xFFFF_0000), (0xC612_0000, 0xFFFE_0000),
      (0xC633_6400, 0xFFFF_FF00), (0xCB00_7100, 0xFFFF_FF00),
      (0xE000_0000, 0xF000_0000), (0xF000_0000, 0xF000_0000),
    ]
    return !blocked.contains { value & $0.1 == $0.0 }
  }

  private func isPublicIPv6(_ bytes: [UInt8]) -> Bool {
    guard bytes.count == 16 else { return false }
    if bytes.prefix(12) == Array(repeating: 0, count: 10) + [0xFF, 0xFF] {
      let value = bytes.suffix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
      return isPublicIPv4(value)
    }
    let globalUnicast = (bytes[0] & 0xE0) == 0x20
    let documentation = bytes[0...3].elementsEqual([0x20, 0x01, 0x0D, 0xB8])
    return globalUnicast && !documentation
  }
}
