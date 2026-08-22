import Foundation
import Testing

@testable import WebKitUIMCPCore

@Suite("Provenance")
struct ProvenanceTests {
  @Test("Mixed content retains independent source classes")
  func mixedContent() throws {
    let trusted = try ProvenancedText(
      text: "Account: ",
      source: .init(classification: .firstPartySiteContent)
    )
    let external = try ProvenancedText(
      text: "urgent instruction",
      source: .init(classification: .thirdPartyEmbed)
    )

    let mixed = try trusted.appending(external)

    #expect(mixed.segments.count == 2)
    #expect(mixed.classifications == [.firstPartySiteContent, .thirdPartyEmbed])
  }

  @Test("Transforms preserve labels and cannot drift across segment offsets")
  func segmentTransform() throws {
    let text = try ProvenancedText(
      segments: [
        try .init(
          text: "A&amp;B",
          sources: [.init(classification: .firstPartySiteContent)]
        ),
        try .init(
          text: "C&amp;D",
          sources: [.init(classification: .advertisement)]
        ),
      ]
    )

    let decoded = try text.transformed(by: .htmlEntityDecode) {
      $0.replacingOccurrences(of: "&amp;", with: "&")
    }

    #expect(decoded.segments.map(\.text) == ["A&B", "C&D"])
    #expect(decoded.segments[1].classifications == [.advertisement])
  }

  @Test("Transformation history is bounded and truncation is explicit")
  func boundedHistory() throws {
    var text = try ProvenancedText(
      text: "value",
      source: .init(classification: .toolResult)
    )
    for _ in 0...ProvenancedTextSegment.maximumRecordedTransformations {
      text = try text.transformed(by: .whitespaceCollapse) { $0 }
    }

    #expect(
      text.segments[0].transformations.count
        == ProvenancedTextSegment.maximumRecordedTransformations
    )
    #expect(text.segments[0].transformationHistoryTruncated)
  }

  @Test("Secrets are redacted without laundering their provenance")
  func secretRedaction() throws {
    let secret = try ProvenancedText(
      text: "correct horse battery staple",
      source: .init(classification: .passwordOrSecret)
    )

    let redacted = try secret.redactedForPlanner()

    #expect(redacted.segments[0].text == "[REDACTED]")
    #expect(redacted.classifications == [.passwordOrSecret])
    #expect(redacted.segments[0].transformations == [.redaction])
  }

  @Test("JSON keeps each string beside its provenance")
  func serialization() throws {
    let text = try ProvenancedText(
      text: "Pay now",
      source: .init(
        classification: .thirdPartyEmbed,
        documentID: "doc-1",
        frameID: "frame-2",
        securityOrigin: .init(scheme: "https", host: "ads.example")
      )
    )

    let data = try JSONEncoder().encode(text)
    let decoded = try JSONDecoder().decode(ProvenancedText.self, from: data)

    #expect(decoded == text)
    #expect(String(decoding: data, as: UTF8.self).contains("THIRD_PARTY_EMBED"))
  }

  @Test("Source encoding is canonical regardless of Set insertion order")
  func canonicalSerialization() throws {
    let first = ProvenanceSource(classification: .thirdPartyEmbed, frameID: "frame-b")
    let second = ProvenanceSource(classification: .firstPartySiteContent, frameID: "frame-a")
    let lhs = try ProvenancedText(
      segments: [try .init(text: "mixed", sources: [first, second])]
    )
    let rhs = try ProvenancedText(
      segments: [try .init(text: "mixed", sources: [second, first])]
    )

    #expect(try lhs.canonicalJSONData() == rhs.canonicalJSONData())
  }
}
