import Foundation
import Testing

@testable import WebKitUIMCPCore

@Suite("Submission destination")
struct SubmissionDestinationTests {
  private let page = URL(string: "https://shop.example/orders/1471")!

  @Test("A same-origin destination is stated plainly")
  func sameOriginIsStated() {
    let line = SubmissionDestination.line(
      pageURL: page, destination: "https://shop.example/orders/1471/track")
    #expect(line == "Data would be sent to:\n\"https://shop.example\" (this page's origin)")
  }

  @Test("Another origin is called out as different, because that is the whole point")
  func foreignOriginIsCalledOut() {
    let line = SubmissionDestination.line(
      pageURL: page, destination: "https://attacker.example/collect?x=1")
    #expect(
      line == "Data would be sent to:\n\"https://attacker.example\" — A DIFFERENT SITE "
        + "from the page you are on, \"https://shop.example\"")
  }

  @Test("A control that sends nothing produces no line at all")
  func silentControlSaysNothing() {
    // A plain button is the common case. An extra line on every dialog is how an
    // operator learns to stop reading them.
    #expect(SubmissionDestination.line(pageURL: page, destination: nil) == nil)
  }

  @Test("A destination that cannot be resolved to an origin fails loud, not silent")
  func unresolvableDestinationIsReported() {
    // javascript: and data: URLs, and anything unparseable. Saying nothing here would
    // hide exactly the case worth showing.
    #expect(
      SubmissionDestination.line(pageURL: page, destination: "javascript:steal()")
        == "Data would be sent to:\nan address with no readable origin — treat as UNKNOWN")
    #expect(
      SubmissionDestination.line(pageURL: page, destination: "   ")
        == "Data would be sent to:\nan address with no readable origin — treat as UNKNOWN")
  }

  @Test("Only the origin is shown, never the query")
  func queryIsNeverShown() {
    let line = SubmissionDestination.line(
      pageURL: page, destination: "https://attacker.example/c?session=abc123&token=xyz")
    #expect(line?.contains("abc123") == false)
    #expect(line?.contains("token") == false)
  }
}
