import Foundation
import Testing

@testable import WebKitUIMCPCore

@Suite("Submission approval")
struct SubmissionApprovalTests {
  private func url(_ value: String) throws -> URL { try #require(URL(string: value)) }

  @Test("A submission to the approved origin continues")
  func sameOriginAllowed() throws {
    #expect(
      SubmissionApproval.decide(
        approvedOrigin: "https://shop.example",
        submissionURL: try url("https://shop.example/orders/track"),
        httpMethod: "POST") == .allow)
  }

  @Test("A submission to another origin is refused by name")
  func foreignOriginRefused() throws {
    #expect(
      SubmissionApproval.decide(
        approvedOrigin: "https://shop.example",
        submissionURL: try url("https://attacker.example/collect"),
        httpMethod: "POST") == .refuseForeignOrigin("https://attacker.example"))
  }

  @Test("A submission with nothing approved is refused, not allowed")
  func unapprovedRefused() throws {
    // Fail closed. A form that submits with no approval on record is the case an
    // attacker constructs, not the case a user asks for.
    #expect(
      SubmissionApproval.decide(
        approvedOrigin: nil,
        submissionURL: try url("https://shop.example/orders/track"),
        httpMethod: "POST") == .refuseUnapproved)
  }

  @Test("An unreadable submission origin is refused")
  func unreadableOriginRefused() throws {
    #expect(
      SubmissionApproval.decide(
        approvedOrigin: "https://shop.example",
        submissionURL: try url("data:text/plain,x"),
        httpMethod: "POST") == .refuseForeignOrigin("unreadable"))
  }

  @Test("A port difference is a different origin")
  func portIsPartOfOrigin() throws {
    #expect(
      SubmissionApproval.decide(
        approvedOrigin: "https://shop.example",
        submissionURL: try url("https://shop.example:8443/collect"),
        httpMethod: "POST") == .refuseForeignOrigin("https://shop.example:8443"))
  }
}
