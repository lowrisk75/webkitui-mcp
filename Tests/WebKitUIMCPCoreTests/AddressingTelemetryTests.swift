import Foundation
import Testing

@testable import WebKitUIMCPCore

@Suite("Addressing telemetry")
struct AddressingTelemetryTests {
  @Test("No final candidate is a resolution failure")
  func resolutionFailure() throws {
    let attempt = try makeAttempt(finalCandidateCount: 0)
    #expect(AddressingClassifier.classify(attempt) == .classified(.addressResolutionFailed))
  }

  @Test("Several final candidates are ambiguous")
  func ambiguity() throws {
    let attempt = try makeAttempt(finalCandidateCount: 2)
    #expect(AddressingClassifier.classify(attempt) == .classified(.addressNowAmbiguous))
  }

  @Test("A semantic mismatch wins over identity and geometry")
  func logicalTargetChanged() throws {
    let attempt = try makeAttempt(
      semanticComparison: .different,
      physicalIdentity: .different,
      geometryComparison: .different
    )
    #expect(AddressingClassifier.classify(attempt) == .classified(.logicalTargetChanged))
  }

  @Test("A replaced node recovered by semantics is counted")
  func semanticRecovery() throws {
    let attempt = try makeAttempt(
      semanticComparison: .same,
      physicalIdentity: .different,
      geometryComparison: .different
    )
    #expect(
      AddressingClassifier.classify(attempt)
        == .classified(.nodeReplacedButSemanticLocatorRecovered)
    )
  }

  @Test("Coordinate invalidation requires stable semantics and identity")
  func coordinateInvalidation() throws {
    let attempt = try makeAttempt(
      semanticComparison: .same,
      physicalIdentity: .same,
      geometryComparison: .different
    )
    #expect(
      AddressingClassifier.classify(attempt)
        == .classified(.coordinateInvalidatedByLayoutChange)
    )
  }

  @Test("All matching evidence is stable")
  func stable() throws {
    let attempt = try makeAttempt(
      semanticComparison: .same,
      physicalIdentity: .same,
      geometryComparison: .same
    )
    #expect(AddressingClassifier.classify(attempt) == .stable)
    #expect(attempt.generationDelta == 2)
    #expect(attempt.latencyNanoseconds == 500)
  }

  @Test(
    "Unknown evidence fails closed",
    arguments: [
      (
        EvidenceComparison.unknown, EvidenceComparison.same, EvidenceComparison.same,
        AddressingEvidenceGap.semanticComparison
      ),
      (.same, .unknown, .same, .physicalIdentity),
      (.same, .same, .unknown, .geometryComparison),
    ]
  )
  func unknownEvidence(
    semantic: EvidenceComparison,
    identity: EvidenceComparison,
    geometry: EvidenceComparison,
    expectedGap: AddressingEvidenceGap
  ) throws {
    let attempt = try makeAttempt(
      semanticComparison: semantic,
      physicalIdentity: identity,
      geometryComparison: geometry
    )
    #expect(AddressingClassifier.classify(attempt) == .insufficientEvidence([expectedGap]))
  }

  @Test("Semantic context catches a virtualized-row recycle")
  func semanticFingerprintDetectsRecycle() {
    let observed = SemanticFingerprint(facts: [
      "role": "button",
      "accessible_name": "Delete",
      "context.invoice_id": "INV-0042",
      "ancestor.0.role": "row",
    ])
    let recycled = SemanticFingerprint(facts: [
      "role": "button",
      "accessible_name": "Delete",
      "context.invoice_id": "INV-0089",
      "ancestor.0.role": "row",
    ])

    #expect(observed.compare(to: recycled) == .different)
  }

  @Test("Missing or empty semantic evidence remains unknown")
  func semanticFingerprintUnknown() {
    let observed = SemanticFingerprint(facts: ["role": "button", "context.id": "42"])
    let incompleteLive = SemanticFingerprint(facts: ["role": "button"])
    let empty = SemanticFingerprint(facts: [:])

    #expect(observed.compare(to: incompleteLive) == .unknown)
    #expect(empty.compare(to: incompleteLive) == .unknown)
  }

  @Test("Stable observed facts tolerate additional live evidence")
  func semanticFingerprintAllowsAdditionalFacts() {
    let observed = SemanticFingerprint(facts: ["role": "button"])
    let live = SemanticFingerprint(facts: ["role": "button", "state.enabled": "true"])

    #expect(observed.compare(to: live) == .same)
  }

  @Test("Invalid temporal evidence is rejected")
  func invalidAttemptEvidence() {
    #expect(throws: AddressingAttemptError.actionPredatesObservation) {
      try makeAttempt(observationTime: 1_000, actionTime: 999)
    }
    #expect(throws: AddressingAttemptError.generationMovedBackwards) {
      try makeAttempt(observationGeneration: 4, actionGeneration: 3)
    }
    #expect(throws: AddressingAttemptError.negativeCandidateCount(-1)) {
      try makeAttempt(finalCandidateCount: -1)
    }
  }

  @Test("The accumulator exposes all five exact JSON counter names")
  func counterSnapshot() throws {
    var snapshot = AddressingCounterSnapshot()
    for counter in AddressingCounter.allCases {
      snapshot.record(.classified(counter))
    }
    snapshot.record(.stable)
    snapshot.record(.insufficientEvidence([.semanticComparison]))

    for counter in AddressingCounter.allCases {
      #expect(snapshot[counter] == 1)
    }

    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot))
        as? [String: NSNumber]
    )
    #expect(Set(object.keys) == Set(AddressingCounter.allCases.map(\.rawValue)))
    #expect(object.values.allSatisfy { $0.uint64Value == 1 })
  }

  private func makeAttempt(
    observationGeneration: UInt64 = 10,
    actionGeneration: UInt64 = 12,
    observationTime: UInt64 = 1_000,
    actionTime: UInt64 = 1_500,
    finalCandidateCount: Int = 1,
    semanticComparison: EvidenceComparison = .unknown,
    physicalIdentity: EvidenceComparison = .unknown,
    geometryComparison: EvidenceComparison = .unknown
  ) throws -> AddressingAttempt {
    try AddressingAttempt(
      observationID: "e17",
      locatorRecipeID: "recipe-17",
      observationGeneration: observationGeneration,
      actionGeneration: actionGeneration,
      observationMonotonicNanoseconds: observationTime,
      actionMonotonicNanoseconds: actionTime,
      finalCandidateCount: finalCandidateCount,
      semanticComparison: semanticComparison,
      physicalIdentity: physicalIdentity,
      geometryComparison: geometryComparison
    )
  }
}
