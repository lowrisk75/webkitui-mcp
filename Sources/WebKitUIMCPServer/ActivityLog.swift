import Darwin
import Foundation

public enum WebKitActivityOutcome: String, Codable, Sendable {
  case succeeded
  case failed
}

public struct WebKitActivityEvent: Codable, Equatable, Identifiable, Sendable {
  public let schemaVersion: Int
  public let id: UUID
  public let timestamp: Date
  public let method: String
  public let toolName: String?
  public let outcome: WebKitActivityOutcome
  public let durationMilliseconds: Int
  public let errorType: String?

  init(
    id: UUID = UUID(),
    timestamp: Date,
    method: String,
    toolName: String?,
    outcome: WebKitActivityOutcome,
    durationMilliseconds: Int,
    errorType: String?
  ) {
    self.schemaVersion = 1
    self.id = id
    self.timestamp = timestamp
    self.method = method
    self.toolName = toolName
    self.outcome = outcome
    self.durationMilliseconds = max(0, durationMilliseconds)
    self.errorType = errorType
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case id
    case timestamp
    case method
    case toolName = "tool_name"
    case outcome
    case durationMilliseconds = "duration_ms"
    case errorType = "error_type"
  }
}

/// A local-only, content-free activity journal. It intentionally accepts no
/// arguments, URLs, page text, element labels, credentials, or response bodies.
public actor WebKitActivityLog {
  public static let allowedMethods: Set<String> = [
    "initialize", "ping", "server/discover", "tools/call", "tools/list",
  ]

  public static let allowedToolNames: Set<String> = [
    "browser_act",
    "browser_capture",
    "browser_fill_siliconpass",
    "browser_inspect_element",
    "browser_navigate",
    "browser_observe",
    "browser_read_text",
    "browser_rotate_siliconpass_password",
    "browser_scroll",
    "browser_session",
    "browser_transaction",
    "element_scroll_into_view",
  ]

  public nonisolated let directoryURL: URL
  public nonisolated let activeFileURL: URL
  private let maximumBytes: Int
  private let maximumArchives: Int
  private let now: @Sendable () -> Date
  private var lastFailureType: String?

  public init(
    directoryURL: URL,
    maximumBytes: Int = 5 * 1_024 * 1_024,
    maximumArchives: Int = 7,
    now: @escaping @Sendable () -> Date = Date.init
  ) throws {
    guard maximumBytes >= 256, maximumArchives >= 0 else {
      throw WebKitActivityLogError.invalidRetention
    }
    self.directoryURL = directoryURL.standardizedFileURL
    self.activeFileURL = directoryURL.standardizedFileURL
      .appending(path: "activity.jsonl", directoryHint: .notDirectory)
    self.maximumBytes = maximumBytes
    self.maximumArchives = maximumArchives
    self.now = now
    try Self.secureDirectory(self.directoryURL)
  }

  public static func durable() throws -> WebKitActivityLog {
    let root = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ).appending(path: "WebkitUIMCP/Activity", directoryHint: .isDirectory)
    return try WebKitActivityLog(directoryURL: root)
  }

  public func record(
    method rawMethod: String,
    toolName rawToolName: String?,
    outcome: WebKitActivityOutcome,
    durationMilliseconds: Int,
    errorType rawErrorType: String? = nil
  ) {
    let method = Self.allowedMethods.contains(rawMethod) ? rawMethod : "unknown"
    let toolName = rawToolName.flatMap {
      Self.allowedToolNames.contains($0) ? $0 : "unknown"
    }
    let errorType = rawErrorType.map(Self.safeErrorType)
    let event = WebKitActivityEvent(
      timestamp: now(),
      method: method,
      toolName: toolName,
      outcome: outcome,
      durationMilliseconds: durationMilliseconds,
      errorType: errorType
    )
    do {
      try append(event)
      lastFailureType = nil
    } catch {
      lastFailureType = Self.safeErrorType(String(describing: type(of: error)))
    }
  }

  public func events(limit: Int = 500) throws -> [WebKitActivityEvent] {
    guard limit > 0 else { return [] }
    var collected: [WebKitActivityEvent] = []
    for url in logFileURLs() {
      guard FileManager.default.fileExists(atPath: url.path) else { continue }
      try Self.requireSecureRegularFile(url)
      let data = try Data(contentsOf: url)
      guard !data.isEmpty else { continue }
      for line in data.split(separator: 0x0A) {
        if let event = try? JSONDecoder.activity.decode(WebKitActivityEvent.self, from: line) {
          collected.append(event)
        }
      }
    }
    return Array(collected.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
  }

  public func exportData(limit: Int = 10_000) throws -> Data {
    try JSONEncoder.activityExport.encode(events(limit: limit))
  }

  public func clear() throws {
    for url in logFileURLs() where FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
    lastFailureType = nil
  }

  public func failureType() -> String? { lastFailureType }

  private func append(_ event: WebKitActivityEvent) throws {
    var line = try JSONEncoder.activityLine.encode(event)
    line.append(0x0A)
    try rotateIfNeeded(forAdditionalBytes: line.count)
    if !FileManager.default.fileExists(atPath: activeFileURL.path) {
      guard
        FileManager.default.createFile(
          atPath: activeFileURL.path,
          contents: nil,
          attributes: [.posixPermissions: 0o600]
        )
      else {
        throw WebKitActivityLogError.cannotCreateFile
      }
    }
    try Self.requireSecureRegularFile(activeFileURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: activeFileURL.path)
    let handle = try FileHandle(forWritingTo: activeFileURL)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: line)
  }

  private func rotateIfNeeded(forAdditionalBytes additionalBytes: Int) throws {
    let size = (try? activeFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    guard size > 0, size + additionalBytes > maximumBytes else { return }
    if maximumArchives == 0 {
      try FileManager.default.removeItem(at: activeFileURL)
      return
    }
    let oldest = archiveURL(maximumArchives)
    if FileManager.default.fileExists(atPath: oldest.path) {
      try FileManager.default.removeItem(at: oldest)
    }
    if maximumArchives > 1 {
      for index in stride(from: maximumArchives - 1, through: 1, by: -1) {
        let source = archiveURL(index)
        guard FileManager.default.fileExists(atPath: source.path) else { continue }
        try FileManager.default.moveItem(at: source, to: archiveURL(index + 1))
      }
    }
    try FileManager.default.moveItem(at: activeFileURL, to: archiveURL(1))
  }

  private func logFileURLs() -> [URL] {
    (stride(from: maximumArchives, through: 1, by: -1).map(archiveURL))
      + [activeFileURL]
  }

  private func archiveURL(_ index: Int) -> URL {
    directoryURL.appending(path: "activity.jsonl.\(index)", directoryHint: .notDirectory)
  }

  private static func secureDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(
      at: url,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    var information = stat()
    guard
      url.path.withCString({ Darwin.lstat($0, &information) }) == 0,
      information.st_mode & S_IFMT == S_IFDIR,
      information.st_uid == geteuid()
    else {
      throw WebKitActivityLogError.unsafePath
    }
  }

  private static func requireSecureRegularFile(_ url: URL) throws {
    var information = stat()
    guard
      url.path.withCString({ Darwin.lstat($0, &information) }) == 0,
      information.st_mode & S_IFMT == S_IFREG,
      information.st_uid == geteuid(),
      information.st_nlink == 1
    else {
      throw WebKitActivityLogError.unsafePath
    }
  }

  private static func safeErrorType(_ value: String) -> String {
    let allowed = value.unicodeScalars.filter {
      CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "_"
    }
    return String(String.UnicodeScalarView(allowed).prefix(96))
  }
}

private enum WebKitActivityLogError: Error {
  case invalidRetention
  case cannotCreateFile
  case unsafePath
}

extension JSONEncoder {
  fileprivate static var activityLine: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }

  fileprivate static var activityExport: JSONEncoder {
    let encoder = activityLine
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }
}

extension JSONDecoder {
  fileprivate static var activity: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
