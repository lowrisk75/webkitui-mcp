import Foundation
import Testing

/// The Status window resolves every label through `text(_:)`, which falls back to
/// the key when the catalog has no entry. A missing entry is therefore invisible in
/// English and shows as raw English inside an otherwise French window — which is how
/// the three recovery buttons shipped. Only the catalogs can prove the coverage.
@Suite("Aqua localization catalog")
struct AquaLocalizationCatalogTests {
  private static var projectRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // WebKitUIMCPServerTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // project root
  }

  private static func brokerLocalizationKeys() throws -> Set<String> {
    let directory = projectRoot.appendingPathComponent("Sources/WebKitUIMCPAquaBroker")
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    var source = ""
    for name in names where name.hasSuffix(".swift") {
      source += try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }
    // text( "one literal" + "a continuation" ) — the call site is free to wrap.
    let call = try NSRegularExpression(
      pattern: #"text\(\s*((?:"(?:[^"\\]|\\.)*"\s*\+?\s*)+)\)"#,
      options: [.dotMatchesLineSeparators])
    let literal = try NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)
    let whole = NSRange(source.startIndex..., in: source)
    var keys: Set<String> = []
    for match in call.matches(in: source, range: whole) {
      guard let argumentRange = Range(match.range(at: 1), in: source) else { continue }
      let argument = String(source[argumentRange])
      let pieces = literal.matches(
        in: argument, range: NSRange(argument.startIndex..., in: argument)
      )
      .compactMap { Range($0.range(at: 1), in: argument).map { String(argument[$0]) } }
      keys.insert(pieces.joined())
    }
    return keys
  }

  private static func catalogKeys(_ language: String) throws -> Set<String> {
    let url =
      projectRoot
      .appendingPathComponent("Support/AquaApp/\(language).lproj/Localizable.strings")
    let data = try Data(contentsOf: url)
    let catalog = try PropertyListSerialization.propertyList(from: data, format: nil)
    guard let entries = catalog as? [String: String] else { return [] }
    return Set(entries.keys)
  }

  @Test("Every Status window string is present in English and French")
  func everyStringIsTranslated() throws {
    let keys = try Self.brokerLocalizationKeys()
    #expect(keys.count > 50, "the scanner found almost nothing, so it stopped proving anything")
    for language in ["en", "fr"] {
      let catalog = try Self.catalogKeys(language)
      let missing = keys.subtracting(catalog).sorted()
      #expect(missing.isEmpty, "\(language) is missing: \(missing.joined(separator: " | "))")
    }
  }

  @Test("French is a translation, not a copy of the English key")
  func frenchIsActuallyTranslated() throws {
    let url = Self.projectRoot
      .appendingPathComponent("Support/AquaApp/fr.lproj/Localizable.strings")
    let data = try Data(contentsOf: url)
    let catalog =
      try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
      ?? [:]
    let keys = try Self.brokerLocalizationKeys()
    // A handful of labels are the same word in both languages; anything longer that
    // matches its key verbatim is an untranslated entry pretending to be covered.
    let untranslated =
      catalog
      .filter { keys.contains($0.key) && $0.key == $0.value && $0.key.count > 24 }
      .keys.sorted()
    #expect(untranslated.isEmpty, "fr copies the English: \(untranslated.joined(separator: " | "))")
  }
}
