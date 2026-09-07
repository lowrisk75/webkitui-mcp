# Resuming a preview release

`scripts/release-loop.sh` tracks evidence for the version in
`Support/AquaApp/Info.plist`. It does not run provider actions and does not grant
permission to sign, install, upload, publish or send promotional messages.

Initialize once with the actual approved destinations:

```sh
scripts/release-loop.sh init \
  --github-repository lowrisk75/webkitui-mcp \
  --website-url https://lorislab.fr/developers/webkitui-mcp/
scripts/release-loop.sh status
scripts/release-loop.sh next
```

State lives in the ignored `audit-output/release-<version>-loop/` directory.
Historical `v6-release-loop.sh` receipts cannot be imported as current evidence.
Keep this state and its referenced proof files together across resumptions.
Temporary files may disappear after a restart: copy evidence into the private
journal before recording it.

## Evidence order

1. Current source audit, corrected blocking source findings, licence review.
2. Complete Debug and Release test bundles, verified unsigned package.
3. Physical Escape, Return and keyboard checks, including `none` mode.
4. Clean source commit; no commit of the Escape change before physical acceptance.
5. Exact signed artifact, signatures, helper launch and provenance.
6. Apple notarization acceptance for that signed input, staple and Gatekeeper.
7. Installed bytes, two clients, physical keyboard check and retained rollback.
8. Prepublication review of the exact candidate and its claims.
9. Public source/tag and actual downloaded release bytes verified.
10. Exact public website file manifest, links and commercial offer verified.
11. Final review of the public result.
12. Current Reddit rules, disclosed affiliation, live links and delivered draft.

A pending physical, provider or publication check is not a source-code defect,
but it still blocks the dependent release steps. Never replace it with a unit
test or a simulated event. `source_review` concerns the source findings; it is
not a GO verdict for publication.

## Recording a gate

Create a redacted JSON receipt and use:

```sh
scripts/release-loop.sh record source_review /absolute/private/receipt.json
```

Every receipt requires `schema_version: 1`, the exact `gate`, `result: "PASS"`,
the current `source_anchor` from `status`, `completed_at`, a concise `summary`,
and `evidence_class: "CURRENT-OBSERVED"`. Physical gates may instead use
`"HUMAN-ATTESTED"`. `proofs` is a nonempty list of absolute regular file paths
and their SHA-256 values: `{"path": "/absolute/file", "sha256": "..."}`.
All completion fields listed for that gate in `scripts/release_loop.py` must be
true and supported by those proofs.

Artifact gates require exact file-backed hashes. Notarization names its signed
input and Apple request ID. Public release requires the frozen commit, configured
release URL, HTTP status, `download_path`, `download_sha256`, `download_bytes`,
and a matching proof of the actual downloaded file. Website publication binds
the configured URL and a file-backed `manifest_sha256`; the manifest must contain
independently fetched public hashes, not just intended deployment hashes.

The controller checks consistency, not the truth of arbitrary statements in a
receipt. The operator must inspect actual test output, human observations and
provider responses. It does not contact providers itself. Never include keys,
cookies, credentials, private review messages or raw process environments.

Changed source files, changed proof bytes, invalid receipt conditions or a
changed frozen commit mark that gate and its dependents stale. Re-record from
the first stale gate; previous receipts remain in history. `complete: true`
requires every gate through draft delivery. It never means Reddit was posted.

Verification of the controller and release guards is hermetic:

```sh
python3 -B scripts/test_release_loop.py
python3 -B scripts/test-release-gates.py
```

For a space-constrained local candidate, packaging accepts an explicit existing
Swift scratch directory as its second argument. It still calls `swift build`
and compares provenance before and after; the default is a fresh isolated build.
Record which mode was used and do not label a cached build as an independent
clean-build reproduction:

```sh
scripts/package-preview.sh /absolute/output /absolute/repository/.build
scripts/verify-package-preview.sh /absolute/output
```
