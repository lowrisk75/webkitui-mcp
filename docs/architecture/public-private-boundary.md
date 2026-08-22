# Public and private boundary

WebkitUIMCP uses two repositories with different trust purposes. Repository
visibility is not a secret-management mechanism.

## Public repository

The public repository contains code that must be independently reviewable:

- native Mac and isolated Linux runtimes;
- protocol, addressing, provenance, transaction, and network-policy tests;
- cited research and measured benchmark outputs;
- deployment templates with inert placeholders and fail-closed defaults;
- public security policy and architectural limitations.

It must not contain live hostnames or addresses, usernames tied to an operator,
host-key fingerprints, `authorized_keys` entries, MCP client configuration,
browser profiles, cookies, storage state, traces, screenshots, logs, tokens,
private keys, or deployment backups.

## Private operations repository

The private repository contains the minimum non-secret operational metadata
needed to reproduce and audit the current installation:

- inventory identifiers and private network topology;
- installed component versions and configuration destinations;
- sanitized runbooks, validation results, and recovery steps;
- references to secret locations, never secret values.

Private Git still must not contain key material, passwords, session state,
cookies, tokens, raw browser captures, or complete environment dumps. Those stay
in the OS keychain, root-owned files on the relevant host, or another dedicated
secret store.

## Publication gate

1. Review the complete staged path list; never use an unreviewed `git add -A`.
2. Scan current files and Git history with a secret scanner in redaction mode.
3. Reject generated browser state and recordings even when the scanner is green.
4. Require pinned dependency locks and preserve browser sandbox defaults.
5. Push a branch, inspect the remote diff, and merge only after the public view is clean.
6. Verify repository visibility through GitHub after every creation or visibility change.

Operational values can move from public to private, but a secret exposed in a
public commit must be revoked; deleting the latest file is not remediation.
