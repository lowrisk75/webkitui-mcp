#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  printf '%s\n' "usage: $0 /path/to/WebKitUI\\ MCP.app EXPECTED_TEAM_ID" >&2
  exit 64
fi

app=$1
expected_team=$2
scratch_dir=$(mktemp -d /private/tmp/webkitui-pre-notary-verify.XXXXXX)
trap 'rm -rf "$scratch_dir"' EXIT HUP INT TERM
version=0.6.0
build=600
broker="$app/Contents/MacOS/webkitui-mcp-aqua-broker"
helper="$app/Contents/MacOS/webkitui-mcp-confirm"
embedded_relay="$app/Contents/MacOS/webkitui-mcp-relay"
resources="$app/Contents/Resources"
licensing_bundle="$resources/WebKitUIMCP_WebKitUIMCPLicensing.bundle"
provenance="$resources/ReleaseProvenance.plist"
source_manifest="$resources/SOURCE-MANIFEST.sha256"

test -d "$app"
test -x "$broker"
test -x "$helper"
test -x "$embedded_relay"
test "$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")" = \
  "com.lorislab.webkitui-mcp.aqua"
test "$(plutil -extract CFBundleDisplayName raw "$app/Contents/Info.plist")" = "WebKitUI MCP"
test "$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")" = "$version"
test "$(plutil -extract CFBundleVersion raw "$app/Contents/Info.plist")" = "$build"
test "$(plutil -extract LSMinimumSystemVersion raw "$app/Contents/Info.plist")" = "15.0"
test "$(plutil -extract CFBundleIconFile raw "$app/Contents/Info.plist")" = "AppIcon"

plutil -lint "$app/Contents/Info.plist" "$resources/PrivacyInfo.xcprivacy" "$provenance"
for required in \
  LICENSE LICENSING.md THIRD_PARTY_NOTICES.md sbom.cdx.json \
  ReleaseProvenance.plist SOURCE-MANIFEST.sha256; do
  test -s "$resources/$required"
done
test "$(plutil -extract SchemaVersion raw "$provenance")" = "2"
test "$(plutil -extract Product raw "$provenance")" = "WebKitUI MCP"
test "$(plutil -extract Version raw "$provenance")" = "$version"
test "$(plutil -extract Build raw "$provenance")" = "$build"
test "$(plutil -extract BuildConfiguration raw "$provenance")" = "Release"
test "$(plutil -extract Architecture raw "$provenance")" = "arm64"
printf '%s\n' "$(plutil -extract GitRevision raw "$provenance")" \
  | grep -Eq '^[0-9a-f]{40}$'
printf '%s\n' "$(plutil -extract SourceTreeState raw "$provenance")" \
  | grep -Eq '^(clean|dirty)$'
test -n "$(plutil -extract SwiftVersion raw "$provenance")"
test -n "$(plutil -extract XcodeVersion raw "$provenance")"
test -n "$(plutil -extract SDKVersion raw "$provenance")"
printf '%s\n' "$(plutil -extract SourceEpoch raw "$provenance")" | grep -Eq '^[0-9]+$'
for field in \
  UnsignedBrokerSHA256 UnsignedConfirmationHelperSHA256 UnsignedEmbeddedRelaySHA256; do
  printf '%s\n' "$(plutil -extract "$field" raw "$provenance")" \
    | grep -Eq '^[0-9a-f]{64}$'
done
manifest_sha=$(shasum -a 256 "$source_manifest" | awk '{print $1}')
test "$manifest_sha" = \
  "$(plutil -extract SourceManifestSHA256 raw "$provenance")"
if grep -Eq '(^|/)(\.env($|\.)|AuthKey_[^/]*\.p8$|[^/]*\.mobileprovision$)' \
  "$source_manifest"; then
  printf '%s\n' "source manifest contains a forbidden secret-bearing path" >&2
  exit 1
fi
mkdir -p "$scratch_dir/current-provenance"
"$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/scripts/generate-release-provenance.sh" \
  "$scratch_dir/current-provenance" >/dev/null
cmp "$source_manifest" "$scratch_dir/current-provenance/SOURCE-MANIFEST.sha256"
test -s "$resources/en.lproj/Localizable.strings"
test -s "$resources/fr.lproj/Localizable.strings"
plutil -lint \
  "$resources/en.lproj/Localizable.strings" \
  "$resources/fr.lproj/Localizable.strings"
sed -n 's/^"\([^"]*\)"[[:space:]]*=.*/\1/p' \
  "$resources/en.lproj/Localizable.strings" \
  | LC_ALL=C sort > "$scratch_dir/en-localization-keys"
sed -n 's/^"\([^"]*\)"[[:space:]]*=.*/\1/p' \
  "$resources/fr.lproj/Localizable.strings" \
  | LC_ALL=C sort > "$scratch_dir/fr-localization-keys"
uniq -d "$scratch_dir/en-localization-keys" > "$scratch_dir/en-localization-duplicates"
uniq -d "$scratch_dir/fr-localization-keys" > "$scratch_dir/fr-localization-duplicates"
test ! -s "$scratch_dir/en-localization-duplicates"
test ! -s "$scratch_dir/fr-localization-duplicates"
diff -u "$scratch_dir/en-localization-keys" "$scratch_dir/fr-localization-keys"
jq -e \
  --arg broker "$(plutil -extract UnsignedBrokerSHA256 raw "$provenance")" \
  --arg helper "$(plutil -extract UnsignedConfirmationHelperSHA256 raw "$provenance")" \
  --arg relay "$(plutil -extract UnsignedEmbeddedRelaySHA256 raw "$provenance")" \
  '
    .metadata.supplier.name == "LorisLabs"
    and (.metadata.tools.components | length > 0)
    and .components[0].hashes[0].content == $broker
    and .components[1].hashes[0].content == $helper
    and .components[2].hashes[0].content == $relay
  ' "$resources/sbom.cdx.json" >/dev/null
test -s "$resources/AppIcon.icns"
file "$resources/AppIcon.icns" | grep -q 'Mac OS X icon'
test -d "$licensing_bundle"
test -s "$licensing_bundle/Contents/Resources/lorislabs-license-public.pem"

file "$broker" | grep -q 'arm64'
file "$helper" | grep -q 'arm64'
file "$embedded_relay" | grep -q 'arm64'
otool -L "$broker" | grep -q '/ServiceManagement.framework/'

setup_command=$("$broker" --print-setup-command)
printf '%s\n' "$setup_command" | grep -Fq "$embedded_relay"
printf '%s\n' "$setup_command" | grep -Fq \
  "$HOME/Library/Application Support/WebkitUIMCP/mcp.sock"
codesign --verify --deep --strict --all-architectures --verbose=2 "$app"

entitlement_index=0
for code in "$app" "$broker" "$helper" "$embedded_relay"; do
  details=$(codesign -dv --verbose=4 "$code" 2>&1)
  printf '%s\n' "$details" | grep -q "TeamIdentifier=$expected_team"
  printf '%s\n' "$details" | grep -q 'Authority=Developer ID Application:'
  printf '%s\n' "$details" | grep -Eq 'flags=.*runtime'
  printf '%s\n' "$details" | grep -Eq '^Timestamp='
  entitlement_index=$((entitlement_index + 1))
  entitlements="$scratch_dir/entitlements-$entitlement_index.plist"
  codesign -d --entitlements :- "$code" > "$entitlements" 2>/dev/null || true
  get_task_allow=false
  if test -s "$entitlements" && plutil -lint "$entitlements" >/dev/null 2>&1; then
    get_task_allow=$(plutil -extract com.apple.security.get-task-allow raw \
      "$entitlements" 2>/dev/null || printf false)
  fi
  if [ "$get_task_allow" = "true" ]; then
    printf '%s\n' "forbidden get-task-allow entitlement: $code" >&2
    exit 1
  fi
done

app_details=$(codesign -dv --verbose=4 "$app" 2>&1)
printf '%s\n' "$app_details" | grep -q 'Sealed Resources version='

printf '%s\n' \
  "Pre-notarization verification passed for WebKitUI MCP $version ($build), Team $expected_team. No upload was performed."
