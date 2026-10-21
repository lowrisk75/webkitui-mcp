import Foundation
import Testing
@testable import WebKitUIMCPRuntime

struct CaptchaAccessibilityTests {
  @Test("Widget metadata hints require provider boundaries and paths")
  func widgetMetadata() throws {
    for raw in [
      "https://www.google.com/recaptcha/api2/anchor?secret=not-retained",
      "https://www.recaptcha.net/recaptcha/enterprise/anchor",
      "https://newassets.hcaptcha.com/captcha/v1/widget",
      "https://challenges.cloudflare.com/turnstile/v0/widget",
    ] {
      #expect(CaptchaAccessibility.isWidgetRequest(try #require(URL(string: raw))))
    }
    for raw in [
      "http://www.google.com/recaptcha/api2/anchor",
      "https://google.com.attacker.invalid/recaptcha/api2/anchor",
      "https://fakegoogle.com/recaptcha/api2/anchor",
      "https://www.google.com/search?q=captcha",
      "https://hcaptcha.com/", "https://fixture.invalid/?captcha=true",
    ] {
      #expect(!CaptchaAccessibility.isWidgetRequest(try #require(URL(string: raw))))
    }
  }
}
