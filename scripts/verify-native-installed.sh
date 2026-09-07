#!/bin/zsh
set -euo pipefail

project_root=${0:A:h:h}
expected_version=$(plutil -extract CFBundleShortVersionString raw \
  "$project_root/Support/AquaApp/Info.plist")
installed_app="$HOME/Applications/WebKitUI MCP.app"
if [[ ! -d "$installed_app" ]]; then
  installed_app="$HOME/Applications/WebkitUIMCP Aqua.app"
fi
installed_app_confirm="$installed_app/Contents/MacOS/webkitui-mcp-confirm"
installed_cli="$HOME/.local/bin/webkitui-mcp"
installed_cli_confirm="$HOME/.local/bin/webkitui-mcp-confirm"
installed_relay="$HOME/.local/bin/webkitui-mcp-relay"
broker_socket="$HOME/Library/Application Support/WebkitUIMCP/mcp.sock"

cd "$project_root"

git diff --check
xcrun swift-format lint --strict --recursive Sources Tests Package.swift

# The installed broker intentionally owns the exclusive host lease. Its
# dedicated test is skipped here and the live two-client check below verifies
# the production ownership path instead.
# Explicitly serialize Swift Testing. WKWebView test processes are reliable in
# isolation but can return noDocument when several suites create WebContent
# processes concurrently on a loaded developer Mac.
# A Swift Testing bundle that exits mid-run — a nested event loop stopped the main
# run loop, and the async entry point calls exit(0) when that returns — prints no
# summary and returns success. `swift test` passed that straight through, so this
# gate said "verified" over a bundle that had run a hundred tests out of 141 and a
# failure that never got the chance to show (2026-09-07). Every bundle has to
# account for itself: one summary line each, none of them a failure.
run_tests() {
  local log
  log=$(mktemp "${TMPDIR:-/tmp}/webkitui-swift-test.XXXXXX")
  swift test "$@" 2>&1 | tee "$log"
  # XCTest bundles report through swift test's own exit status; the summary line
  # exists only for Swift Testing, so count the targets that use it.
  local bundles summaries
  bundles=$(grep -rl '^import Testing' Tests --include='*.swift' | cut -d/ -f2 | sort -u | wc -l | tr -d ' ')
  summaries=$(grep -c 'Test run with' "$log" || true)
  if [[ "$summaries" != "$bundles" ]]; then
    print -u2 "swift test $*: $summaries of $bundles test bundles reported a summary"
    rm -f "$log"
    exit 1
  fi
  if grep -q 'Test run with .* failed' "$log"; then
    print -u2 "swift test $*: a test bundle reported failures"
    rm -f "$log"
    exit 1
  fi
  rm -f "$log"
}
run_tests -c debug --no-parallel --skip hostExclusiveSession
run_tests -c release --no-parallel --skip hostExclusiveSession

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
