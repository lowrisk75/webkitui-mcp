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
      let role = element.role?.segments.map(\.text).joined().lowercased()
      if role == "heading", let heading = element.accessibleName ?? element.text {
        entries.append(.init(key: elementKey(element, "@heading"), value: heading))
      }
      if role == "dialog" || role == "alertdialog",
        let dialogName = element.accessibleName ?? element.label ?? element.text
      {
        entries.append(.init(key: elementKey(element, "@dialog_name"), value: dialogName))
      }
      if role == "dialog" || role == "alertdialog" || role == "region",
        let panelName = element.accessibleName ?? element.label ?? element.text
      {
        entries.append(.init(key: elementKey(element, "@panel_name"), value: panelName))
      }
      if element.visible, !element.sensitive,
        element.boundingBox.width > 0, element.boundingBox.height > 0,
        let value = element.value
      {
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
      let validationState = try ProvenancedText(
        text: element.validationState.rawValue, source: toolSource)
      let validationAccepted = try ProvenancedText(
        text: String(element.validationState != .invalid), source: toolSource)
      entries.append(.init(key: elementKey(element, "@validation_state"), value: validationState))
      entries.append(
        .init(
          key: elementKey(element, "@validation_accepted"), value: validationAccepted))
      if let characterCount = element.characterCount {
        entries.append(
          .init(
            key: elementKey(element, "@character_count"),
            value: try ProvenancedText(text: String(characterCount), source: toolSource)))
      }
      if let checked = element.checked {
        entries.append(
          .init(
            key: elementKey(element, "@checked"),
            value: try ProvenancedText(text: String(checked), source: toolSource)
          ))
      }
      if let selected = element.selected {
        entries.append(
          .init(
            key: elementKey(element, "@selected"),
            value: try ProvenancedText(text: String(selected), source: toolSource)
          ))
      }
      if let selectedOption = element.selectedOption {
        entries.append(.init(key: elementKey(element, "@selected_option"), value: selectedOption))
      }
      for (name, value) in element.stateAttributes.sorted(by: { $0.key < $1.key }) {
        entries.append(.init(key: elementKey(element, "@attribute:\(name)"), value: value))
      }
      if semanticIdentityCounts[element.locatorRecipe.semanticIdentity] == 1 {
        let semanticID = element.locatorRecipe.semanticIdentity
        func appendSemantic(_ field: String, _ value: ProvenancedText) {
          entries.append(
            .init(
              key: ObservationFieldKey(frameID: "main", elementID: semanticID, field: field),
              value: value
            ))
        }
        if let checked = element.checked {
          appendSemantic(
            "@checked", try ProvenancedText(text: String(checked), source: toolSource))
        }
        if let selected = element.selected {
          appendSemantic(
            "@selected", try ProvenancedText(text: String(selected), source: toolSource))
        }
        if let selectedOption = element.selectedOption {
          appendSemantic("@selected_option", selectedOption)
        }
        appendSemantic(
          "@enabled", try ProvenancedText(text: String(!element.disabled), source: toolSource))
        appendSemantic("@validation_state", validationState)
        appendSemantic("@validation_accepted", validationAccepted)
        if let characterCount = element.characterCount {
          appendSemantic(
            "@character_count",
            try ProvenancedText(text: String(characterCount), source: toolSource))
        }
        for (name, value) in element.stateAttributes.sorted(by: { $0.key < $1.key }) {
          appendSemantic("@attribute:\(name)", value)
        }
      }
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
