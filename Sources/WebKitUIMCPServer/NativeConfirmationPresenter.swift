import Darwin
import Foundation
import Security

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

  var state: NativeConfirmationState { activeProcess == nil ? .idle : .pending }

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
    guard activeProcess == nil else { return .failed }
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

  func cancel() {
    cancellationRequested = activeProcess != nil
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
    let executable =
      Bundle.main.executableURL
      ?? URL(fileURLWithPath: CommandLine.arguments[0])
    return executable.deletingLastPathComponent().appendingPathComponent("webkitui-mcp-confirm")
  }

  private static func verifyPackagedHelper(_ helperURL: URL) -> Bool {
    let helper = helperURL.standardizedFileURL
    let executable =
      (Bundle.main.executableURL
      ?? URL(fileURLWithPath: CommandLine.arguments[0])).standardizedFileURL
    guard
      helper.deletingLastPathComponent() == executable.deletingLastPathComponent(),
      helper.lastPathComponent == "webkitui-mcp-confirm",
      FileManager.default.isExecutableFile(atPath: helper.path),
      let helperIdentity = validatedSigningIdentity(at: helper),
      let executableIdentity = validatedSigningIdentity(at: executable),
      helperIdentity.team == executableIdentity.team,
      helperIdentity.identifier == "com.lorislab.webkitui-mcp.confirm"
    else {
      return false
    }
    return true
  }

  private static func validatedSigningIdentity(at url: URL) -> (team: String, identifier: String)? {
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
      let team = values[kSecCodeInfoTeamIdentifier] as? String,
      let identifier = values[kSecCodeInfoIdentifier] as? String,
      !team.isEmpty,
      !identifier.isEmpty
    else {
      return nil
    }
    return (team, identifier)
  }

  private static func verifyRunningHelper(_ processID: pid_t, matches helperURL: URL) -> Bool {
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
      let team = values[kSecCodeInfoTeamIdentifier] as? String,
      let identifier = values[kSecCodeInfoIdentifier] as? String
    else {
      return false
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
