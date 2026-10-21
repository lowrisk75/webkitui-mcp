#!/bin/sh
set -eu

if [ "$#" -ne 4 ]; then
  printf '%s\n' "usage: $0 CONNECTOR RESOURCE_BUNDLE POLICY_PLIST input|embedded" >&2
  exit 64
fi

connector=$1
resource_bundle=$2
policy=$3
mode=$4
workspace_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

test -x "$connector"
plutil -lint "$policy" "$resource_bundle/Contents/Info.plist" \
  "$resource_bundle/Contents/Resources/en.lproj/Localizable.strings" \
  "$resource_bundle/Contents/Resources/fr.lproj/Localizable.strings" >/dev/null
file "$connector" | grep -q 'arm64'
text_sha=$(otool -s __TEXT __text "$connector" \
  | sed -n '/^[0-9a-f][0-9a-f]* /s/^[^ ]* //p' \
  | shasum -a 256 | awk '{print $1}')
test "$text_sha" = "$(plutil -extract ConnectorTextSHA256 raw "$policy")"

if [ "$mode" = input ]; then
  expected_sha=$(plutil -extract ConnectorInputSHA256 raw "$policy")
  actual_sha=$(shasum -a 256 "$connector" | awk '{print $1}')
  test "$actual_sha" = "$expected_sha"
elif [ "$mode" != embedded ]; then
  printf '%s\n' "invalid verification mode: $mode" >&2
  exit 64
fi

codesign --verify --strict --all-architectures "$connector"
details=$(codesign -dv --verbose=4 "$connector" 2>&1)
test "$(printf '%s\n' "$details" | sed -n 's/^Identifier=//p')" = \
  "$(plutil -extract ConnectorIdentifier raw "$policy")"
printf '%s\n' "$details" | grep -q \
  "TeamIdentifier=$(plutil -extract ExpectedTeamIdentifier raw "$policy")"
printf '%s\n' "$details" | grep -Eq 'flags=.*runtime'

entitlements=$(mktemp /private/tmp/webkitui-siliconpass-entitlements.XXXXXX)
printf 'RESOURCE_CREATED=connector-entitlements:%s\n' "$entitlements" >&2
trap 'rm -f "$entitlements"; printf "RESOURCE_REMOVED=connector-entitlements:%s\n" "$entitlements" >&2' EXIT HUP INT TERM
codesign -d --entitlements :- "$connector" > "$entitlements" 2>/dev/null || true
if test -s "$entitlements" && plutil -lint "$entitlements" >/dev/null 2>&1; then
  for key in \
    com.apple.security.get-task-allow \
    com.apple.security.cs.disable-library-validation \
    com.apple.security.cs.allow-dyld-environment-variables \
    keychain-access-groups \
    com.apple.security.application-groups; do
    if plutil -extract "$key" raw "$entitlements" >/dev/null 2>&1; then
      printf '%s\n' "forbidden SiliconPass connector entitlement: $key" >&2
      exit 1
    fi
  done
fi

python3 "$workspace_dir/scripts/verify-siliconpass-vault-mcp.py" "$connector" \
  --expected-version "$(plutil -extract ConnectorVersion raw "$policy")"
