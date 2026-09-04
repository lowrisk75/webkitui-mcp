import AppKit
import Foundation

@MainActor
protocol SafariCompatibilityPresenting: AnyObject {
  func openPrivateAuthenticationURL(_ url: URL) async -> Bool
}

@MainActor
final class NativeSafariCompatibilityPresenter: SafariCompatibilityPresenting {
  func openPrivateAuthenticationURL(_ url: URL) async -> Bool {
    guard
      url.scheme?.lowercased() == "https",
      let safariURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: "com.apple.Safari")
    else { return false }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    return await withCheckedContinuation { continuation in
      NSWorkspace.shared.open(
        [url],
        withApplicationAt: safariURL,
        configuration: configuration
      ) { _, error in
        continuation.resume(returning: error == nil)
      }
    }
  }
}
