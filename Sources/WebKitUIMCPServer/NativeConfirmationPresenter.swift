import Darwin
import Foundation
import Security

@MainActor
protocol BrowserConfirmationPresenting: AnyObject {
  func confirm(title: String, message: String, approveLabel: String) -> Bool
}

@MainActor
final class NativeBrowserConfirmationPresenter: BrowserConfirmationPresenting {
  static let helperProtocolVersion = "1"

  private let helperURL: URL
  private let helperVerification: (URL) -> Bool
  private let runningHelperVerification: ((pid_t) -> Bool)?

  init(
    helperURL: URL? = nil,
    helperVerification: ((URL) -> Bool)? = nil,
    runningHelperVerification: ((pid_t) -> Bool)? = nil
  ) {
    self.helperURL = helperURL ?? Self.defaultHelperURL()
    self.helperVerification = helperVerification ?? Self.verifyPackagedHelper
    self.runningHelperVerification = runningHelperVerification
  }

  func confirm(title: String, message: String, approveLabel: String) -> Bool {
    let payload: Data
    do {
      payload = try JSONEncoder().encode(
        NativeConfirmationRequest(
          title: title,
          message: message,
          approveLabel: approveLabel
        ))
    } catch {
      return false
    }
    guard helperVerification(helperURL) else { return false }
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
        return false
      }
      try Self.writePayload(payload, to: input.fileHandleForWriting)
      try input.fileHandleForWriting.close()
      process.waitUntilExit()
    } catch {
      try? input.fileHandleForWriting.close()
      return false
    }
    return process.terminationReason == .exit && process.terminationStatus == EXIT_SUCCESS
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

private struct NativeConfirmationRequest: Encodable {
  let title: String
  let message: String
  let approveLabel: String
}
