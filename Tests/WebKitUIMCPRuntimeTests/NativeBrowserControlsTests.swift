import AppKit
import Foundation
import Testing
import WebKit

@testable import WebKitUIMCPRuntime

@MainActor
private final class NativeControlPermission {
  var allowed = true
}

@Suite("Native browser controls", .serialized)
@MainActor
struct NativeBrowserControlsTests {
  // Actual native sheet lifecycle is qualified by the dedicated run-loop probe.
  @Test(
    "An unavailable or revoked destination request never opens a sheet", arguments: [false, true])
  func refusedDestinationSheet(revoked: Bool) async throws {
    _ = NSApplication.shared
    let parent = NSWindow(
      contentRect: NSRect(x: 100, y: 100, width: 640, height: 400), styleMask: [.titled],
      backing: .buffered, defer: false)
    parent.isReleasedWhenClosed = false
    if revoked { parent.orderFront(nil) }
    defer {
      parent.orderOut(nil)
      parent.close()
    }
    let presenter = NativeDownloadDestinationPresenter()
    let choice = await presenter.choose(
      filename: "synthetic-only.txt", parent: parent, isCurrent: { !revoked })
    #expect(choice == nil)
    presenter.cancel()
    presenter.cancel()
    #expect(parent.attachedSheet == nil)
  }

  @Test("Native find searches locally and closing invalidates results")
  func nativeFindAndClose() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      "<h1>Local search fixture</h1><p>unique-needle</p>",
      baseURL: URL(string: "https://fixture.invalid/find"), timeout: .seconds(5),
      quietWindow: .milliseconds(40))
    let parent = try #require(runtime.webView.window)
    let permission = NativeControlPermission()
    let controller = NativePageFindController(
      webView: runtime.webView, parent: parent, canSearch: { permission.allowed })
    defer { controller.close() }
    let shortcut = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
        windowNumber: parent.windowNumber, context: nil, characters: "f",
        charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3))
    #expect(controller.handleKeyEquivalent(shortcut))
    #expect(controller.field.maximumRecents == 0)
    controller.updateQuery("unique-needle")
    let deadline = ContinuousClock.now + .seconds(3)
    while controller.isSearching && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(controller.matchFound == true)
    controller.updateQuery("absent-synthetic-needle")
    controller.close()
    try await Task.sleep(for: .milliseconds(120))
    #expect(!controller.isVisible)
    #expect(controller.matchFound == nil)
    #expect(controller.field.stringValue.isEmpty)
    permission.allowed = false
    #expect(!controller.handleKeyEquivalent(shortcut))
    #expect(!controller.isVisible)
  }
}
