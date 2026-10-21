# Lumen native MCP follow-up — installed 0.6.41 (641)

Date: 2026-10-20. Outcome: requested Reddit publication completed using the official simpler interface.

## Current observations

- Installed app metadata independently reads version 0.6.41 / build 641.
- A new owned session was opened; unrelated sessions were not adopted or changed.
- Modern Reddit feed and composer observation both return the stable code
  privacy_scan_limit_exceeded, now with safe diagnostic:
  privacy_budget.category=roots, limit=64, observedCountAtLeast=65.
- This is an improvement in diagnostic precision, not closure of the modern
  Reddit observation failure.
- Navigating to the official origin https://old.reddit.com produced a usable
  composer with the privacy filter still active. No budget or protection changed.
- Native title and body fill each dispatched once. Their automatic value checks
  were indeterminate on anonymous textareas. Their locator hashes were identical
  despite inspected stable attributes name=title and name=text.
- Scrolling one anonymous textarea by element returned targetNotUnique(18).
  Bounded document scrolling and native screenshots allowed independent visual
  confirmation. No fill was replayed.
- Native submit dispatched once. Fresh permalink navigation independently showed
  the intended title, full body and four expected links. Publication is verified
  in the authenticated owner view, not an independent nonowner moderation check.

## Remaining findings

1. Modern Reddit roots budget prevents semantic inspection. Preserve fail-closed
   behavior while investigating bounded per-root coverage and safe recovery.
2. Anonymous textarea stable name attributes are available to inspect but do not
   produce distinguishable verification locators in this workflow. Please test
   title/body identity separately, including value checks and element scrolling.
3. The previous handoff/resume deadlock was not re-tested on 641; do not mark it
   fixed from this alternative-page success.

## Scope and privacy

No raw protocol export, user identity, post text, URL path/query, session handle,
opaque grant, idempotency key, receipt payload, cookie or credential is included.
The detailed publication receipt stays in the originating project. This note is
a manual sanitized observation summary. No browser restart, installation, build,
source patch, shared process termination, or unrelated mission cleanup occurred.

