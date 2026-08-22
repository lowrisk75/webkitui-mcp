import Foundation
import WebKitUIMCPCore
import WebKitUIMCPRuntime

enum SessionAuthorizationAction: String, Codable, CaseIterable, Hashable, Sendable {
  case navigate
}

struct SessionAuthorizationGrant: Equatable, Sendable {
  let origin: SecurityOrigin
  let actions: Set<SessionAuthorizationAction>
  let expiresAt: Date
  var remainingUses: Int
}

enum SessionAuthorizationDecision: Equatable, Sendable {
  case allowed(remainingUses: Int)
  case denied
}

@MainActor
final class SessionAuthorizationStore {
  static let maximumGrantsPerSession = 16

  private var grants: [WebKitSessionHandle: [SecurityOrigin: SessionAuthorizationGrant]] = [:]

  func grant(
    session: WebKitSessionHandle,
    origin: SecurityOrigin,
    actions: Set<SessionAuthorizationAction>,
    expiresAt: Date,
    maximumUses: Int,
    now: Date = Date()
  ) throws {
    guard now < expiresAt, !actions.isEmpty, maximumUses > 0 else {
      throw SessionAuthorizationError.invalidGrant
    }
    prune(session: session, now: now)
    var sessionGrants = grants[session] ?? [:]
    guard sessionGrants[origin] != nil || sessionGrants.count < Self.maximumGrantsPerSession else {
      throw SessionAuthorizationError.tooManyGrants
    }
    sessionGrants[origin] = SessionAuthorizationGrant(
      origin: origin,
      actions: actions,
      expiresAt: expiresAt,
      remainingUses: maximumUses
    )
    grants[session] = sessionGrants
  }

  func consume(
    session: WebKitSessionHandle,
    origin: SecurityOrigin,
    action: SessionAuthorizationAction,
    now: Date = Date()
  ) -> SessionAuthorizationDecision {
    prune(session: session, now: now)
    guard var grant = grants[session]?[origin], grant.actions.contains(action) else {
      return .denied
    }
    grant.remainingUses -= 1
    if grant.remainingUses == 0 {
      grants[session]?.removeValue(forKey: origin)
    } else {
      grants[session]?[origin] = grant
    }
    return .allowed(remainingUses: grant.remainingUses)
  }

  func activeGrants(
    session: WebKitSessionHandle,
    now: Date = Date()
  ) -> [SessionAuthorizationGrant] {
    prune(session: session, now: now)
    return (grants[session] ?? [:]).values.sorted { lhs, rhs in
      Self.originString(lhs.origin) < Self.originString(rhs.origin)
    }
  }

  func revoke(session: WebKitSessionHandle, origin: SecurityOrigin? = nil) {
    guard let origin else {
      grants.removeValue(forKey: session)
      return
    }
    grants[session]?.removeValue(forKey: origin)
    if grants[session]?.isEmpty == true { grants.removeValue(forKey: session) }
  }

  static func originString(_ origin: SecurityOrigin) -> String {
    var result = "\(origin.scheme)://\(origin.host)"
    if let port = origin.port { result += ":\(port)" }
    return result
  }

  private func prune(session: WebKitSessionHandle, now: Date) {
    grants[session] = grants[session]?.filter {
      now < $0.value.expiresAt && $0.value.remainingUses > 0
    }
    if grants[session]?.isEmpty == true { grants.removeValue(forKey: session) }
  }
}

enum SessionAuthorizationError: Error, Equatable {
  case invalidGrant
  case tooManyGrants
}
