import Foundation

/// Proposed owner-side broker fix. The sink's exact origin/binding never changes.
enum AppleCredentialOriginMatching {
  private static let signInSites: Set<String> = [
    "idmsa.apple.com", "appleid.apple.com", "account.apple.com",
    "developer.apple.com", "appstoreconnect.apple.com",
  ]
  private static let savedAccountSites = signInSites.union(["apple.com", "www.apple.com"])

  static func matches(savedURL: URL, scheme: String, host: String, port: UInt16) -> Bool {
    guard let savedScheme = savedURL.scheme?.lowercased(),
      let savedHost = savedURL.host?.lowercased()
    else { return false }
    let savedPort = savedURL.port ?? (savedScheme == "https" ? 443 : 80)
    if savedScheme == scheme && savedHost == host && savedPort == Int(port) { return true }
    // Explicit Apple Account relationships only. Never infer a relationship from
    // an email address, title, substring or an arbitrary apple.com subdomain.
    return scheme == "https" && savedScheme == "https"
      && port == 443 && savedPort == 443
      && savedURL.user == nil && savedURL.password == nil
      && signInSites.contains(host) && savedAccountSites.contains(savedHost)
  }
}
