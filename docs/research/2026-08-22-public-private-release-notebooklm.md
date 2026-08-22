# Public/private release counter-audit — 2026-08-22

## Scope

Publish reviewable WebkitUIMCP code without publishing live infrastructure,
browser state, credentials, or secret-bearing artifacts. Maintain a separate
private operations repository which itself contains no secret values.

## Measured locally

- The existing GitHub repository was public and its latest remote commit did
  not contain the current Mac relay, credential boundary, or Linux worker work.
- No private Git remote was configured before this release slice.
- Gitleaks 8.30.1 reported zero findings in both the existing Git history and
  the complete current worktree before staging.
- The deployment templates use placeholders. No private key, storage-state
  file, HAR, Playwright trace, environment file, or known-hosts file was found
  among the publishable source paths.

## NotebookLM synthesis requiring independent checks

The primary notebook highlighted browser profiles, test recordings, commit
history, permissive authentication defaults, raw CDP ports, disabled browser
sandboxes, floating dependencies, and telemetry captures as common leak paths.
These are useful audit categories, not measurements of this repository.

The opportunity notebook proposed credential brokering, outbound-payload
accounting, checkpoint/delta delivery, and sealed confirmation state as
differentiators. Its numerical memory, token, and latency claims had no returned
citations and are treated as conjectural. Sealing session state into client-held
tokens was not adopted because this implementation intentionally keeps a single
host-owned controller and does not need horizontally stateless browser sessions.

## Missed opportunity adopted

The project now documents its public/private type boundary and public security
invariants. The measurable differentiator remains failure telemetry and verified
postconditions, not a claim that repository visibility alone provides safety.
