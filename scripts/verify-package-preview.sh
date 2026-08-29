#!/bin/sh
set -eu

workspace_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
artifact_dir=${1:-"$workspace_dir/dist"}
scratch_dir=$(mktemp -d /private/tmp/webkitui-package-verify.XXXXXX)
trap 'rm -rf "$scratch_dir"' EXIT HUP INT TERM

app_archive="$artifact_dir/WebKitUI-MCP-0.6.0-preview.zip"
relay_archive="$artifact_dir/webkitui-mcp-relay-0.6.0.zip"

test -f "$app_archive"
test -f "$relay_archive"
test -f "$artifact_dir/SHA256SUMS"

(
  cd "$artifact_dir"
  shasum -a 256 -c SHA256SUMS
)

ditto -x -k "$app_archive" "$scratch_dir/app"
ditto -x -k "$relay_archive" "$scratch_dir/relay"

app="$scratch_dir/app/WebKitUI MCP.app"
relay="$scratch_dir/relay/webkitui-mcp-relay-0.6.0"

plutil -lint \
  "$app/Contents/Info.plist" \
  "$app/Contents/Resources/PrivacyInfo.xcprivacy" \
  "$app/Contents/Resources/ReleaseProvenance.plist"
plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist" | grep -qx '0.6.0'
plutil -extract CFBundleDisplayName raw "$app/Contents/Info.plist" | grep -qx 'WebKitUI MCP'
plutil -extract CFBundleIconFile raw "$app/Contents/Info.plist" | grep -qx 'AppIcon'
file "$app/Contents/MacOS/webkitui-mcp-aqua-broker" | grep -q 'arm64'
file "$app/Contents/MacOS/webkitui-mcp-confirm" | grep -q 'arm64'
file "$app/Contents/MacOS/webkitui-mcp-relay" | grep -q 'arm64'
otool -L "$app/Contents/MacOS/webkitui-mcp-aqua-broker" \
  | grep -q '/ServiceManagement.framework/'

setup_command=$("$app/Contents/MacOS/webkitui-mcp-aqua-broker" --print-setup-command)
printf '%s\n' "$setup_command" | grep -Fq \
  "$app/Contents/MacOS/webkitui-mcp-relay"
printf '%s\n' "$setup_command" | grep -Fq \
  "$HOME/Library/Application Support/WebkitUIMCP/mcp.sock"
file "$relay/webkitui-mcp-relay" | grep -q 'arm64'

for required in \
  LICENSE LICENSING.md THIRD_PARTY_NOTICES.md sbom.cdx.json \
  ReleaseProvenance.plist SOURCE-MANIFEST.sha256; do
  test -s "$app/Contents/Resources/$required"
  test -s "$relay/$required"
done

provenance="$app/Contents/Resources/ReleaseProvenance.plist"
source_manifest="$app/Contents/Resources/SOURCE-MANIFEST.sha256"
test "$(plutil -extract SchemaVersion raw "$provenance")" = "2"
test "$(plutil -extract Product raw "$provenance")" = "WebKitUI MCP"
test "$(plutil -extract Version raw "$provenance")" = "0.6.0"
test "$(plutil -extract Build raw "$provenance")" = "600"
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
manifest_sha=$(shasum -a 256 "$source_manifest" | awk '{print $1}')
test "$manifest_sha" = \
  "$(plutil -extract SourceManifestSHA256 raw "$provenance")"
if grep -Eq '(^|/)(\.env($|\.)|AuthKey_[^/]*\.p8$|[^/]*\.mobileprovision$)' \
  "$source_manifest"; then
  printf '%s\n' "source manifest contains a forbidden secret-bearing path" >&2
  exit 1
fi
mkdir -p "$scratch_dir/current-provenance"
"$workspace_dir/scripts/generate-release-provenance.sh" \
  "$scratch_dir/current-provenance" >/dev/null
cmp "$source_manifest" "$scratch_dir/current-provenance/SOURCE-MANIFEST.sha256"

for specification in \
  "UnsignedBrokerSHA256:$app/Contents/MacOS/webkitui-mcp-aqua-broker" \
  "UnsignedConfirmationHelperSHA256:$app/Contents/MacOS/webkitui-mcp-confirm" \
  "UnsignedEmbeddedRelaySHA256:$app/Contents/MacOS/webkitui-mcp-relay"; do
  field=${specification%%:*}
  binary=${specification#*:}
  expected=$(plutil -extract "$field" raw "$provenance")
  actual=$(shasum -a 256 "$binary" | awk '{print $1}')
  test "$actual" = "$expected"
done

sbom="$app/Contents/Resources/sbom.cdx.json"
jq -e \
  --arg broker "$(plutil -extract UnsignedBrokerSHA256 raw "$provenance")" \
  --arg helper "$(plutil -extract UnsignedConfirmationHelperSHA256 raw "$provenance")" \
  --arg relay "$(plutil -extract UnsignedEmbeddedRelaySHA256 raw "$provenance")" \
  '
    .bomFormat == "CycloneDX"
    and .specVersion == "1.6"
    and (.metadata.timestamp | type == "string")
    and .metadata.supplier.name == "LorisLabs"
    and (.metadata.tools.components | length > 0)
    and .components[0].hashes[0].content == $broker
    and .components[1].hashes[0].content == $helper
    and .components[2].hashes[0].content == $relay
  ' "$sbom" >/dev/null

test -s "$app/Contents/Resources/en.lproj/Localizable.strings"
test -s "$app/Contents/Resources/fr.lproj/Localizable.strings"
plutil -lint \
  "$app/Contents/Resources/en.lproj/Localizable.strings" \
  "$app/Contents/Resources/fr.lproj/Localizable.strings"
sed -n 's/^"\([^"]*\)"[[:space:]]*=.*/\1/p' \
  "$app/Contents/Resources/en.lproj/Localizable.strings" \
  | LC_ALL=C sort > "$scratch_dir/en-localization-keys"
sed -n 's/^"\([^"]*\)"[[:space:]]*=.*/\1/p' \
  "$app/Contents/Resources/fr.lproj/Localizable.strings" \
  | LC_ALL=C sort > "$scratch_dir/fr-localization-keys"
uniq -d "$scratch_dir/en-localization-keys" > "$scratch_dir/en-localization-duplicates"
uniq -d "$scratch_dir/fr-localization-keys" > "$scratch_dir/fr-localization-duplicates"
test ! -s "$scratch_dir/en-localization-duplicates"
test ! -s "$scratch_dir/fr-localization-duplicates"
diff -u "$scratch_dir/en-localization-keys" "$scratch_dir/fr-localization-keys"
perl -0777 -ne 'while (/text\(\s*"((?:[^"\\]|\\.)*)"/g) { print "$1\n" }' \
  "$workspace_dir/Sources/WebKitUIMCPAquaBroker/CompanionController.swift" \
  | LC_ALL=C sort -u > "$scratch_dir/companion-localization-keys"
comm -23 "$scratch_dir/companion-localization-keys" "$scratch_dir/en-localization-keys" \
  > "$scratch_dir/missing-localization-keys"
test ! -s "$scratch_dir/missing-localization-keys"
test -s "$app/Contents/Resources/AppIcon.icns"
file "$app/Contents/Resources/AppIcon.icns" | grep -q 'Mac OS X icon'
test -s \
  "$app/Contents/Resources/WebKitUIMCP_WebKitUIMCPLicensing.bundle/Contents/Resources/lorislabs-license-public.pem"

printf '%s\n' "Preview archives and embedded source provenance verified. Code signing, notarization and clean installation remain separate gates."
