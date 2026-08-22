import CryptoKit
import Foundation

public enum ObservationCompleteness: String, Codable, Sendable {
  case complete
  case partial
}

public struct TransactionObservation: Sendable {
  public let state: CanonicalObservationState
  public let completeness: ObservationCompleteness

  public init(state: CanonicalObservationState, completeness: ObservationCompleteness) {
    self.state = state
    self.completeness = completeness
  }
}

public enum PredicateResult: String, Codable, Equatable, Sendable {
  case satisfied
  case unsatisfied
  case unknown
}

public enum ObservationTextField: String, Codable, CaseIterable, Sendable {
  case accessibleName = "@accessible_name"
  case label = "@label"
  case text = "@text"
  case value = "@value"
}

public enum ObservationPredicate: Codable, Equatable, Sendable {
  case entryPresent(ObservationFieldKey)
  case entryAbsent(ObservationFieldKey)
  case entryValueDigest(ObservationFieldKey, String)
  /// Compares only the exact concatenated text bytes. This is useful for a
  /// caller-supplied expected value while keeping the value out of receipts.
  /// Provenance remains available in the canonical observation, but is not
  /// silently synthesized by the caller for this comparison.
  case entryTextDigest(ObservationFieldKey, String)
  /// Matches exact text in a bounded set of semantic fields without relying
  /// on an ephemeral element ID. Transaction preparation rejects a match that
  /// was already present before dispatch.
  case anyEntryTextDigest([ObservationTextField], String)

  public static func digest(of value: ProvenancedText) throws -> String {
    SHA256.hash(data: try value.canonicalJSONData())
      .map { String(format: "%02x", $0) }
      .joined()
  }

  public static func textDigest(of text: String) -> String {
    SHA256.hash(data: Data(text.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  public func evaluate(in observation: TransactionObservation) throws -> PredicateResult {
    let values = Dictionary(
      uniqueKeysWithValues: observation.state.entries.map { ($0.key, $0.value) }
    )

    switch self {
    case .entryPresent(let key):
      if values[key] != nil { return .satisfied }
      return observation.completeness == .complete ? .unsatisfied : .unknown
    case .entryAbsent(let key):
      if values[key] != nil { return .unsatisfied }
      return observation.completeness == .complete ? .satisfied : .unknown
    case .entryValueDigest(let key, let expectedDigest):
      guard let value = values[key] else {
        return observation.completeness == .complete ? .unsatisfied : .unknown
      }
      return try Self.digest(of: value) == expectedDigest ? .satisfied : .unsatisfied
    case .entryTextDigest(let key, let expectedDigest):
      guard let value = values[key] else {
        return observation.completeness == .complete ? .unsatisfied : .unknown
      }
      let text = value.segments.map(\.text).joined()
      let digest = Self.textDigest(of: text)
      return digest == expectedDigest ? .satisfied : .unsatisfied
    case .anyEntryTextDigest(let fields, let expectedDigest):
      let allowedFields = Set(fields.map(\.rawValue))
      let found = observation.state.entries.contains { entry in
        guard allowedFields.contains(entry.key.field) else { return false }
        let text = entry.value.segments.map(\.text).joined()
        return Self.textDigest(of: text) == expectedDigest
      }
      if found { return .satisfied }
      return observation.completeness == .complete ? .unsatisfied : .unknown
    }
  }
}

public struct PredicateEvidence: Codable, Equatable, Sendable {
  public let predicate: ObservationPredicate
  public let result: PredicateResult

  public init(predicate: ObservationPredicate, result: PredicateResult) {
    self.predicate = predicate
    self.result = result
  }
}

public struct TransactionalWritePlan: Codable, Sendable {
  public let idempotencyKey: String
  public let target: LocatorRecipe
  public let requiredCapability: BrowserCapability
  public let inputProvenance: Set<ProvenanceClass>
  public let expectedOrigin: SecurityOrigin
  public let preconditions: [ObservationPredicate]
  public let postconditions: [ObservationPredicate]
  public let verificationTimeoutNanoseconds: UInt64

  public init(
    idempotencyKey: String,
    target: LocatorRecipe,
    requiredCapability: BrowserCapability,
    inputProvenance: Set<ProvenanceClass>,
    expectedOrigin: SecurityOrigin,
    preconditions: [ObservationPredicate],
    postconditions: [ObservationPredicate],
    verificationTimeoutNanoseconds: UInt64
  ) throws {
    guard !idempotencyKey.isEmpty else { throw TransactionError.emptyIdempotencyKey }
    guard !postconditions.isEmpty else { throw TransactionError.emptyPostconditions }
    guard verificationTimeoutNanoseconds > 0 else {
      throw TransactionError.invalidVerificationTimeout
    }
    for predicate in preconditions + postconditions {
      let digest: String?
      switch predicate {
      case .entryValueDigest(_, let value), .entryTextDigest(_, let value),
        .anyEntryTextDigest(_, let value):
        digest = value
      default: digest = nil
      }
      if let digest {
        guard digest.count == 64, digest.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
          throw TransactionError.invalidExpectedDigest
        }
      }
      if case .anyEntryTextDigest(let fields, _) = predicate, fields.isEmpty {
        throw TransactionError.emptySemanticTextFields
      }
    }

    self.idempotencyKey = idempotencyKey
    self.target = target
    self.requiredCapability = requiredCapability
    self.inputProvenance = inputProvenance
    self.expectedOrigin = expectedOrigin
    self.preconditions = preconditions
    self.postconditions = postconditions
    self.verificationTimeoutNanoseconds = verificationTimeoutNanoseconds
  }

  public func digest() throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return SHA256.hash(data: try encoder.encode(self))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private enum CodingKeys: String, CodingKey {
    case idempotencyKey = "idempotency_key"
    case target
    case requiredCapability = "required_capability"
    case inputProvenance = "input_provenance"
    case expectedOrigin = "expected_origin"
    case preconditions
    case postconditions
    case verificationTimeoutNanoseconds = "verification_timeout_nanoseconds"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      idempotencyKey: container.decode(String.self, forKey: .idempotencyKey),
      target: container.decode(LocatorRecipe.self, forKey: .target),
      requiredCapability: container.decode(BrowserCapability.self, forKey: .requiredCapability),
      inputProvenance: Set(
        container.decode([ProvenanceClass].self, forKey: .inputProvenance)
      ),
      expectedOrigin: container.decode(SecurityOrigin.self, forKey: .expectedOrigin),
      preconditions: container.decode([ObservationPredicate].self, forKey: .preconditions),
      postconditions: container.decode([ObservationPredicate].self, forKey: .postconditions),
      verificationTimeoutNanoseconds: container.decode(
        UInt64.self,
        forKey: .verificationTimeoutNanoseconds
      )
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(idempotencyKey, forKey: .idempotencyKey)
    try container.encode(target, forKey: .target)
    try container.encode(requiredCapability, forKey: .requiredCapability)
    try container.encode(
      inputProvenance.sorted { $0.rawValue < $1.rawValue },
      forKey: .inputProvenance
    )
    try container.encode(expectedOrigin, forKey: .expectedOrigin)
    try container.encode(preconditions, forKey: .preconditions)
    try container.encode(postconditions, forKey: .postconditions)
    try container.encode(verificationTimeoutNanoseconds, forKey: .verificationTimeoutNanoseconds)
  }
}

public enum DispatchOutcome: String, Codable, Sendable {
  /// The adapter knows the browser event was not dispatched. A later retry is safe.
  case notDispatched = "not_dispatched"
  /// The adapter knows the browser accepted the event. This does not prove the server write.
  case dispatched
  /// The adapter cannot determine whether the browser accepted the event.
  case unknown
}

public enum TransactionPhase: String, Codable, Equatable, Sendable {
  case prepared
  case dispatching
  case dispatched
  case verified
  case indeterminate
}

public struct TransactionReceipt: Codable, Equatable, Sendable {
  public let idempotencyKey: String
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
}

public enum TransactionPreparation: Equatable, Sendable {
  case prepared(TransactionReceipt)
  case alreadyExists(TransactionReceipt)
}

public enum TransactionVerification: Codable, Equatable, Sendable {
  case pending(TransactionReceipt)
  case verified(TransactionReceipt)
  case indeterminate(TransactionReceipt)
}

public enum TransactionError: Error, Equatable, Sendable {
  case emptyIdempotencyKey
  case emptyPostconditions
  case invalidVerificationTimeout
  case idempotencyKeyConflict
  case originMismatch
  case capabilityDenied(CapabilityDenial)
  case preconditionUnsatisfied
  case preconditionUnknown
  case postconditionAlreadySatisfied
  case targetResolutionMismatch
  case targetNotUnique(Int)
  case invalidExpectedDigest
  case emptySemanticTextFields
  case unknownTransaction
  case invalidPhase(expected: TransactionPhase, actual: TransactionPhase)
  case monotonicClockRegressed
  case deadlineOverflow
}

/// The ledger guarantees local transition integrity. It deliberately does not
/// claim rollback or exactly-once delivery on an uncooperative web server.
public actor TransactionalWriteLedger {
  private struct Record: Sendable {
    let plan: TransactionalWritePlan
    let planDigest: String
    let baseObservationDigest: String
    let preparedAtNanoseconds: UInt64
    var phase: TransactionPhase
    var dispatchedAtNanoseconds: UInt64?
    var deadlineNanoseconds: UInt64?
    var resultObservationDigest: String?
    var observedAtNanoseconds: UInt64?
    var evidence: [PredicateEvidence]
    var recoveredByReconciliation: Bool
  }

  private var records: [String: Record] = [:]

  public init() {}

  public func prepare(
    _ plan: TransactionalWritePlan,
    observation: TransactionObservation,
    capabilityAuthority: CapabilityAuthority,
    capabilityHandle: CapabilityHandle,
    wallClockNow: Date,
    monotonicNowNanoseconds: UInt64
  ) async throws -> TransactionPreparation {
    let planDigest = try plan.digest()
    if let existing = records[plan.idempotencyKey] {
      guard existing.planDigest == planDigest else {
        throw TransactionError.idempotencyKeyConflict
      }
      return .alreadyExists(receipt(for: existing))
    }

    guard observation.state.securityOrigin == plan.expectedOrigin else {
      throw TransactionError.originMismatch
    }
    let decision = await capabilityAuthority.evaluate(
      CapabilityRequest(
        action: plan.requiredCapability,
        liveOrigin: observation.state.securityOrigin,
        inputProvenance: plan.inputProvenance
      ),
      using: capabilityHandle,
      now: wallClockNow
    )
    if case .denied(let denial) = decision {
      throw TransactionError.capabilityDenied(denial)
    }
    try requireSatisfied(plan.preconditions, in: observation)
    let initialPostconditions = try evaluate(plan.postconditions, in: observation)
    if initialPostconditions.allSatisfy({ $0.result == .satisfied }) {
      throw TransactionError.postconditionAlreadySatisfied
    }

    let record = Record(
      plan: plan,
      planDigest: planDigest,
      baseObservationDigest: try observation.state.digest(),
      preparedAtNanoseconds: monotonicNowNanoseconds,
      phase: .prepared,
      dispatchedAtNanoseconds: nil,
      deadlineNanoseconds: nil,
      resultObservationDigest: nil,
      observedAtNanoseconds: nil,
      evidence: [],
      recoveredByReconciliation: false
    )
    records[plan.idempotencyKey] = record
    return .prepared(receipt(for: record))
  }

  /// Must be called immediately before browser dispatch, after fresh locator
  /// resolution. The capability and preconditions are checked again.
  public func beginDispatch(
    idempotencyKey: String,
    observation: TransactionObservation,
    resolution: LocatorResolution,
    capabilityAuthority: CapabilityAuthority,
    capabilityHandle: CapabilityHandle,
    wallClockNow: Date,
    monotonicNowNanoseconds: UInt64
  ) async throws -> TransactionReceipt {
    guard var record = records[idempotencyKey] else {
      throw TransactionError.unknownTransaction
    }
    guard record.phase == .prepared else {
      throw TransactionError.invalidPhase(expected: .prepared, actual: record.phase)
    }
    guard monotonicNowNanoseconds >= record.preparedAtNanoseconds else {
      throw TransactionError.monotonicClockRegressed
    }
    guard observation.state.securityOrigin == record.plan.expectedOrigin else {
      throw TransactionError.originMismatch
    }
    guard resolution.recipeElementID == record.plan.target.elementID else {
      throw TransactionError.targetResolutionMismatch
    }
    guard resolution.finalCandidateCount == 1 else {
      throw TransactionError.targetNotUnique(resolution.finalCandidateCount)
    }
    let decision = await capabilityAuthority.evaluate(
      CapabilityRequest(
        action: record.plan.requiredCapability,
        liveOrigin: observation.state.securityOrigin,
        inputProvenance: record.plan.inputProvenance
      ),
      using: capabilityHandle,
      now: wallClockNow
    )
    if case .denied(let denial) = decision {
      throw TransactionError.capabilityDenied(denial)
    }
    try requireSatisfied(record.plan.preconditions, in: observation)

    record.phase = .dispatching
    records[idempotencyKey] = record
    return receipt(for: record)
  }

  public func recordDispatchOutcome(
    idempotencyKey: String,
    outcome: DispatchOutcome,
    monotonicNowNanoseconds: UInt64
  ) throws -> TransactionReceipt {
    guard var record = records[idempotencyKey] else {
      throw TransactionError.unknownTransaction
    }
    guard record.phase == .dispatching else {
      throw TransactionError.invalidPhase(expected: .dispatching, actual: record.phase)
    }
    guard monotonicNowNanoseconds >= record.preparedAtNanoseconds else {
      throw TransactionError.monotonicClockRegressed
    }

    switch outcome {
    case .notDispatched:
      record.phase = .prepared
    case .unknown:
      record.phase = .indeterminate
      record.observedAtNanoseconds = monotonicNowNanoseconds
    case .dispatched:
      let (deadline, overflow) = monotonicNowNanoseconds.addingReportingOverflow(
        record.plan.verificationTimeoutNanoseconds
      )
      guard !overflow else { throw TransactionError.deadlineOverflow }
      record.phase = .dispatched
      record.dispatchedAtNanoseconds = monotonicNowNanoseconds
      record.deadlineNanoseconds = deadline
    }

    records[idempotencyKey] = record
    return receipt(for: record)
  }

  /// Converts an interrupted dispatch handshake into ambiguity. It never
  /// assumes that the event did or did not reach the page.
  public func markDispatchInterrupted(
    idempotencyKey: String,
    monotonicNowNanoseconds: UInt64
  ) throws -> TransactionReceipt {
    guard var record = records[idempotencyKey] else {
      throw TransactionError.unknownTransaction
    }
    guard record.phase == .dispatching else {
      throw TransactionError.invalidPhase(expected: .dispatching, actual: record.phase)
    }
    guard monotonicNowNanoseconds >= record.preparedAtNanoseconds else {
      throw TransactionError.monotonicClockRegressed
    }
    record.phase = .indeterminate
    record.observedAtNanoseconds = monotonicNowNanoseconds
    records[idempotencyKey] = record
    return receipt(for: record)
  }

  public func verify(
    idempotencyKey: String,
    observation: TransactionObservation,
    monotonicNowNanoseconds: UInt64
  ) throws -> TransactionVerification {
    guard var record = records[idempotencyKey] else {
      throw TransactionError.unknownTransaction
    }
    guard record.phase == .dispatched else {
      throw TransactionError.invalidPhase(expected: .dispatched, actual: record.phase)
    }
    guard let dispatchedAt = record.dispatchedAtNanoseconds,
      monotonicNowNanoseconds >= dispatchedAt
    else {
      throw TransactionError.monotonicClockRegressed
    }

    let evidence = try postconditionEvidence(for: record.plan, in: observation)
    record.evidence = evidence
    record.resultObservationDigest = try observation.state.digest()
    record.observedAtNanoseconds = monotonicNowNanoseconds

    if evidence.allSatisfy({ $0.result == .satisfied }) {
      record.phase = .verified
      records[idempotencyKey] = record
      return .verified(receipt(for: record))
    }
    if let deadline = record.deadlineNanoseconds, monotonicNowNanoseconds >= deadline {
      record.phase = .indeterminate
      records[idempotencyKey] = record
      return .indeterminate(receipt(for: record))
    }

    records[idempotencyKey] = record
    return .pending(receipt(for: record))
  }

  /// Reconciliation can prove a late postcondition, but never authorizes a
  /// replay. Unsatisfied or incomplete evidence remains indeterminate.
  public func reconcile(
    idempotencyKey: String,
    observation: TransactionObservation,
    monotonicNowNanoseconds: UInt64
  ) throws -> TransactionVerification {
    guard var record = records[idempotencyKey] else {
      throw TransactionError.unknownTransaction
    }
    guard record.phase == .indeterminate else {
      throw TransactionError.invalidPhase(expected: .indeterminate, actual: record.phase)
    }
    guard monotonicNowNanoseconds >= record.preparedAtNanoseconds else {
      throw TransactionError.monotonicClockRegressed
    }

    record.evidence = try postconditionEvidence(for: record.plan, in: observation)
    record.resultObservationDigest = try observation.state.digest()
    record.observedAtNanoseconds = monotonicNowNanoseconds
    if record.evidence.allSatisfy({ $0.result == .satisfied }) {
      record.phase = .verified
      record.recoveredByReconciliation = true
      records[idempotencyKey] = record
      return .verified(receipt(for: record))
    }

    records[idempotencyKey] = record
    return .indeterminate(receipt(for: record))
  }

  public func receipt(idempotencyKey: String) throws -> TransactionReceipt {
    guard let record = records[idempotencyKey] else {
      throw TransactionError.unknownTransaction
    }
    return receipt(for: record)
  }

  private func evaluate(
    _ predicates: [ObservationPredicate],
    in observation: TransactionObservation
  ) throws -> [PredicateEvidence] {
    try predicates.map {
      PredicateEvidence(predicate: $0, result: try $0.evaluate(in: observation))
    }
  }

  private func postconditionEvidence(
    for plan: TransactionalWritePlan,
    in observation: TransactionObservation
  ) throws -> [PredicateEvidence] {
    guard observation.state.securityOrigin == plan.expectedOrigin else {
      return plan.postconditions.map {
        PredicateEvidence(predicate: $0, result: .unknown)
      }
    }
    return try evaluate(plan.postconditions, in: observation)
  }

  private func requireSatisfied(
    _ predicates: [ObservationPredicate],
    in observation: TransactionObservation
  ) throws {
    for evidence in try evaluate(predicates, in: observation) {
      switch evidence.result {
      case .satisfied:
        continue
      case .unsatisfied:
        throw TransactionError.preconditionUnsatisfied
      case .unknown:
        throw TransactionError.preconditionUnknown
      }
    }
  }

  private func receipt(for record: Record) -> TransactionReceipt {
    TransactionReceipt(
      idempotencyKey: record.plan.idempotencyKey,
      planDigest: record.planDigest,
      phase: record.phase,
      baseObservationDigest: record.baseObservationDigest,
      resultObservationDigest: record.resultObservationDigest,
      preparedAtNanoseconds: record.preparedAtNanoseconds,
      dispatchedAtNanoseconds: record.dispatchedAtNanoseconds,
      observedAtNanoseconds: record.observedAtNanoseconds,
      deadlineNanoseconds: record.deadlineNanoseconds,
      postconditionEvidence: record.evidence,
      recoveredByReconciliation: record.recoveredByReconciliation
    )
  }
}
