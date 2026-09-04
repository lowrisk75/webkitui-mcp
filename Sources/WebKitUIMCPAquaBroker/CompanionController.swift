import AppKit
import Darwin
import Foundation
import ServiceManagement
import WebKitUIMCPLicensing
import WebKitUIMCPRuntime
import WebKitUIMCPServer

private final class TopAnchoredDocumentView: NSView {
  override var isFlipped: Bool { true }
}

private final class StatusBackgroundView: NSView {
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    NSColor.windowBackgroundColor.setFill()
    dirtyRect.fill()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
}

private final class StatusCardView: NSView {
  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
    NSColor.controlBackgroundColor.setFill()
    path.fill()
    NSColor.separatorColor.setStroke()
    path.lineWidth = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 2 : 1
    path.stroke()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
}

@MainActor
final class WebKitUICompanionController: NSObject, NSApplicationDelegate, NSWindowDelegate {
  struct StatusLayoutAudit: Codable {
    let language: String
    let title: String
    let subtitle: String
    let prepareToUninstallTitle: String
    let scrollOriginX: Double
    let scrollOriginY: Double
    let titleIsFullyVisible: Bool
    let subtitleIsFullyVisible: Bool
  }

  private let statusItem: NSStatusItem
  private let window: NSWindow
  private let localizationBundle: Bundle
  private let licenseValue = NSTextField(wrappingLabelWithString: "")
  private let serviceValue = NSTextField(wrappingLabelWithString: "")
  private let launchAtLoginValue = NSTextField(wrappingLabelWithString: "")
  private let socketValue = NSTextField(wrappingLabelWithString: "")
  private let launchAtLoginButton = NSButton()
  private let goalValue = NSTextField(labelWithString: "")
  private let goalDetail = NSTextField(wrappingLabelWithString: "")
  private let goalStopButton = NSButton()
  private let ownedSocket: SocketOwnership?
  private let activityWindowController: ActivityLogWindowController
  private let goalDelegationMonitor: GoalDelegationMonitor
  private weak var statusScrollView: NSScrollView?

  init(
    application: NSApplication,
    ownedSocket: SocketOwnership? = nil,
    activityLog: WebKitActivityLog? = nil,
    goalDelegationMonitor: GoalDelegationMonitor = GoalDelegationMonitor(),
    localizationBundle: Bundle = .main,
    automaticallyShowsStatus: Bool = true,
    automaticallyRefreshesStatus: Bool = true
  ) {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    self.ownedSocket = ownedSocket
    self.localizationBundle = localizationBundle
    self.activityWindowController = ActivityLogWindowController(activityLog: activityLog)
    self.goalDelegationMonitor = goalDelegationMonitor
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 610),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    super.init()
    application.delegate = self
    configureStatusItem(application: application)
    configureWindow()
    if automaticallyRefreshesStatus { refreshStatus() }
    if automaticallyShowsStatus, SMAppService.mainApp.status != .enabled {
      DispatchQueue.main.async { [weak self] in self?.showStatus() }
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    ownedSocket?.removeIfStillOwned()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
    -> Bool
  {
    showStatus()
    return true
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
    menu.addItem(
      NSMenuItem(
        title: text("Open Activity Journal"),
        action: #selector(showActivityLog),
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
    window.minSize = NSSize(width: 620, height: 520)
    window.delegate = self
    window.center()

    let title = NSTextField(labelWithString: text("WebKitUI MCP"))
    title.font = .systemFont(ofSize: 30, weight: .bold)
    title.maximumNumberOfLines = 2
    title.setAccessibilityIdentifier("webkitui.status.title")
    let subtitle = NSTextField(
      wrappingLabelWithString: text(
        "Local browser authority for sessions, approvals and private receipts."))
    subtitle.textColor = .secondaryLabelColor
    subtitle.font = .systemFont(ofSize: 14)
    subtitle.setAccessibilityIdentifier("webkitui.status.subtitle")

    let headerIcon = NSImageView()
    headerIcon.image = NSImage(
      systemSymbolName: "checkmark.shield.fill",
      accessibilityDescription: text("Local browser authority"))
    headerIcon.contentTintColor = .systemBlue
    headerIcon.symbolConfiguration = .init(pointSize: 34, weight: .semibold)
    headerIcon.setContentHuggingPriority(.required, for: .horizontal)
    let headerText = NSStackView(views: [title, subtitle])
    headerText.orientation = .vertical
    headerText.alignment = .leading
    headerText.spacing = 4
    let header = NSStackView(views: [headerIcon, headerText])
    header.orientation = .horizontal
    header.alignment = .centerY
    header.spacing = 14

    let service = statusRow(
      label: text("Service"), value: serviceValue, identifier: "webkitui.status.service")
    let launchAtLogin = statusRow(
      label: text("Launch at login"), value: launchAtLoginValue,
      identifier: "webkitui.status.launch-at-login")
    let license = statusRow(
      label: text("License"), value: licenseValue, identifier: "webkitui.status.license")
    let socket = statusRow(
      label: text("Relay socket"), value: socketValue, identifier: "webkitui.status.socket",
      monospaced: true)
    let authorityCard = card(
      title: text("Browser authority"), views: [service, launchAtLogin, license, socket])

    goalValue.font = .systemFont(ofSize: 15, weight: .semibold)
    goalValue.textColor = .labelColor
    goalValue.setAccessibilityIdentifier("webkitui.goal.title")
    goalDetail.font = .systemFont(ofSize: 12)
    goalDetail.textColor = .secondaryLabelColor
    goalDetail.maximumNumberOfLines = 3
    goalDetail.setAccessibilityIdentifier("webkitui.goal.detail")
    goalValue.stringValue = text("No temporary authorization active")
    goalDetail.stringValue = text(
      "WebKitUI will request an exact confirmation for consequential navigation.")
    goalStopButton.title = text("Stop temporary authorization")
    goalStopButton.target = self
    goalStopButton.action = #selector(stopGoalDelegation)
    goalStopButton.bezelStyle = .rounded
    goalStopButton.contentTintColor = .systemRed
    goalStopButton.setAccessibilityIdentifier("webkitui.goal.stop")
    goalStopButton.isHidden = true
    let goalCard = card(
      title: text("Temporary goal authorization"),
      views: [goalValue, goalDetail, goalStopButton])
    goalValue.isHidden = false
    goalDetail.isHidden = false
    goalStopButton.isHidden = true
    goalDetail.widthAnchor.constraint(equalTo: goalCard.widthAnchor, constant: -32).isActive = true

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
    let activity = NSButton(
      title: text("Activity journal"), target: self, action: #selector(showActivityLog))
    activity.bezelStyle = .rounded
    activity.setAccessibilityIdentifier("webkitui.action.activity-log")
    let buttons = NSStackView(views: [launchAtLoginButton, receipts, activity])
    buttons.orientation = .horizontal
    buttons.spacing = 8
    buttons.alignment = .centerY
    buttons.setContentHuggingPriority(.required, for: .vertical)
    buttons.setContentCompressionResistancePriority(.required, for: .vertical)

    let secondaryButtons = NSStackView(views: [copySetup, docs])
    secondaryButtons.orientation = .horizontal
    secondaryButtons.spacing = 8
    secondaryButtons.alignment = .centerY
    secondaryButtons.setContentHuggingPriority(.required, for: .vertical)
    secondaryButtons.setContentCompressionResistancePriority(.required, for: .vertical)
    let prepareToUninstall = NSButton(
      title: text("Prepare to uninstall"),
      target: self,
      action: #selector(prepareToUninstall)
    )
    prepareToUninstall.bezelStyle = .rounded
    prepareToUninstall.setAccessibilityIdentifier("webkitui.action.prepare-uninstall")
    let actionsCard = card(title: text("Quick actions"), views: [secondaryButtons, buttons])

    let note = NSTextField(
      wrappingLabelWithString: text(
        "Developer Preview · Browser data, credentials and page content stay on this Mac. Sensitive actions always fail closed."
      ))
    note.textColor = .secondaryLabelColor
    note.font = .systemFont(ofSize: 12)
    note.setAccessibilityIdentifier("webkitui.status.preview-note")

    let content = NSStackView(
      views: [
        header, authorityCard, goalCard, actionsCard, prepareToUninstall, note,
      ])
    content.orientation = .vertical
    content.alignment = .leading
    content.spacing = 16
    content.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)
    let document = TopAnchoredDocumentView()
    document.translatesAutoresizingMaskIntoConstraints = false
    let scrollView = NSScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.documentView = document
    statusScrollView = scrollView
    content.translatesAutoresizingMaskIntoConstraints = false
    let windowBackground = StatusBackgroundView()
    window.contentView = windowBackground
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
      header.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -56),
      authorityCard.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -56),
      goalCard.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -56),
      actionsCard.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -56),
      note.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -56),
    ])
    window.initialFirstResponder = nil
  }

  func renderStatusSnapshot(to url: URL) throws {
    refreshStatus()
    guard let contentView = window.contentView else {
      throw CocoaError(.featureUnsupported)
    }
    contentView.frame = NSRect(origin: .zero, size: window.contentLayoutRect.size)
    contentView.layoutSubtreeIfNeeded()
    contentView.displayIfNeeded()
    guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
      throw CocoaError(.fileWriteUnknown)
    }
    contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
      throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url, options: .atomic)
  }

  func auditStatusLayout(language: String) throws -> StatusLayoutAudit {
    guard let scrollView = statusScrollView,
      let title = descendant(withAccessibilityIdentifier: "webkitui.status.title"),
      let subtitle = descendant(withAccessibilityIdentifier: "webkitui.status.subtitle"),
      let prepareToUninstall = descendant(
        withAccessibilityIdentifier: "webkitui.action.prepare-uninstall") as? NSButton
    else {
      throw CocoaError(.featureUnsupported)
    }
    window.contentView?.layoutSubtreeIfNeeded()
    scrollView.documentView?.layoutSubtreeIfNeeded()
    scrollView.contentView.scroll(to: NSPoint(x: 0, y: 10_000))
    resetStatusScrollPosition()

    let viewport = scrollView.contentView.bounds
    let titleFrame = title.convert(title.bounds, to: scrollView.contentView)
    let subtitleFrame = subtitle.convert(subtitle.bounds, to: scrollView.contentView)
    return StatusLayoutAudit(
      language: language,
      title: (title as? NSTextField)?.stringValue ?? "",
      subtitle: (subtitle as? NSTextField)?.stringValue ?? "",
      prepareToUninstallTitle: prepareToUninstall.title,
      scrollOriginX: scrollView.contentView.bounds.origin.x,
      scrollOriginY: scrollView.contentView.bounds.origin.y,
      titleIsFullyVisible: viewport.contains(titleFrame),
      subtitleIsFullyVisible: viewport.contains(subtitleFrame)
    )
  }

  private func descendant(withAccessibilityIdentifier identifier: String) -> NSView? {
    func find(in view: NSView) -> NSView? {
      if view.accessibilityIdentifier() == identifier { return view }
      for child in view.subviews {
        if let match = find(in: child) { return match }
      }
      return nil
    }
    guard let contentView = window.contentView else { return nil }
    return find(in: contentView)
  }

  private func card(title: String, views: [NSView]) -> NSView {
    let heading = NSTextField(labelWithString: title)
    heading.font = .systemFont(ofSize: 13, weight: .semibold)
    heading.textColor = .secondaryLabelColor
    let stack = NSStackView(views: [heading] + views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    let box = StatusCardView()
    box.setAccessibilityRole(.group)
    box.setAccessibilityLabel(title)
    box.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
      stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -16),
    ])
    return box
  }

  private func statusRow(
    label: String,
    value: NSTextField,
    identifier: String,
    monospaced: Bool = false
  ) -> NSView {
    let key = NSTextField(labelWithString: label)
    key.font = .systemFont(ofSize: 13, weight: .medium)
    key.textColor = .secondaryLabelColor
    key.setContentHuggingPriority(.required, for: .horizontal)
    key.setAccessibilityElement(false)
    key.widthAnchor.constraint(equalToConstant: 150).isActive = true
    value.font =
      monospaced
      ? .monospacedSystemFont(ofSize: 13, weight: .regular)
      : .systemFont(ofSize: 13, weight: .regular)
    value.maximumNumberOfLines = 2
    value.lineBreakMode = .byWordWrapping
    value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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
    if window.isMiniaturized { window.deminiaturize(nil) }
    NSApplication.shared.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    window.makeFirstResponder(nil)
    resetStatusScrollPosition()
    DispatchQueue.main.async { [weak self] in self?.resetStatusScrollPosition() }
  }

  private func resetStatusScrollPosition() {
    guard let scrollView = statusScrollView else { return }
    window.contentView?.layoutSubtreeIfNeeded()
    scrollView.documentView?.layoutSubtreeIfNeeded()
    scrollView.contentView.scroll(to: .zero)
    scrollView.reflectScrolledClipView(scrollView.contentView)
  }

  @objc private func refreshStatusAction() { refreshStatus() }

  @objc private func showActivityLog() { activityWindowController.show() }

  private func refreshStatus() {
    let active = socketIsActive
    setStatusValue(
      serviceValue,
      active
        ? text("Running — local socket active")
        : text("Needs attention — local socket unavailable")
    )
    updateStatusIcon(active: active)
    let abbreviatedSocket = socketPath.replacingOccurrences(
      of: FileManager.default.homeDirectoryForCurrentUser.path
        + "/Library/Application Support/",
      with: "~/…/"
    )
    setStatusValue(socketValue, abbreviatedSocket)
    socketValue.toolTip = socketPath
    socketValue.setAccessibilityValue(socketPath)
    refreshLaunchAtLoginStatus()
    refreshGoalDelegation()
    setStatusValue(licenseValue, text("Checking…"))
    let manager = WebKitUILicenseManager(
      store: WebKitUIKeychainLicenseStore(),
      api: WebKitUILicenseHTTPAPI(),
      verifier: WebKitUIRS256TokenVerifier.bundled(),
      appVersion: { WebKitUIRelease.version })
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

  private func refreshGoalDelegation() {
    Task { @MainActor [weak self] in
      guard let self else { return }
      if let snapshot = await goalDelegationMonitor.snapshot() {
        goalValue.stringValue = snapshot.goalDisplay
        let remaining = String(
          format: text("%ld navigations remaining"), snapshot.remainingNavigations)
        let expiry = RelativeDateTimeFormatter().localizedString(
          for: snapshot.expiresAt, relativeTo: Date())
        goalDetail.stringValue = "\(snapshot.origin) · \(remaining) · \(expiry)"
        goalStopButton.isHidden = false
      } else {
        goalValue.stringValue = text("No temporary authorization active")
        goalDetail.stringValue = text(
          "WebKitUI will request an exact confirmation for consequential navigation.")
        goalStopButton.isHidden = true
      }
    }
  }

  @objc private func stopGoalDelegation() {
    Task { @MainActor [weak self] in
      guard let self else { return }
      _ = await goalDelegationMonitor.requestImmediateRevocation()
      refreshGoalDelegation()
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
    NSLocalizedString(value, bundle: localizationBundle, comment: "WebKitUI MCP companion")
  }
}
