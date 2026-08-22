# Provenance and capabilities

Every string exposed as page or tool content is represented as
`ProvenancedText`, a sequence of independently labelled segments. Concatenation
preserves segment boundaries and the union of source classes. Transformations
operate per segment, use typed steps, and expose history truncation. Sources are
encoded in canonical order; `canonicalJSONData()` also sorts object keys so
identical observations produce stable bytes.

Provenance is evidence, not authority. `CapabilityAuthority` is the independent
runtime gate. It issues unguessable handles whose grants are scoped by action,
exact structured security origin, accepted input provenance, and expiry. Merely
serializing or discovering a handle or origin never creates a grant.

At the native action boundary the adapter must re-resolve the locator and
re-check its live frame and security origin. The current core cannot prove that
invariant without a live `WKWebView`; it therefore does not cache an authorization
decision for later reuse.
