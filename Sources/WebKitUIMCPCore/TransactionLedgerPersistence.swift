import CryptoKit
import Foundation

public struct PersistedTransactionRecord: Codable, Sendable {
  public let plan: TransactionalWritePlan
  public let planDigest: String
  public let baseObservationDigest: String
  public let phase: TransactionPhase
  public let resultObservationDigest: String?
  public let evidence: [PredicateEvidence]
  public let recoveredByReconciliation: Bool

  public init(
    plan: TransactionalWritePlan,
    planDigest: String,
    baseObservationDigest: String,
    phase: TransactionPhase,
    resultObservationDigest: String?,
    evidence: [PredicateEvidence],
    recoveredByReconciliation: Bool
  ) {
    self.plan = plan
    self.planDigest = planDigest
    self.baseObservationDigest = baseObservationDigest
    self.phase = phase
    self.resultObservationDigest = resultObservationDigest
    self.evidence = evidence
    self.recoveredByReconciliation = recoveredByReconciliation
  }
}

public protocol TransactionLedgerPersisting: Sendable {
  func load() throws -> [PersistedTransactionRecord]
  func save(_ records: [PersistedTransactionRecord]) throws
}

public struct TransactionLedgerAnchor: Codable, Equatable, Sendable {
  public let generation: UInt64
  public let envelopeSHA256: String

  public init(generation: UInt64, envelopeSHA256: String) {
    self.generation = generation
    self.envelopeSHA256 = envelopeSHA256
  }
}

public struct TransactionLedgerAnchorState: Codable, Equatable, Sendable {
  public let committed: TransactionLedgerAnchor?
  public let pending: TransactionLedgerAnchor?

  public init(
    committed: TransactionLedgerAnchor?,
    pending: TransactionLedgerAnchor?
  ) {
    self.committed = committed
    self.pending = pending
  }
}

public protocol TransactionLedgerAnchoring: Sendable {
  func loadAnchorState() throws -> TransactionLedgerAnchorState?
  func saveAnchorState(_ state: TransactionLedgerAnchorState) throws
}

public enum TransactionLedgerPersistenceError: Error, Equatable, Sendable {
  case authenticationKeyTooShort
  case unsupportedVersion(Int)
  case authenticationFailed
  case duplicateIdempotencyKey
  case ledgerMissing
  case anchorMissing
  case rollbackDetected
  case generationOverflow
  case invalidCapacity
  case capacityExceeded
}

public final class FileTransactionLedgerStore: TransactionLedgerPersisting, @unchecked Sendable {
  private struct Envelope: Codable {
    let version: Int
    let generation: UInt64?
    let previousEnvelopeSHA256: String?
    let payload: Data
    let authenticationCode: Data
  }

  private struct AuthenticatedEnvelopeV2: Codable {
    let version: Int
    let generation: UInt64
    let previousEnvelopeSHA256: String?
    let payload: Data
  }

  private let url: URL
  private let key: SymmetricKey
  private let anchor: (any TransactionLedgerAnchoring)?
  private let maximumRecordCount: Int
  private let maximumPayloadBytes: Int
  private let lock = NSLock()

  public init(
    url: URL,
    authenticationKey: Data,
    anchor: (any TransactionLedgerAnchoring)? = nil,
    maximumRecordCount: Int = 10_000,
    maximumPayloadBytes: Int = 16 * 1_024 * 1_024
  ) throws {
    guard authenticationKey.count >= 32 else {
      throw TransactionLedgerPersistenceError.authenticationKeyTooShort
    }
    guard maximumRecordCount > 0, maximumPayloadBytes > 0 else {
      throw TransactionLedgerPersistenceError.invalidCapacity
    }
    self.url = url.standardizedFileURL
    self.key = SymmetricKey(data: authenticationKey)
    self.anchor = anchor
    self.maximumRecordCount = maximumRecordCount
    self.maximumPayloadBytes = maximumPayloadBytes
  }

  public func load() throws -> [PersistedTransactionRecord] {
    try lock.withLock {
      guard let (_, envelope) = try authenticatedEnvelopeAndReconciledAnchor() else { return [] }
      return try JSONDecoder().decode([PersistedTransactionRecord].self, from: envelope.payload)
    }
  }

  public func save(_ records: [PersistedTransactionRecord]) throws {
    try lock.withLock {
      let previous = try authenticatedEnvelopeAndReconciledAnchor()?.anchor
      guard previous?.generation != UInt64.max else {
        throw TransactionLedgerPersistenceError.generationOverflow
      }
      let sorted = records.sorted { $0.plan.idempotencyKey < $1.plan.idempotencyKey }
      guard sorted.count <= maximumRecordCount else {
        throw TransactionLedgerPersistenceError.capacityExceeded
      }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let payload = try encoder.encode(sorted)
      guard payload.count <= maximumPayloadBytes else {
        throw TransactionLedgerPersistenceError.capacityExceeded
      }
      let authenticated = AuthenticatedEnvelopeV2(
        version: 2,
        generation: (previous?.generation ?? 0) + 1,
        previousEnvelopeSHA256: previous?.envelopeSHA256,
        payload: payload
      )
      let authenticatedData = try encoder.encode(authenticated)
      let code = Data(HMAC<SHA256>.authenticationCode(for: authenticatedData, using: key))
      let envelope = try encoder.encode(
        Envelope(
          version: authenticated.version,
          generation: authenticated.generation,
          previousEnvelopeSHA256: authenticated.previousEnvelopeSHA256,
          payload: authenticated.payload,
          authenticationCode: code
        ))
      let next = TransactionLedgerAnchor(
        generation: authenticated.generation,
        envelopeSHA256: sha256(envelope)
      )
      if let anchor {
        try anchor.saveAnchorState(
          TransactionLedgerAnchorState(committed: previous, pending: next))
      }
      let directory = url.deletingLastPathComponent()
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      try envelope.write(to: url, options: [.atomic])
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
      if let anchor {
        try anchor.saveAnchorState(
          TransactionLedgerAnchorState(committed: next, pending: nil))
      }
    }
  }

  private func authenticatedEnvelopeAndReconciledAnchor() throws -> (
    anchor: TransactionLedgerAnchor?, envelope: Envelope
  )? {
    let state = try anchor?.loadAnchorState()
    guard FileManager.default.fileExists(atPath: url.path) else {
      if state?.committed != nil || state?.pending != nil {
        throw TransactionLedgerPersistenceError.ledgerMissing
      }
      return nil
    }

    let data = try Data(contentsOf: url)
    let envelope = try JSONDecoder().decode(Envelope.self, from: data)
    switch envelope.version {
    case 1:
      guard
        HMAC<SHA256>.isValidAuthenticationCode(
          envelope.authenticationCode,
          authenticating: envelope.payload,
          using: key
        )
      else {
        throw TransactionLedgerPersistenceError.authenticationFailed
      }
      guard state?.committed == nil, state?.pending == nil else {
        throw TransactionLedgerPersistenceError.rollbackDetected
      }
      return (nil, envelope)
    case 2:
      guard let generation = envelope.generation else {
        throw TransactionLedgerPersistenceError.authenticationFailed
      }
      let authenticated = AuthenticatedEnvelopeV2(
        version: envelope.version,
        generation: generation,
        previousEnvelopeSHA256: envelope.previousEnvelopeSHA256,
        payload: envelope.payload
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      guard
        HMAC<SHA256>.isValidAuthenticationCode(
          envelope.authenticationCode,
          authenticating: try encoder.encode(authenticated),
          using: key
        )
      else {
        throw TransactionLedgerPersistenceError.authenticationFailed
      }
      let observed = TransactionLedgerAnchor(
        generation: generation,
        envelopeSHA256: sha256(data)
      )
      guard let anchor else { return (observed, envelope) }
      guard let state else {
        throw TransactionLedgerPersistenceError.anchorMissing
      }

      if state.committed == observed {
        if state.pending != nil {
          try anchor.saveAnchorState(
            TransactionLedgerAnchorState(committed: observed, pending: nil))
        }
        return (observed, envelope)
      }

      if state.pending == observed {
        let followsCommitted: Bool
        if let committed = state.committed {
          followsCommitted =
            committed.generation < UInt64.max
            && observed.generation == committed.generation + 1
            && envelope.previousEnvelopeSHA256 == committed.envelopeSHA256
        } else {
          followsCommitted = observed.generation == 1 && envelope.previousEnvelopeSHA256 == nil
        }
        guard followsCommitted else {
          throw TransactionLedgerPersistenceError.rollbackDetected
        }
        try anchor.saveAnchorState(
          TransactionLedgerAnchorState(committed: observed, pending: nil))
        return (observed, envelope)
      }

      throw TransactionLedgerPersistenceError.rollbackDetected
    default:
      throw TransactionLedgerPersistenceError.unsupportedVersion(envelope.version)
    }
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data)
      .map { String(format: "%02x", $0) }
      .joined()
  }
}
