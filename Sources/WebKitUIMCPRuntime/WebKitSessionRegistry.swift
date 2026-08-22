import Foundation

public struct WebKitSessionHandle: Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }
}

public struct WebKitSessionStatus: Codable, Equatable, Sendable {
  public let sessionID: UUID
  public let currentURL: String?
  public let isLoading: Bool
}

public enum WebKitSessionRegistryError: Error, Equatable, Sendable {
  case invalidMaximumSessions
  case capacityReached
  case unknownSession
  case networkBoundaryUnavailable
}

@MainActor
public final class WebKitSessionRegistry {
  public let maximumSessions: Int
  private var sessions: [WebKitSessionHandle: WebKitRuntime] = [:]

  public init(maximumSessions: Int = 1) throws {
    guard maximumSessions > 0 else { throw WebKitSessionRegistryError.invalidMaximumSessions }
    self.maximumSessions = maximumSessions
  }

  public var count: Int { sessions.count }

  public func open() throws -> WebKitSessionHandle {
    guard sessions.count < maximumSessions else {
      throw WebKitSessionRegistryError.capacityReached
    }
    let handle = WebKitSessionHandle(rawValue: UUID())
    do {
      sessions[handle] = try WebKitRuntime(protectedWebsiteDataStore: .default())
    } catch {
      throw WebKitSessionRegistryError.networkBoundaryUnavailable
    }
    return handle
  }

  public func close(_ handle: WebKitSessionHandle) throws {
    guard sessions.removeValue(forKey: handle) != nil else {
      throw WebKitSessionRegistryError.unknownSession
    }
  }

  public func runtime(for handle: WebKitSessionHandle) throws -> WebKitRuntime {
    guard let runtime = sessions[handle] else {
      throw WebKitSessionRegistryError.unknownSession
    }
    return runtime
  }

  public func status(_ handle: WebKitSessionHandle) throws -> WebKitSessionStatus {
    let runtime = try runtime(for: handle)
    return WebKitSessionStatus(
      sessionID: handle.rawValue,
      currentURL: runtime.webView.url?.absoluteString,
      isLoading: runtime.webView.isLoading
    )
  }
}
