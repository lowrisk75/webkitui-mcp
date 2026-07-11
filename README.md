# webkitui-mcp

A local **Model Context Protocol** server that drives a **real Chrome** via
**Playwright/CDP** — a self-contained, reliable replacement for the "Claude in
Chrome" extension for the one thing it can't do: **load an unpacked browser
extension** and reliably inspect its console/network behavior.

It launches Google Chrome (the real browser, via `channel: "chrome"` — not
Playwright's bundled Chromium) with a persistent user-data dir, optionally
side-loading an unpacked MV3 extension, and exposes navigation, interaction,
screenshot, JS evaluation, console-log capture, network-request capture, and
extension-id lookup as MCP tools.

---

## Why this server exists

Claude in Chrome cannot load an unpacked extension (`chrome://extensions` →
"Load unpacked") and has been unreliable for extension-development-loop
testing (frequent disconnects). This server is a **separate, long-lived
process** driving Chrome directly over CDP via Playwright — no extension
dependency, no reconnect flakiness, and full support for the
`--load-extension` launch flag that unpacked-extension testing requires.

**Key constraint:** Chrome refuses to load unpacked extensions in headless
mode, full stop, regardless of channel. `webkitui_launch` enforces this —
`headless: true` + `loadExtensionPath` throws instead of silently loading a
browser without your extension.

---

## Tools

| Tool | Purpose |
|---|---|
| `webkitui_launch` | Launch real Chrome (`launchPersistentContext`) with a persistent profile dir. `loadExtensionPath` side-loads an unpacked extension (forces `headless: false`). Re-launching closes any prior session. |
| `webkitui_navigate` | Navigate the active page to a URL. Clears console/network buffers (so subsequent reads are "since last navigate"). |
| `webkitui_click` | Click the first element matching a Playwright locator string (CSS or `text=`). |
| `webkitui_type` | Fill text into the first matching element. |
| `webkitui_screenshot` | Screenshot the active page — file path or base64. |
| `webkitui_evaluate` | Run a JS expression/IIFE in the page via `page.evaluate`, return the JSON result. |
| `webkitui_console_logs` | Return `console.*`/`pageerror` messages captured since the last navigate. |
| `webkitui_network_requests` | Return network requests (method/status/ok/failure) since the last navigate, optional URL substring filter. |
| `webkitui_extension_id` | Resolve the `chrome-extension://<id>` generated for the side-loaded unpacked extension, via its registered service worker. |
| `webkitui_close` | Close the browser context cleanly. |

---

## Build

```bash
cd ~/GitHub/webkitui-mcp
npm install     # also runs `tsc` via the prepare script
npm run build   # tsc → dist/
```

Requirements: Node 18+, Google Chrome installed at the default macOS location
(`/Applications/Google Chrome.app`). Uses `playwright-core` (no bundled
Chromium download) — Chrome itself is driven via the `chrome` browser
channel.

---

## Register in Claude Code

```bash
claude mcp add webkitui-mcp -s user -- node ~/GitHub/webkitui-mcp/dist/index.js
```

`-s user` registers it globally (available from any project), matching how
this instance was set up. Use `-s local` instead to scope it to one project
only.

...or add directly to `~/.claude.json` (user scope) or a project's `.mcp.json`:

```json
{
  "mcpServers": {
    "webkitui-mcp": {
      "command": "node",
      "args": ["/Users/kevinnadjarian/GitHub/webkitui-mcp/dist/index.js"]
    }
  }
}
```

No one-time TCC/permission grant is needed (unlike `shotkit-mcp` — this
server doesn't screen-capture the desktop, Playwright drives Chrome directly
over CDP).

---

## Example: testing an unpacked MV3 extension end-to-end

```jsonc
// 1. webkitui_launch
{ "loadExtensionPath": "~/GitHub/RGPD/dlp-endpoint/extension" }

// 2. webkitui_extension_id
{}
// → { "extensionId": "abcdefghijklmnopabcdefghijklmnop", "url": "chrome-extension://.../background.js" }

// 3. (separate terminal) install the Native Messaging host for that id — see
//    the "Native Messaging + custom userDataDir" gotcha below before running this:
//    ~/GitHub/RGPD/dlp-endpoint/scripts/install_native_host.sh <extension-id>

// 4. webkitui_navigate
{ "url": "https://chatgpt.com" }

// 5. webkitui_evaluate — confirm interceptor.js patched fetch in the MAIN world
{ "script": "window.fetch.toString()" }

// 6. webkitui_console_logs
{}

// 7. webkitui_network_requests
{ "urlContains": "backend-api" }
```

---

## Native Messaging + custom userDataDir (real gotcha, cost hours to find)

If your extension talks to a Native Messaging host (like `dlp-endpoint`'s
`com.lorislab.dlp`), the **standard per-user manifest locations
(`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`,
`.../Chrome for Testing/...`, `.../Chromium/...`) do not work here** and
Chrome fails completely silently — `chrome.runtime.connectNative()` returns a
port, but `onDisconnect` fires almost immediately with
`chrome.runtime.lastError.message === "Specified native messaging host not
found."`. Nothing is logged to the page console (the DLP extension's own
`background.js` doesn't log `chrome.runtime.lastError` either — worth fixing
there too), so this fails **open** and invisible: secrets go out in cleartext
with zero error anywhere in sight.

**Root cause:** when Chrome/Chromium is launched via
`launchPersistentContext(userDataDir, ...)` with a *custom* `userDataDir`
(which every `webkitui_launch` call does), the Native Messaging host manifest
lookup follows that custom dir instead of the OS-default profile location. The
manifest has to be installed at:

```
<userDataDir>/NativeMessagingHosts/<host-name>.json
```

e.g. for the default profile dir, `~/.webkitui-mcp/chrome-profile/NativeMessagingHosts/com.lorislab.dlp.json`.
Confirmed by directly `worker.evaluate()`-ing `chrome.runtime.connectNative()`
diagnostics against the extension's own service worker — every other
candidate directory (including the literal `/Library/Google/ChromeForTesting/NativeMessagingHosts`
string found via `strings` on the Chrome for Testing binary) left the port
disconnected with "not found"; only the userDataDir-relative path connected.

If you're scripting an install like `dlp-endpoint/scripts/install_native_host.sh`,
either point its `DEST_DIR` at `<userDataDir>/NativeMessagingHosts` when
targeting a webkitui-mcp session, or symlink it there after the standard
install.

---

## Notes & assumptions

- `userDataDir` defaults to `~/.webkitui-mcp/chrome-profile` and persists
  across launches (extension installs, cookies, etc. survive restarts) unless
  you pass a different path or delete it.
- `webkitui_evaluate` passes your `script` string straight to
  `page.evaluate()`. Simple expressions work as-is (`"window.fetch.toString()"`);
  multi-statement scripts need an IIFE wrapper: `"(() => { ...; return x; })()"`.
- Console/network buffers are cleared on every `webkitui_navigate` and capped
  at 2000 entries (oldest dropped first) to avoid unbounded memory growth in
  a long-lived process.
- `webkitui_click` / `webkitui_type` accept any Playwright locator string —
  CSS (`"button.submit"`), text (`"text=Sign in"`), or other built-in engines.
- Only one browser session is tracked at a time; `webkitui_launch` closes any
  existing session first.
- This server does not itself install Native Messaging hosts, build native
  daemons, or manage extension IDs at rest — pair it with the target
  project's own install scripts (e.g. `dlp-endpoint/scripts/install_native_host.sh`).
