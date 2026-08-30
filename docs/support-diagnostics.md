# Secret-free support diagnostics

Date: 2026-08-29  
Contract version: 1

`webkitui-mcp doctor` is the only supported machine-generated diagnostic for
the Developer Preview. It is local and read-only: it opens no website, reads no
browser data or credential, performs no license network request and writes no
support bundle.

## Allowed output

- overall readiness enum and boolean;
- CPU architecture and macOS version;
- whether the native confirmation helper is executable;
- the symbolic expected helper placement, never its absolute path;
- whether macOS currently offers `deviceOwnerAuthentication` and the public
  LocalAuthentication error code when unavailable;
- the biometric hardware class reported by macOS, without biometric data;
- a generic, system-managed fallback description and a local recovery action;
- commercial license state enum only, never the token, key, organization,
  machine identifier or server response;
- explicit booleans confirming that browser data, credentials and network were
  not accessed.

## Forbidden output

Diagnostics must never contain usernames, home paths, environment variables,
process arguments from other processes, URLs beyond a canonical origin,
queries, page text, screenshots, cookies, storage, profile contents, ledger
contents, idempotency keys, ReceiptV1 payloads, license keys/tokens, Keychain
items, credential metadata, network inventory, host identifiers or raw errors.

Support must ask the user to run `webkitui-mcp doctor` and paste only that JSON.
It must not ask for an environment dump, browser profile, Keychain export,
receipt directory or screen recording as a default troubleshooting step.

## Failure behavior

Every failed check returns one bounded `requiredAction`. The action may tell the
user where a component belongs or to retry from an unlocked interactive Mac;
it may not authenticate, install, delete, retry a write or change external
state. Unrecognized internal errors collapse to a stable enum.

The current CLI implementation follows this allowlist. A future graphical
diagnostic must consume the same model and receive a separate accessibility and
physical-Mac review before replacing the CLI contract.
