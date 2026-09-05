#!/bin/zsh
set -euo pipefail

project_root=${0:A:h:h}
expected_version=$(plutil -extract CFBundleShortVersionString raw \
  "$project_root/Support/AquaApp/Info.plist")
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

# The installed binaries must be the ones this source builds. `swift build
# --show-bin-path` prints a path without building, so an install script that asks for
# the path and copies what it finds can ship the previous build and pass every other
# check — which is exactly what happened, twice, while a real page kept failing on a
# defect that had already been fixed.
swift build -c release --arch arm64 >/dev/null
release_bin=$(swift build -c release --arch arm64 --show-bin-path)
for tool in webkitui-mcp webkitui-mcp-confirm webkitui-mcp-relay; do
  installed_path="$HOME/.local/bin/$tool"
  [[ -x "$installed_path" ]] || { print -u2 "missing installed $tool"; exit 1; }
  # Signing rewrites the code directory, so compare the machine code itself, which it
  # leaves untouched.
  built_text=$(otool -s __TEXT __text "$release_bin/$tool" | tail -n +3 | shasum -a 256 | cut -d' ' -f1)
  installed_text=$(otool -s __TEXT __text "$installed_path" | tail -n +3 | shasum -a 256 | cut -d' ' -f1)
  if [[ "$built_text" != "$installed_text" ]]; then
    print -u2 "installed $tool is not built from this source"
    print -u2 "  built:     $built_text"
    print -u2 "  installed: $installed_text"
    exit 1
  fi
done

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

# The lease must be free when the verifier leaves. It used to stay taken until it timed
# out, so every delivery handed the next client a locked host — including the client
# about to test what was just installed.
lock="$HOME/Library/Caches/com.lorislab.webkitui-mcp/controller.lock"
released=0
for _ in {1..40}; do
  if [[ ! -f "$lock" ]] || ! lsof "$lock" >/dev/null 2>&1; then released=1; break; fi
  sleep 1
done
if (( ! released )); then
  print -u2 "host lease still held after verification"
  exit 1
fi

echo "WebKitUI MCP $expected_version source, installation, two-client transport, and host release verified."
