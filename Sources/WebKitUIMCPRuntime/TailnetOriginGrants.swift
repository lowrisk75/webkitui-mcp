import Foundation
import WebKit

extension Notification.Name {
  /// Posted on the main queue whenever the set of granted tailnet origins changes.
  public static let webKitUITailnetGrantsChanged = Notification.Name(
    "com.lorislab.webkitui-mcp.tailnet-grants-changed")
}

/// Exact Tailscale origins a person allowed this app to reach, by host and port.
///
/// The protected browser never connects to private address space: that is what keeps
/// a steered agent from probing a home network. A tailnet service the owner runs —
/// Home Assistant on a `.ts.net` name, say — is the one private destination worth
/// opening, and only this way: one exact origin, after a native confirmation, only to
/// Tailscale's 100.64.0.0/10 range, pinned against rebinding like any public name,
/// and forgotten when the app quits. Every other private range stays refused.
///
/// The proxy sees host and port, not who asked. So that a page on another origin —
/// in any session — cannot reach a granted service through the grant (a forged form
/// post or fetch against a home service), every runtime also installs a content rule
/// that blocks loads of a granted origin unless the top-level page is that origin.
public final class TailnetOriginGrants: @unchecked Sendable {
  public static let shared = TailnetOriginGrants()

  private let lock = NSLock()
  private var granted: Set<String> = []

  public init() {}

  public func grant(host: String, port: UInt16) {
    let inserted = lock.withLock { granted.insert(Self.key(host: host, port: port)).inserted }
    if inserted, self === Self.shared { Self.announce() }
  }

  public func isGranted(host: String, port: UInt16) -> Bool {
    lock.withLock { granted.contains(Self.key(host: host, port: port)) }
  }

  public func revokeAll() {
    let changed = lock.withLock {
      defer { granted.removeAll() }
      return !granted.isEmpty
    }
    if changed, self === Self.shared { Self.announce() }
  }

  public var grantCount: Int { lock.withLock { granted.count } }

  /// Granted origins as (host, port), sorted, for building the content rule.
  public func origins() -> [(host: String, port: UInt16)] {
    lock.withLock { granted.sorted() }.compactMap { key in
      guard let separator = key.lastIndex(of: ":"),
        let port = UInt16(key[key.index(after: separator)...])
      else { return nil }
      return (String(key[..<separator]), port)
    }
  }

  static func key(host: String, port: UInt16) -> String {
    "\(host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))):\(port)"
  }

  private static func announce() {
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: .webKitUITailnetGrantsChanged, object: nil)
    }
  }

  /// WebKit content rules: block each granted origin unless it is the top-level page.
  static func contentRuleJSON(for origins: [(host: String, port: UInt16)]) -> String? {
    guard !origins.isEmpty else { return nil }
    let rules: [[String: Any]] = origins.map { origin in
      let host = NSRegularExpression.escapedPattern(for: origin.host)
      let port = origin.port == 443 || origin.port == 80 ? "(:\(origin.port))?" : ":\(origin.port)"
      let pattern = "^https?://\(host)\(port)[/?#]"
      return [
        "trigger": ["url-filter": pattern, "unless-top-url": [pattern]],
        "action": ["type": "block"],
      ]
    }
    guard let data = try? JSONSerialization.data(withJSONObject: rules) else { return nil }
    return String(decoding: data, as: UTF8.self)
  }
}
