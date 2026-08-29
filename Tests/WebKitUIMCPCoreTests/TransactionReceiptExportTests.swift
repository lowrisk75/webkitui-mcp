import Foundation
import Testing

@testable import WebKitUIMCPCore

@Suite("ReceiptV1 export")
struct TransactionReceiptExportTests {
  @Test("JSON and Markdown share one redacted canonical receipt")
  func canonicalRedactedExport() throws {
    let rawSecret = "lumen-purchase-verifier@example.test"
    let rawKey = "\(rawSecret)/order/12345"
    let valueKey = ObservationFieldKey(
      frameID: "main", elementID: "semantic-target", field: "@value")
    let receipt = TransactionReceipt(
      idempotencyKey: rawKey,
      planDigest: String(repeating: "a", count: 64),
      phase: .verified,
      baseObservationDigest: String(repeating: "b", count: 64),
      resultObservationDigest: String(repeating: "c", count: 64),
      preparedAtNanoseconds: 10,
      dispatchedAtNanoseconds: 20,
      observedAtNanoseconds: 30,
      deadlineNanoseconds: 40,
      postconditionEvidence: [
        PredicateEvidence(predicate: .entryPresent(valueKey), result: .satisfied),
        PredicateEvidence(
          predicate: .entryTextDigest(valueKey, ObservationPredicate.textDigest(of: rawSecret)),
          result: .satisfied),
      ],
      recoveredByReconciliation: true
    )
    let export = TransactionReceiptExportV1(
      receipt: receipt,
      exportedAt: "2026-08-29T10:00:00Z")

    let first = try export.canonicalJSONData()
    let second = try export.canonicalJSONData()
    let json = try #require(String(data: first, encoding: .utf8))
    let markdown = export.markdown()

    #expect(first == second)
    #expect(try JSONDecoder().decode(TransactionReceiptExportV1.self, from: first) == export)
    #expect(export.receipt.idempotencyKeySHA256.count == 64)
    #expect(!json.contains(rawKey))
    #expect(!markdown.contains(rawKey))
    #expect(!json.contains(rawSecret))
    #expect(!markdown.contains(rawSecret))
    #expect(json.contains(export.receipt.idempotencyKeySHA256))
    #expect(markdown.contains(export.receipt.idempotencyKeySHA256))
    #expect(markdown.contains("Phase: `verified`"))
    #expect(markdown.contains("Postcondition 1: `satisfied`"))
    #expect(markdown.contains("Postcondition 2: `satisfied`"))
    #expect(markdown.contains(TransactionReceiptExportV1.replaySafetyStatement))
    #expect(try export.canonicalJSONSHA256().count == 64)
  }
}
