# Minimal Failure Set coverage

`MFSBenchmark` evaluates extractive observation reducers against preconstructed
approximate Minimal Failure Sets. An ablation unit is an observation-scoped
element identifier paired with `@tag`, `@text`, or a named attribute.

The canonical metric is binary per instance and follows arXiv:2605.29397:
coverage is the fraction of reductions retaining every MFS unit. The reduction
ratio is the mean per-instance retained character fraction. Unit recall and the
optional token-retention ratio are diagnostics, not substitutes for coverage.

Inputs fail closed on empty MFSs, MFS units outside the source observation,
unknown or duplicate instance IDs, missing reductions, retained foreign units,
and inconsistent size measurements. MFS construction and its non-deterministic
browser/model oracle are deliberately outside this pure deterministic metric.
