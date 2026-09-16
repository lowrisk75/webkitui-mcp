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

  private static func text(_ relativePath: String) throws -> String {
    try String(
      contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
  }

  @Test("The README names every capability this product refuses, and why")
  func refusalsAreDocumented() throws {
    let readme = try Self.text("README.md")
    for refusal in ["arbitrary JavaScript", "raw CDP escape hatch", "subresource", "tabs"] {
      #expect(readme.contains(refusal), "README no longer explains refusing: \(refusal)")
    }
  }

  /// A regression pin, green from the day it was written. Its job is to fail later: the
  /// two claims above were removed from prose that had been correct once, so prose that
  /// is correct now is not evidence it will stay so.
  @Test("The README still says the WKFormInfo gate does not fire")
  func inertGateStaysDocumented() throws {
    let readme = try Self.text("README.md")
    // e86f737 implemented a submission gate that WebKit never calls. Describing it as a
    // live second gate would be the same class of false claim as the ones this suite
    // exists to keep out, and the more tempting one, because the code is really there.
    #expect(
      readme.contains("does not fire") || readme.contains("untriggered"),
      "README no longer says the WKFormInfo gate is inert")
    #expect(
      readme.contains("26A5416b"),
      "README no longer names a build the callback was measured absent on")
  }

  @Test("The README makes no claim the research refuted")
  func refutedClaimsAreAbsent() throws {
    let readme = try Self.text("README.md")
    // Each of these was published and is false. safaridriver dispatches NSEvent through
    // [window sendEvent:] exactly as this does; Claude in Chrome shipped per-action
    // approval first; Browserbase exposes six tools with no evaluate; and WebKit does
    // expose subresource inspection, through proxyConfigurations and WKWebExtension.
    for claim in [
      "only MCP browser", "first to", "unique in", "no API for inspecting",
      "hashed prefixes",
    ] {
      #expect(!readme.contains(claim), "README makes a refuted claim: \(claim)")
    }
  }

  @Test("The README keeps the adversarial measurement and its narrow claim")
  func adversarialMeasurementStaysDocumented() throws {
    let readme = try Self.text("README.md")
    #expect(
      readme.contains("docs/research/2026-09-09-adversarial-corpus-measurement.md"),
      "README no longer links the dated adversarial measurement")
    #expect(
      readme.contains("not human or model attack success"),
      "README widened fixture truthfulness into an attack-success claim")
  }

  @Test("Permission delegates deny and expose no grant branch")
  func permissionDelegatesFailClosed() throws {
    let runtime = try Self.text("Sources/WebKitUIMCPRuntime/WebKitRuntime.swift")
    #expect(
      runtime.components(separatedBy: "decisionHandler(.deny)").count - 1 == 2,
      "camera/media and geolocation delegates must each deny explicitly")
    #expect(!runtime.contains("decisionHandler(.grant)"))
    #expect(!runtime.contains("decisionHandler(.prompt)"))
    let readme = try Self.text("README.md")
    #expect(readme.contains("there is no MCP operation\n  that can grant one"))
  }
}
