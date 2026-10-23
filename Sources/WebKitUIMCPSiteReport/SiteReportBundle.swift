import CryptoKit
import Foundation

/// What the Status window collects before a report is written. Every field is already
/// reduced to what may leave the Mac; the bundle only arranges it.
public struct SiteReportInput: Sendable {
  /// The page's scheme and host, from `WebKitRuntime.agentSafeCurrentOrigin()`. Never a
  /// path, query, fragment, title or credentials.
  public let origin: String
  public let reason: SiteReportReason
  /// The person's own words. Carried as `user_description`.
  public let userDescription: String
  /// The visible label the person typed to point at the control, echoed back only as
  /// the thing the shape was taken around. May be empty.
  public let label: String
  /// `BrowserLoadDiagnostics` encoded as JSON by the runtime: counters only.
  public let diagnosticsJSON: Data
  /// `BrowserDOMShape` encoded as JSON by the runtime: tags, roles and attribute names
  /// around the label, never values. Nil when no label was given.
  public let domShapeJSON: Data?
  public let appVersion: String
  public let appBuild: String
  public let osVersion: String
  public let locale: String?
  public let occurredAt: Date

  public init(
    origin: String, reason: SiteReportReason, userDescription: String, label: String,
    diagnosticsJSON: Data, domShapeJSON: Data?, appVersion: String, appBuild: String,
    osVersion: String, locale: String?, occurredAt: Date = Date()
  ) {
    self.origin = origin
    self.reason = reason
    self.userDescription = userDescription
    self.label = label
    self.diagnosticsJSON = diagnosticsJSON
    self.domShapeJSON = domShapeJSON
    self.appVersion = appVersion
    self.appBuild = appBuild
    self.osVersion = osVersion
    self.locale = locale
    self.occurredAt = occurredAt
  }
}

public enum SiteReportError: Error, Equatable {
  /// The origin given was not a bare scheme://host[:port]. The bundle refuses rather
  /// than trims, because a trimmed path is a path that was there.
  case originNotBare(String)
  case descriptionTooLong(Int)
  case labelTooLong(Int)
  case artifactTooLarge(String)
}

/// The files a report consists of, ready to be reviewed and attached to a mail.
public struct SiteReportBundle: Equatable, Sendable {
  public static let maximumDescriptionCharacters = 2_000
  public static let maximumLabelCharacters = 200
  public static let maximumArtifactBytes = 65_536
  public static let envelopeFilename = "webkitui-site-report.json"
  public static let diagnosticsFilename = "load-diagnostics.json"
  public static let domShapeFilename = "dom-shape.json"

  public let envelope: SiteReportEnvelope
  public let envelopeJSON: Data
  /// Filename to bytes, in the order they are attached.
  public let artifacts: [(filename: String, data: Data)]

  public static func == (lhs: SiteReportBundle, rhs: SiteReportBundle) -> Bool {
    lhs.envelopeJSON == rhs.envelopeJSON
      && lhs.artifacts.map(\.filename) == rhs.artifacts.map(\.filename)
      && lhs.artifacts.map(\.data) == rhs.artifacts.map(\.data)
  }

  public static func make(_ input: SiteReportInput, reportID: UUID = UUID()) throws
    -> SiteReportBundle
  {
    guard Self.isBareOrigin(input.origin) else {
      throw SiteReportError.originNotBare(input.origin)
    }
    let description = input.userDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    guard description.count <= maximumDescriptionCharacters else {
      throw SiteReportError.descriptionTooLong(description.count)
    }
    let label = input.label.trimmingCharacters(in: .whitespacesAndNewlines)
    guard label.count <= maximumLabelCharacters else {
      throw SiteReportError.labelTooLong(label.count)
    }

    var artifactFiles: [(filename: String, data: Data)] = [
      (diagnosticsFilename, input.diagnosticsJSON)
    ]
    if let shape = input.domShapeJSON { artifactFiles.append((domShapeFilename, shape)) }
    for file in artifactFiles where file.data.count > maximumArtifactBytes {
      throw SiteReportError.artifactTooLarge(file.filename)
    }
    let artifacts = artifactFiles.map { file in
      SiteReportArtifact(
        id: UUID(), filename: file.filename, mediaType: "application/json",
        sizeBytes: file.data.count, sha256: Self.hex(SHA256.hash(data: file.data)),
        category: "system_diagnostics",
        retentionDays: SiteReportContract.artifactRetentionDays)
    }

    // Schema 2 structured context: fixed field names, bounded token values only.
    let structured: [String: String] = [
      "component": "native_webkit",
      "operation": label.isEmpty ? "observe" : "observe_label",
      "error_code": input.reason.rawValue,
    ]
    let categories = structured.keys.reduce(into: [String: String]()) {
      $0[$1] = "system_diagnostics"
    }

    let envelope = SiteReportEnvelope(
      version: SiteReportContract.schemaVersion,
      clientReportID: reportID,
      occurredAt: input.occurredAt,
      source: SiteReportContract.source,
      kind: SiteReportContract.kind,
      title: "WebKitUI MCP: \(input.reason.rawValue) on \(input.origin)",
      description: description.isEmpty ? "(no description)" : description,
      expectedResult: nil,
      actualResult: label.isEmpty ? nil : "Visible label the agent needed: \(label)",
      reproductionSteps: [],
      app: SiteReportAppContext(
        appVersion: input.appVersion, appBuild: input.appBuild, osVersion: input.osVersion,
        locale: input.locale),
      structuredContext: structured,
      contextCategories: categories,
      artifacts: artifacts,
      consent: SiteReportConsent(grantedAt: input.occurredAt),
      reporter: nil)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    let json = try encoder.encode(envelope)
    return SiteReportBundle(envelope: envelope, envelopeJSON: json, artifacts: artifactFiles)
  }

  /// `scheme://host` or `scheme://host:port`, lowercase, nothing else.
  public static func isBareOrigin(_ value: String) -> Bool {
    let pattern = #"^https?://[a-z0-9.-]+(:[0-9]{1,5})?$"#
    return value.range(of: pattern, options: .regularExpression) != nil
  }

  /// Writes the files into `directory` with owner-only permissions and returns them in
  /// attachment order, envelope first.
  public func write(into directory: URL) throws -> [URL] {
    let manager = FileManager.default
    try manager.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    var urls: [URL] = []
    for (name, data) in [(Self.envelopeFilename, envelopeJSON)] + artifacts {
      let url = directory.appendingPathComponent(name)
      try data.write(to: url, options: .atomic)
      try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
      urls.append(url)
    }
    return urls
  }

  /// The mail body: the envelope the person is about to send, so what is on screen is
  /// what leaves.
  public var mailBody: String {
    let text = String(decoding: envelopeJSON, as: UTF8.self)
    return """
      WebKitUI MCP site report \(envelope.clientReportID.uuidString)

      Origin: \(envelope.title)
      Attached: \(([Self.envelopeFilename] + artifacts.map(\.filename)).joined(separator: ", "))

      \(text)
      """
  }

  private static func hex(_ digest: SHA256Digest) -> String {
    digest.map { String(format: "%02x", $0) }.joined()
  }
}
