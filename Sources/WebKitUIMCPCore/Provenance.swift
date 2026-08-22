import Foundation

public enum ProvenanceClass: String, Codable, CaseIterable, Hashable, Sendable {
  case userIntent = "USER_INTENT"
  case userEnteredSiteData = "USER_ENTERED_SITE_DATA"
  case firstPartySiteContent = "FIRST_PARTY_SITE_CONTENT"
  case thirdPartyEmbed = "THIRD_PARTY_EMBED"
  case emailFromExternalSender = "EMAIL_FROM_EXTERNAL_SENDER"
  case advertisement = "ADVERTISEMENT"
  case toolResult = "TOOL_RESULT"
  case passwordOrSecret = "PASSWORD_OR_SECRET"
  case modelGenerated = "MODEL_GENERATED"
  case localTrustedPolicy = "LOCAL_TRUSTED_POLICY"
}

/// Structured identity avoids suffix or substring comparisons between origins.
public struct SecurityOrigin: Codable, Hashable, Sendable {
  public let scheme: String
  public let host: String
  public let port: Int?

  public init(scheme: String, host: String, port: Int? = nil) {
    self.scheme = scheme.lowercased()
    self.host = host.lowercased()
    self.port = port
  }
}

public struct ProvenanceSource: Codable, Hashable, Sendable {
  public let classification: ProvenanceClass
  public let documentID: String?
  public let frameID: String?
  public let securityOrigin: SecurityOrigin?

  public init(
    classification: ProvenanceClass,
    documentID: String? = nil,
    frameID: String? = nil,
    securityOrigin: SecurityOrigin? = nil
  ) {
    self.classification = classification
    self.documentID = documentID
    self.frameID = frameID
    self.securityOrigin = securityOrigin
  }

  fileprivate var canonicalOrderingKey: String {
    [
      classification.rawValue,
      documentID ?? "",
      frameID ?? "",
      securityOrigin?.scheme ?? "",
      securityOrigin?.host ?? "",
      securityOrigin?.port.map(String.init) ?? "",
    ].joined(separator: "\u{1F}")
  }
}

public enum ProvenanceTransformation: String, Codable, CaseIterable, Sendable {
  case htmlEntityDecode = "html_entity_decode"
  case whitespaceCollapse = "whitespace_collapse"
  case deterministicExtraction = "deterministic_extraction"
  case localModelSelection = "local_model_selection"
  case redaction = "redaction"
}

public enum ProvenanceError: Error, Equatable, Sendable {
  case emptySources
  case emptySegments
}

public struct ProvenancedTextSegment: Codable, Equatable, Sendable {
  public static let maximumRecordedTransformations = 8

  public let text: String
  public let sources: Set<ProvenanceSource>
  public let transformations: [ProvenanceTransformation]
  public let transformationHistoryTruncated: Bool

  public init(
    text: String,
    sources: Set<ProvenanceSource>,
    transformations: [ProvenanceTransformation] = [],
    transformationHistoryTruncated: Bool = false
  ) throws {
    guard !sources.isEmpty else { throw ProvenanceError.emptySources }

    let overflowed = transformations.count > Self.maximumRecordedTransformations
    self.text = text
    self.sources = sources
    self.transformations = Array(transformations.suffix(Self.maximumRecordedTransformations))
    self.transformationHistoryTruncated = transformationHistoryTruncated || overflowed
  }

  public var classifications: Set<ProvenanceClass> {
    Set(sources.map(\.classification))
  }

  public func transformed(
    by step: ProvenanceTransformation,
    _ operation: (String) -> String
  ) throws -> Self {
    try Self(
      text: operation(text),
      sources: sources,
      transformations: transformations + [step],
      transformationHistoryTruncated: transformationHistoryTruncated
    )
  }

  private enum CodingKeys: String, CodingKey {
    case text
    case sources
    case transformations
    case transformationHistoryTruncated = "transformation_history_truncated"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      text: container.decode(String.self, forKey: .text),
      sources: Set(container.decode([ProvenanceSource].self, forKey: .sources)),
      transformations: container.decode([ProvenanceTransformation].self, forKey: .transformations),
      transformationHistoryTruncated: container.decode(
        Bool.self,
        forKey: .transformationHistoryTruncated
      )
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(text, forKey: .text)
    try container.encode(
      sources.sorted { $0.canonicalOrderingKey < $1.canonicalOrderingKey },
      forKey: .sources
    )
    try container.encode(transformations, forKey: .transformations)
    try container.encode(
      transformationHistoryTruncated,
      forKey: .transformationHistoryTruncated
    )
  }
}

/// There is deliberately no unlabelled string initializer or flattening API.
public struct ProvenancedText: Codable, Equatable, Sendable {
  public let segments: [ProvenancedTextSegment]

  public init(segments: [ProvenancedTextSegment]) throws {
    guard !segments.isEmpty else { throw ProvenanceError.emptySegments }
    self.segments = segments
  }

  public init(text: String, source: ProvenanceSource) throws {
    try self.init(segments: [.init(text: text, sources: [source])])
  }

  public var classifications: Set<ProvenanceClass> {
    segments.reduce(into: Set<ProvenanceClass>()) { result, segment in
      result.formUnion(segment.classifications)
    }
  }

  public func appending(_ other: Self) throws -> Self {
    try Self(segments: segments + other.segments)
  }

  public func transformed(
    by step: ProvenanceTransformation,
    _ operation: (String) -> String
  ) throws -> Self {
    try Self(segments: try segments.map { try $0.transformed(by: step, operation) })
  }

  public func redactedForPlanner(replacement: String = "[REDACTED]") throws -> Self {
    try Self(
      segments: try segments.map { segment in
        guard segment.classifications.contains(.passwordOrSecret) else { return segment }
        return try segment.transformed(by: .redaction) { _ in replacement }
      }
    )
  }

  public func canonicalJSONData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(self)
  }
}
