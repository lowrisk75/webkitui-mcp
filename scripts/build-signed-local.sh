#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
  printf '%s\n' \
    "usage: $0 OUTPUT_DIRECTORY SIGNING_IDENTITY_SHA1 EXPECTED_TEAM_ID" >&2
  exit 64
fi

output_dir=$1
signing_identity=$2
expected_team=$3
workspace_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
scratch_dir=$(mktemp -d /private/tmp/webkitui-signed-build.XXXXXX)
trap 'rm -rf "$scratch_dir"' EXIT HUP INT TERM

cd "$workspace_dir"
swift build -c release --arch arm64 --scratch-path "$scratch_dir/build"
release_dir=$(swift build -c release --arch arm64 --scratch-path "$scratch_dir/build" --show-bin-path)
app="$scratch_dir/WebKitUI MCP.app"
relay_dir="$scratch_dir/webkitui-mcp-relay-0.6.0"

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$relay_dir" "$output_dir"
install -m 0755 "$release_dir/webkitui-mcp-aqua-broker" \
  "$app/Contents/MacOS/webkitui-mcp-aqua-broker"
install -m 0755 "$release_dir/webkitui-mcp-confirm" \
  "$app/Contents/MacOS/webkitui-mcp-confirm"
install -m 0755 "$release_dir/webkitui-mcp-relay" \
  "$app/Contents/MacOS/webkitui-mcp-relay"
cp -R "$release_dir/WebKitUIMCP_WebKitUIMCPLicensing.bundle" \
  "$app/Contents/Resources/"
install -m 0644 Support/AquaApp/Info.plist "$app/Contents/Info.plist"
install -m 0644 Support/AquaApp/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
install -m 0644 Support/AquaApp/PrivacyInfo.xcprivacy \
  "$app/Contents/Resources/PrivacyInfo.xcprivacy"
cp -R Support/AquaApp/en.lproj Support/AquaApp/fr.lproj "$app/Contents/Resources/"
install -m 0644 LICENSE LICENSING.md THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
install -m 0644 Support/Packaging/sbom.cdx.json "$app/Contents/Resources/sbom.cdx.json"

install -m 0755 "$release_dir/webkitui-mcp-relay" "$relay_dir/webkitui-mcp-relay"
install -m 0644 LICENSE LICENSING.md THIRD_PARTY_NOTICES.md "$relay_dir/"
install -m 0644 Support/Packaging/sbom.cdx.json "$relay_dir/sbom.cdx.json"

codesign --force --sign "$signing_identity" --identifier com.lorislab.webkitui-mcp.confirm \
  --options runtime --timestamp "$app/Contents/MacOS/webkitui-mcp-confirm"
codesign --force --sign "$signing_identity" --identifier com.lorislab.webkitui-mcp.relay \
  --options runtime --timestamp "$app/Contents/MacOS/webkitui-mcp-relay"
codesign --force --sign "$signing_identity" --options runtime --timestamp "$app"
codesign --force --sign "$signing_identity" --identifier com.lorislab.webkitui-mcp.relay \
  --options runtime --timestamp "$relay_dir/webkitui-mcp-relay"

scripts/verify-pre-notarization.sh "$app" "$expected_team"
codesign --verify --strict --all-architectures --verbose=2 "$relay_dir/webkitui-mcp-relay"
relay_details=$(codesign -dv --verbose=4 "$relay_dir/webkitui-mcp-relay" 2>&1)
printf '%s\n' "$relay_details" | grep -q "TeamIdentifier=$expected_team"
printf '%s\n' "$relay_details" | grep -q 'Authority=Developer ID Application:'
printf '%s\n' "$relay_details" | grep -Eq 'flags=.*runtime'
printf '%s\n' "$relay_details" | grep -Eq '^Timestamp='

app_archive="$output_dir/WebKitUI-MCP-0.6.0-signed-local.zip"
relay_archive="$output_dir/webkitui-mcp-relay-0.6.0-signed-local.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$app_archive"
ditto -c -k --sequesterRsrc --keepParent "$relay_dir" "$relay_archive"

(
  cd "$output_dir"
  shasum -a 256 "$(basename "$app_archive")" "$(basename "$relay_archive")" \
    > SHA256SUMS.signed-local
  cat SHA256SUMS.signed-local
)

printf '%s\n' \
  "Signed local artifacts created and verified. No notarization or publication was performed."
