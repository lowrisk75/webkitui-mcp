# Security policy

WebkitUIMCP controls browsers and can mediate authenticated sessions. Treat a
security defect as potentially capable of crossing a credential, browser, or
network boundary.

## Reporting

Do not open a public issue for a suspected vulnerability. Use GitHub's private
vulnerability reporting for this repository. Include the affected revision,
the smallest reproduction, the authority gained, and whether credentials or
private network access were exposed.

## Supported code

Only the latest revision of the default branch is supported. Research notes,
benchmarks, prior-art TypeScript files, and deployment templates are evidence or
examples; they are not separately supported releases.

## Security invariants

- No raw JavaScript, CDP port, general shell, or silent capability escalation.
- No password, cookie jar, browser profile, SSH key, or live deployment state in Git.
- Navigation and writes fail closed without exact confirmation and fresh resolution.
- Indeterminate writes are never automatically replayed.
- Linux browsers run non-root in a dedicated VM; Chromium sandboxing is explicit.
- Public templates contain placeholders and secure defaults, never working credentials.
- Activity logging accepts only allowlisted method/tool identifiers, outcome,
  timestamp, duration and bounded error type. It has no API for parameters,
  URLs, page content, credentials, cookies, keystrokes or response bodies.
- Activity files and their directory are owner-only, symlink/hard-link unsafe
  paths fail closed, rotation is bounded, and clearing activity never removes
  authenticated transaction receipts.

## Release checks

Before publishing, scan both Git history and the complete worktree for secrets,
review every changed path, run the relevant Swift and Linux test suites, and
verify the remote visibility and exact commit after push.

The supported update channel, rollback limits, evidence retention and incident
ownership are defined in
[`docs/release-maintenance-policy.md`](docs/release-maintenance-policy.md).
The native runtime's intentionally bounded network claim is defined in
[`docs/network-boundary.md`](docs/network-boundary.md).
