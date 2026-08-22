# Checkpoint and delta history

`ObservationHistory` owns one canonical checkpoint and a bounded sequence of
atomic deltas. State entries are keyed by frame, observation-scoped element ID,
and field. Values retain `ProvenancedText`.

Each delta binds consecutive generations, the complete base-state SHA-256, the
expected digest of every replaced or removed value, and the complete result
digest. Reconstruction stops on the first mismatch. Application never mutates
the supplied base state.

The configured depth is a hard bound. The next append becomes a fresh checkpoint
when the bound is reached, when the caller declares a semantic boundary, or when
document identity/security origin changes. Hashes protect stored history; live
actionability still requires fresh locator resolution and origin validation.
