# Security policy

## Reporting a vulnerability

Use GitHub private vulnerability reporting for security issues. Do not open a
public issue containing exploit details, session material, private endpoints,
credentials, cookies, tokens, keys, or user data.

Include the affected commit, the smallest reproducible case, expected and
observed behavior, and whether the issue can trigger navigation, disclosure,
or a state-changing action.

## Scope

Security reports should target the current public Swift implementation. The
research notes distinguish measured results from conjecture and do not create
a security guarantee by themselves.

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

## Release checks

Before publishing, scan both Git history and the complete worktree for secrets,
review every changed path, run the relevant Swift and Linux test suites, and
verify the remote visibility and exact commit after push.
