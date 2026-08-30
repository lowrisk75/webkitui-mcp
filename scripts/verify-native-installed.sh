#!/bin/zsh
set -euo pipefail

project_root=${0:A:h:h}
expected_version=0.6.0
installed_app="/Users/kevinnadjarian/Applications/WebKitUI MCP.app"
if [[ ! -d "$installed_app" ]]; then
  installed_app="/Users/kevinnadjarian/Applications/WebkitUIMCP Aqua.app"
fi
installed_app_confirm="$installed_app/Contents/MacOS/webkitui-mcp-confirm"
installed_cli="/Users/kevinnadjarian/.local/bin/webkitui-mcp"
installed_cli_confirm="/Users/kevinnadjarian/.local/bin/webkitui-mcp-confirm"
installed_relay="/Users/kevinnadjarian/.local/bin/webkitui-mcp-relay"
broker_socket="/Users/kevinnadjarian/Library/Application Support/WebkitUIMCP/mcp.sock"

cd "$project_root"

git diff --check
xcrun swift-format lint --strict --recursive Sources Tests Package.swift

# The installed broker intentionally owns the exclusive host lease. Its
# dedicated test is skipped here and the live two-client check below verifies
# the production ownership path instead.
# Explicitly serialize Swift Testing. WKWebView test processes are reliable in
# isolation but can return noDocument when several suites create WebContent
# processes concurrently on a loaded developer Mac.
swift test -c debug --no-parallel --skip hostExclusiveSession
swift test -c release --no-parallel --skip hostExclusiveSession

test -x "$installed_app/Contents/MacOS/webkitui-mcp-aqua-broker"
test -x "$installed_app_confirm"
test -x "$installed_cli"
test -x "$installed_cli_confirm"
test -x "$installed_relay"
test -S "$broker_socket"

installed_version=$(plutil -extract CFBundleShortVersionString raw "$installed_app/Contents/Info.plist")
test "$installed_version" = "$expected_version"
codesign --verify --deep --strict --verbose=2 "$installed_app"

node scripts/verify-installed-native.mjs "$broker_socket" "$expected_version"
shasum -a 256 \
  "$installed_app/Contents/MacOS/webkitui-mcp-aqua-broker" \
  "$installed_app_confirm" \
  "$installed_cli" \
  "$installed_cli_confirm" \
  "$installed_relay"

echo "WebKitUI MCP $expected_version source, installation, and two-client transport verified."
