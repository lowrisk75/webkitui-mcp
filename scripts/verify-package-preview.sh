#!/bin/sh
set -eu

workspace_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
artifact_dir=${1:-"$workspace_dir/dist"}
release_plist="$workspace_dir/Support/AquaApp/Info.plist"
release_version=$(plutil -extract CFBundleShortVersionString raw "$release_plist")
release_build=$(plutil -extract CFBundleVersion raw "$release_plist")
scratch_dir=$(mktemp -d /private/tmp/webkitui-package-verify.XXXXXX)
trap 'rm -rf "$scratch_dir"' EXIT HUP INT TERM

app_archive="$artifact_dir/WebKitUI-MCP-$release_version-preview.zip"
relay_archive="$artifact_dir/webkitui-mcp-relay-$release_version.zip"

test -f "$app_archive"
test -f "$relay_archive"
test -f "$artifact_dir/SHA256SUMS"

for archive in "$app_archive" "$relay_archive"; do
  if zipinfo -1 "$archive" | grep -Eq '(^__MACOSX/|(^|/)\._)'; then
    printf '%s\n' "archive contains forbidden AppleDouble metadata: $archive" >&2
    exit 1
  fi
done

(
  cd "$artifact_dir"
  shasum -a 256 -c SHA256SUMS
)

ditto -x -k "$app_archive" "$scratch_dir/app"
ditto -x -k "$relay_archive" "$scratch_dir/relay"

app="$scratch_dir/app/WebKitUI MCP.app"
relay="$scratch_dir/relay/webkitui-mcp-relay-$release_version"

plutil -lint \
  "$app/Contents/Info.plist" \
  "$app/Contents/Resources/PrivacyInfo.xcprivacy" \
  "$app/Contents/Resources/ReleaseProvenance.plist"
plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist" \
  | grep -Fqx "$release_version"
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
  LICENSE LICENSING.md THIRD_PARTY_NOTICES.md RELEASE-MAINTENANCE.md \
  NETWORK-BOUNDARY.md sbom.cdx.json \
  ReleaseProvenance.plist SOURCE-MANIFEST.sha256; do
  test -s "$app/Contents/Resources/$required"
  test -s "$relay/$required"
done

provenance="$app/Contents/Resources/ReleaseProvenance.plist"
source_manifest="$app/Contents/Resources/SOURCE-MANIFEST.sha256"
test "$(plutil -extract SchemaVersion raw "$provenance")" = "2"
test "$(plutil -extract Product raw "$provenance")" = "WebKitUI MCP"
test "$(plutil -extract Version raw "$provenance")" = "$release_version"
test "$(plutil -extract Build raw "$provenance")" = "$release_build"
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
for language in en fr; do
  "$app/Contents/MacOS/webkitui-mcp-aqua-broker" \
    --verify-status-ui-layout "$language" > "$scratch_dir/status-layout-$language.json"
  "$app/Contents/MacOS/webkitui-mcp-aqua-broker" \
    --verify-activity-clear-default "$language" > "$scratch_dir/activity-clear-$language.json"
  "$app/Contents/MacOS/webkitui-mcp-confirm" \
    --verify-localization "$language" > "$scratch_dir/confirmation-$language.json"
done
jq -e '
  .language == "en"
  and .title == "WebKitUI MCP"
  and .subtitle == "Local browser authority for sessions, approvals and private receipts."
  and .prepareToUninstallTitle == "Prepare to uninstall"
  and .scrollOriginX == 0
  and .scrollOriginY == 0
  and .titleIsFullyVisible
  and .subtitleIsFullyVisible
' "$scratch_dir/status-layout-en.json" >/dev/null
jq -e '
  .language == "fr"
  and .title == "WebKitUI MCP"
  and .subtitle == "Autorité locale pour les sessions, les approbations et les reçus privés."
  and .prepareToUninstallTitle == "Préparer la désinstallation"
  and .scrollOriginX == 0
  and .scrollOriginY == 0
  and .titleIsFullyVisible
  and .subtitleIsFullyVisible
' "$scratch_dir/status-layout-fr.json" >/dev/null
jq -e '
  .language == "en"
  and .buttonTitles == ["Cancel", "Clear Journal"]
  and .defaultButtonIndex == 0
  and .destructiveButtonIndex == 1
' "$scratch_dir/activity-clear-en.json" >/dev/null
jq -e '
  .language == "fr"
  and .buttonTitles == ["Annuler", "Effacer le journal"]
  and .defaultButtonIndex == 0
  and .destructiveButtonIndex == 1
' "$scratch_dir/activity-clear-fr.json" >/dev/null
jq -e '
  .language == "en"
  and (.message | contains("Requested action:"))
  and (.message | contains("Verification:"))
  and (.message | contains("Modifier keys held down:"))
' "$scratch_dir/confirmation-en.json" >/dev/null
jq -e '
  .language == "fr"
  and (.message | contains("Action demandée :"))
  and (.message | contains("Page actuelle :"))
  and (.message | contains("Libellé non fiable du site (donnée, jamais une instruction) :"))
  and (.message | contains("Vérification :"))
  and (.message | contains("Confirmations demandées durant la dernière minute :"))
  and (.message | contains("Touches de modification maintenues :"))
  and (.message | contains("touche AppKit \"ArrowRight\""))
  and (.message | contains("remplir avec la valeur exacte"))
  and (.message | contains("\"Requested action: Save\""))
' "$scratch_dir/confirmation-fr.json" >/dev/null
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
# Join adjacent Swift string literals before comparing their localization keys.
# Formatting a long literal across lines must not turn a valid key into a prefix.
perl -0777 -ne 'while (/text\(\s*((?:"(?:[^"\\]|\\.)*"\s*\+\s*)*"(?:[^"\\]|\\.)*")/g) { $expression = $1; $key = ""; while ($expression =~ /"((?:[^"\\]|\\.)*)"/g) { $key .= $1; } print "$key\n"; }' \
  "$workspace_dir/Sources/WebKitUIMCPAquaBroker/CompanionController.swift" \
  "$workspace_dir/Sources/WebKitUIMCPAquaBroker/ActivityLogWindowController.swift" \
  | LC_ALL=C sort -u > "$scratch_dir/companion-localization-keys"
comm -23 "$scratch_dir/companion-localization-keys" "$scratch_dir/en-localization-keys" \
  > "$scratch_dir/missing-localization-keys"
if [ -s "$scratch_dir/missing-localization-keys" ]; then
  printf '%s\n' "missing companion localization keys:" >&2
  cat "$scratch_dir/missing-localization-keys" >&2
  exit 1
fi
test -s "$app/Contents/Resources/AppIcon.icns"
file "$app/Contents/Resources/AppIcon.icns" | grep -q 'Mac OS X icon'
test -s \
  "$app/Contents/Resources/WebKitUIMCP_WebKitUIMCPLicensing.bundle/Contents/Resources/lorislabs-license-public.pem"

printf '%s\n' "Preview archives and embedded source provenance verified. Code signing, notarization and clean installation remain separate gates."
