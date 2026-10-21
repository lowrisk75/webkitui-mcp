#!/bin/sh
set -eu
workspace_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# This standalone swiftc probe needs an isolated executable, not SwiftPM output.
probe_dir=/Volumes/DeveloperStorage/BuildScratch/Auto/webkitui-mcp/native-controls-probe
mkdir -p "$(dirname "$probe_dir")"
mkdir "$probe_dir" || { echo "Probe directory already exists; refusing to touch an unowned resource" >&2; exit 1; }
printf 'RESOURCE_CREATED=native-controls-probe:%s\n' "$probe_dir"
trap 'rm -f "$probe_dir/probe"; rmdir "$probe_dir"; printf "RESOURCE_REMOVED=native-controls-probe:%s\n" "$probe_dir"' EXIT HUP INT TERM
cd "$workspace_dir"
swiftc -parse-as-library Sources/WebKitUIMCPRuntime/NativeBrowserControls.swift \
  scripts/native-browser-controls-probe.swift -o "$probe_dir/probe" \
  -framework AppKit -framework WebKit
for branch in cancel revoke parent-close; do
  perl -e 'alarm 15; exec @ARGV or die $!' "$probe_dir/probe" "$branch"
done
