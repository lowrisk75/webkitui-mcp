import Darwin
import Foundation
import Security
import WebKitUIMCPConfirmPolicy

/// Where the confirmation helper must sit. `doctor` and the presenter have to
/// agree: a doctor that resolved its own executable differently reported
/// `action_required` on an installation the server was perfectly happy with.
public enum NativeConfirmationHelperLocation {
  public static let helperName = "webkitui-mcp-confirm"

  /// `CommandLine.arguments[0]` is whatever the caller typed. Invoked by bare
  /// name through PATH it carries no directory at all, and the helper was then
  /// looked for in the working directory. The bundle knows the real path.
  public static var executableURL: URL {
    Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
  }

  public static func helperURL(besideExecutable executable: URL) -> URL {
    executable.standardizedFileURL
      .deletingLastPathComponent()
      .appendingPathComponent(helperName)
  }

  public static var helperURL: URL { helperURL(besideExecutable: executableURL) }

  public static func helperIsAvailable(
    besideExecutable executable: URL,
    fileManager: FileManager = .default
  ) -> Bool {
    fileManager.isExecutableFile(atPath: helperURL(besideExecutable: executable).path)
  }

  public static var helperIsAvailable: Bool {
    helperIsAvailable(besideExecutable: executableURL)
  }
}

enum NativeConfirmationOutcome: String, Equatable, Sendable {
  case approved
  case approvedSessionNavigation
  case approvedPersistentNavigation
  case approvedSessionInteractions
  case approvedPersistentInteractions
  case declined
  case timedOut = "timed_out"
  case queueTimedOut = "queue_timed_out"
  case cancelled
  case failed
  /// The panel was shown but never visible (covered, or on another Space).
  case hidden

  var rememberedChoice: RememberedApprovalChoice? {
    switch self {
    case .approvedSessionNavigation: .sessionNavigation
    case .approvedPersistentNavigation: .persistentNavigation
    case .approvedSessionInteractions: .sessionInteractions
    case .approvedPersistentInteractions: .persistentInteractions
    default: nil
    }
  }
}

enum NativeConfirmationState: String, Equatable, Sendable {
  case idle
  case pending = "pending_native_confirmation"
}

@MainActor
protocol BrowserConfirmationPresenting: AnyObject {
  var state: NativeConfirmationState { get }
  var presentationReceipt: ConfirmationPresentationReceipt? { get }
  func confirm(title: String, message: String, approveLabel: String) async
    -> NativeConfirmationOutcome
  func cancel()
  func rePresent(requestID: UUID) -> Bool
  func confirmRemembering(
    title: String, message: String, approveLabel: String, allowPersistent: Bool
  ) async -> NativeConfirmationOutcome
}

extension BrowserConfirmationPresenting {
  var presentationReceipt: ConfirmationPresentationReceipt? { nil }
  func rePresent(requestID: UUID) -> Bool { false }
  func confirmRemembering(
    title: String, message: String, approveLabel: String, allowPersistent: Bool
  ) async -> NativeConfirmationOutcome {
    await confirm(title: title, message: message, approveLabel: approveLabel)
  }
}

@MainActor
final class NativeBrowserConfirmationPresenter: BrowserConfirmationPresenting {
  static let helperProtocolVersion = "1"

  private let helperURL: URL
  private let helperVerification: (URL) -> Bool
  private let runningHelperVerification: ((pid_t) -> Bool)?
  private let timeout: Duration
  private var activeProcess: Process?
  private var cancellationRequested = false
  private var refocusCount = 0
  private var lastRefocus: ContinuousClock.Instant?
  private var waitingForTurn = false
  private let turnWaitLimit: Duration
  private var completedReceipt: ConfirmationPresentationReceipt?
  private var activeReceipt: (buffer: ConfirmationReceiptBuffer, request: UUID, pid: Int32)?
  var presentationReceipt: ConfirmationPresentationReceipt? {
    guard let activeReceipt else { return completedReceipt }
    return Self.validatedReceipt(
      activeReceipt.buffer.snapshot(), requestID: activeReceipt.request,
      helperPID: activeReceipt.pid)
  }
  nonisolated static let maximumReceiptBytes = 16_384

  var state: NativeConfirmationState {
    activeProcess == nil && !waitingForTurn ? .idle : .pending
  }

  init(
    helperURL: URL? = nil,
    helperVerification: ((URL) -> Bool)? = nil,
    runningHelperVerification: ((pid_t) -> Bool)? = nil,
    timeout: Duration = .seconds(60),
    turnWaitLimit: Duration = .seconds(90)
  ) {
    self.turnWaitLimit = turnWaitLimit
    self.helperURL = helperURL ?? Self.defaultHelperURL()
    self.helperVerification = helperVerification ?? Self.verifyPackagedHelper
    self.runningHelperVerification = runningHelperVerification
    self.timeout = timeout
  }

  func confirm(title: String, message: String, approveLabel: String) async
    -> NativeConfirmationOutcome
  {
    await performConfirmation(
      title: title, message: message, approveLabel: approveLabel, allowRemembering: false,
      allowPersistent: false)
  }

  func confirmRemembering(
    title: String, message: String, approveLabel: String, allowPersistent: Bool
  ) async -> NativeConfirmationOutcome {
    await performConfirmation(
      title: title, message: message, approveLabel: approveLabel, allowRemembering: true,
      allowPersistent: allowPersistent)
  }

  private func performConfirmation(
    title: String, message: String, approveLabel: String, allowRemembering: Bool,
    allowPersistent: Bool
  ) async -> NativeConfirmationOutcome {
    guard activeProcess == nil, !waitingForTurn else { return .failed }
    completedReceipt = nil
    refocusCount = 0
    lastRefocus = nil
    let requestID = UUID()
    // One panel on screen at a time for the whole app: with several agents, two
    // confirmations asked for together used to open two panels on top of each other,
    // and the person could approve the one they had not read. The wait does not count
    // against the panel's own timeout, and a cancel asked for while waiting holds.
    waitingForTurn = true
    cancellationRequested = false
    // Bounded: a client waiting behind others is frozen on its relay, and past this its
    // own call has usually given up. Showing the panel then would let a person approve
    // a request nobody is waiting for any more.
    let acquired = await ConfirmationTurnstile.shared.acquire(timeout: turnWaitLimit)
    waitingForTurn = false
    guard acquired else { return .queueTimedOut }
    defer { ConfirmationTurnstile.shared.release() }
    if cancellationRequested {
      cancellationRequested = false
      return .cancelled
    }
    let payload: Data
    do {
      payload = try JSONEncoder().encode(
        NativeConfirmationRequest(
          requestID: requestID,
          title: title,
          message: message,
          approveLabel: approveLabel,
          allowRemembering: allowRemembering,
          allowPersistent: allowPersistent
        ))
    } catch {
      return .failed
    }
    guard helperVerification(helperURL) else { return .failed }
    let process = Process()
    let input = Pipe()
    let output = Pipe()
    let receiptBuffer = ConfirmationReceiptBuffer()
    process.executableURL = helperURL
    process.arguments = Self.helperArguments
    process.environment = Self.helperEnvironment(from: ProcessInfo.processInfo.environment)
    process.standardInput = input
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      try? output.fileHandleForWriting.close()
      let descriptor = output.fileHandleForReading.fileDescriptor
      let flags = fcntl(descriptor, F_GETFL)
      guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
        process.terminate()
        _ = await Self.wait(for: process, timeout: .milliseconds(100))
        return .failed
      }
      output.fileHandleForReading.readabilityHandler = { handle in
        receiptBuffer.drain(handle.fileDescriptor)
      }
      var runningIsVerified = false
      defer {
        output.fileHandleForReading.readabilityHandler = nil
        receiptBuffer.drain(descriptor)
        if runningIsVerified {
          completedReceipt = Self.validatedReceipt(
            receiptBuffer.snapshot(), requestID: requestID, helperPID: process.processIdentifier)
        }
        activeReceipt = nil
      }
      let runningIsTrusted =
        runningHelperVerification?(process.processIdentifier)
        ?? Self.verifyRunningHelper(process.processIdentifier, matches: helperURL)
      guard runningIsTrusted else {
        process.terminate()
        try? input.fileHandleForWriting.close()
        _ = await Self.wait(for: process, timeout: .milliseconds(100))
        return .failed
      }
      runningIsVerified = true
      activeReceipt = (receiptBuffer, requestID, process.processIdentifier)
      try Self.writePayload(payload, to: input.fileHandleForWriting)
      try input.fileHandleForWriting.close()
      activeProcess = process
      cancellationRequested = false
      defer {
        activeProcess = nil
        cancellationRequested = false
      }
      let waitOutcome = await Self.wait(
        for: process, timeout: timeout, cancellation: { self.cancellationRequested })
      if waitOutcome == .timedOut { return .timedOut }
      if waitOutcome == .cancelled || cancellationRequested || Task.isCancelled {
        return .cancelled
      }
    } catch {
      try? input.fileHandleForWriting.close()
      if process.isRunning {
        process.terminate()
        _ = await Self.wait(for: process, timeout: .milliseconds(100))
      }
      return .failed
    }
    guard process.terminationReason == .exit else { return .failed }
    if process.terminationStatus == EXIT_SUCCESS { return .approved }
    if process.terminationStatus == 2 { return .declined }
    if process.terminationStatus == 3 { return .cancelled }
    if process.terminationStatus == 4 { return .hidden }
    if let choice = RememberedApprovalChoice(rawValue: process.terminationStatus) {
      guard allowRemembering, !choice.persistent || allowPersistent,
        let receipt = completedReceipt, receipt.decision == .approve,
        receipt.windowVisible, receipt.onActiveSpace, receipt.intersectsScreen
      else { return .failed }
      switch choice {
      case .sessionNavigation: return .approvedSessionNavigation
      case .persistentNavigation: return .approvedPersistentNavigation
      case .sessionInteractions: return .approvedSessionInteractions
      case .persistentInteractions: return .approvedPersistentInteractions
      }
    }
    return .failed
  }

  /// The UI helper needs user preferences and locale, not the host's service
  /// credentials or dynamic-loader configuration.
  static func helperEnvironment(from parent: [String: String]) -> [String: String] {
    let allowed = Set(["HOME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "__CF_USER_TEXT_ENCODING"])
    var environment = parent.filter { allowed.contains($0.key) }
    environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
    return environment
  }

  func cancel() {
    cancellationRequested = activeProcess != nil || waitingForTurn
    activeProcess?.terminate()
  }

  /// Presentation only: exact currently running helper/request, no decision,
  /// deadline extension, new prompt or browser dispatch. Bound focus flooding.
  func rePresent(requestID: UUID) -> Bool {
    guard !cancellationRequested, let process = activeProcess, process.isRunning,
      let activeReceipt, activeReceipt.request == requestID,
      let receipt = presentationReceipt, receipt.requestID == requestID,
      receipt.helperPID == process.processIdentifier, receipt.decision == nil,
      refocusCount < 3,
      lastRefocus.map({ $0.duration(to: .now) >= .seconds(1) }) ?? true,
      runningHelperVerification?(process.processIdentifier)
        ?? Self.verifyRunningHelper(process.processIdentifier, matches: helperURL)
    else { return false }
    guard Darwin.kill(process.processIdentifier, SIGUSR1) == 0 else { return false }
    refocusCount += 1
    lastRefocus = .now
    return true
  }

  private static func wait(
    for process: Process, timeout: Duration, cancellation: () -> Bool = { false }
  ) async
    -> NativeConfirmationOutcome
  {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while process.isRunning {
      let cancelled = Task.isCancelled || cancellation()
      if cancelled || clock.now >= deadline {
        let outcome: NativeConfirmationOutcome = cancelled ? .cancelled : .timedOut
        process.terminate()
        let grace = clock.now.advanced(by: .milliseconds(500))
        while process.isRunning, clock.now < grace {
          await Task.detached { try? await Task.sleep(for: .milliseconds(20)) }.value
        }
        // Only the exact subprocess we launched; never a broker or user's app.
        if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
        let reapDeadline = clock.now.advanced(by: .milliseconds(500))
        while process.isRunning, clock.now < reapDeadline {
          await Task.detached { try? await Task.sleep(for: .milliseconds(20)) }.value
        }
        return outcome
      }
      try? await Task.sleep(for: .milliseconds(20))
    }
    return .declined
  }

  static var helperArguments: [String] {
    ["--protocol-version", helperProtocolVersion, "--request-stdin"]
  }

  static func validatedReceipt(_ data: Data, requestID: UUID, helperPID: Int32)
    -> ConfirmationPresentationReceipt?
  {
    guard data.count <= maximumReceiptBytes else { return nil }
    let lines = data.split(separator: 0x0A)
    guard lines.count <= 32 else { return nil }
    var latest: ConfirmationPresentationReceipt?
    for line in lines {
      guard
        let receipt = try? JSONDecoder().decode(
          ConfirmationPresentationReceipt.self, from: Data(line)),
        receipt.requestID == requestID, receipt.helperPID == helperPID,
        receipt.windowNumber > 0, receipt.monotonicNanoseconds > 0,
        receipt.monotonicNanoseconds >= (latest?.monotonicNanoseconds ?? 0)
      else { return nil }
      latest = receipt
    }
    return latest
  }

  static func writePayload(_ payload: Data, to input: FileHandle) throws {
    guard fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    try input.write(contentsOf: payload)
  }

  private static func defaultHelperURL() -> URL {
    NativeConfirmationHelperLocation.helperURL
  }

  private static func verifyPackagedHelper(_ helperURL: URL) -> Bool {
    let helper = helperURL.standardizedFileURL
    let executable = NativeConfirmationHelperLocation.executableURL.standardizedFileURL
    guard
      helper.deletingLastPathComponent() == executable.deletingLastPathComponent(),
      helper.lastPathComponent == NativeConfirmationHelperLocation.helperName,
      FileManager.default.isExecutableFile(atPath: helper.path),
      let helperIdentity = validatedSigningIdentity(at: helper),
      let executableIdentity = validatedSigningIdentity(at: executable),
      helperIsTrusted(
        helperTeam: helperIdentity.team,
        helperIdentifier: helperIdentity.identifier,
        serverTeam: executableIdentity.team)
    else {
      return false
    }
    return true
  }

  /// The identifier the release signing script stamps on the packaged helper.
  nonisolated static let releaseHelperIdentifier = "com.lorislab.webkitui-mcp.confirm"

  /// The identifier an unsigned `swift build` product carries: its own file name.
  nonisolated static let sourceBuildHelperIdentifier = "webkitui-mcp-confirm"

  /// Whether the helper sitting beside the server may be run.
  ///
  /// A notarized server pins both its team and the exact identifier the release script
  /// stamps, and that is where this check has teeth: nobody can drop a helper of their own
  /// next to it. A server built from source has neither — an ad-hoc signature carries no
  /// team, and the identifier is just the file name — and demanding the release values
  /// there made the documented source install refuse to show any confirmation at all, so
  /// the product did nothing for everyone but the release signer. For such a server the
  /// check can only assert co-location and the plain executable name, which gives nothing
  /// away: whoever can write a helper beside an unsigned server can replace that server
  /// too.
  ///
  /// What is never allowed is the mismatch — a signed server with a helper that is not its
  /// own, or an unsigned helper smuggled in beside a signed one.
  nonisolated static func helperIsTrusted(
    helperTeam: String?,
    helperIdentifier: String,
    serverTeam: String?
  ) -> Bool {
    switch (helperTeam, serverTeam) {
    case (let helper?, let server?):
      return helper == server && helperIdentifier == releaseHelperIdentifier
    case (nil, nil):
      return helperIdentifier == sourceBuildHelperIdentifier
        || helperIdentifier == releaseHelperIdentifier
    default:
      return false
    }
  }

  /// A source build is ad-hoc signed and carries no team, so demanding one made every
  /// installation built from this repository refuse to show a confirmation at all. The
  /// team is now optional here and compared by `verifyPackagedHelper`, which is where the
  /// decision about what an absent team means belongs.
  static func validatedSigningIdentity(at url: URL) -> (team: String?, identifier: String)? {
    var code: SecStaticCode?
    guard
      SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &code) == errSecSuccess,
      let code,
      SecStaticCodeCheckValidity(
        code,
        SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures),
        nil
      ) == errSecSuccess
    else {
      return nil
    }
    var information: CFDictionary?
    guard
      SecCodeCopySigningInformation(
        code, SecCSFlags(rawValue: kSecCSSigningInformation),
        &information) == errSecSuccess,
      let values = information as? [CFString: Any],
      let identifier = values[kSecCodeInfoIdentifier] as? String,
      !identifier.isEmpty
    else {
      return nil
    }
    let team = (values[kSecCodeInfoTeamIdentifier] as? String).flatMap {
      $0.isEmpty ? nil : $0
    }
    return (team, identifier)
  }

  static func verifyRunningHelper(_ processID: pid_t, matches helperURL: URL) -> Bool {
    guard let expected = validatedSigningIdentity(at: helperURL) else { return false }
    var code: SecCode?
    guard
      SecCodeCopyGuestWithAttributes(
        nil,
        [kSecGuestAttributePid as String: NSNumber(value: processID)] as CFDictionary,
        SecCSFlags(),
        &code
      ) == errSecSuccess,
      let code,
      SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess
    else {
      return false
    }
    var staticCode: SecStaticCode?
    var information: CFDictionary?
    guard
      SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
      let staticCode,
      SecCodeCopySigningInformation(
        staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
      let values = information as? [CFString: Any],
      let identifier = values[kSecCodeInfoIdentifier] as? String
    else {
      return false
    }
    let team = (values[kSecCodeInfoTeamIdentifier] as? String).flatMap {
      $0.isEmpty ? nil : $0
    }
    return team == expected.team && identifier == expected.identifier
  }
}

private struct NativeConfirmationRequest: Encodable {
  let requestID: UUID
  let title: String
  let message: String
  let approveLabel: String
  let allowRemembering: Bool
  let allowPersistent: Bool
}

private final class ConfirmationReceiptBuffer: @unchecked Sendable {
  private let lock = NSLock()
  private var data = Data()
  private var overflow = false

  func drain(_ descriptor: Int32) {
    lock.lock()
    defer { lock.unlock() }
    var bytes = [UInt8](repeating: 0, count: 4096)
    var drained = 0
    while true {
      let count = Darwin.read(descriptor, &bytes, bytes.count)
      guard count > 0 else { return }
      drained += count
      if data.count + count <= NativeBrowserConfirmationPresenter.maximumReceiptBytes, !overflow {
        data.append(contentsOf: bytes.prefix(count))
      } else {
        overflow = true
      }
      if drained >= 65_536 { return }
    }
  }

  func snapshot() -> Data {
    lock.lock()
    defer { lock.unlock() }
    return overflow
      ? Data(repeating: 0, count: NativeBrowserConfirmationPresenter.maximumReceiptBytes + 1) : data
  }
}

/// First come, first shown: the single native confirmation slot of the app, shared by
/// every client's server in the process.
@MainActor
final class ConfirmationTurnstile {
  static let shared = ConfirmationTurnstile()

  private var busy = false
  private var waiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []

  var queuedCount: Int { waiters.count }

  /// True once it is this caller's turn; false if the wait ran past `timeout`, in which
  /// case the caller holds nothing and must not release.
  func acquire(timeout: Duration) async -> Bool {
    guard busy else {
      busy = true
      return true
    }
    let id = UUID()
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: timeout)
      guard let self, let index = self.waiters.firstIndex(where: { $0.id == id }) else {
        return
      }
      self.waiters.remove(at: index).continuation.resume(returning: false)
    }
    return await withCheckedContinuation { waiters.append((id, $0)) }
  }

  func release() {
    guard !waiters.isEmpty else {
      busy = false
      return
    }
    waiters.removeFirst().continuation.resume(returning: true)
  }
}
