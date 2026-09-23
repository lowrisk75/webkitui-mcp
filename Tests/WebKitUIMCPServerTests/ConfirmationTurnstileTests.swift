import Foundation
import Testing

@testable import WebKitUIMCPServer

@Suite("One native confirmation at a time", .serialized)
@MainActor
struct ConfirmationTurnstileTests {
  @Test("Two clients' confirmations are shown one after the other, never together")
  func confirmationsDoNotOverlap() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("webkitui-turnstile-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    // Stands in for the panel: it appends "start" and "end" around a short wait, so an
    // overlap would read start, start.
    let journal = directory.appendingPathComponent("journal")
    let helper = directory.appendingPathComponent("helper")
    try Data(
      """
      #!/bin/sh
      /bin/cat >/dev/null
      echo start >> '\(journal.path)'
      /bin/sleep 0.3
      echo end >> '\(journal.path)'
      """.utf8
    ).write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
    func presenter() -> NativeBrowserConfirmationPresenter {
      NativeBrowserConfirmationPresenter(
        helperURL: helper, helperVerification: { _ in true },
        runningHelperVerification: { _ in true })
    }
    let alice = presenter()
    let bob = presenter()
    async let first = alice.confirm(title: "A", message: "A", approveLabel: "Go")
    async let second = bob.confirm(title: "B", message: "B", approveLabel: "Go")
    let outcomes = await [first, second]
    #expect(outcomes == [.approved, .approved])
    let lines = try String(contentsOf: journal, encoding: .utf8)
      .split(separator: "\n").map(String.init)
    #expect(lines == ["start", "end", "start", "end"])
  }

  @Test("A cancel asked for while waiting its turn is honoured without a panel")
  func cancelWhileQueued() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("webkitui-turnstile-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let slow = directory.appendingPathComponent("slow")
    try Data("#!/bin/sh\n/bin/cat >/dev/null\n/bin/sleep 1\n".utf8).write(to: slow)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: slow.path)
    let blocking = NativeBrowserConfirmationPresenter(
      helperURL: slow, helperVerification: { _ in true },
      runningHelperVerification: { _ in true })
    let queued = NativeBrowserConfirmationPresenter(
      helperURL: URL(fileURLWithPath: "/usr/bin/true"), helperVerification: { _ in true },
      runningHelperVerification: { _ in true })
    async let held = blocking.confirm(title: "A", message: "A", approveLabel: "Go")
    try await Task.sleep(for: .milliseconds(100))
    async let waiting = queued.confirm(title: "B", message: "B", approveLabel: "Go")
    try await Task.sleep(for: .milliseconds(50))
    #expect(queued.state == .pending)
    queued.cancel()
    let results = await (held, waiting)
    #expect(results.0 == .approved)
    #expect(results.1 == .cancelled)
    #expect(ConfirmationTurnstile.shared.queuedCount == 0)
  }

  @Test("A confirmation that waits past its limit times out without ever being shown")
  func queuedConfirmationTimesOut() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("webkitui-turnstile-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let slow = directory.appendingPathComponent("slow")
    try Data("#!/bin/sh\n/bin/cat >/dev/null\n/bin/sleep 1\n".utf8).write(to: slow)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: slow.path)
    let shown = directory.appendingPathComponent("shown")
    let marker = directory.appendingPathComponent("marker")
    try Data("#!/bin/sh\n/bin/cat >/dev/null\ntouch '\(shown.path)'\n".utf8).write(to: marker)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: marker.path)
    let holder = NativeBrowserConfirmationPresenter(
      helperURL: slow, helperVerification: { _ in true }, runningHelperVerification: { _ in true })
    let late = NativeBrowserConfirmationPresenter(
      helperURL: marker, helperVerification: { _ in true },
      runningHelperVerification: { _ in true }, turnWaitLimit: .milliseconds(200))
    async let held = holder.confirm(title: "A", message: "A", approveLabel: "Go")
    try await Task.sleep(for: .milliseconds(100))
    let waited = await late.confirm(title: "B", message: "B", approveLabel: "Go")
    #expect(waited == .timedOut)
    #expect(await held == .approved)
    #expect(!FileManager.default.fileExists(atPath: shown.path))
    #expect(ConfirmationTurnstile.shared.queuedCount == 0)
  }

  @Test("A panel the helper reports hidden is a distinct outcome, reported at once")
  func hiddenPanelIsReported() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("webkitui-hidden-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let helper = directory.appendingPathComponent("hidden")
    try Data("#!/bin/sh\n/bin/cat >/dev/null\nexit 4\n".utf8).write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
    let presenter = NativeBrowserConfirmationPresenter(
      helperURL: helper, helperVerification: { _ in true }, runningHelperVerification: { _ in true }
    )
    #expect(await presenter.confirm(title: "A", message: "A", approveLabel: "Go") == .hidden)
  }
}
