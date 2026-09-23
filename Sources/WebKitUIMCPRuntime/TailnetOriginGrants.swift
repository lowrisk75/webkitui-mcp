import Foundation

/// Exact Tailscale origins a person allowed this app to reach, by host and port.
///
/// The protected browser never connects to private address space: that is what keeps
/// a steered agent from probing a home network. A tailnet service the owner runs —
/// Home Assistant on a `.ts.net` name, say — is the one private destination worth
/// opening, and only this way: one exact origin, after a native confirmation, only to
/// Tailscale's 100.64.0.0/10 range, pinned against rebinding like any public name,
/// and forgotten when the app quits. Every other private range stays refused.
public final class TailnetOriginGrants: @unchecked Sendable {
  public static let shared = TailnetOriginGrants()

  private let lock = NSLock()
  private var granted: Set<String> = []

  public init() {}

  public func grant(host: String, port: UInt16) {
    lock.withLock { _ = granted.insert(Self.key(host: host, port: port)) }
  }

  public func isGranted(host: String, port: UInt16) -> Bool {
    lock.withLock { granted.contains(Self.key(host: host, port: port)) }
  }

  public func revokeAll() {
    lock.withLock { granted.removeAll() }
  }

  public var grantCount: Int { lock.withLock { granted.count } }

  static func key(host: String, port: UInt16) -> String {
    "\(host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))):\(port)"
  }
}
