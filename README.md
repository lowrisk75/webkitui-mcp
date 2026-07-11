# webkitui-mcp

A local **Model Context Protocol** server that drives a **real Chrome** via
**Playwright/CDP** — a self-contained, reliable replacement for the "Claude in
Chrome" extension for the one thing it can't do: **load an unpacked browser
extension** and reliably inspect its console/network behavior, including the
extension's own **service worker console** (which Playwright has no public
API for at all — see the CDP section below).

It launches Google Chrome (the real browser, via `channel: "chrome"` — not
Playwright's bundled Chromium, *except* when loading an unpacked extension,
which forces the bundled Chromium — see "Why not always real Chrome?" below)
with a persistent user-data dir, optionally side-loading an unpacked MV3
extension, and exposes multi-tab navigation/interaction, screenshots, JS
evaluation, console/network/worker-console capture, extension-id lookup, and
a raw CDP escape hatch as MCP tools.

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

### Why not always real Chrome?

Google removed the `--load-extension` CLI flag from **branded** Chrome/Edge
builds in Chrome 137 (June 2025), to stop malware from side-loading unpacked
extensions — it's silently ignored there (no error, the extension just never
appears). It still works in Playwright's bundled Chromium ("Chrome for
Testing"), so `webkitui_launch` automatically pins extension loads to that,
regardless of any requested `channel`, and uses real Chrome (`channel:
"chrome"` by default) only when no extension is being loaded.

---

## Tools

| Tool | Purpose |
|---|---|
| `webkitui_launch` | Launch real Chrome (`launchPersistentContext`) with a persistent profile dir. `loadExtensionPath` side-loads an unpacked extension (forces `headless: false`, pins to bundled Chromium). Re-launching closes any prior session. |
| `webkitui_list_tabs` | List open tabs — id, url, title, which is active. |
| `webkitui_new_tab` | Open a tab, make it active, optionally navigate it. |
| `webkitui_switch_tab` | Make a tab active (subsequent tools target it) and bring it to front. |
| `webkitui_close_tab` | Close a tab. Another open tab becomes active if it was. |
| `webkitui_navigate` | Navigate the active tab to a URL. Clears that tab's console/network buffers. |
| `webkitui_click` | Click the first element matching a Playwright locator string (CSS or `text=`) in the active tab. |
| `webkitui_type` | Fill text into the first matching element in the active tab. |
| `webkitui_press_key` | Press a key/chord (e.g. `"Enter"`, `"Control+A"`), optionally focusing a selector first. |
| `webkitui_wait_for` | Block until a selector reaches a state (default `visible`) or the URL matches — use instead of guessing a fixed delay. |
| `webkitui_screenshot` | Screenshot the active tab — file path or base64. |
| `webkitui_get_page_text` | Return the active tab's visible body text — cheaper than a screenshot for content checks. |
| `webkitui_evaluate` | Run a JS expression/IIFE in the active tab via `page.evaluate`, return the JSON result. |
| `webkitui_console_logs` | Return `console.*`/`pageerror` messages captured since the last navigate, for a tab (default: active). |
| `webkitui_network_requests` | Return network requests (method/status/ok/failure/postDataPreview) since the last navigate, optional URL substring filter, for a tab (default: active). |
| `webkitui_worker_console_logs` | Return console output from **service/shared workers** (e.g. an extension's MV3 `background.js`) — see below, this is the capability Playwright has no public API for. |
| `webkitui_extension_id` | Resolve the `chrome-extension://<id>` generated for the side-loaded unpacked extension, via its registered service worker. |
| `webkitui_cdp_send` | Send a raw CDP command against the active tab and return the result — escape hatch for anything not covered above. |
| `webkitui_close` | Close the browser context and all tabs cleanly. |

---

## Service worker console capture (`webkitui_worker_console_logs`)

Playwright's `Worker` class has no `'console'` event — there is no public API
to see what an extension's background script logs. This server fills that
gap with a raw CDP `Target.attachToTarget` session (legacy, non-flat mode;
Playwright's `CDPSession` wrapper can't address flat sub-sessions), set up
automatically at `webkitui_launch` and covering every `service_worker` /
`worker` / `shared_worker` target for the session's lifetime.

**Load-bearing detail, found by hours of empirical elimination:** attaching
with only `Runtime.enable` unreliably misses `console.*` calls made from
*inside* a `chrome.*` extension API event callback (`chrome.runtime
.onMessage`, a native-messaging `Port`'s `onDisconnect`, etc.) — the callback
demonstrably runs (state it sets is observable via a follow-up
`Runtime.evaluate`) but no `Runtime.consoleAPICalled` event arrives, and
`Target.targetCreated`/`targetDestroyed` tracking rules out the target simply
respawning around it. Also sending `Log.enable` on the same session fixes
this — confirmed clean across repeated runs. `Log.entryAdded` is captured
too, as a bonus: Chrome's own internal diagnostics for these events (e.g.
`"Unchecked runtime.lastError: Native host has exited."`) surface there even
in the rare case a developer's own `console.*` call still doesn't fire.

---

## Build

```bash
cd ~/GitHub/webkitui-mcp
npm install     # also runs `tsc` via the prepare script
npm run build   # tsc → dist/
```

Requirements: Node 18+, Google Chrome installed at the default macOS location
(`/Applications/Google Chrome.app`) for non-extension sessions. Uses the full
`playwright` package (not `playwright-core`) so its bundled Chromium ("Chrome
for Testing") downloads on `npm install` — extension loads always use that
build, real Chrome is driven via the `chrome` channel otherwise.

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
//    the "Native Messaging + custom userDataDir" gotcha below, this needs the
//    userDataDir arg or the extension silently can't reach its native host:
//    ~/GitHub/RGPD/dlp-endpoint/scripts/install_native_host.sh <extension-id> ~/.webkitui-mcp/chrome-profile

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
Chrome fails silently by default — `chrome.runtime.connectNative()` returns a
port, but `onDisconnect` fires almost immediately with
`chrome.runtime.lastError.message === "Specified native messaging host not
found."`. If the extension doesn't log `chrome.runtime.lastError` in its
`onDisconnect` handler (an easy thing to skip — nothing about the API forces
it), this fails **open** and invisible: secrets go out in cleartext with zero
error anywhere in sight. Use `webkitui_worker_console_logs` (above) to see it
either way, logged or not — Chrome's own `"Unchecked runtime.lastError"`
diagnostic surfaces there regardless.

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

`dlp-endpoint/scripts/install_native_host.sh` now takes this `userDataDir` as
an optional second argument and installs the manifest to both the standard
location and `<userDataDir>/NativeMessagingHosts` in one call:

```bash
./scripts/install_native_host.sh <extension-id> ~/.webkitui-mcp/chrome-profile
```

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
- `webkitui_click` / `webkitui_type` / `webkitui_press_key` accept any
  Playwright locator string — CSS (`"button.submit"`), text (`"text=Sign
  in"`), or other built-in engines.
- Multiple tabs are tracked (including ones opened by the page itself —
  `target=_blank`, `window.open`, extension popups); everything except
  `webkitui_list_tabs`/`new_tab`/`switch_tab`/`close_tab`/`worker_console_logs`
  operates on the *active* tab. Console/network buffers are per-tab and
  cleared on that tab's `webkitui_navigate`; worker console logs are
  session-wide (workers aren't tied to one tab). All buffers cap at 2000
  entries (oldest dropped first).
- Only one browser session (one `launchPersistentContext`) is tracked at a
  time; `webkitui_launch` closes any existing session first.
- `webkitui_evaluate` times out after 30s by default so a hung script can't
  block the server forever, but the script keeps running in the page after
  that (no true mid-eval cancellation over CDP) — prefer `webkitui_navigate`
  or closing/reopening the tab to recover a wedged one.
- This server does not itself install Native Messaging hosts, build native
  daemons, or manage extension IDs at rest — pair it with the target
  project's own install scripts (e.g. `dlp-endpoint/scripts/install_native_host.sh`).
