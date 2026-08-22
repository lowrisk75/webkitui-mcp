# WebkitUIMCP Linux worker

This is a separate, ephemeral headless backend for Linux automation hosts. It
does not share the native Mac profile and it is not Safari: the available
engines are Playwright Chromium and Playwright's patched WebKit build.

## Security contract

- Six bounded MCP tools; no raw JavaScript, CDP port, shell, or persistent profile.
- Chromium's process sandbox is explicitly enabled; the worker refuses root deployment.
- Read-only by default. Transactional click/fill is an explicit opt-in.
- Every navigation and action requires exact MCP multi-round confirmation.
- Public HTTP(S) only. DNS answers are validated and the chosen address is pinned.
- Cross-origin subresources are denied unless the operator lists their bare origins.
- Service workers, WebSockets, downloads, password filling, and newline fill are denied.
- One host-wide controller lease can cover every SSH process.
- Observation symbols are ephemeral; actions re-resolve a semantic locator recipe.
- Receipts never claim exactly-once delivery and indeterminate actions are not replayed.

Use a dedicated non-root VM for untrusted websites. Do not expose this process as
a TCP service; its interface is newline-delimited JSON-RPC on stdin/stdout.

## Build and test

Node 22 or newer is required.

```bash
npm ci --ignore-scripts
npx playwright install --with-deps chromium webkit
npm run build
WEBKITUI_RUN_BROWSER_TESTS=1 npm test
```

Run read-only with a host-wide lease:

```bash
WEBKITUI_LINUX_CONTROLLER_LOCK=/var/lib/webkitui-mcp/controller.lock \
  node dist/src/index.js
```

Environment variables:

- `WEBKITUI_LINUX_ENGINE`: `chromium` (default) or `webkit`.
- `WEBKITUI_LINUX_CONTROLLER_LOCK`: absolute lease-directory path.
- `WEBKITUI_LINUX_SUBRESOURCE_ORIGINS`: comma-separated exact bare origins.
- `WEBKITUI_LINUX_WRITE_MODE=transactional`: opt into confirmed click/fill.
- `WEBKITUI_LINUX_EXECUTABLE_PATH`: optional operator-selected browser binary.

The default empty subresource list is deliberately strict and will break many
multi-origin sites. Add only origins observed and approved for the task.
