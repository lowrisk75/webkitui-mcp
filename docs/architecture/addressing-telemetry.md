# Addressing telemetry contract

The model-facing element ID is an observation-scoped lease. It is never a DOM
pointer, coordinate, or durable browser identity.

## Inputs

Each action attempt records:

- observation and locator-recipe IDs;
- observation/action generations;
- monotonic observation/action timestamps;
- final candidate cardinality **after** deterministic recipe filtering;
- semantic, physical-identity, and geometry comparisons;
- `unknown` whenever evidence is missing or cannot be trusted.

## Exclusive classification order

1. Zero final candidates: `address_resolution_failed`.
2. More than one final candidate: `address_now_ambiguous`.
3. One candidate with different semantics: `logical_target_changed`.
4. Same semantics but different physical identity:
   `node_replaced_but_semantic_locator_recovered`.
5. Same semantics and identity but changed geometry:
   `coordinate_invalidated_by_layout_change`.
6. All three comparisons are the same: stable.
7. Any required comparison is unknown: insufficient evidence; no failure
   counter is incremented.

This precedence makes the five counters mutually exclusive. It also means a
semantic recovery is the primary outcome even if the replacement moved. The
raw trace retains geometry evidence for later multi-label analysis.

## Deliberate limits

- `logical_target_changed` is asserted only from deterministic semantic facts.
  A model opinion is not an oracle.
- Context anchors such as a row's invoice ID are required to detect virtualized
  node recycling; role and accessible name alone are insufficient.
- Geometry does not prove event reception. Overlay and hit-testing evidence
  belongs to the WebKit integration tranche.
- Shadow-root/frame access failures can look like zero matches. The integration
  layer must preserve frame/world provenance so those causes remain separable.
- Mutation count and elapsed time measure drift exposure, not semantic change.
