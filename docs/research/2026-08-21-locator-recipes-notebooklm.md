# Locator recipes — NotebookLM review (2026-08-21)

Notebook: **WebKITUI MPC** (private notebook ID redacted).

Three queries covered measured field value, blind spots, and deterministic
opportunities. The first formulation was blocked locally as `restricted`; a
shorter English reformulation passed. No blocked content left the Mac.

## Source-reported measurements

- The notebook repeated MFS coverage ablations: WebLinx text 59.5% and `href`
  16.7%; WorkArena text 30.5%, `value` 22.0%, `id` 16.9%, `class` 10.2%.
- It repeated benchmark-specific visibility and coordinate ablations. These
  results motivate retaining facts but do not prove a universal locator order.

## Adopted findings

- Values change as a direct consequence of typing and cannot define identity.
- Framework-generated IDs and duplicated `data-testid` values are not assumed
  unique; final cardinality remains observable.
- Context anchors are necessary for recycled virtual rows.
- Frame access failures and overlay interception need separate WebKit evidence.
- Required versus corroborating status must be explicit and deterministic.

## Rejected or deferred

- Any page mutation does not automatically invalidate a recipe. Re-resolution
  exists specifically to recover across harmless mutations.
- Transaction postconditions and node-level provenance are important but belong
  to their later planned layers, not the locator recipe itself.
- Page strings remain untrusted data; putting them in a recipe does not elevate
  them into instructions or trusted policy.
