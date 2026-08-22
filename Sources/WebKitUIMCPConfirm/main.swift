import AppKit
import Foundation

private struct NativeConfirmationRequest: Decodable {
  let title: String
  let message: String
  let approveLabel: String

  func validate() -> Bool {
    !title.isEmpty && title.count <= 120
      && !message.isEmpty && message.count <= 20_000
      && !approveLabel.isEmpty && approveLabel.count <= 80
  }
}

@main
private struct WebKitUIMCPConfirm {
  @MainActor
  static func main() {
    guard
      CommandLine.arguments.count == 1,
      let data = try? FileHandle.standardInput.readToEnd(),
      !data.isEmpty,
      let request = try? JSONDecoder().decode(NativeConfirmationRequest.self, from: data),
      request.validate()
    else {
      Foundation.exit(EX_USAGE)
    }

    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    application.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = request.title
    alert.informativeText = request.message
    let cancelButton = alert.addButton(withTitle: "Cancel")
    cancelButton.keyEquivalent = "\r"
    let approveButton = alert.addButton(withTitle: request.approveLabel)
    approveButton.keyEquivalent = ""
    let approved = alert.runModal() == .alertSecondButtonReturn
    Foundation.exit(approved ? EXIT_SUCCESS : 2)
  }
}
