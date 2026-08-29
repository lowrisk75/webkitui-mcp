import AppKit
import Foundation
import LocalAuthentication
import WebKit
import WebKitUIMCPLicensing
import WebKitUIMCPRuntime
import WebKitUIMCPServer

@main
struct WebKitUIMCPCLI {
  @MainActor
  static func main() async {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["doctor"] {
      await runDoctor()
      return
    }
    if arguments.first == "license" {
      await runLicenseCommand(Array(arguments.dropFirst()))
      return
    }
    if arguments.contains(where: { $0 == "--help" || $0 == "-h" }) {
      FileHandle.standardOutput.write(
        Data(
          """
          Usage:
            webkitui-mcp
            webkitui-mcp doctor
            webkitui-mcp license status
            webkitui-mcp license activate WEBKITUI-XXXX-XXXX-XXXX-XXXX
            webkitui-mcp license refresh
            webkitui-mcp license deactivate

          Native WebKit MCP server. Reads newline-delimited JSON-RPC from stdin and writes responses to stdout.

          Commercial activation is optional for uses permitted directly by the BSL
          Additional Use Grant. The license key is never exposed through MCP.

          doctor performs local, secret-free readiness checks. It never authenticates,
          opens a website, contacts the license service, or reads browser data.
          """.utf8))
      FileHandle.standardOutput.write(Data("\n".utf8))
      return
    }
    let visualSmokeTest = CommandLine.arguments.dropFirst().contains("--visual-smoke-test")
    guard CommandLine.arguments.count == 1 || visualSmokeTest else {
      FileHandle.standardError.write(
        Data("webkitui-mcp: unexpected arguments; use --help\n".utf8))
      Foundation.exit(EX_USAGE)
    }

    let application = NSApplication.shared
    WebKitNativeApplicationMenu.install(on: application)
    application.finishLaunching()
    application.setActivationPolicy(.accessory)
    if visualSmokeTest {
      runVisualSmokeTest()
      return
    }
    Task { @MainActor in
      await runProtocolServer()
    }
    application.run()
  }

  private static func runDoctor() async {
    let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let helperURL = executableURL.deletingLastPathComponent()
      .appendingPathComponent("webkitui-mcp-confirm")
    let helperAvailable = FileManager.default.isExecutableFile(atPath: helperURL.path)

    let context = LAContext()
    var authenticationError: NSError?
    let authenticationAvailable = context.canEvaluatePolicy(
      .deviceOwnerAuthentication,
      error: &authenticationError
    )
    let biometry: String
    switch context.biometryType {
    case .touchID: biometry = "touch_id"
    case .faceID: biometry = "face_id"
    case .opticID: biometry = "optic_id"
    case .none: biometry = "none"
    @unknown default: biometry = "unknown"
    }

    let licenseState: String
    do {
      licenseState = try await makeLicenseManager().status().state.rawValue
    } catch {
      licenseState = "unavailable"
    }

    let readiness: String
    if !helperAvailable {
      readiness = "action_required"
    } else if !authenticationAvailable {
      readiness = "ready_without_siliconpass_fill"
    } else {
      readiness = "ready"
    }
    let runtime: [String: Any] = [
      "architecture": runtimeArchitecture(),
      "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
    ]
    let nativeConfirmation: [String: Any] = [
      "helperAvailable": helperAvailable,
      "expectedPlacement": "beside_webkitui_mcp_executable",
      "requiredAction": helperAvailable
        ? NSNull()
        : "Install webkitui-mcp-confirm beside the webkitui-mcp executable.",
    ]
    let credentialAuthorization: [String: Any] = [
      "policy": "device_owner_authentication",
      "available": authenticationAvailable,
      "biometry": biometry,
      "macOSFallback": "system_managed_device_owner_authentication",
      "closedLidBehavior": "not_inferred_check_locally",
      "unavailableBehavior": "fail_closed_without_secret_release_or_automatic_retry",
      "requiredAction": authenticationAvailable
        ? NSNull()
        : "Run from an unlocked interactive Mac session and complete the authentication method offered by macOS. Closed-lid availability must be checked on this Mac.",
      "errorCode": authenticationError.map { String($0.code) } ?? NSNull(),
    ]
    let commercialLicense: [String: Any] = [
      "state": licenseState,
      "requiredForPermittedEvaluation": false,
    ]
    let privacy: [String: Any] = [
      "browserDataRead": false,
      "credentialsRead": false,
      "networkRequestMade": false,
    ]
    let report: [String: Any] = [
      "ok": helperAvailable,
      "readiness": readiness,
      "runtime": runtime,
      "nativeConfirmation": nativeConfirmation,
      "credentialAuthorization": credentialAuthorization,
      "commercialLicense": commercialLicense,
      "privacy": privacy,
    ]
    writeJSON(report)
  }

  private static func runtimeArchitecture() -> String {
    #if arch(arm64)
      "arm64"
    #elseif arch(x86_64)
      "x86_64"
    #else
      "unknown"
    #endif
  }

  private static func makeLicenseManager() -> WebKitUILicenseManager {
    WebKitUILicenseManager(
      store: WebKitUIKeychainLicenseStore(),
      api: WebKitUILicenseHTTPAPI(),
      verifier: WebKitUIRS256TokenVerifier.bundled(),
      appVersion: {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
          ?? "source-build"
      }
    )
  }

  private static func runLicenseCommand(_ arguments: [String]) async {
    let manager = makeLicenseManager()
    do {
      if arguments == ["status"] {
        writeLicenseStatus(try await manager.status())
      } else if arguments.count == 2, arguments.first == "activate" {
        writeLicenseStatus(try await manager.activate(licenseKey: arguments[1]))
      } else if arguments == ["deactivate"] {
        try await manager.deactivate()
        writeJSON(["deactivated": true, "state": "none"])
      } else if arguments == ["refresh"] {
        writeLicenseStatus(try await manager.refresh())
      } else {
        FileHandle.standardError.write(
          Data(
            "webkitui-mcp: expected license status, license activate KEY, license refresh, or license deactivate\n"
              .utf8
          ))
        Foundation.exit(EX_USAGE)
      }
    } catch {
      writeLicenseError(error)
      Foundation.exit(EXIT_FAILURE)
    }
  }

  private static func writeLicenseStatus(_ status: WebKitUILicenseStatus) {
    var payload: [String: Any] = ["state": status.state.rawValue]
    if let value = status.maskedKey { payload["licenseKey"] = value }
    if let value = status.organization { payload["organization"] = value }
    if let value = status.plan { payload["plan"] = value }
    if let value = status.seatLimit { payload["seatLimit"] = value }
    if let value = status.machineLimit { payload["machineLimit"] = value }
    if let value = status.expiresAt {
      payload["expiresAt"] = ISO8601DateFormatter().string(from: value)
    }
    writeJSON(payload)
  }

  private static func writeLicenseError(_ error: Error) {
    let code: String
    switch error {
    case WebKitUILicenseError.invalidKey: code = "invalid_license"
    case WebKitUILicenseError.machineLimitReached: code = "machine_limit_reached"
    case WebKitUILicenseError.inactiveSubscription: code = "inactive_subscription"
    case WebKitUILicenseError.revoked: code = "revoked"
    case WebKitUILicenseError.tokenVerificationFailed: code = "token_verification_failed"
    case WebKitUILicenseError.clockRollbackDetected: code = "clock_rollback_detected"
    case WebKitUILicenseError.secureStorage: code = "secure_storage_failed"
    case WebKitUILicenseError.transport: code = "transport_failed"
    default: code = "license_command_failed"
    }
    let data = try? JSONSerialization.data(withJSONObject: ["error": code, "ok": false])
    FileHandle.standardError.write(data ?? Data("{\"ok\":false}".utf8))
    FileHandle.standardError.write(Data("\n".utf8))
  }

  private static func writeJSON(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    else {
      return
    }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  }

  @MainActor
  private static func runVisualSmokeTest() {
    Task { @MainActor in
      let runtime = WebKitRuntime(websiteDataStore: .nonPersistent())
      do {
        _ = try await runtime.loadHTML(
          """
          <!doctype html>
          <title>WebkitUIMCP direct stdio visual smoke test</title>
          <style>
            html, body { margin: 0; width: 100%; height: 100%; background: #31572c; }
            h1 { color: white; font: 48px -apple-system; padding: 64px; }
          </style>
          <h1>WebkitUIMCP direct stdio visual smoke test</h1>
          """,
          baseURL: URL(string: "https://fixture.invalid/direct-visual-smoke"),
          timeout: .seconds(5),
          quietWindow: .milliseconds(50)
        )
        try runtime.requestHumanHandoff()
        try runtime.beginHumanControl(presentWindow: true)
      } catch {
        FileHandle.standardError.write(Data("direct visual smoke test failed: \(error)\n".utf8))
      }
    }
    NSApplication.shared.run()
  }

  @MainActor
  private static func runProtocolServer() async {
    do {
      let server = try WebKitMCPServer(
        maximumSessions: 1,
        enforceHostExclusiveSession: true,
        transactionLedgerFactory: .durable()
      )
      for try await line in FileHandle.standardInput.bytes.lines {
        if let response = await server.handle(Data(line.utf8)) {
          FileHandle.standardOutput.write(response)
          FileHandle.standardOutput.write(Data("\n".utf8))
        }
      }
      Foundation.exit(EXIT_SUCCESS)
    } catch {
      FileHandle.standardError.write(Data("webkitui-mcp stopped: \(error)\n".utf8))
      Foundation.exit(EXIT_FAILURE)
    }
  }
}
