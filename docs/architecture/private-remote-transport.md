# Private remote transport

The browser and its authenticated WebKit data store stay on the Mac. A remote
agent transports MCP bytes to that Mac; it never receives browser-profile files,
cookies, passwords, or a general shell.

## Provider-neutral target

Run WebKit in the logged-in Aqua session through a per-user `LaunchAgent`.
The agent owns a mode `0600` Unix socket and starts
`webkitui-mcp-aqua-broker` with launchd socket activation. SSH only carries
stdio to `webkitui-mcp-relay`; it never launches WebKit itself.

Use a dedicated key whose `authorized_keys` entry is restricted to the relay:

```text
from="<LINUX_SOURCE_IP>",restrict,command="/Users/<MAC_USER>/.local/bin/webkitui-mcp-relay '/Users/<MAC_USER>/Library/Application Support/WebkitUIMCP/mcp.sock'" ssh-ed25519 <DEDICATED_PUBLIC_KEY>
```

On Linux, pin the Mac host key in a dedicated known-hosts file and use an SSH
host stanza equivalent to:

```sshconfig
Host webkitui-mac
  HostName <MAC_PRIVATE_NAME_OR_IP>
  User <MAC_USER>
  IdentityFile ~/.ssh/webkitui_mcp
  IdentitiesOnly yes
  StrictHostKeyChecking yes
  UserKnownHostsFile ~/.ssh/known_hosts_webkitui
  ClearAllForwardings yes
  RequestTTY no
  ControlMaster no
  ServerAliveInterval 15
  ServerAliveCountMax 2
```

The remote MCP command is then `ssh -T` with the pinned options above. Verify
the host-key fingerprint from the Mac itself before accepting it;
`ssh-keyscan` alone does not establish trust. The checked-in LaunchAgent
template is in `Support/LaunchAgents/` and deliberately contains placeholders.

Tailscale SSH is not assumed here: its SSH server is unavailable in the normal
macOS GUI variant. Ordinary OpenSSH over a private routed address remains
encrypted, but its reachability policy is independent of the tailnet ACL.

## Host ownership

The broker creates one MCP server per socket connection. The production runtime
takes a non-blocking advisory lock before opening WebKit, so only one connection
can control a browser session for the macOS account.
A second process remains discoverable but its session-open call fails closed.
The OS releases the lease if the owner exits or crashes.

This is intentionally a control lock, not session migration. A handle belongs
to the server process that created it and cannot be resumed in another process.

## Measured deployment state

The private path was exercised end to end on 2026-08-22:

1. Remote `open → status → close` succeeded through SSH, relay, Unix socket,
   Aqua broker, and `WKWebView` on the Mac.
2. The handoff window was captured on screen with a title, nonblank placeholder,
   regular activation policy, and application icon; accepted resume hid it.
3. Host-key pinning, forced command, source-IP restriction, no PTY, and no
   forwarding were observed on the two actual hosts.
4. An abrupt SSH cut released controller ownership; a new connection opened on
   its first attempt after 664 ms. No action was replayed.
5. Ten cold discovery connections measured 369–4,213 ms (median 958 ms); five
   cold session opens measured 713–1,159 ms (median 1,053 ms). These numbers
   include SSH startup on a busy development machine and are not steady-state
   action latency.

Still open: disconnect during an indeterminate real website write, authenticated
task success, and steady-state observe/action latency. Existing Codex or Claude
conversations must be restarted to load a newly installed MCP catalog.

OpenAI Secure MCP Tunnel is a separate optional transport for supported OpenAI
products. It is outbound-only, but requires external Platform configuration and
credentials and does not replace the provider-neutral Claude/SSH path.
