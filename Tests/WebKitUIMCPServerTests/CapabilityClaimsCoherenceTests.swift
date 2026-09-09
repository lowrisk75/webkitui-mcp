import Foundation
import Testing

/// README promises no arbitrary JavaScript and no raw CDP escape hatch. The public tree
/// also carried a retained Playwright shim registering `webkitui_cdp_send`, described in
/// its own text as "an escape hatch for anything not covered by the other tools". Its
/// `package.json` said legacy prior art, which a reader auditing the promise has no
/// reason to read first. Nothing compared the claim to the tracked files.
@Suite("Capability claims coherence")
struct CapabilityClaimsCoherenceTests {
  private static var projectRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // WebKitUIMCPServerTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // project root
  }

  /// Only the files git actually tracks. A shim kept on disk and ignored is prior art
  /// nobody can mistake for the product; a shim in the index is a published
  /// contradiction.
  private static func trackedFiles() throws -> [String] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", projectRoot.path, "ls-files"]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0, "git ls-files failed")
    return String(decoding: data, as: UTF8.self)
      .split(separator: "\n")
      .map(String.init)
      .filter { !$0.isEmpty }
  }

  @Test("No tracked file offers a CDP or JavaScript-evaluation tool")
  func noEscapeHatchIsTracked() throws {
    let forbidden = ["webkitui_cdp_send", "cdp_send", "webkitui_evaluate", "evaluateHandle"]
    var offenders: [String] = []
    for path in try Self.trackedFiles()
    where path.hasSuffix(".ts") || path.hasSuffix(".js") || path.hasSuffix(".mjs") {
      guard
        let body = try? String(
          contentsOf: Self.projectRoot.appendingPathComponent(path), encoding: .utf8)
      else { continue }
      for token in forbidden where body.contains(token) {
        offenders.append("\(path) offers \(token)")
      }
    }
    #expect(offenders.isEmpty, "tracked files contradict the refusal claim: \(offenders)")
  }
}
