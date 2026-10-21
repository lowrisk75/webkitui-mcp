/**
 * Client-side example only. Normalizing a receipt grants no action authority.
 * Keep the returned observationID together with elementID, and replace both after
 * any new observation. Full segments and compact document provenance are retained.
 * @param {Record<string, any>} observation browser_observe structuredContent
 * @returns {{observationID: string, elements: Array<Record<string, any>>}}
 */
export function normalizeObservation(observation) {
  if (typeof observation?.observationID !== 'string'
      || !Array.isArray(observation.elements)) {
    throw new TypeError('Expected an observation, not a navigation or action receipt');
  }
  const compact = observation.compact === true;
  const text = value => {
    if (value == null) return null;
    if (compact && typeof value === 'string') return value;
    if (!compact && Array.isArray(value.segments)
        && value.segments.every(segment => typeof segment.text === 'string')) {
      return value.segments.map(segment => segment.text).join('');
    }
    throw new TypeError('Unexpected text shape');
  };
  return {
    observationID: observation.observationID,
    elements: observation.elements.map(row => {
      if (typeof row.elementID !== 'string') throw new TypeError('Missing elementID');
      const name = compact ? row.name : row.accessibleName;
      const compactEvidence = {
        document: observation.document,
        provenance: row.provenance ?? observation.document?.provenance,
        frame_origin: row.frame_origin,
        frame_is_main: row.frame_is_main,
      };
      return {
        observationID: observation.observationID,
        elementID: row.elementID,
        name: text(name),
        nameEvidence: compact ? {...compactEvidence, field: 'name'} : name,
        stateAttributes: Object.fromEntries(Object.entries(row.stateAttributes ?? {})
          .map(([key, value]) => [key, text(value)])),
        stateEvidence: compact
          ? {...compactEvidence, fields: row.stateAttributes}
          : row.stateAttributes,
        fillCapability: row.fillCapability ?? 'unknown',
        sensitive: row.sensitive,
        actionable: row.actionable,
        source: row,
      };
    }),
  };
}
