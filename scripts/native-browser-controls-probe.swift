import AppKit
import WebKit

// Compile with NativeBrowserControls.swift. Never validates by pressing Save or
// generating files; use a separate process because native panels can stop the
// async Swift Testing entry loop with exit0 and no summary.
@main
struct NativeControlsProbe {
  @MainActor static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    let parent = NSWindow(
      contentRect: NSRect(x: 100, y: 100, width: 640, height: 400),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    parent.isReleasedWhenClosed = false
    parent.title = "Test local WebKitUI [LOCAL]"
    parent.makeKeyAndOrderFront(nil)
    let presenter = NativeDownloadDestinationPresenter()
    let branch = CommandLine.arguments.dropFirst().first ?? "cancel"
    guard ["cancel", "revoke", "parent-close"].contains(branch) else { exit(64) }
    var current = true
    var passed = false
    Task { @MainActor in
      let cancellation = Task { @MainActor in
        do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
        passed = (parent.attachedSheet as? NSSavePanel)?.isVisible == true
        let duplicate = await presenter.choose(
          filename: "duplicate.txt", parent: parent, isCurrent: { true })
        passed = passed && duplicate == nil
        switch branch {
        case "revoke": current = false
        case "parent-close": parent.close()
        default: presenter.cancel()
        }
      }
      let destination = await presenter.choose(
        filename: "synthetic-only.txt", parent: parent, isCurrent: { current })
      cancellation.cancel()
      passed = passed && destination == nil
      presenter.cancel()
      parent.orderOut(nil)
      print(
        passed
          ? "PASS native sheet \(branch), duplicate refused, no destination, one-shot completion"
          : "FAIL native sheet \(branch)")
      app.stop(nil)
      if let event = NSEvent.otherEvent(
        with: .applicationDefined, location: .zero, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil, subtype: 0,
        data1: 0, data2: 0)
      {
        app.postEvent(event, atStart: true)
      }
    }
    app.run()
    exit(passed ? 0 : 1)
  }
}
