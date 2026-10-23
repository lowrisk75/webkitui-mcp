# Site report

A person who watches the agent fail on a site can send LorisLabs what a collector
fix needs without sending the site. The Status window's **Report this site…**
button produces files, shows them, and opens a Mail draft; nothing else.

## Shape, not content

`WebKitRuntime.domShape(aroundLabel:)` finds every rendered element whose
collapsed text equals a label the person typed and reports, for it and up to six
ancestors: tag, `role`, whether `href`, `tabindex` or `onclick` are present,
computed cursor and display, `aria-hidden`, shadow-root membership, allowlisted attribute
*names* (sorted, at most 20). Custom tag names become `custom`; roles and style
categories use fixed vocabularies. CSS class values are never exported
(`classTokens` remains an empty array for compatibility). Hidden and sensitive
matches are excluded. Collection uses bounded TreeWalker traversal (20,000
elements, 512 roots), after completing the global privacy inventory; exhaustion
refuses the report. Ancestor chains deeper than 256 also refuse instead of
claiming zero matches. Each artifact is limited to 65,536 bytes before writing. Attribute values, text other than the typed label, URLs and field
values are never read. At most five matches are described; the count is exact.

Load counters come from `loadDiagnostics()`, which already carries no console or
request data.

## Envelope

`WebKitUIMCPSiteReport` writes the LorisReports `ReportEnvelope` schema-2 JSON
key for key (`SiteReportBundleTests.matchesLorisReportsContract`), so the same
support tooling reads it. Structured context is limited to the three fixed
fields the schema admits (`component`, `operation`, `error_code`) with bounded
token values; everything else travels as `system_diagnostics` artifacts named
in the envelope with size and SHA-256.

## Why LorisReports is not a dependency

`LorisLabsKit/Package.swift` depends on the private `LorisFoundation` package.
WebKitUI MCP is source-available: anyone building it from the public repository
must be able to resolve every dependency, and the provenance manifest lists no
external packages. The target therefore reproduces the JSON contract and pins
it with a test instead of importing the package. If LorisReports ever ships
without the private dependency, the target can be replaced by the real one
without changing the files that reach support. Recorded 2026-10-22; the SDK
catalogue entry for LorisReports still lists no consumer.

## Delivery

The bundle is written under
`~/Library/Application Support/WebkitUIMCP/SiteReports/<report id>/` with
owner-only permissions, then handed to `NSSharingService(.composeEmail)` with
`support@lorislab.fr` as recipient and the envelope as the body. The broker
keeps no sending path: the mail client the person already uses sends it, from
their address, when they choose. When no mail client can take the files, the
folder is revealed instead.

Origins must be bare (`scheme://host[:port]`); a report is refused rather than
trimmed when anything else is given, because a trimmed path was a path.

## SDK discovery revalidated 2026-10-23

Catalogue: `LorisFoundation/docs/SDK-CATALOG.json`,
LorisReports `source-observed`. Live LabsKit revision `728b674`, macOS 14 minimum;
`LorisReports` target itself has no target dependencies, but the package manifest
resolves LorisFoundation 0.2.x. Preserve the existing dependency-free schema adapter
for this public source checkout. No SDK owner or catalogue was changed. No new
shared mechanism or dependency is introduced by this hardening.
