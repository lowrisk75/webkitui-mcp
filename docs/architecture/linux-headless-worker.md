# Linux headless worker

## Boundary

The Linux worker is a separate execution lane, not a Linux build of `WKWebView`.
It is intended for disposable, unauthenticated, headless work. The native Mac
backend remains the only lane for the user's Safari-adjacent authenticated state,
password-manager handoff, MFA, CAPTCHA, and visible human control.

```text
LLM client on Proxmox
        |
        | forced-command SSH, pinned host key
        v
dedicated non-root VM
        |
        +-- one newline JSON-RPC process per connection
        +-- one host-wide controller lease
        +-- ephemeral Playwright context
        +-- authenticated loopback pinning proxy
        +-- Chromium or patched WebKit, headless
```

There is no listening MCP port. The SSH key has one forced command, no PTY,
forwarding, agent forwarding, X11 forwarding, or user command authority.

## Routing policy

| Need | Backend |
|---|---|
| Public, disposable, unauthenticated reading | Linux headless |
| Repeatable cross-engine comparison | Linux Chromium plus WebKit |
| Existing authenticated session | Native Mac WebKit |
| Password, MFA, CAPTCHA, consent, visual handoff | Native Mac WebKit |
| Transactional write | Native Mac by default; Linux only after explicit operator opt-in |

## Deliberate non-claims

- Playwright WebKit on Linux is not Safari and proves no Safari compatibility.
- A VM reduces blast radius; it does not make hostile websites safe.
- A receipt records local evidence, not an exactly-once remote commit.
- An empty cross-origin allowlist is secure-by-default, not universal compatibility.
- Local tests do not prove the Proxmox deployment, which has separate evidence.

## Deployment gates

1. Dedicated VM and non-root runtime user.
2. Official runtime archive verified against its published checksum.
3. SSH host key verified through the guest agent and pinned separately.
4. Forced command restricted to the hypervisor management address.
5. Read-only default and host-wide controller lease.
6. Both browser engines pass the integration suite inside the VM.
7. Private-address denial, controller exclusion, and shell denial pass over SSH.
8. Clients discover `webkitui-linux` only after a fresh session restart.
