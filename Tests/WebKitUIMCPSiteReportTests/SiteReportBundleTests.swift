import Foundation
import Testing

@testable import WebKitUIMCPSiteReport

@Suite("Site report bundle")
struct SiteReportBundleTests {
  private func input(
    origin: String = "https://appstoreconnect.apple.com",
    description: String = "The Configure links are in the page text but never observed.",
    label: String = "Configurer l'identifiant de l'appareil",
    shape: Data? = Data(#"{"label":"x","matchCount":1,"matches":[],"truncated":false}"#.utf8)
  ) -> SiteReportInput {
    SiteReportInput(
      origin: origin, reason: .controlNotObserved, userDescription: description, label: label,
      diagnosticsJSON: Data(#"{"documentReadyState":"complete","scriptErrors":0}"#.utf8),
      domShapeJSON: shape, appVersion: "0.6.43", appBuild: "643", osVersion: "27.0",
      locale: "fr_FR", occurredAt: Date(timeIntervalSince1970: 1_792_600_000))
  }

  /// The JSON is LorisReports `ReportEnvelope` schema 2, key for key, so LorisLabs
  /// support tooling reads it unchanged.
  @Test("Envelope JSON has exactly the LorisReports schema-2 keys and values")
  func matchesLorisReportsContract() throws {
    let bundle = try SiteReportBundle.make(
      input(), reportID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!)
    let object = try #require(
      JSONSerialization.jsonObject(with: bundle.envelopeJSON) as? [String: Any])
    #expect(
      Set(object.keys) == [
        "schema_version", "client_report_id", "occurred_at", "source", "kind", "title",
        "description", "actual_result", "reproduction_steps", "app", "structured_context",
        "context_categories", "artifacts", "consent",
      ])
    #expect(object["schema_version"] as? Int == 2)
    #expect(object["source"] as? String == "app_api")
    #expect(object["kind"] as? String == "bug")
    #expect(object["client_report_id"] as? String == "11111111-2222-3333-4444-555555555555")
    #expect(object["occurred_at"] as? String == "2026-10-21T16:26:40Z")
    let app = try #require(object["app"] as? [String: Any])
    #expect(
      Set(app.keys) == ["app_id", "app_version", "app_build", "platform", "os_version", "locale"])
    #expect(app["app_id"] as? String == "webkitui-mcp")
    #expect(app["platform"] as? String == "macos")
    let consent = try #require(object["consent"] as? [String: Any])
    #expect(consent["notice_version"] as? String == SiteReportContract.noticeVersion)
    #expect(
      consent["categories"] as? [String] == [
        "app_metadata", "system_diagnostics", "user_description",
      ])
    #expect(consent["remote_ai_allowed"] as? Bool == false)
    // Schema 2: every structured field is classified and its value is a bounded token.
    let structured = try #require(object["structured_context"] as? [String: String])
    let categories = try #require(object["context_categories"] as? [String: String])
    #expect(Set(structured.keys) == Set(categories.keys))
    #expect(Set(structured.keys) == ["component", "operation", "error_code"])
    for value in structured.values {
      #expect(value.range(of: "^[a-zA-Z0-9_.-]{1,64}$", options: .regularExpression) != nil)
    }
    #expect(structured["error_code"] == "control_not_observed")
    let artifacts = try #require(object["artifacts"] as? [[String: Any]])
    #expect(
      artifacts.map { $0["filename"] as? String } == ["load-diagnostics.json", "dom-shape.json"])
    for artifact in artifacts {
      #expect(
        Set(artifact.keys) == [
          "artifact_id", "filename", "media_type", "size_bytes", "sha256", "category",
          "retention_days",
        ])
      #expect(artifact["category"] as? String == "system_diagnostics")
      #expect((artifact["sha256"] as? String)?.count == 64)
    }
  }

  /// Everything that must never leave the Mac, checked by absence on the bytes that
  /// would be attached.
  @Test("No URL path, query, credential, cookie or page text reaches the files")
  func exclusions() throws {
    let bundle = try SiteReportBundle.make(input())
    let everything =
      String(decoding: bundle.envelopeJSON, as: UTF8.self)
      + bundle.artifacts.map { String(decoding: $0.data, as: UTF8.self) }.joined()
    for forbidden in ["/apps/", "?", "password", "cookie", "Bearer", "/Users/"] {
      #expect(!everything.contains(forbidden), "found \(forbidden)")
    }
    #expect(bundle.envelope.reporter == nil)
    #expect(bundle.envelope.title.contains("https://appstoreconnect.apple.com"))
  }

  @Test(
    "An origin that is not bare is refused, not trimmed",
    arguments: [
      "https://appstoreconnect.apple.com/apps/123/privacy",
      "https://appstoreconnect.apple.com/?x=1",
      "https://user:pw@appstoreconnect.apple.com",
      "https://appstoreconnect.apple.com#frag",
      "file:///tmp",
      "APPSTORECONNECT.APPLE.COM",
    ])
  func refusesNonBareOrigin(origin: String) {
    #expect(throws: SiteReportError.originNotBare(origin)) {
      try SiteReportBundle.make(input(origin: origin))
    }
  }

  @Test("Oversized free text is refused before anything is written")
  func boundsFreeText() {
    #expect(throws: SiteReportError.self) {
      try SiteReportBundle.make(input(description: String(repeating: "a", count: 2_001)))
    }
    #expect(throws: SiteReportError.self) {
      try SiteReportBundle.make(input(label: String(repeating: "b", count: 201)))
    }
  }

  @Test("Files are written owner-only, envelope first, and the body shows the envelope")
  func writesOwnerOnly() throws {
    let bundle = try SiteReportBundle.make(input())
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("site-report-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let urls = try bundle.write(into: directory)
    #expect(
      urls.map(\.lastPathComponent) == [
        "webkitui-site-report.json", "load-diagnostics.json", "dom-shape.json",
      ])
    for url in urls {
      let mode =
        try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
        as? Int
      #expect(mode == 0o600)
    }
    let directoryMode =
      try FileManager.default.attributesOfItem(atPath: directory.path)[
        .posixPermissions] as? Int
    #expect(directoryMode == 0o700)
    #expect(bundle.mailBody.contains("\"schema_version\" : 2"))
    #expect(bundle.mailBody.contains("dom-shape.json"))
  }

  @Test("Oversized diagnostic artifacts are refused before writing")
  func boundsArtifactBytes() {
    #expect(throws: SiteReportError.artifactTooLarge(SiteReportBundle.domShapeFilename)) {
      try SiteReportBundle.make(input(shape: Data(repeating: 32, count: 65_537)))
    }
  }

  @Test("Without a label there is no shape artifact and the operation says so")
  func noLabel() throws {
    let bundle = try SiteReportBundle.make(input(label: "", shape: nil))
    #expect(bundle.artifacts.map(\.filename) == ["load-diagnostics.json"])
    #expect(bundle.envelope.structuredContext["operation"] == "observe")
    #expect(bundle.envelope.actualResult == nil)
  }
}
