import Foundation
import WebKit

@available(macOS 27.0, *)
@main
struct WKJSHandleProbe {
  @MainActor
  static func main() async {
    do {
      let report = try await run()
      let data = try JSONSerialization.data(
        withJSONObject: report,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      )
      FileHandle.standardOutput.write(data)
      FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
      let failure: [String: Any] = [
        "ok": false,
        "error": String(describing: error),
      ]
      let data = try? JSONSerialization.data(
        withJSONObject: failure,
        options: [.prettyPrinted, .sortedKeys]
      )
      if let data {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
      }
      Foundation.exit(EXIT_FAILURE)
    }
  }

  @MainActor
  private static func run() async throws -> [String: Any] {
    let primaryConfiguration = WKContentWorld.Configuration()
    primaryConfiguration.jsHandleCreationEnabled = true
    primaryConfiguration.nodeSnapshotCreationEnabled = true
    let primaryWorld = WKContentWorld(configuration: primaryConfiguration)

    let secondaryConfiguration = WKContentWorld.Configuration()
    secondaryConfiguration.jsHandleCreationEnabled = true
    let secondaryWorld = WKContentWorld(configuration: secondaryConfiguration)

    let navigationDelegate = NavigationPreferencesDelegate()
    let webView = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600))
    webView.navigationDelegate = navigationDelegate
    try await load(
      """
      <!doctype html>
      <button id="target">Original</button>
      """,
      in: webView
    )

    let createJSHandleType = try await webView.evaluateJavaScript(
      "typeof window.webkit.createJSHandle",
      in: nil,
      contentWorld: primaryWorld
    )
    let pageWorldCreateJSHandleType = try await webView.evaluateJavaScript(
      "typeof window.webkit === 'undefined' ? 'missing-webkit' : typeof window.webkit.createJSHandle",
      in: nil,
      contentWorld: .page
    )
    let nodeSnapshotProbe = await probeNodeSnapshot(in: primaryWorld, webView: webView)

    var rawHandle: Any?
    var creationNanoseconds: UInt64 = 0
    var creationAttempts: [[String: Any]] = []
    var handleWorld = primaryWorld
    var creationStart = DispatchTime.now().uptimeNanoseconds
    do {
      rawHandle = try await webView.evaluateJavaScript(
        "window.webkit.createJSHandle(document.getElementById('target'))",
        in: nil,
        contentWorld: primaryWorld
      )
      creationNanoseconds = DispatchTime.now().uptimeNanoseconds - creationStart
      creationAttempts.append([
        "api": "evaluateJavaScript",
        "succeeded": true,
        "nanoseconds": creationNanoseconds,
      ])
    } catch {
      creationAttempts.append([
        "api": "evaluateJavaScript",
        "succeeded": false,
        "error": String(describing: error),
        "nanoseconds": DispatchTime.now().uptimeNanoseconds - creationStart,
      ])
    }

    if rawHandle == nil {
      creationStart = DispatchTime.now().uptimeNanoseconds
      do {
        rawHandle = try await webView.callAsyncJavaScript(
          "return window.webkit.createJSHandle(document.getElementById('target'));",
          arguments: [:],
          in: nil,
          contentWorld: primaryWorld
        )
        creationNanoseconds = DispatchTime.now().uptimeNanoseconds - creationStart
        creationAttempts.append([
          "api": "callAsyncJavaScript",
          "succeeded": true,
          "nanoseconds": creationNanoseconds,
        ])
      } catch {
        creationAttempts.append([
          "api": "callAsyncJavaScript",
          "succeeded": false,
          "error": String(describing: error),
          "nanoseconds": DispatchTime.now().uptimeNanoseconds - creationStart,
        ])
      }
    }

    if rawHandle == nil {
      creationStart = DispatchTime.now().uptimeNanoseconds
      do {
        let container = try await webView.evaluateJavaScript(
          "({ handle: window.webkit.createJSHandle(document.getElementById('target')) })",
          in: nil,
          contentWorld: primaryWorld
        )
        rawHandle = (container as? [String: Any])?["handle"]
        creationNanoseconds = DispatchTime.now().uptimeNanoseconds - creationStart
        creationAttempts.append([
          "api": "evaluateJavaScript.container",
          "succeeded": rawHandle != nil,
          "returned_type": String(describing: type(of: container)),
          "nanoseconds": creationNanoseconds,
        ])
      } catch {
        creationAttempts.append([
          "api": "evaluateJavaScript.container",
          "succeeded": false,
          "error": String(describing: error),
          "nanoseconds": DispatchTime.now().uptimeNanoseconds - creationStart,
        ])
      }
    }

    if rawHandle == nil {
      creationStart = DispatchTime.now().uptimeNanoseconds
      do {
        rawHandle = try await webView.evaluateJavaScript(
          "window.webkit.createJSHandle(document.getElementById('target'))",
          in: nil,
          contentWorld: .page
        )
        handleWorld = .page
        creationNanoseconds = DispatchTime.now().uptimeNanoseconds - creationStart
        creationAttempts.append([
          "api": "evaluateJavaScript.pageWorld",
          "succeeded": true,
          "nanoseconds": creationNanoseconds,
        ])
      } catch {
        creationAttempts.append([
          "api": "evaluateJavaScript.pageWorld",
          "succeeded": false,
          "error": String(describing: error),
          "nanoseconds": DispatchTime.now().uptimeNanoseconds - creationStart,
        ])
      }
    }

    guard let rawHandle else {
      return [
        "ok": false,
        "failed_stage": "create_handle",
        "environment": environmentReport(),
        "preflight": [
          "configuration_enabled": primaryConfiguration.jsHandleCreationEnabled,
          "create_js_handle_type": jsonValue(createJSHandleType),
          "page_world_create_js_handle_type": jsonValue(pageWorldCreateJSHandleType),
          "node_snapshot": nodeSnapshotProbe,
        ],
        "creation_attempts": creationAttempts,
      ]
    }
    guard let handle = rawHandle as? WKJSHandle else {
      throw ProbeError.unexpectedHandleType(String(describing: type(of: rawHandle)))
    }

    let (sameWorldValue, sameWorldNanoseconds) = try await timed {
      try await inspect(handle: handle, in: handleWorld, webView: webView)
    }

    _ = try await webView.callAsyncJavaScript(
      """
      const replacement = document.createElement('button');
      replacement.id = 'target';
      replacement.textContent = 'Replacement';
      document.getElementById('target').replaceWith(replacement);
      return replacement.textContent;
      """,
      arguments: [:],
      in: nil,
      contentWorld: handleWorld
    )
    let (detachedValue, detachedNanoseconds) = try await timed {
      try await inspect(handle: handle, in: handleWorld, webView: webView)
    }

    let (wrongWorldValue, wrongWorldNanoseconds) = try await timed {
      try await inspect(handle: handle, in: secondaryWorld, webView: webView)
    }

    try await load(
      """
      <!doctype html>
      <button id="target">After navigation</button>
      """,
      in: webView
    )

    let postNavigation: [String: Any]
    let postNavigationStart = DispatchTime.now().uptimeNanoseconds
    do {
      let value = try await inspect(handle: handle, in: handleWorld, webView: webView)
      postNavigation = [
        "threw": false,
        "value": jsonValue(value),
      ]
    } catch {
      postNavigation = [
        "threw": true,
        "error": String(describing: error),
      ]
    }
    let postNavigationNanoseconds = DispatchTime.now().uptimeNanoseconds - postNavigationStart

    return [
      "ok": true,
      "environment": environmentReport(),
      "preflight": [
        "configuration_enabled": primaryConfiguration.jsHandleCreationEnabled,
        "create_js_handle_type": jsonValue(createJSHandleType),
        "page_world_create_js_handle_type": jsonValue(pageWorldCreateJSHandleType),
        "creation_attempts": creationAttempts,
        "node_snapshot": nodeSnapshotProbe,
      ],
      "sdk_behavior": [
        "created_type": String(describing: type(of: handle)),
        "same_world": jsonValue(sameWorldValue),
        "after_node_replacement": jsonValue(detachedValue),
        "wrong_world": jsonValue(wrongWorldValue),
        "after_navigation": postNavigation,
      ],
      "timing_nanoseconds": [
        "create_handle": creationNanoseconds,
        "same_world_read": sameWorldNanoseconds,
        "detached_node_read": detachedNanoseconds,
        "wrong_world_read": wrongWorldNanoseconds,
        "post_navigation_read": postNavigationNanoseconds,
      ],
      "interpretation": [
        "handle_is_not_durable_identity": true,
        "locator_recipe_remains_required": true,
      ],
    ]
  }

  @MainActor
  private static func probeNodeSnapshot(
    in world: WKContentWorld,
    webView: WKWebView
  ) async -> [String: Any] {
    let start = DispatchTime.now().uptimeNanoseconds
    do {
      let value = try await webView.evaluateJavaScript(
        "window.webkit.createNodeSnapshot(document.getElementById('target'))",
        in: nil,
        contentWorld: world
      )
      return [
        "succeeded": value is WKDOMNodeSnapshot,
        "returned_type": String(describing: type(of: value)),
        "nanoseconds": DispatchTime.now().uptimeNanoseconds - start,
      ]
    } catch {
      return [
        "succeeded": false,
        "error": String(describing: error),
        "nanoseconds": DispatchTime.now().uptimeNanoseconds - start,
      ]
    }
  }

  @MainActor
  private static func inspect(
    handle: WKJSHandle,
    in world: WKContentWorld,
    webView: WKWebView
  ) async throws -> Any? {
    try await webView.callAsyncJavaScript(
      """
      return {
          type: typeof target,
          text: typeof target === 'undefined' ? null : target.textContent,
          connected: typeof target === 'undefined' ? null : target.isConnected
      };
      """,
      arguments: ["target": handle],
      in: nil,
      contentWorld: world
    )
  }

  @MainActor
  private static func load(_ html: String, in webView: WKWebView) async throws {
    webView.loadHTMLString(html, baseURL: URL(string: "https://probe.invalid/"))
    let deadline = ContinuousClock.now + .seconds(10)
    while webView.isLoading {
      guard ContinuousClock.now < deadline else { throw ProbeError.navigationTimeout }
      try await Task.sleep(for: .milliseconds(10))
    }

    let readyState = try await webView.evaluateJavaScript("document.readyState") as? String
    guard readyState == "complete" else {
      throw ProbeError.unexpectedReadyState(readyState ?? "nil")
    }
  }

  @MainActor
  private static func timed<T>(
    _ operation: () async throws -> T
  ) async throws -> (value: T, nanoseconds: UInt64) {
    let start = DispatchTime.now().uptimeNanoseconds
    let value = try await operation()
    return (value, DispatchTime.now().uptimeNanoseconds - start)
  }

  private static func jsonValue(_ value: Any?) -> Any {
    value ?? NSNull()
  }

  private static func environmentReport() -> [String: Any] {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return [
      "macos": "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
      "build": ProcessInfo.processInfo.operatingSystemVersionString,
      "architecture": "arm64",
    ]
  }
}

private enum ProbeError: Error {
  case navigationTimeout
  case unexpectedReadyState(String)
  case unexpectedHandleType(String)
}

@available(macOS 27.0, *)
@MainActor
private final class NavigationPreferencesDelegate: NSObject, WKNavigationDelegate {
  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    preferences: WKWebpagePreferences
  ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
    preferences.allowsJSHandleCreationInPageWorld = true
    return (.allow, preferences)
  }
}
