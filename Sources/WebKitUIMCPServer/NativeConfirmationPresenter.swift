import Darwin
import Foundation
import Security

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
  case declined
  case timedOut = "timed_out"
  case cancelled
  case failed
}

enum NativeConfirmationState: String, Equatable, Sendable {
  case idle
  case pending = "pending_native_confirmation"
}

@MainActor
protocol BrowserConfirmationPresenting: AnyObject {
  var state: NativeConfirmationState { get }
  func confirm(title: String, message: String, approveLabel: String) async
    -> NativeConfirmationOutcome
  func cancel()
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
  private var waitingForTurn = false

  var state: NativeConfirmationState {
    activeProcess == nil && !waitingForTurn ? .idle : .pending
  }

  init(
    helperURL: URL? = nil,
    helperVerification: ((URL) -> Bool)? = nil,
    runningHelperVerification: ((pid_t) -> Bool)? = nil,
    timeout: Duration = .seconds(60)
  ) {
    self.helperURL = helperURL ?? Self.defaultHelperURL()
    self.helperVerification = helperVerification ?? Self.verifyPackagedHelper
    self.runningHelperVerification = runningHelperVerification
    self.timeout = timeout
  }

  func confirm(title: String, message: String, approveLabel: String) async
    -> NativeConfirmationOutcome
  {
    guard activeProcess == nil, !waitingForTurn else { return .failed }
    // One panel on screen at a time for the whole app: with several agents, two
    // confirmations asked for together used to open two panels on top of each other,
    // and the person could approve the one they had not read. The wait does not count
    // against the panel's own timeout, and a cancel asked for while waiting holds.
    waitingForTurn = true
    cancellationRequested = false
    await ConfirmationTurnstile.shared.acquire()
    waitingForTurn = false
    defer { ConfirmationTurnstile.shared.release() }
    if cancellationRequested {
      cancellationRequested = false
      return .cancelled
    }
    let payload: Data
    do {
      payload = try JSONEncoder().encode(
        NativeConfirmationRequest(
          title: title,
          message: message,
          approveLabel: approveLabel
        ))
    } catch {
      return .failed
    }
    guard helperVerification(helperURL) else { return .failed }
    let process = Process()
    let input = Pipe()
    process.executableURL = helperURL
    process.arguments = Self.helperArguments
    process.environment = Self.helperEnvironment(from: ProcessInfo.processInfo.environment)
    process.standardInput = input
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      let runningIsTrusted =
        runningHelperVerification?(process.processIdentifier)
        ?? Self.verifyRunningHelper(process.processIdentifier, matches: helperURL)
      guard runningIsTrusted else {
        process.terminate()
        try? input.fileHandleForWriting.close()
        process.waitUntilExit()
        return .failed
      }
      try Self.writePayload(payload, to: input.fileHandleForWriting)
      try input.fileHandleForWriting.close()
      activeProcess = process
      cancellationRequested = false
      defer {
        activeProcess = nil
        cancellationRequested = false
      }
      let waitOutcome = await Self.wait(for: process, timeout: timeout)
      if waitOutcome == .timedOut { return .timedOut }
      if cancellationRequested { return .cancelled }
    } catch {
      try? input.fileHandleForWriting.close()
      return .failed
    }
    guard process.terminationReason == .exit else { return .failed }
    if process.terminationStatus == EXIT_SUCCESS { return .approved }
    if process.terminationStatus == 2 { return .declined }
    if process.terminationStatus == 3 { return .cancelled }
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

  private static func wait(for process: Process, timeout: Duration) async
    -> NativeConfirmationOutcome
  {
    let box = SendableProcess(process)
    return await withTaskGroup(of: NativeConfirmationOutcome.self) { group in
      group.addTask {
        box.process.waitUntilExit()
        return .declined
      }
      group.addTask {
        do {
          try await Task.sleep(for: timeout)
          return .timedOut
        } catch {
          return .cancelled
        }
      }
      let first = await group.next() ?? .failed
      if first == .timedOut, box.process.isRunning { box.process.terminate() }
      group.cancelAll()
      return first
    }
  }

  static var helperArguments: [String] {
    ["--protocol-version", helperProtocolVersion, "--request-stdin"]
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

private final class SendableProcess: @unchecked Sendable {
  let process: Process
  init(_ process: Process) { self.process = process }
}

private struct NativeConfirmationRequest: Encodable {
  let title: String
  let message: String
  let approveLabel: String
}

/// First come, first shown: the single native confirmation slot of the app, shared by
/// every client's server in the process.
@MainActor
final class ConfirmationTurnstile {
  static let shared = ConfirmationTurnstile()

  private var busy = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  var queuedCount: Int { waiters.count }

  func acquire() async {
    guard busy else {
      busy = true
      return
    }
    await withCheckedContinuation { waiters.append($0) }
  }

  func release() {
    guard !waiters.isEmpty else {
      busy = false
      return
    }
    waiters.removeFirst().resume()
  }
}
