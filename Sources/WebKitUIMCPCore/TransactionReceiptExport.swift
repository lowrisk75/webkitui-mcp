import CryptoKit
import Foundation

public struct RedactedTransactionReceiptV1: Codable, Equatable, Sendable {
  public let idempotencyKeySHA256: String
  public let planDigest: String
  public let phase: TransactionPhase
  public let baseObservationDigest: String
  public let resultObservationDigest: String?
  public let preparedAtNanoseconds: UInt64
  public let dispatchedAtNanoseconds: UInt64?
  public let observedAtNanoseconds: UInt64?
  public let deadlineNanoseconds: UInt64?
  public let postconditionEvidence: [PredicateEvidence]
  public let recoveredByReconciliation: Bool

  public init(receipt: TransactionReceipt) {
    idempotencyKeySHA256 = Self.digest(receipt.idempotencyKey)
    planDigest = receipt.planDigest
    phase = receipt.phase
    baseObservationDigest = receipt.baseObservationDigest
    resultObservationDigest = receipt.resultObservationDigest
    preparedAtNanoseconds = receipt.preparedAtNanoseconds
    dispatchedAtNanoseconds = receipt.dispatchedAtNanoseconds
    observedAtNanoseconds = receipt.observedAtNanoseconds
    deadlineNanoseconds = receipt.deadlineNanoseconds
    postconditionEvidence = receipt.postconditionEvidence
    recoveredByReconciliation = receipt.recoveredByReconciliation
  }

  private static func digest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private enum CodingKeys: String, CodingKey {
    case idempotencyKeySHA256 = "idempotency_key_sha256"
    case planDigest = "plan_digest"
    case phase
    case baseObservationDigest = "base_observation_digest"
    case resultObservationDigest = "result_observation_digest"
    case preparedAtNanoseconds = "prepared_at_nanoseconds"
    case dispatchedAtNanoseconds = "dispatched_at_nanoseconds"
    case observedAtNanoseconds = "observed_at_nanoseconds"
    case deadlineNanoseconds = "deadline_nanoseconds"
    case postconditionEvidence = "postcondition_evidence"
    case recoveredByReconciliation = "recovered_by_reconciliation"
  }
}

public struct TransactionReceiptExportV1: Codable, Equatable, Sendable {
  public static let schemaIdentifier = "com.lorislab.webkitui-mcp.transaction-receipt.v1"
  public static let replaySafetyStatement = "evidence_only_never_authorizes_replay"

  public let schema: String
  public let receipt: RedactedTransactionReceiptV1
  public let replaySafety: String
  public let exportedAt: String

  public init(receipt: TransactionReceipt, exportedAt: String) {
    schema = Self.schemaIdentifier
    self.receipt = RedactedTransactionReceiptV1(receipt: receipt)
    replaySafety = Self.replaySafetyStatement
    self.exportedAt = exportedAt
  }

  public func canonicalJSONData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self)
  }

  public func canonicalJSONSHA256() throws -> String {
    SHA256.hash(data: try canonicalJSONData())
      .map { String(format: "%02x", $0) }
      .joined()
  }

  public func markdown() -> String {
    let resultDigest = receipt.resultObservationDigest ?? "not-observed"
    let dispatched = receipt.dispatchedAtNanoseconds.map(String.init) ?? "not-dispatched"
    let observed = receipt.observedAtNanoseconds.map(String.init) ?? "not-observed"
    let deadline = receipt.deadlineNanoseconds.map(String.init) ?? "not-set"
    let evidence = receipt.postconditionEvidence.enumerated().map { index, item in
      "- Postcondition \(index + 1): `\(item.result.rawValue)`"
    }.joined(separator: "\n")
    let evidenceBlock = evidence.isEmpty ? "- No postcondition evidence recorded." : evidence

    return """
      # WebKitUI MCP Transaction Receipt

      - Schema: `\(schema)`
      - Exported at: `\(exportedAt)`
      - Phase: `\(receipt.phase.rawValue)`
      - Idempotency key SHA-256: `\(receipt.idempotencyKeySHA256)`
      - Plan digest: `\(receipt.planDigest)`
      - Base observation digest: `\(receipt.baseObservationDigest)`
      - Result observation digest: `\(resultDigest)`
      - Prepared monotonic nanoseconds: `\(receipt.preparedAtNanoseconds)`
      - Dispatched monotonic nanoseconds: `\(dispatched)`
      - Observed monotonic nanoseconds: `\(observed)`
      - Verification deadline monotonic nanoseconds: `\(deadline)`
      - Recovered by reconciliation: `\(receipt.recoveredByReconciliation)`
      - Replay safety: `\(replaySafety)`

      ## Postcondition evidence

      \(evidenceBlock)

      This receipt is evidence only. It never authorizes dispatch or replay.
      """
  }

  private enum CodingKeys: String, CodingKey {
    case schema
    case receipt
    case replaySafety = "replay_safety"
    case exportedAt = "exported_at"
  }
}
