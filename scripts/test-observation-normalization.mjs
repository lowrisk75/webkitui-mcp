import assert from 'node:assert/strict';
import {normalizeObservation} from '../docs/examples/normalize-observation.mjs';

const segment = text => ({segments: [{text, sources: [{classification: 'FIRST_PARTY_SITE_CONTENT'}]}]});
const document = {provenance: ['FIRST_PARTY_SITE_CONTENT']};
const fullRow = {
  elementID: 'e1', accessibleName: segment('Duo'),
  stateAttributes: {'aria-expanded': segment('true')}, fillCapability: 'unsupported',
  sensitive: false, actionable: true,
};
const compactRow = {
  elementID: 'e9', name: 'Duo', stateAttributes: {'aria-expanded': 'true'},
  fillCapability: 'unsupported', sensitive: false, actionable: true,
};
const full = normalizeObservation({observationID: 'fresh-full', elements: [fullRow]});
const compact = normalizeObservation({observationID: 'fresh-compact', compact: true, document, elements: [compactRow]});
assert.equal(full.elements[0].name, compact.elements[0].name);
assert.deepEqual(full.elements[0].stateAttributes, compact.elements[0].stateAttributes);
assert.equal(full.elements[0].nameEvidence, fullRow.accessibleName);
assert.equal(compact.elements[0].nameEvidence.document, document);
const embedded = normalizeObservation({observationID: 'embedded', compact: true, document, elements: [{
  ...compactRow, frame_origin: 'https://frame.fixture.invalid', frame_is_main: false,
  provenance: ['THIRD_PARTY_EMBED'],
}]}).elements[0];
assert.deepEqual(embedded.nameEvidence.provenance, ['THIRD_PARTY_EMBED']);
assert.deepEqual(embedded.stateEvidence.provenance, ['THIRD_PARTY_EMBED']);
assert.equal(embedded.nameEvidence.frame_origin, 'https://frame.fixture.invalid');
assert.equal(full.elements[0].stateEvidence, fullRow.stateAttributes);
assert.equal(full.elements[0].source, fullRow);
assert.equal(compact.elements[0].observationID, 'fresh-compact');
assert.equal(compact.elements[0].elementID, 'e9');
assert.notEqual(full.elements[0].observationID, compact.elements[0].observationID);
assert.equal(normalizeObservation({observationID: 'filtered', compact: true, elements: [{elementID: 'e2'}]}).elements[0].name, null);
assert.equal(normalizeObservation({observationID: 'old-format', elements: [{elementID: 'e3'}]}).elements[0].fillCapability, 'unknown');
assert.throws(() => normalizeObservation({ready: true}), TypeError);
assert.throws(() => normalizeObservation({observationID: 'invalid', elements: [{}]}), TypeError);
assert.throws(() => normalizeObservation({observationID: 'invalid', compact: true, elements: [{elementID: 'e1', name: segment('wrong shape')}]}), TypeError);
console.log('PASS compact/full normalization, evidence retained, fresh IDs, malformed receipts refused');
