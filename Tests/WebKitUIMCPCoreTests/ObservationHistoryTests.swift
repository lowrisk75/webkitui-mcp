import Testing

@testable import WebKitUIMCPCore

@Suite("Checkpoint and delta history")
struct ObservationHistoryTests {
  private let origin = SecurityOrigin(scheme: "https", host: "example.com")
  private let key = ObservationFieldKey(frameID: "main", elementID: "e17", field: "value")

  @Test("Insert, replace and remove reconstruct exactly")
  func roundTrip() throws {
    let zero = try state(generation: 0, values: [:])
    let one = try state(generation: 1, values: [key: "Paris"])
    let two = try state(generation: 2, values: [key: "Lyon"])
    let three = try state(generation: 3, values: [:])
    var history = try ObservationHistory(checkpoint: zero, maximumDeltaDepth: 8)

    #expect(try history.append(one) == .delta(depth: 1))
    #expect(try history.append(two) == .delta(depth: 2))
    #expect(try history.append(three) == .delta(depth: 3))
    #expect(try history.reconstruct() == three)
  }

  @Test("Delta chain has a hard checkpoint bound")
  func boundedChain() throws {
    var history = try ObservationHistory(
      checkpoint: state(generation: 0, values: [:]),
      maximumDeltaDepth: 2
    )
    #expect(try history.append(state(generation: 1, values: [key: "1"])) == .delta(depth: 1))
    #expect(try history.append(state(generation: 2, values: [key: "2"])) == .delta(depth: 2))
    #expect(
      try history.append(state(generation: 3, values: [key: "3"]))
        == .checkpoint(.periodicLimit)
    )
    #expect(history.deltas.isEmpty)
    #expect(history.checkpoint.generation == 3)
  }

  @Test("Document and origin transitions force a checkpoint")
  func documentBoundary() throws {
    var history = try ObservationHistory(
      checkpoint: state(generation: 0, values: [:]),
      maximumDeltaDepth: 8
    )
    let next = try CanonicalObservationState(
      generation: 1,
      documentID: "document-2",
      securityOrigin: .init(scheme: "https", host: "other.example"),
      entries: []
    )

    #expect(try history.append(next) == .checkpoint(.documentChanged))
    #expect(try history.reconstruct() == next)
  }

  @Test("Wrong base and corrupted result digests fail closed")
  func digestIntegrity() throws {
    let base = try state(generation: 0, values: [key: "A"])
    let result = try state(generation: 1, values: [key: "B"])
    let delta = try ObservationDelta.between(base, and: result)
    let wrongBase = try state(generation: 0, values: [key: "X"])

    #expect(throws: ObservationHistoryError.baseDigestMismatch) {
      try delta.applying(to: wrongBase)
    }

    let corrupted = ObservationDelta(
      baseGeneration: delta.baseGeneration,
      resultGeneration: delta.resultGeneration,
      baseDigest: delta.baseDigest,
      resultDigest: String(repeating: "0", count: 64),
      operations: delta.operations
    )
    #expect(throws: ObservationHistoryError.resultDigestMismatch) {
      try corrupted.applying(to: base)
    }
  }

  @Test("Generation gaps and duplicate keys are rejected")
  func invariants() throws {
    let entry = try makeEntry(key: key, text: "A")
    #expect(throws: ObservationHistoryError.duplicateKey(key)) {
      try CanonicalObservationState(
        generation: 0,
        documentID: "document-1",
        securityOrigin: origin,
        entries: [entry, entry]
      )
    }

    var history = try ObservationHistory(
      checkpoint: state(generation: 0, values: [:]),
      maximumDeltaDepth: 2
    )
    #expect(throws: ObservationHistoryError.generationGap(expected: 1, actual: 2)) {
      try history.append(state(generation: 2, values: [:]))
    }
  }

  @Test("Canonical state bytes ignore input entry order")
  func canonicalOrder() throws {
    let secondKey = ObservationFieldKey(frameID: "main", elementID: "e18", field: "name")
    let first = try makeEntry(key: key, text: "A")
    let second = try makeEntry(key: secondKey, text: "B")
    let lhs = try CanonicalObservationState(
      generation: 0,
      documentID: "document-1",
      securityOrigin: origin,
      entries: [first, second]
    )
    let rhs = try CanonicalObservationState(
      generation: 0,
      documentID: "document-1",
      securityOrigin: origin,
      entries: [second, first]
    )

    #expect(try lhs.canonicalJSONData() == rhs.canonicalJSONData())
    #expect(try lhs.digest() == rhs.digest())
  }

  private func state(
    generation: UInt64,
    values: [ObservationFieldKey: String]
  ) throws -> CanonicalObservationState {
    try CanonicalObservationState(
      generation: generation,
      documentID: "document-1",
      securityOrigin: origin,
      entries: try values.map { try makeEntry(key: $0.key, text: $0.value) }
    )
  }

  private func makeEntry(key: ObservationFieldKey, text: String) throws -> ObservationStateEntry {
    ObservationStateEntry(
      key: key,
      value: try ProvenancedText(
        text: text,
        source: .init(
          classification: .firstPartySiteContent,
          documentID: "document-1",
          frameID: key.frameID,
          securityOrigin: origin
        )
      )
    )
  }
}
