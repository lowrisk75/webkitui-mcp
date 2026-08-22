import Testing

@testable import WebKitUIMCPCore

@Suite("MFS coverage")
struct MFSCoverageTests {
  private let tag = MFSUnit(observationElementID: "e17", information: .tag)
  private let text = MFSUnit(observationElementID: "e17", information: .text)
  private let value = MFSUnit(observationElementID: "e17", information: .attribute("value"))

  @Test("Coverage is binary while unit recall remains diagnostic")
  func binaryCoverage() throws {
    let instance = try makeInstance()
    let reduction = MFSReduction(
      instanceID: instance.id,
      retainedUnits: [tag, value],
      serializedCharacterCount: 40,
      serializedTokenCount: 12
    )

    let report = try MFSBenchmark.evaluate(instances: [instance], reductions: [reduction])

    #expect(report.coverage == 0)
    #expect(report.results[0].mfsUnitRecall == 0.5)
    #expect(report.results[0].missingMFSUnits == [text])
    #expect(report.meanCharacterRetentionRatio == 0.4)
    #expect(report.meanTokenRetentionRatio == 0.3)
  }

  @Test("Full observation is the trivial perfect-coverage baseline")
  func fullBaseline() throws {
    let instance = try makeInstance()
    let reduction = MFSReduction(
      instanceID: instance.id,
      retainedUnits: Set(instance.observationUnits),
      serializedCharacterCount: 100,
      serializedTokenCount: 40
    )

    let report = try MFSBenchmark.evaluate(instances: [instance], reductions: [reduction])

    #expect(report.coverage == 1)
    #expect(report.meanCharacterRetentionRatio == 1)
    #expect(report.meanTokenRetentionRatio == 1)
  }

  @Test("Dataset ratios are means of per-instance ratios")
  func perInstanceMean() throws {
    let first = try makeInstance(id: "a", characters: 100, tokens: nil)
    let second = try makeInstance(id: "b", characters: 1_000, tokens: nil)
    let reductions = [
      MFSReduction(instanceID: "a", retainedUnits: [tag, text], serializedCharacterCount: 50),
      MFSReduction(instanceID: "b", retainedUnits: [tag], serializedCharacterCount: 100),
    ]

    let report = try MFSBenchmark.evaluate(instances: [second, first], reductions: reductions)

    #expect(report.coverage == 0.5)
    #expect(report.meanCharacterRetentionRatio == 0.3)
    #expect(report.meanTokenRetentionRatio == nil)
    #expect(report.results.map(\.instanceID) == ["a", "b"])
  }

  @Test("Tag, text and named attributes are distinct ablation units")
  func distinctInformationUnits() {
    #expect(Set([tag, text, value]).count == 3)
  }

  @Test("Malformed MFS instances fail closed")
  func invalidInstances() {
    #expect(throws: MFSError.invalidAttributeName("")) {
      try MFSInstance(
        id: "x",
        observationUnits: [.init(observationElementID: "e1", information: .attribute(""))],
        approximateMFS: [.init(observationElementID: "e1", information: .attribute(""))],
        originalCharacterCount: 1
      )
    }
    #expect(throws: MFSError.emptyApproximateMFS) {
      try MFSInstance(
        id: "x",
        observationUnits: [tag],
        approximateMFS: [],
        originalCharacterCount: 1
      )
    }
    #expect(throws: MFSError.approximateMFSOutsideObservation([text])) {
      try MFSInstance(
        id: "x",
        observationUnits: [tag],
        approximateMFS: [text],
        originalCharacterCount: 1
      )
    }
    #expect(throws: MFSError.nonPositiveOriginalCharacterCount(0)) {
      try MFSInstance(
        id: "x",
        observationUnits: [tag],
        approximateMFS: [tag],
        originalCharacterCount: 0
      )
    }
  }

  @Test("Dataset identity and membership mismatches fail closed")
  func identityMismatches() throws {
    let instance = try makeInstance()
    let valid = MFSReduction(
      instanceID: instance.id,
      retainedUnits: [tag, text],
      serializedCharacterCount: 10,
      serializedTokenCount: 4
    )

    #expect(throws: MFSError.emptyDataset) {
      try MFSBenchmark.evaluate(instances: [], reductions: [])
    }

    #expect(throws: MFSError.duplicateInstanceID(instance.id)) {
      try MFSBenchmark.evaluate(instances: [instance, instance], reductions: [valid])
    }
    #expect(throws: MFSError.duplicateReductionID(instance.id)) {
      try MFSBenchmark.evaluate(instances: [instance], reductions: [valid, valid])
    }
    #expect(throws: MFSError.missingReduction(instance.id)) {
      try MFSBenchmark.evaluate(instances: [instance], reductions: [])
    }
    #expect(throws: MFSError.unknownInstance("unknown")) {
      try MFSBenchmark.evaluate(
        instances: [instance],
        reductions: [
          .init(instanceID: "unknown", retainedUnits: [], serializedCharacterCount: 0)
        ]
      )
    }
    let foreign = MFSUnit(observationElementID: "foreign", information: .text)
    #expect(
      throws: MFSError.retainedUnitOutsideObservation(
        instanceID: instance.id,
        units: [foreign]
      )
    ) {
      try MFSBenchmark.evaluate(
        instances: [instance],
        reductions: [
          .init(
            instanceID: instance.id,
            retainedUnits: [foreign],
            serializedCharacterCount: 1,
            serializedTokenCount: 1
          )
        ]
      )
    }
  }

  @Test("Size and token measurements cannot exceed the source observation")
  func invalidMeasurements() throws {
    let instance = try makeInstance()

    #expect(throws: MFSError.invalidReducedCharacterCount(instanceID: instance.id, count: 101)) {
      try MFSBenchmark.evaluate(
        instances: [instance],
        reductions: [
          .init(instanceID: instance.id, retainedUnits: [], serializedCharacterCount: 101)
        ]
      )
    }
    #expect(throws: MFSError.incompleteTokenCounts(instanceID: instance.id)) {
      try MFSBenchmark.evaluate(
        instances: [instance],
        reductions: [
          .init(instanceID: instance.id, retainedUnits: [], serializedCharacterCount: 10)
        ]
      )
    }
    #expect(throws: MFSError.invalidReducedTokenCount(instanceID: instance.id, count: 41)) {
      try MFSBenchmark.evaluate(
        instances: [instance],
        reductions: [
          .init(
            instanceID: instance.id,
            retainedUnits: [],
            serializedCharacterCount: 10,
            serializedTokenCount: 41
          )
        ]
      )
    }
  }

  private func makeInstance(
    id: String = "instance-1",
    characters: Int = 100,
    tokens: Int? = 40
  ) throws -> MFSInstance {
    try MFSInstance(
      id: id,
      observationUnits: [tag, text, value],
      approximateMFS: [tag, text],
      originalCharacterCount: characters,
      originalTokenCount: tokens
    )
  }
}
