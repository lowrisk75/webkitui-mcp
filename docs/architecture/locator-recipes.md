# Locator recipes

Each model-facing element ID is scoped to one observation and maps to a recipe.
The recipe is re-evaluated against fresh browser facts before every action.

## Required identity facts

Recipes can require browser-derived facts such as:

- semantic role;
- accessible name or label;
- stable contextual anchor, such as an invoice identifier in the same row;
- explicitly selected stable attributes;
- frame path.

At least one identity fact is required. Missing required facts fail closed.

## Corroborating facts

Mutable values and structural DOM paths may be recorded only as corroboration.
They cannot define identity because typing, re-rendering, or navigation can
legitimately change them.

Corroboration is observable but never silently breaks a tie. If two candidates
match every required clause, the result remains ambiguous even when one has a
higher corroboration score.

Geometry is intentionally outside this string-fact resolver. It corroborates a
fresh semantic resolution and feeds addressing telemetry, but it never becomes
a coordinate fallback.
