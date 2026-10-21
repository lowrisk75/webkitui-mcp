import Foundation

/// A conservative URL-metadata hint, never a challenge reader or a proof of a CAPTCHA.
/// Query strings, tokens, widget contents and answers are neither retained nor returned.
enum CaptchaAccessibility {
  static func isWidgetRequest(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
      return false
    }
    let path = url.path.lowercased()
    func domain(_ value: String) -> Bool {
      host == value || host.hasSuffix("." + value)
    }
    return ((domain("google.com") || domain("recaptcha.net")) && path.hasPrefix("/recaptcha/"))
      || (domain("hcaptcha.com") && path.hasPrefix("/captcha/"))
      || (host == "challenges.cloudflare.com" && path.hasPrefix("/turnstile/"))
  }
}
