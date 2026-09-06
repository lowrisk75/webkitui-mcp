import Foundation

enum GoalDelegationDenial: String, Equatable, Sendable {
  case expired
  case exhausted
  case originMismatch = "origin_mismatch"
  case pathOutsideScope = "path_outside_scope"
  case queryKeyOutsideScope = "query_key_outside_scope"
  case consequentialDestination = "consequential_destination"
}

enum GoalDelegationDecision: Equatable, Sendable {
  case allowed
  case denied(GoalDelegationDenial)
}

/// A local, session-owned navigation grant. `goalDisplay` is explanatory only;
/// the typed origin, path, query, expiry, and count fields are the authority.
struct GoalDelegation: Equatable, Sendable {
  let identifier: String
  let goalDisplay: String
  let scheme: String
  let host: String
  let port: Int
  let pathPrefixes: [String]
  let allowedQueryKeys: Set<String>
  let issuedAt: Date
  let expiresAt: Date
  private(set) var remainingNavigations: Int

  init(
    identifier: String = UUID().uuidString,
    goalDisplay: String,
    origin: URL,
    pathPrefixes: [String],
    allowedQueryKeys: Set<String>,
    issuedAt: Date,
    expiresAt: Date,
    maximumNavigations: Int
  ) throws {
    guard
      let scheme = origin.scheme?.lowercased(),
      let host = origin.host?.lowercased(),
      ["http", "https"].contains(scheme),
      origin.user == nil,
      origin.password == nil,
      origin.path.isEmpty || origin.path == "/",
      origin.query == nil,
      origin.fragment == nil,
      !goalDisplay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      goalDisplay.count <= 200,
      !pathPrefixes.isEmpty,
      maximumNavigations > 0,
      expiresAt > issuedAt
    else { throw GoalDelegationValidationError.invalidScope }

    let normalizedPrefixes = try pathPrefixes.map(Self.normalizedPathPrefix)
    let normalizedQueryKeys = Set(try allowedQueryKeys.map(Self.normalizedQueryKey))
    self.identifier = identifier
    self.goalDisplay = goalDisplay
    self.scheme = scheme
    self.host = host
    self.port = origin.port ?? (scheme == "https" ? 443 : 80)
    self.pathPrefixes = Array(Set(normalizedPrefixes)).sorted()
    self.allowedQueryKeys = normalizedQueryKeys
    self.issuedAt = issuedAt
    self.expiresAt = expiresAt
    self.remainingNavigations = maximumNavigations
  }

  var originDisplay: String {
    let defaultPort = scheme == "https" ? 443 : 80
    return port == defaultPort ? "\(scheme)://\(host)" : "\(scheme)://\(host):\(port)"
  }

  mutating func authorizeNavigation(to url: URL, now: Date) -> GoalDelegationDecision {
    guard now < expiresAt else { return .denied(.expired) }
    guard remainingNavigations > 0 else { return .denied(.exhausted) }
    guard
      url.scheme?.lowercased() == scheme,
      url.host?.lowercased() == host,
      (url.port ?? (scheme == "https" ? 443 : 80)) == port,
      url.user == nil,
      url.password == nil
    else { return .denied(.originMismatch) }

    let path = Self.repeatedlyRemovingPercentEncoding(url.path)
    guard pathPrefixes.contains(where: { Self.path(path, isWithin: $0) }) else {
      return .denied(.pathOutsideScope)
    }
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    guard items.allSatisfy({ allowedQueryKeys.contains($0.name.lowercased()) }) else {
      return .denied(.queryKeyOutsideScope)
    }
    let securityText = ([path] + items.flatMap { [$0.name, $0.value ?? ""] })
      .map(Self.repeatedlyRemovingPercentEncoding)
      .joined(separator: " ")
      .lowercased()
    guard !Self.containsConsequentialTerm(securityText) else {
      return .denied(.consequentialDestination)
    }

    remainingNavigations -= 1
    return .allowed
  }

  private static func normalizedPathPrefix(_ value: String) throws -> String {
    guard
      value.hasPrefix("/"), value.count <= 1_024,
      !value.contains("?"), !value.contains("#"), !value.contains("\\"),
      !value.split(separator: "/").contains("..")
    else { throw GoalDelegationValidationError.invalidScope }
    let decoded = repeatedlyRemovingPercentEncoding(value)
    guard decoded.hasPrefix("/"), !decoded.split(separator: "/").contains("..") else {
      throw GoalDelegationValidationError.invalidScope
    }
    return decoded.count > 1 && decoded.hasSuffix("/") ? String(decoded.dropLast()) : decoded
  }

  private static func normalizedQueryKey(_ value: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard
      !normalized.isEmpty, normalized.count <= 128,
      normalized.unicodeScalars.allSatisfy({
        CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-.")).contains($0)
      }),
      !containsConsequentialTerm(normalized)
    else { throw GoalDelegationValidationError.invalidScope }
    return normalized
  }

  private static func path(_ path: String, isWithin prefix: String) -> Bool {
    prefix == "/" || path == prefix || path.hasPrefix(prefix + "/")
  }

  private static func repeatedlyRemovingPercentEncoding(_ value: String) -> String {
    var current = value
    for _ in 0..<3 {
      guard let decoded = current.removingPercentEncoding, decoded != current else { break }
      current = decoded
    }
    return current
  }

  private static func containsConsequentialTerm(_ value: String) -> Bool {
    let folded = value.lowercased().unicodeScalars.map {
      CharacterSet.alphanumerics.contains($0) ? Character($0) : " "
    }
    let words = String(folded).split(whereSeparator: \Character.isWhitespace).map(String.init)
    let joined = words.joined()
    let terms = [
      "apikey", "token", "secret", "credential", "password", "passkey",
      "payment", "billing", "checkout", "purchase", "permission", "consent",
      "delete", "remove", "revoke", "upload", "publish", "submit", "send",
      "message", "invite", "production", "deploy", "release",
    ]
    return terms.contains { term in words.contains(term) || joined.contains(term) }
  }
}

enum GoalDelegationValidationError: Error, Equatable {
  case invalidScope
}
