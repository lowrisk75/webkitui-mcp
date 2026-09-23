import AppKit
import WebKit

/// Real pop-up windows for a person holding the human control window.
///
/// A "Sign in with Google" or "Sign in with Apple" button opens a window and reports
/// back to the page through `window.opener`. Refusing the window, which is right while
/// an agent drives, left a person unable to finish such a sign-in in the handoff
/// window at all. While a person holds control, the pop-up is shown as a real window
/// built from the configuration WebKit hands over, so it shares the page's profile,
/// its protected proxy and its opener. The agent never sees these windows: they are
/// closed when control returns to it, and there are at most four.
@MainActor
final class HumanPopupWindows: NSObject, WKUIDelegate, NSWindowDelegate {
  static let maximumWindows = 4

  private var windows: [ObjectIdentifier: NSWindow] = [:]

  var openCount: Int { windows.count }

  func open(
    configuration: WKWebViewConfiguration,
    windowFeatures: WKWindowFeatures,
    above parent: NSWindow?
  ) -> WKWebView? {
    guard windows.count < Self.maximumWindows else { return nil }
    // The size a site asks for is only a hint, bounded to something usable.
    let width = min(max(windowFeatures.width?.doubleValue ?? 520, 320), 1_400)
    let height = min(max(windowFeatures.height?.doubleValue ?? 640, 240), 1_000)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: width, height: height),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false)
    window.isReleasedWhenClosed = false
    window.title = "WebkitUIMCP — Pop-up"
    window.level = .floating
    window.delegate = self
    let popup = WKWebView(frame: window.contentLayoutRect, configuration: configuration)
    popup.uiDelegate = self
    popup.autoresizingMask = [.width, .height]
    window.contentView = popup
    if let parent {
      let frame = parent.frame
      window.setFrameOrigin(
        NSPoint(x: frame.midX - width / 2, y: frame.midY - height / 2))
    } else {
      window.center()
    }
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    windows[ObjectIdentifier(popup)] = window
    return popup
  }

  func closeAll() {
    for window in windows.values {
      window.delegate = nil
      window.orderOut(nil)
      window.contentView = nil
      window.close()
    }
    windows.removeAll()
  }

  // MARK: WKUIDelegate

  func webView(
    _ webView: WKWebView,
    createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction,
    windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    open(configuration: configuration, windowFeatures: windowFeatures, above: webView.window)
  }

  func webViewDidClose(_ webView: WKWebView) {
    guard let window = windows.removeValue(forKey: ObjectIdentifier(webView)) else { return }
    window.delegate = nil
    window.orderOut(nil)
    window.contentView = nil
    window.close()
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptAlertPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo
  ) async {
    _ = runAlert(message: message, frame: frame, buttons: ["OK"])
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptConfirmPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo
  ) async -> Bool {
    runAlert(message: message, frame: frame, buttons: ["OK", "Cancel"]) == .alertFirstButtonReturn
  }

  // MARK: NSWindowDelegate

  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    windows = windows.filter { $0.value !== window }
  }

  private func runAlert(
    message: String, frame: WKFrameInfo, buttons: [String]
  ) -> NSApplication.ModalResponse {
    let alert = NSAlert()
    // The message is the site's text: shown as such, under the site's own origin.
    let origin = frame.securityOrigin
    alert.messageText = "\(origin.protocol)://\(origin.host)"
    alert.informativeText = String(message.prefix(2_000))
    for title in buttons { alert.addButton(withTitle: title) }
    return alert.runModal()
  }
}
