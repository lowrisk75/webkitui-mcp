import Foundation

/// A voluntary report about a site the agent could not drive, in the exact JSON shape of
/// LorisReports `ReportEnvelope` schema version 2 (LorisLabsKit), so the same support
/// tooling reads it. The LorisReports package itself is not a dependency: its manifest
/// pulls a private package, which a source-available product cannot ask its builders
/// to resolve. The contract is the JSON, pinned by `SiteReportContract`.
///
/// Nothing here reaches the network. A report is files on disk that the person reviews
/// and sends themselves; see `SiteReportBundle`.
public enum SiteReportContract {
  public static let schemaVersion = 2
  public static let appID = "webkitui-mcp"
  public static let source = "app_api"
  public static let kind = "bug"
  public static let platform = "macos"
  /// Bumped whenever the notice text in docs/privacy-retention.md changes.
  public static let noticeVersion = "2026-10-22"
  public static let supportAddress = "support@lorislab.fr"
  /// Exactly the LorisReports category raw values this product may ever put in a report.
  public static let consentCategories = ["app_metadata", "system_diagnostics", "user_description"]
  public static let artifactRetentionDays = 90
}

/// Why the person is reporting, as a closed list. The raw value is the LorisReports
/// `error_code` context field, which admits only `[a-zA-Z0-9_.-]{1,64}`.
public enum SiteReportReason: String, CaseIterable, Codable, Sendable {
  case controlNotObserved = "control_not_observed"
  case postconditionRefused = "postcondition_refused"
  case pageEmptyOrNotLoading = "page_empty_or_not_loading"
  case confirmationProblem = "confirmation_problem"
  case other = "other"
}

public struct SiteReportAppContext: Codable, Equatable, Sendable {
  public let appID: String
  public let appVersion: String
  public let appBuild: String
  public let platform: String
  public let osVersion: String
  public let locale: String?

  public init(appVersion: String, appBuild: String, osVersion: String, locale: String?) {
    appID = SiteReportContract.appID
    self.appVersion = appVersion
    self.appBuild = appBuild
    platform = SiteReportContract.platform
    self.osVersion = osVersion
    self.locale = locale
  }

  enum CodingKeys: String, CodingKey {
    case appID = "app_id"
    case appVersion = "app_version"
    case appBuild = "app_build"
    case platform
    case osVersion = "os_version"
    case locale
  }
}

public struct SiteReportConsent: Codable, Equatable, Sendable {
  public let noticeVersion: String
  public let grantedAt: Date
  public let categories: [String]
  public let remoteAIAllowed: Bool

  public init(grantedAt: Date) {
    noticeVersion = SiteReportContract.noticeVersion
    self.grantedAt = grantedAt
    categories = SiteReportContract.consentCategories
    remoteAIAllowed = false
  }

  enum CodingKeys: String, CodingKey {
    case noticeVersion = "notice_version"
    case grantedAt = "granted_at"
    case categories
    case remoteAIAllowed = "remote_ai_allowed"
  }
}

public struct SiteReportArtifact: Codable, Equatable, Sendable {
  public let id: UUID
  public let filename: String
  public let mediaType: String
  public let sizeBytes: Int
  public let sha256: String
  public let category: String
  public let retentionDays: Int

  enum CodingKeys: String, CodingKey {
    case id = "artifact_id"
    case filename
    case mediaType = "media_type"
    case sizeBytes = "size_bytes"
    case sha256, category
    case retentionDays = "retention_days"
  }
}

public struct SiteReportEnvelope: Codable, Equatable, Sendable {
  public let version: Int
  public let clientReportID: UUID
  public let occurredAt: Date
  public let source: String
  public let kind: String
  public let title: String
  public let description: String
  public let expectedResult: String?
  public let actualResult: String?
  public let reproductionSteps: [String]
  public let app: SiteReportAppContext
  public let structuredContext: [String: String]
  public let contextCategories: [String: String]
  public let artifacts: [SiteReportArtifact]
  public let consent: SiteReportConsent
  /// Always absent: schema 2 forbids an unverified contact, and this product never
  /// collects an address. The sender's own mail client carries their identity.
  public let reporter: String?

  enum CodingKeys: String, CodingKey {
    case version = "schema_version"
    case clientReportID = "client_report_id"
    case occurredAt = "occurred_at"
    case source, kind, title, description
    case expectedResult = "expected_result"
    case actualResult = "actual_result"
    case reproductionSteps = "reproduction_steps"
    case app
    case structuredContext = "structured_context"
    case contextCategories = "context_categories"
    case artifacts, consent, reporter
  }
}
