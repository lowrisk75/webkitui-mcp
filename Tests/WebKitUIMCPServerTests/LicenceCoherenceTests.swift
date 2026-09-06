import Foundation
import Testing

/// A stray sentence in THIRD_PARTY_NOTICES.md went on claiming the project was MIT for
/// three releases after the licence had been restored to BUSL-1.1, and it shipped inside
/// the notarized app. Nothing compared the places that name a licence to each other.
@Suite("Licence coherence")
struct LicenceCoherenceTests {
  private static var projectRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // WebKitUIMCPServerTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // project root
  }

  private static func text(_ relativePath: String) throws -> String {
    try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
  }

  @Test("LICENSE is the Business Source License and nothing contradicts it")
  func everyDeclarationAgrees() throws {
    let licence = try Self.text("LICENSE")
    #expect(
      licence.hasPrefix("Business Source License 1.1"),
      "LICENSE no longer starts with the licence this suite pins")

    // Prose that names a licence for *this project*. Dependency licences in
    // package-lock.json are somebody else's and are deliberately not read here.
    for path in ["LICENSING.md", "README.md", "THIRD_PARTY_NOTICES.md"] {
      let body = try Self.text(path)
      #expect(
        !body.contains("MIT License") && !body.contains("MIT license"),
        "\(path) names the MIT License while LICENSE is the Business Source License")
    }

    let manifest = try Self.text("package.json")
    #expect(
      manifest.contains("\"license\": \"BUSL-1.1\""),
      "package.json does not declare BUSL-1.1")

    let sbom = try Self.text("Support/Packaging/sbom.cdx.json")
    #expect(
      sbom.contains("\"BUSL-1.1\""),
      "the SBOM template does not carry BUSL-1.1 as the root licence")
  }
}
