import Foundation
import Testing
import WebKit
import WebKitUIMCPCore

@testable import WebKitUIMCPRuntime

@Suite("Several sessions in one process", .serialized)
@MainActor
struct MultiSessionTests {
  private func lockURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("webkitui-multi-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("controller.lock")
  }

  @Test("A second session in the holding process reuses its host lease")
  func secondSessionReusesTheLease() throws {
    let url = lockURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = WKWebsiteDataStore.nonPersistent()
    let registry = try WebKitSessionRegistry(
      maximumSessions: 2, enforceHostExclusiveSession: true, hostControllerLockURL: url,
      runtimeFactory: { _ in try WebKitRuntime(protectedWebsiteDataStore: store) })
    let first = try registry.open()
    let second = try registry.open()
    #expect(first != second)
    #expect(registry.count == 2)
    // Another process is still refused.
    let other = try WebKitSessionRegistry(
      enforceHostExclusiveSession: true, hostControllerLockURL: url)
    #expect(throws: WebKitSessionRegistryError.self) { _ = try other.open() }
    // The lease outlives the first close and goes with the last.
    try registry.close(first)
    #expect(throws: WebKitSessionRegistryError.self) { _ = try other.open() }
    try registry.close(second)
    let reopened = try other.open()
    try other.close(reopened)
  }

  @Test("Two sessions on one profile share one egress proxy")
  func sessionsOnOneStoreShareTheProxy() throws {
    let store = WKWebsiteDataStore.nonPersistent()
    let first = try WebKitRuntime(protectedWebsiteDataStore: store)
    let second = try WebKitRuntime(protectedWebsiteDataStore: store)
    #expect(first.egressProxyIdentity != nil)
    #expect(first.egressProxyIdentity == second.egressProxyIdentity)
    let other = try WebKitRuntime(protectedWebsiteDataStore: .nonPersistent())
    #expect(other.egressProxyIdentity != first.egressProxyIdentity)
  }

  @Test("A reconnecting client gets a free session, then a new one, then waits")
  func reuseRespectsOwnership() throws {
    let registry = try WebKitSessionRegistry(
      maximumSessions: 2,
      runtimeFactory: { _ in try WebKitRuntime(protectedWebsiteDataStore: .nonPersistent()) })
    let alice = UUID()
    let bob = UUID()
    let first = try registry.openOrReuse()
    #expect(!first.reused)
    _ = try registry.claimSessionOwnership(for: first.handle, owner: alice)
    // Owned elsewhere and there is room: a new session, not Alice's.
    let second = try registry.openOrReuse()
    #expect(!second.reused)
    #expect(second.handle != first.handle)
    _ = try registry.claimSessionOwnership(for: second.handle, owner: bob)
    // Full: handed an owned session, which the caller cannot claim.
    let third = try registry.openOrReuse()
    #expect(third.reused)
    #expect(try registry.claimSessionOwnership(for: third.handle, owner: UUID()) == false)
    // Released by its owner: handed back first.
    registry.releaseSessionOwnerships(owner: bob)
    #expect(try registry.openOrReuse().handle == second.handle)
  }

  @Test("A person holding the window gets real pop-ups, closed when the agent resumes")
  func humanPopupsAreRealAndBounded() async throws {
    let runtime = WebKitRuntime()
    // Tests have no user gesture to open a window with; the preference stands in.
    runtime.webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
    _ = try await runtime.loadHTML(
      "<p>Sign in</p>", baseURL: URL(string: "https://fixture.invalid/login"),
      timeout: .seconds(15), quietWindow: .milliseconds(40))

    // Under agent control the window is refused, as before.
    _ = try await runtime.webView.evaluateJavaScript("window.open('about:blank'); 1")
    #expect(runtime.humanPopups.openCount == 0)

    try runtime.requestHumanHandoff()
    try runtime.beginHumanControl(presentWindow: false)
    let framesBefore = runtime.frameRegistrySnapshot().capabilities.count
    _ = try await runtime.webView.evaluateJavaScript(
      "globalThis.popup = window.open('about:blank', 'signin');"
        + "globalThis.popup.document.write('<iframe srcdoc=\"<p>x</p>\"></iframe>'); 1")
    try await Task.sleep(for: .milliseconds(200))
    // The pop-up shares this page's content controller; its frames are not this page's.
    #expect(runtime.frameRegistrySnapshot().capabilities.count == framesBefore)
    #expect(runtime.humanPopups.openCount == 1)
    let linked =
      try await runtime.webView.evaluateJavaScript(
        "globalThis.popup !== null && globalThis.popup.opener === window") as? Bool
    #expect(linked == true)
    for index in 0..<6 {
      _ = try await runtime.webView.evaluateJavaScript("window.open('about:blank', 'w\(index)'); 1")
    }
    #expect(runtime.humanPopups.openCount == HumanPopupWindows.maximumWindows)

    try runtime.markHumanStepCompleted()
    try runtime.requestAgentResume()
    #expect(runtime.humanPopups.openCount == 0)
  }

  @Test("read_text includes text rendered inside shadow roots")
  func readTextIncludesShadowText() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <p>Outer page</p>
      <chat-panel></chat-panel>
      <slot-card><span>Slotted light text</span></slot-card>
      <script>
        customElements.define('slot-card', class extends HTMLElement {
          constructor() {
            super();
            this.attachShadow({ mode: 'open' }).innerHTML = '<h3>Card title</h3><slot></slot>';
          }
        });
        customElements.define('chat-panel', class extends HTMLElement {
          constructor() {
            super();
            const root = this.attachShadow({ mode: 'open' });
            root.innerHTML = '<ul><li>Message from Alex: can I join the beta?</li></ul>'
              + '<nested-item></nested-item>';
          }
        });
        customElements.define('nested-item', class extends HTMLElement {
          constructor() {
            super();
            this.attachShadow({ mode: 'closed' }).innerHTML = '<p>Closed root text</p>';
          }
        });
      </script>
      """,
      baseURL: URL(string: "https://fixture.invalid/chat"),
      timeout: .seconds(15), quietWindow: .milliseconds(40))
    let snapshot = try await runtime.readText()
    #expect(snapshot.bodyText.contains("Outer page"))
    #expect(snapshot.bodyText.contains("Message from Alex: can I join the beta?"))
    #expect(snapshot.bodyText.contains("Card title\nSlotted light text"))
    // A closed root is not readable from the page's own script, and not from here.
    #expect(!snapshot.bodyText.contains("Closed root text"))
  }

  @Test("A control labelled only inside its shadow root is named and can be clicked")
  func shadowLabelledControlIsNamedAndClickable() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <chat-request role="button" tabindex="0" onclick="this.dataset.opened='yes'"></chat-request>
      <script>
        customElements.define('chat-request', class extends HTMLElement {
          constructor() {
            super();
            this.attachShadow({ mode: 'open' }).innerHTML =
              '<style>:host{display:block;padding:8px}</style><span>Request from Sam</span>';
          }
        });
      </script>
      """,
      baseURL: URL(string: "https://fixture.invalid/chat/requests"),
      timeout: .seconds(15), quietWindow: .milliseconds(40))
    let observation = try await runtime.observe()
    let request = try #require(
      observation.elements.first {
        $0.accessibleName?.segments.first?.text == "Request from Sam"
      })
    let result = try await runtime.perform(
      observationID: observation.observationID,
      elementID: request.elementID,
      operation: .click,
      stabilityInterval: .milliseconds(10))
    #expect(result.dispatched)
    let opened =
      try await runtime.webView.evaluateJavaScript(
        "document.querySelector('chat-request').dataset.opened") as? String
    #expect(opened == "yes")
  }

  @Test("A row whose first label is sensitive resolves by the same label it was observed by")
  func sameRowLabelSkipsSensitiveLikeObservation() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <div class="row"><span>Session limit</span><span>Billing</span>
        <button onclick="this.dataset.done='1'">Configure</button></div>
      <div class="row"><span>Session limit</span><span>Alerts</span>
        <button onclick="this.dataset.done='1'">Configure</button></div>
      """,
      baseURL: URL(string: "https://fixture.invalid/settings"),
      timeout: .seconds(15), quietWindow: .milliseconds(40))
    let observation = try await runtime.observe()
    let billing = try #require(
      observation.elements.first {
        $0.accessibleName?.segments.first?.text == "Configure"
          && $0.contextAnchors.first?.text.segments.first?.text == "Billing"
      })
    let result = try await runtime.perform(
      observationID: observation.observationID,
      elementID: billing.elementID,
      operation: .click,
      stabilityInterval: .milliseconds(10))
    #expect(result.dispatched)
  }

  @Test("A native fill of one block of a document editor leaves the other blocks alone")
  func nativeFillInsideLargeEditorStaysInItsBlock() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <div id="doc" contenteditable="true">
        <p>Keep this paragraph</p>
        <div role="textbox" aria-label="Summary">Old summary</div>
      </div>
      """,
      baseURL: URL(string: "https://fixture.invalid/doc"),
      timeout: .seconds(15), quietWindow: .milliseconds(40))
    let observation = try await runtime.observe()
    let summary = try #require(
      observation.elements.first { $0.accessibleName?.segments.first?.text == "Summary" })
    _ = try await runtime.perform(
      observationID: observation.observationID,
      elementID: summary.elementID,
      operation: .fill(
        try ProvenancedText(
          text: "New summary", source: ProvenanceSource(classification: .userIntent))),
      dispatchMode: .nativeAppKit,
      stabilityInterval: .milliseconds(10))
    let text =
      try await runtime.webView.evaluateJavaScript(
        "document.getElementById('doc').innerText") as? String
    #expect(text?.contains("Keep this paragraph") == true)
    #expect(text?.contains("New summary") == true)
    #expect(text?.contains("Old summary") == false)
  }

  @Test("A native fill refuses when the page moves focus to another field")
  func nativeFillRefusesStolenFocus() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <label>Name <input id="name"></label>
      <label>Notes <input id="notes" value="keep me"></label>
      <script>
        document.getElementById('name').addEventListener('focus', () =>
          setTimeout(() => document.getElementById('notes').focus(), 0));
      </script>
      """,
      baseURL: URL(string: "https://fixture.invalid/form"),
      timeout: .seconds(15), quietWindow: .milliseconds(40))
    let observation = try await runtime.observe()
    let name = try #require(
      observation.elements.first { $0.accessibleName?.segments.first?.text == "Name" })
    await #expect(throws: WebKitRuntimeError.targetNotActionable) {
      _ = try await runtime.perform(
        observationID: observation.observationID,
        elementID: name.elementID,
        operation: .fill(
          try ProvenancedText(text: "Sam", source: ProvenanceSource(classification: .userIntent))),
        dispatchMode: .nativeAppKit,
        stabilityInterval: .milliseconds(10))
    }
    let notes =
      try await runtime.webView.evaluateJavaScript(
        "document.getElementById('notes').value") as? String
    #expect(notes == "keep me")
  }
}
