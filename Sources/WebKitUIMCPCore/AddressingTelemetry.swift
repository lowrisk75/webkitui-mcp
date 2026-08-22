public enum EvidenceComparison: String, Codable, CaseIterable, Sendable {
  case same
  case different
  case unknown
}

public enum AddressingCounter: String, Codable, CaseIterable, Sendable {
  case addressResolutionFailed = "address_resolution_failed"
  case addressNowAmbiguous = "address_now_ambiguous"
  case logicalTargetChanged = "logical_target_changed"
  case nodeReplacedButSemanticLocatorRecovered = "node_replaced_but_semantic_locator_recovered"
  case coordinateInvalidatedByLayoutChange = "coordinate_invalidated_by_layout_change"
}

public enum AddressingEvidenceGap: String, Codable, CaseIterable, Hashable, Sendable {
  case semanticComparison = "semantic_comparison"
  case physicalIdentity = "physical_identity"
  case geometryComparison = "geometry_comparison"
}

/// Exactly one primary result is produced for an action attempt.
/// `insufficientEvidence` never increments one of the five failure counters.
public enum AddressingOutcome: Codable, Equatable, Sendable {
  case classified(AddressingCounter)
  case stable
  case insufficientEvidence(Set<AddressingEvidenceGap>)
}

public enum AddressingAttemptError: Error, Equatable, Sendable {
  case negativeCandidateCount(Int)
  case actionPredatesObservation
  case generationMovedBackwards
}

/// Browser-independent evidence captured between one observation and one action.
///
/// `finalCandidateCount` is the count after every deterministic locator-recipe
/// filter has run. A broad selector's raw match count must not be passed here.
public struct AddressingAttempt: Codable, Equatable, Sendable {
  public let observationID: String
  public let locatorRecipeID: String
  public let observationGeneration: UInt64
  public let actionGeneration: UInt64
  public let observationMonotonicNanoseconds: UInt64
  public let actionMonotonicNanoseconds: UInt64
  public let finalCandidateCount: Int
  public let semanticComparison: EvidenceComparison
  public let physicalIdentity: EvidenceComparison
  public let geometryComparison: EvidenceComparison

  public init(
    observationID: String,
    locatorRecipeID: String,
    observationGeneration: UInt64,
    actionGeneration: UInt64,
    observationMonotonicNanoseconds: UInt64,
    actionMonotonicNanoseconds: UInt64,
    finalCandidateCount: Int,
    semanticComparison: EvidenceComparison,
    physicalIdentity: EvidenceComparison,
    geometryComparison: EvidenceComparison
  ) throws {
    guard finalCandidateCount >= 0 else {
      throw AddressingAttemptError.negativeCandidateCount(finalCandidateCount)
    }
    guard actionMonotonicNanoseconds >= observationMonotonicNanoseconds else {
      throw AddressingAttemptError.actionPredatesObservation
    }
    guard actionGeneration >= observationGeneration else {
      throw AddressingAttemptError.generationMovedBackwards
    }

    self.observationID = observationID
    self.locatorRecipeID = locatorRecipeID
    self.observationGeneration = observationGeneration
    self.actionGeneration = actionGeneration
    self.observationMonotonicNanoseconds = observationMonotonicNanoseconds
    self.actionMonotonicNanoseconds = actionMonotonicNanoseconds
    self.finalCandidateCount = finalCandidateCount
    self.semanticComparison = semanticComparison
    self.physicalIdentity = physicalIdentity
    self.geometryComparison = geometryComparison
  }

  public var generationDelta: UInt64 {
    actionGeneration - observationGeneration
  }

  public var latencyNanoseconds: UInt64 {
    actionMonotonicNanoseconds - observationMonotonicNanoseconds
  }
}

public enum AddressingClassifier {
  /// Classifies one primary outcome using a documented precedence order.
  /// Cardinality is conclusive first, then semantics, physical replacement,
  /// and finally coordinate validity. Unknown evidence fails closed.
  public static func classify(_ attempt: AddressingAttempt) -> AddressingOutcome {
    if attempt.finalCandidateCount == 0 {
      return .classified(.addressResolutionFailed)
    }

    if attempt.finalCandidateCount > 1 {
      return .classified(.addressNowAmbiguous)
    }

    switch attempt.semanticComparison {
    case .different:
      return .classified(.logicalTargetChanged)
    case .unknown:
      return .insufficientEvidence([.semanticComparison])
    case .same:
      break
    }

    switch attempt.physicalIdentity {
    case .different:
      return .classified(.nodeReplacedButSemanticLocatorRecovered)
    case .unknown:
      return .insufficientEvidence([.physicalIdentity])
    case .same:
      break
    }

    switch attempt.geometryComparison {
    case .different:
      return .classified(.coordinateInvalidatedByLayoutChange)
    case .unknown:
      return .insufficientEvidence([.geometryComparison])
    case .same:
      return .stable
    }
  }
}

/// Deterministic semantic evidence. Keys identify facts such as `role`,
/// `accessible_name`, `context.invoice_id`, or `ancestor.0.role`.
public struct SemanticFingerprint: Codable, Equatable, Sendable {
  public let facts: [String: String]

  public init(facts: [String: String]) {
    self.facts = facts
  }

  /// Compares every fact captured at observation time. Extra live facts do not
  /// invalidate the target; a missing live fact is unknown rather than changed.
  public func compare(to live: SemanticFingerprint) -> EvidenceComparison {
    guard !facts.isEmpty else { return .unknown }

    for (key, observedValue) in facts {
      guard let liveValue = live.facts[key] else { return .unknown }
      guard liveValue == observedValue else { return .different }
    }

    return .same
  }
}

public struct AddressingCounterSnapshot: Codable, Equatable, Sendable {
  public var addressResolutionFailed: UInt64 = 0
  public var addressNowAmbiguous: UInt64 = 0
  public var logicalTargetChanged: UInt64 = 0
  public var nodeReplacedButSemanticLocatorRecovered: UInt64 = 0
  public var coordinateInvalidatedByLayoutChange: UInt64 = 0

  public init() {}

  enum CodingKeys: String, CodingKey {
    case addressResolutionFailed = "address_resolution_failed"
    case addressNowAmbiguous = "address_now_ambiguous"
    case logicalTargetChanged = "logical_target_changed"
    case nodeReplacedButSemanticLocatorRecovered = "node_replaced_but_semantic_locator_recovered"
    case coordinateInvalidatedByLayoutChange = "coordinate_invalidated_by_layout_change"
  }

  public subscript(counter: AddressingCounter) -> UInt64 {
    switch counter {
    case .addressResolutionFailed:
      addressResolutionFailed
    case .addressNowAmbiguous:
      addressNowAmbiguous
    case .logicalTargetChanged:
      logicalTargetChanged
    case .nodeReplacedButSemanticLocatorRecovered:
      nodeReplacedButSemanticLocatorRecovered
    case .coordinateInvalidatedByLayoutChange:
      coordinateInvalidatedByLayoutChange
    }
  }

  public mutating func record(_ outcome: AddressingOutcome) {
    guard case .classified(let counter) = outcome else { return }

    switch counter {
    case .addressResolutionFailed:
      addressResolutionFailed = Self.incrementWithoutOverflow(addressResolutionFailed)
    case .addressNowAmbiguous:
      addressNowAmbiguous = Self.incrementWithoutOverflow(addressNowAmbiguous)
    case .logicalTargetChanged:
      logicalTargetChanged = Self.incrementWithoutOverflow(logicalTargetChanged)
    case .nodeReplacedButSemanticLocatorRecovered:
      nodeReplacedButSemanticLocatorRecovered = Self.incrementWithoutOverflow(
        nodeReplacedButSemanticLocatorRecovered
      )
    case .coordinateInvalidatedByLayoutChange:
      coordinateInvalidatedByLayoutChange = Self.incrementWithoutOverflow(
        coordinateInvalidatedByLayoutChange
      )
    }
  }

  private static func incrementWithoutOverflow(_ value: UInt64) -> UInt64 {
    value == .max ? .max : value + 1
  }
}
