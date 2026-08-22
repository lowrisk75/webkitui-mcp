import Foundation
import WebKitUIMCPCore

extension WebKitPageObservation {
  public func canonicalState() throws -> CanonicalObservationState {
    guard
      let urlString = url.segments.first?.text,
      let parsedURL = URL(string: urlString),
      let scheme = parsedURL.scheme,
      let host = parsedURL.host
    else {
      throw WebKitRuntimeError.malformedInstrumentationResult
    }
    let origin = SecurityOrigin(scheme: scheme, host: host, port: parsedURL.port)
    let toolSource = ProvenanceSource(
      classification: .toolResult,
      documentID: documentID,
      frameID: "main",
      securityOrigin: origin
    )
    var entries: [ObservationStateEntry] = [
      .init(key: pageKey("url"), value: url),
      .init(key: pageKey("title"), value: title),
      .init(
        key: pageKey("ready_state"),
        value: try ProvenancedText(text: readyState, source: toolSource)
      ),
    ]

    let semanticIdentityCounts = Dictionary(
      grouping: elements, by: { $0.locatorRecipe.semanticIdentity }
    ).mapValues(\.count)

    for element in elements {
      entries.append(.init(key: elementKey(element, "@tag"), value: element.tag))
      if let value = element.role {
        entries.append(.init(key: elementKey(element, "@role"), value: value))
      }
      if let value = element.accessibleName {
        entries.append(.init(key: elementKey(element, "@accessible_name"), value: value))
      }
      if let value = element.label {
        entries.append(.init(key: elementKey(element, "@label"), value: value))
      }
      if let value = element.text {
        entries.append(.init(key: elementKey(element, "@text"), value: value))
      }
      if let value = element.value {
        entries.append(.init(key: elementKey(element, "@value"), value: value))
        if semanticIdentityCounts[element.locatorRecipe.semanticIdentity] == 1 {
          entries.append(
            .init(
              key: ObservationFieldKey(
                frameID: "main",
                elementID: element.locatorRecipe.semanticIdentity,
                field: "@value"
              ),
              value: value
            ))
        }
      }
      entries.append(
        .init(
          key: elementKey(element, "@disabled"),
          value: try ProvenancedText(text: String(element.disabled), source: toolSource)
        )
      )
      entries.append(
        .init(
          key: elementKey(element, "@visible"),
          value: try ProvenancedText(text: String(element.visible), source: toolSource)
        )
      )
    }

    return try CanonicalObservationState(
      generation: generation,
      documentID: documentID,
      securityOrigin: origin,
      entries: entries
    )
  }

  private func pageKey(_ field: String) -> ObservationFieldKey {
    ObservationFieldKey(frameID: "main", elementID: "@page", field: field)
  }

  private func elementKey(
    _ element: WebKitObservedElement,
    _ field: String
  ) -> ObservationFieldKey {
    ObservationFieldKey(frameID: "main", elementID: element.elementID, field: field)
  }
}
