import Foundation
import Testing

@testable import WebKitUIMCPLicensing

@Suite("Licence resource packaging")
struct LicenseResourceBundleTests {
  @Test("A missing licence resource bundle degrades instead of killing the process")
  func missingLicenceBundleDegrades() async throws {
    // SPM's generated Bundle.module accessor calls fatalError when the bundle is
    // absent. An MCP server that dies on a licence resource is undiagnosable from
    // the client, so the lookup must never touch it.
    let empty = FileManager.default.temporaryDirectory.appendingPathComponent(
      "webkitui-no-bundle-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: empty) }
    let missing = WebKitUIRS256TokenVerifier.bundledPublicKeyPEM(searchRoots: [empty])
    #expect(missing.isEmpty)

    let present = FileManager.default.temporaryDirectory.appendingPathComponent(
      "webkitui-bundle-\(UUID().uuidString)", isDirectory: true)
    let bundle = present.appendingPathComponent(
      "WebKitUIMCP_WebKitUIMCPLicensing.bundle", isDirectory: true)
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: present) }
    try "-----BEGIN PUBLIC KEY-----\nfixture\n-----END PUBLIC KEY-----\n".write(
      to: bundle.appendingPathComponent("lorislabs-license-public.pem"),
      atomically: true, encoding: .utf8)
    let found = WebKitUIRS256TokenVerifier.bundledPublicKeyPEM(searchRoots: [present])
    #expect(found.contains("BEGIN PUBLIC KEY"))

    // An absent key yields a verifier that rejects, rather than one that traps.
    let verdict = WebKitUIRS256TokenVerifier(pem: "")
      .verify("a.b.c", machineID: "machine", now: Date())
    #expect(verdict == .invalid)
  }
}
