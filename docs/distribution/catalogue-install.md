# WebKitUI MCP connector for Mac

This connector targets the public **0.6.24 Developer Preview**. Requires an Apple silicon Mac running macOS 15 or later. It contains the original signed stdio relay from that release; **the companion app is installed separately**.

## Install

1. Download `WebKitUI-MCP-0.6.24-notarized.zip` and `SHA256SUMS` from the [0.6.24 release](https://github.com/lowrisk75/webkitui-mcp/releases/tag/v0.6.24). Check the archive with `shasum -a 256 -c SHA256SUMS` from your download directory.
2. Extract `WebKitUI MCP.app`, move it to `/Applications`, and open it. Leave it running. Finish active tasks before replacing an older app. The app's setup command uses its actual relay and socket paths.
3. If your MCP client supports MCPB binary extensions, install the WebKitUI MCP `.mcpb` connector. It connects to the app's default local Unix socket. The client must support `${HOME}` and `${__dirname}` substitution. The bundle's `darwin` compatibility flag does not encode architecture or minimum macOS, so check those requirements yourself.
4. Restart the client conversation to refresh the tool catalogue. Open a browser session, navigate to `https://example.com`, approve the native navigation prompt, and inspect the rendered page. Keep the returned session ID for that task.

The MCPB connector is a local distribution candidate until it appears as a downloadable release asset. Download the app directly to use the manual setup today.

## Manual setup without MCPB

The app has a **Copy Codex setup command** control. Prefer that command when the app is installed at a different path. For the default Applications installation, a generic stdio configuration is:

```json
{
  "mcpServers": {
    "webkitui-mcp": {
      "command": "/Applications/WebKitUI MCP.app/Contents/MacOS/webkitui-mcp-relay",
      "args": ["/Users/YOUR_ACCOUNT/Library/Application Support/WebkitUIMCP/mcp.sock"]
    }
  }
}
```

Replace `YOUR_ACCOUNT` with your macOS account's home directory. Use absolute paths; a client may not expand `~`. Do not change an existing client's configuration without preserving its other servers. Check your client's current configuration documentation for the outer JSON shape.

## Sign-in and permissions

WebKitUI maintains its own persistent WebKit profiles. It does not import Safari's cookies or sign-ins. Complete private steps using the app's human handoff. SiliconPass integration is optional and requires a separate compatible installation. Do not put passwords, session cookies or tokens in MCP arguments.

Default native confirmations apply to browser actions. The current checkout may include later features that are absent from the public 0.6.24 app. This connector does not upgrade the companion or enable additional capabilities.

## Troubleshooting

- **App unavailable / socket missing:** open the companion app, then check the socket path shown in its status window. Avoid running a second broker for the same profile.
- **Wrong architecture:** this release supports Apple silicon, not Intel Macs, Windows or Linux.
- **Missing tools:** restart the MCP conversation after registration.
- **A website needs private interaction:** use human handoff; do not retry an uncertain submission.
- **Custom socket:** use the app's actual setup command rather than this default connector.

## Licence

Source available under Business Source License 1.1. Personal noncommercial, qualifying noncommercial organization and evaluation uses are granted as specified in the bundled licence; commercial production use requires a separate agreement. No activation key is required for granted uses. Read `LICENSE` and `LICENSING.md` distributed with the release.
