import AppKit
import Darwin
import Foundation
import ServiceManagement
import WebKitUIMCPLicensing

@MainActor
final class WebKitUICompanionController: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private let statusItem: NSStatusItem
  private let window: NSWindow
  private let licenseValue = NSTextField(labelWithString: "")
  private let serviceValue = NSTextField(labelWithString: "")
  private let launchAtLoginValue = NSTextField(labelWithString: "")
  private let socketValue = NSTextField(wrappingLabelWithString: "")
  private let launchAtLoginButton = NSButton()
  private let ownedSocket: SocketOwnership?

  init(application: NSApplication, ownedSocket: SocketOwnership? = nil) {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    self.ownedSocket = ownedSocket
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 450),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    super.init()
    application.delegate = self
    configureStatusItem(application: application)
    configureWindow()
    refreshStatus()
    if SMAppService.mainApp.status != .enabled {
      DispatchQueue.main.async { [weak self] in self?.showStatus() }
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    ownedSocket?.removeIfStillOwned()
  }

  private func configureStatusItem(application: NSApplication) {
    if let button = statusItem.button {
      button.image = NSImage(
        systemSymbolName: "checkmark.shield.fill",
        accessibilityDescription: text("WebKitUI MCP status"))
      button.toolTip = text("WebKitUI MCP — local authority")
    }
    let menu = NSMenu(title: "WebKitUI MCP")
    menu.addItem(
      NSMenuItem(
        title: text("Open WebKitUI MCP Status"),
        action: #selector(showStatus),
        keyEquivalent: ""))
    menu.addItem(
      NSMenuItem(
        title: text("Refresh License Status"),
        action: #selector(refreshStatusAction),
        keyEquivalent: ""))
    menu.addItem(.separator())
    menu.addItem(
      NSMenuItem(
        title: text("Quit WebKitUI MCP"),
        action: #selector(application.terminate(_:)),
        keyEquivalent: "q"))
    for item in menu.items where item.action != #selector(application.terminate(_:)) {
      item.target = self
    }
    statusItem.menu = menu
  }

  private func configureWindow() {
    window.title = text("WebKitUI MCP Status")
    window.isReleasedWhenClosed = false
    window.minSize = NSSize(width: 560, height: 360)
    window.delegate = self
    window.center()

    let title = NSTextField(labelWithString: text("Local browser authority"))
    title.font = .systemFont(ofSize: 26, weight: .semibold)
    title.maximumNumberOfLines = 2
    title.setAccessibilityIdentifier("webkitui.status.title")
    let subtitle = NSTextField(
      wrappingLabelWithString: text(
        "One MCP authority keeps sessions, exact approvals and durable receipts on this Mac."))
    subtitle.textColor = .secondaryLabelColor
    subtitle.setAccessibilityIdentifier("webkitui.status.subtitle")

    let service = statusRow(
      label: text("Service"), value: serviceValue, identifier: "webkitui.status.service")
    let launchAtLogin = statusRow(
      label: text("Launch at login"), value: launchAtLoginValue,
      identifier: "webkitui.status.launch-at-login")
    let license = statusRow(
      label: text("License"), value: licenseValue, identifier: "webkitui.status.license")
    let socket = statusRow(
      label: text("Relay socket"), value: socketValue, identifier: "webkitui.status.socket")

    let copySetup = NSButton(
      title: text("Copy Codex setup command"), target: self, action: #selector(copySetupCommand))
    copySetup.bezelStyle = .rounded
    copySetup.setAccessibilityIdentifier("webkitui.action.copy-setup")
    launchAtLoginButton.target = self
    launchAtLoginButton.action = #selector(configureLaunchAtLogin)
    launchAtLoginButton.bezelStyle = .rounded
    launchAtLoginButton.setAccessibilityIdentifier("webkitui.action.launch-at-login")
    let receipts = NSButton(
      title: text("Show receipts"), target: self, action: #selector(showReceipts))
    receipts.bezelStyle = .rounded
    receipts.setAccessibilityIdentifier("webkitui.action.show-receipts")
    let docs = NSButton(
      title: text("Open documentation"), target: self, action: #selector(openDocs))
    docs.bezelStyle = .rounded
    docs.setAccessibilityIdentifier("webkitui.action.open-documentation")
    let buttons = NSStackView(views: [launchAtLoginButton, receipts])
    buttons.orientation = .horizontal
    buttons.spacing = 8
    buttons.alignment = .centerY

    let secondaryButtons = NSStackView()
    secondaryButtons.orientation = .horizontal
    secondaryButtons.spacing = 8
    let prepareToUninstall = NSButton(
      title: text("Prepare to uninstall"),
      target: self,
      action: #selector(prepareToUninstall)
    )
    prepareToUninstall.bezelStyle = .rounded
    prepareToUninstall.contentTintColor = .secondaryLabelColor
    prepareToUninstall.setAccessibilityIdentifier("webkitui.action.prepare-uninstall")
    secondaryButtons.addArrangedSubview(copySetup)
    secondaryButtons.addArrangedSubview(docs)

    let uninstallButtons = NSStackView(views: [prepareToUninstall])
    uninstallButtons.orientation = .horizontal
    uninstallButtons.spacing = 8

    let note = NSTextField(
      wrappingLabelWithString: text(
        "Developer Preview. Authentication availability is checked locally when needed; if macOS cannot present it, credential release fails closed."
      ))
    note.textColor = .tertiaryLabelColor
    note.font = .systemFont(ofSize: 12)
    note.setAccessibilityIdentifier("webkitui.status.preview-note")

    let content = NSStackView(
      views: [
        title, subtitle, service, launchAtLogin, license, socket, buttons, secondaryButtons,
        uninstallButtons, note,
      ])
    content.orientation = .vertical
    content.alignment = .leading
    content.spacing = 18
    content.edgeInsets = NSEdgeInsets(top: 28, left: 30, bottom: 28, right: 30)
    let document = NSView()
    document.translatesAutoresizingMaskIntoConstraints = false
    let scrollView = NSScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.documentView = document
    content.translatesAutoresizingMaskIntoConstraints = false
    window.contentView = NSView()
    window.contentView?.addSubview(scrollView)
    document.addSubview(content)
    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
      document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
      content.leadingAnchor.constraint(equalTo: document.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: document.trailingAnchor),
      content.topAnchor.constraint(equalTo: document.topAnchor),
      content.bottomAnchor.constraint(equalTo: document.bottomAnchor),
      subtitle.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -60),
      note.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -60),
    ])
    window.initialFirstResponder = docs
  }

  private func statusRow(label: String, value: NSTextField, identifier: String) -> NSView {
    let key = NSTextField(labelWithString: label)
    key.font = .systemFont(ofSize: 13, weight: .medium)
    key.textColor = .secondaryLabelColor
    key.setContentHuggingPriority(.required, for: .horizontal)
    key.setAccessibilityElement(false)
    value.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    value.maximumNumberOfLines = 2
    value.setAccessibilityLabel(label)
    value.setAccessibilityIdentifier(identifier)
    let row = NSStackView(views: [key, value])
    row.orientation = .horizontal
    row.spacing = 14
    row.alignment = .firstBaseline
    return row
  }

  @objc private func showStatus() {
    refreshStatus()
    window.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  @objc private func refreshStatusAction() { refreshStatus() }

  private func refreshStatus() {
    let active = socketIsActive
    setStatusValue(
      serviceValue,
      active
        ? text("Running — local socket active")
        : text("Needs attention — local socket unavailable")
    )
    updateStatusIcon(active: active)
    setStatusValue(
      socketValue,
      socketPath.replacingOccurrences(
        of: FileManager.default.homeDirectoryForCurrentUser.path,
        with: "~"
      ))
    refreshLaunchAtLoginStatus()
    setStatusValue(licenseValue, text("Checking…"))
    let manager = WebKitUILicenseManager(
      store: WebKitUIKeychainLicenseStore(),
      api: WebKitUILicenseHTTPAPI(),
      verifier: WebKitUIRS256TokenVerifier.bundled(),
      appVersion: { "0.6.0" })
    Task { @MainActor [weak self] in
      do {
        let status = try await manager.status()
        guard let self else { return }
        self.setStatusValue(
          self.licenseValue,
          self.licenseLabel(for: status.state)
            + (status.maskedKey.map { " · \($0)" } ?? "")
        )
      } catch {
        guard let self else { return }
        self.setStatusValue(
          self.licenseValue,
          self.text("Unavailable — secure storage error")
        )
      }
    }
  }

  private func setStatusValue(_ field: NSTextField, _ value: String) {
    field.stringValue = value
    field.setAccessibilityValue(value)
  }

  private func updateStatusIcon(active: Bool) {
    statusItem.button?.image = NSImage(
      systemSymbolName: active ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
      accessibilityDescription: text(
        active ? "WebKitUI MCP status" : "WebKitUI MCP needs attention"))
  }

  private func licenseLabel(for state: WebKitUILicenseState) -> String {
    switch state {
    case .none: text("No license — local preview")
    case .active: text("Active")
    case .grace: text("Grace period")
    case .expired: text("Expired")
    case .invalid: text("Invalid")
    }
  }

  private var socketPath: String {
    if let override = ProcessInfo.processInfo.environment["WEBKITUI_MCP_SOCKET_PATH"],
      override.hasPrefix("/")
    {
      return override
    }
    return FileManager.default.homeDirectoryForCurrentUser
      .appending(
        path: "Library/Application Support/WebkitUIMCP/mcp.sock",
        directoryHint: .notDirectory
      )
      .path
  }

  private var socketIsActive: Bool {
    var information = stat()
    guard socketPath.withCString({ Darwin.lstat($0, &information) }) == 0 else { return false }
    return information.st_mode & S_IFMT == S_IFSOCK
  }

  private func refreshLaunchAtLoginStatus() {
    switch SMAppService.mainApp.status {
    case .enabled:
      setStatusValue(launchAtLoginValue, text("Enabled"))
      launchAtLoginButton.title = text("Open Login Items…")
    case .notRegistered:
      setStatusValue(launchAtLoginValue, text("Not enabled"))
      launchAtLoginButton.title = text("Enable at Login")
    case .requiresApproval:
      setStatusValue(launchAtLoginValue, text("Approval required in System Settings"))
      launchAtLoginButton.title = text("Open Login Items…")
    case .notFound:
      setStatusValue(launchAtLoginValue, text("Unavailable — move the app to Applications"))
      launchAtLoginButton.title = text("Open Login Items…")
    @unknown default:
      setStatusValue(launchAtLoginValue, text("Unavailable"))
      launchAtLoginButton.title = text("Open Login Items…")
    }
  }

  @objc private func configureLaunchAtLogin() {
    switch SMAppService.mainApp.status {
    case .notRegistered:
      do {
        try SMAppService.mainApp.register()
        refreshStatus()
      } catch {
        presentError(
          title: text("Launch at Login could not be enabled"),
          message: error.localizedDescription
        )
      }
    case .enabled, .requiresApproval, .notFound:
      SMAppService.openSystemSettingsLoginItems()
    @unknown default:
      SMAppService.openSystemSettingsLoginItems()
    }
  }

  @objc private func copySetupCommand() {
    let command = Self.setupCommand(
      executableURL: Bundle.main.executableURL,
      socketPath: socketPath
    )
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(command, forType: .string)
  }

  static func setupCommand(executableURL: URL?, socketPath: String) -> String {
    let relayPath =
      executableURL?.deletingLastPathComponent()
      .appending(path: "webkitui-mcp-relay").path
      ?? "webkitui-mcp-relay"
    return "codex mcp add webkitui-mcp -- \(shellQuote(relayPath)) \(shellQuote(socketPath))"
  }

  @objc private func prepareToUninstall() {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = text("Prepare WebKitUI MCP for removal?")
    alert.informativeText = text(
      "This disables Launch at Login. Receipts and license data stay on this Mac. Then quit the app and move it to the Trash."
    )
    alert.addButton(withTitle: text("Disable Launch at Login"))
    alert.addButton(withTitle: text("Cancel"))
    guard alert.runModal() == .alertFirstButtonReturn else { return }

    guard SMAppService.mainApp.status != .notRegistered else {
      showUninstallReadyAlert()
      return
    }
    do {
      try SMAppService.mainApp.unregister()
      refreshStatus()
      showUninstallReadyAlert()
    } catch {
      presentError(
        title: text("Launch at Login could not be disabled"),
        message: error.localizedDescription
      )
    }
  }

  private func showUninstallReadyAlert() {
    let alert = NSAlert()
    alert.messageText = text("Ready to remove")
    alert.informativeText = text(
      "Quit WebKitUI MCP, then move the app to the Trash. Receipts and license data were preserved."
    )
    alert.addButton(withTitle: text("OK"))
    alert.runModal()
  }

  private func presentError(title: String, message: String) {
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: text("OK"))
    alert.runModal()
  }

  private static func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  @objc private func showReceipts() {
    let url = FileManager.default.homeDirectoryForCurrentUser
      .appending(
        path: "Library/Application Support/WebkitUIMCP/Receipts", directoryHint: .isDirectory)
    do {
      try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    } catch {
      presentError(title: text("Receipts are unavailable"), message: error.localizedDescription)
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  @objc private func openDocs() {
    guard
      let configured = Bundle.main.object(forInfoDictionaryKey: "WebKitUIDocumentationURL")
        as? String,
      let url = URL(string: configured),
      url.scheme == "https",
      url.host != nil
    else {
      presentError(
        title: text("Documentation is unavailable"),
        message: text("The packaged documentation URL is missing or invalid.")
      )
      return
    }
    NSWorkspace.shared.open(url)
  }

  private func text(_ value: String) -> String {
    NSLocalizedString(value, bundle: .main, comment: "WebKitUI MCP companion")
  }
}
