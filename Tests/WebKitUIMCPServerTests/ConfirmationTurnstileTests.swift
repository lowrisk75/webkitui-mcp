import Foundation
import Testing
import WebKitUIMCPConfirmPolicy

@testable import WebKitUIMCPServer

@Suite("One native confirmation at a time", .serialized)
@MainActor
struct ConfirmationTurnstileTests {
  @Test(
    "Re-presentation binds the live request, changes no approval and cannot revive it",
    arguments: [false, true])
  func exactConfirmationRefocus(timesOut: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "webkitui-refocus-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let helper = directory.appendingPathComponent("helper")
    try Data(
      #"""
      #!/bin/sh
      trap ':' USR1
      request=$(/bin/cat | /usr/bin/sed -n 's/.*"requestID":"\([^"]*\)".*/\1/p')
      printf '{"requestID":"%s","helperPID":%s,"phase":"sampled","monotonicNanoseconds":1,"windowNumber":7,"windowVisible":true,"appKitVisible":true,"keyWindow":false,"onActiveSpace":true,"intersectsScreen":true}\n' "$request" "$$"
      /bin/sleep 0.8
      exit 2
      """#.utf8
    ).write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
    let presenter = NativeBrowserConfirmationPresenter(
      helperURL: helper,
      helperVerification: { _ in true }, runningHelperVerification: { _ in true },
      timeout: timesOut ? .milliseconds(150) : .seconds(2))
    #expect(!presenter.rePresent(requestID: UUID()))
    async let outcome = presenter.confirm(title: "Local", message: "Synthetic", approveLabel: "Go")
    let deadline = ContinuousClock.now + .seconds(2)
    while presenter.presentationReceipt == nil, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    let receipt = try #require(presenter.presentationReceipt)
    #expect(!presenter.rePresent(requestID: UUID()))
    #expect(presenter.rePresent(requestID: receipt.requestID))
    #expect(!presenter.rePresent(requestID: receipt.requestID))  // bounded, no focus flooding
    #expect(presenter.state == .pending)
    #expect(await outcome == (timesOut ? .timedOut : .declined))
    #expect(!presenter.rePresent(requestID: receipt.requestID))
  }
  @Test(
    "Remembered choices require opted-in request and bound approval metadata",
    arguments: [Int32(8), 9, 10, 11])
  func rememberedChoiceIsBound(code: Int32) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let helper = directory.appendingPathComponent("helper")
    try Data(
      #"""
      #!/bin/sh
      request=$(/bin/cat | /usr/bin/sed -n 's/.*"requestID":"\([^"]*\)".*/\1/p')
      printf '{"requestID":"%s","helperPID":%s,"phase":"decision","decision":"approve","monotonicNanoseconds":1,"windowNumber":7,"windowVisible":true,"appKitVisible":true,"keyWindow":true,"onActiveSpace":true,"intersectsScreen":true}\n' "$request" "$$"
      exit \#(code)
      """#.utf8
    ).write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
    let presenter = NativeBrowserConfirmationPresenter(
      helperURL: helper, helperVerification: { _ in true }, runningHelperVerification: { _ in true }
    )
    let scoped = await presenter.confirmRemembering(
      title: "Local", message: "Synthetic", approveLabel: "Once", allowPersistent: true)
    #expect(scoped.rememberedChoice == RememberedApprovalChoice(rawValue: code))
    let unscoped = await presenter.confirm(
      title: "Local", message: "Synthetic", approveLabel: "Once")
    #expect(unscoped == .failed)
    if scoped.rememberedChoice?.persistent == true {
      #expect(
        await presenter.confirmRemembering(
          title: "Local", message: "Synthetic", approveLabel: "Once", allowPersistent: false)
          == .failed)
    }
  }

  @Test("A remembered exit code without a bound decision is never authority")
  func rememberedChoiceWithoutReceiptIsRefused() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let helper = directory.appendingPathComponent("helper")
    try Data("#!/bin/sh\n/bin/cat >/dev/null\nexit 10\n".utf8).write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
    let presenter = NativeBrowserConfirmationPresenter(
      helperURL: helper, helperVerification: { _ in true }, runningHelperVerification: { _ in true }
    )
    #expect(
      await presenter.confirmRemembering(
        title: "Local", message: "Synthetic", approveLabel: "Once", allowPersistent: true)
        == .failed)
  }

  @Test("Explicit cancellation reaps an unresponsive helper without waiting for its deadline")
  func unresponsiveHelperCancellationIsBounded() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let helper = directory.appendingPathComponent("helper")
    try Data(
      "#!/bin/sh\ntrap '' TERM\n/bin/cat >/dev/null\nwhile :; do /bin/sleep 0.05; done\n".utf8
    ).write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
    let presenter = NativeBrowserConfirmationPresenter(
      helperURL: helper, helperVerification: { _ in true },
      runningHelperVerification: { _ in true }, timeout: .seconds(60))
    async let outcome = presenter.confirm(title: "Local", message: "Synthetic", approveLabel: "Go")
    let launchDeadline = ContinuousClock.now.advanced(by: .seconds(2))
    while presenter.state != .pending, ContinuousClock.now < launchDeadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    // Let the synthetic helper install its TERM trap before cancellation.
    try await Task.sleep(for: .milliseconds(100))
    let start = ContinuousClock.now
    presenter.cancel()
    #expect(await outcome == .cancelled)
    #expect(start.duration(to: .now) < .seconds(2))
    #expect(presenter.state == .idle)
    #expect(ConfirmationTurnstile.shared.queuedCount == 0)
  }

  @Test("A helper ignoring termination cannot retain the confirmation turnstile")
  func unresponsiveHelperDeadlineIsBounded() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let helper = directory.appendingPathComponent("helper")
    try Data(
      "#!/bin/sh\ntrap '' TERM\n/bin/cat >/dev/null\nwhile :; do /bin/sleep 0.05; done\n".utf8
    ).write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
    let presenter = NativeBrowserConfirmationPresenter(
      helperURL: helper, helperVerification: { _ in true },
      runningHelperVerification: { _ in true }, timeout: .milliseconds(120))
    let start = ContinuousClock.now
    let outcome = await presenter.confirm(title: "Local", message: "Synthetic", approveLabel: "Go")
    #expect(outcome == .timedOut)
    #expect(start.duration(to: .now) < .seconds(2))
    #expect(presenter.state == .idle)
    #expect(presenter.presentationReceipt == nil)
    #expect(ConfirmationTurnstile.shared.queuedCount == 0)
  }

  @Test("Live measured metadata is readable before a helper exits and never grants approval")
  func receiptIsReadableWhilePending() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let helper = directory.appendingPathComponent("helper")
    try Data(
      #"""
      #!/bin/sh
      request=$(/bin/cat | /usr/bin/sed -n 's/.*"requestID":"\([^"]*\)".*/\1/p')
      printf '{"requestID":"%s","helperPID":%s,"phase":"decision","decision":"approve","monotonicNanoseconds":1,"windowNumber":7,"windowVisible":true,"appKitVisible":true,"keyWindow":true,"onActiveSpace":true,"intersectsScreen":true}\n' "$request" "$$"
      /bin/sleep 0.4
      exit 2
      """#.utf8
    ).write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
    let presenter = NativeBrowserConfirmationPresenter(
      helperURL: helper, helperVerification: { _ in true },
      runningHelperVerification: { _ in true })
    async let outcome = presenter.confirm(title: "Local", message: "Synthetic", approveLabel: "Go")
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while presenter.presentationReceipt == nil, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(presenter.state == .pending)
    #expect(presenter.presentationReceipt?.decision == .approve)
    #expect(await outcome == .declined)
  }

  @Test("Presentation metadata is drained from the launched helper without becoming an approval")
  func helperPresentationPipeIsMeasured() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("webkitui-receipt-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let helper = directory.appendingPathComponent("helper")
    try Data(
      #"""
      #!/bin/sh
      request=$(/bin/cat | /usr/bin/sed -n 's/.*"requestID":"\([^"]*\)".*/\1/p')
      printf '{"requestID":"%s","helperPID":%s,"phase":"sampled","monotonicNanoseconds":1,"windowNumber":7,"windowVisible":false,"appKitVisible":false,"keyWindow":false,"onActiveSpace":false,"intersectsScreen":false}\n' "$request" "$$"
      exit 4
      """#.utf8
    ).write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
    let presenter = NativeBrowserConfirmationPresenter(
      helperURL: helper,
      helperVerification: { _ in true }, runningHelperVerification: { _ in true })
    #expect(
      await presenter.confirm(title: "Local", message: "Synthetic", approveLabel: "Go") == .hidden)
    #expect(presenter.presentationReceipt?.windowNumber == 7)
    #expect(presenter.presentationReceipt?.windowVisible == false)
  }

  @Test("Presentation metadata is bounded and bound to its helper PID and request")
  func presentationReceiptIsBoundedAndBound() throws {
    let request = UUID()
    let fields: [String: Any] = [
      "requestID": request.uuidString, "helperPID": 42,
      "phase": "sampled", "monotonicNanoseconds": 1, "windowNumber": 7,
      "windowVisible": true, "appKitVisible": true, "keyWindow": true,
      "onActiveSpace": true, "intersectsScreen": true,
    ]
    let data = try JSONSerialization.data(withJSONObject: fields)
    let receipt = NativeBrowserConfirmationPresenter.validatedReceipt(
      data, requestID: request, helperPID: 42)
    #expect(receipt?.windowNumber == 7)
    #expect(
      NativeBrowserConfirmationPresenter.validatedReceipt(data, requestID: UUID(), helperPID: 42)
        == nil)
    #expect(
      NativeBrowserConfirmationPresenter.validatedReceipt(data, requestID: request, helperPID: 43)
        == nil)
    #expect(
      NativeBrowserConfirmationPresenter.validatedReceipt(
        Data(repeating: 65, count: NativeBrowserConfirmationPresenter.maximumReceiptBytes + 1),
        requestID: request, helperPID: 42) == nil)
    #expect(
      NativeBrowserConfirmationPresenter.validatedReceipt(
        Data("not json".utf8), requestID: request, helperPID: 42) == nil)
    let encoded = try JSONEncoder().encode(try #require(receipt))
    let keys = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any]).keys
    #expect(Set(keys) == Set(fields.keys))
    let tooMany = (0..<33).reduce(into: Data()) { result, _ in
      result.append(data)
      result.append(0x0A)
    }
    #expect(
      NativeBrowserConfirmationPresenter.validatedReceipt(
        tooMany, requestID: request, helperPID: 42) == nil)
  }

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
    #expect(waited == .queueTimedOut)
    #expect(late.presentationReceipt == nil)
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
