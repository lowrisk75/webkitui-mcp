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
release_version=$(plutil -extract CFBundleShortVersionString raw \
  "$workspace_dir/Support/AquaApp/Info.plist")
scratch_dir=$(mktemp -d /private/tmp/webkitui-signed-build.XXXXXX)
trap 'rm -rf "$scratch_dir"' EXIT HUP INT TERM
provenance_before="$scratch_dir/provenance-before"
provenance_after="$scratch_dir/provenance-after"

cd "$workspace_dir"
mkdir -p "$provenance_before" "$provenance_after"
scripts/generate-release-provenance.sh "$provenance_before" >/dev/null
swift build -c release --arch arm64 --scratch-path "$scratch_dir/build"
release_dir=$(swift build -c release --arch arm64 --scratch-path "$scratch_dir/build" --show-bin-path)
scripts/generate-release-provenance.sh "$provenance_after" >/dev/null
cmp "$provenance_before/SOURCE-MANIFEST.sha256" \
  "$provenance_after/SOURCE-MANIFEST.sha256"
app="$scratch_dir/WebKitUI MCP.app"
relay_dir="$scratch_dir/webkitui-mcp-relay-$release_version"

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
install -m 0644 docs/release-maintenance-policy.md \
  "$app/Contents/Resources/RELEASE-MAINTENANCE.md"
install -m 0644 docs/network-boundary.md \
  "$app/Contents/Resources/NETWORK-BOUNDARY.md"
install -m 0644 \
  "$provenance_before/ReleaseProvenance.plist" \
  "$provenance_before/SOURCE-MANIFEST.sha256" \
  "$app/Contents/Resources/"
broker_sha=$(shasum -a 256 "$app/Contents/MacOS/webkitui-mcp-aqua-broker" | awk '{print $1}')
helper_sha=$(shasum -a 256 "$app/Contents/MacOS/webkitui-mcp-confirm" | awk '{print $1}')
relay_sha=$(shasum -a 256 "$app/Contents/MacOS/webkitui-mcp-relay" | awk '{print $1}')
plutil -insert UnsignedBrokerSHA256 -string "$broker_sha" \
  "$app/Contents/Resources/ReleaseProvenance.plist"
plutil -insert UnsignedConfirmationHelperSHA256 -string "$helper_sha" \
  "$app/Contents/Resources/ReleaseProvenance.plist"
plutil -insert UnsignedEmbeddedRelaySHA256 -string "$relay_sha" \
  "$app/Contents/Resources/ReleaseProvenance.plist"
scripts/generate-release-sbom.sh \
  "$app/Contents/Resources/ReleaseProvenance.plist" \
  "$app/Contents/Resources/sbom.cdx.json"

install -m 0755 "$release_dir/webkitui-mcp-relay" "$relay_dir/webkitui-mcp-relay"
install -m 0644 LICENSE LICENSING.md THIRD_PARTY_NOTICES.md "$relay_dir/"
install -m 0644 docs/release-maintenance-policy.md \
  "$relay_dir/RELEASE-MAINTENANCE.md"
install -m 0644 docs/network-boundary.md "$relay_dir/NETWORK-BOUNDARY.md"
install -m 0644 "$app/Contents/Resources/sbom.cdx.json" "$relay_dir/sbom.cdx.json"
install -m 0644 \
  "$app/Contents/Resources/ReleaseProvenance.plist" \
  "$app/Contents/Resources/SOURCE-MANIFEST.sha256" \
  "$relay_dir/"

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

app_archive="$output_dir/WebKitUI-MCP-$release_version-signed-local.zip"
relay_archive="$output_dir/webkitui-mcp-relay-$release_version-signed-local.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$app_archive"
ditto -c -k --sequesterRsrc --keepParent "$relay_dir" "$relay_archive"
mkdir -p "$scratch_dir/roundtrip-app" "$scratch_dir/roundtrip-relay"
ditto -x -k "$app_archive" "$scratch_dir/roundtrip-app"
ditto -x -k "$relay_archive" "$scratch_dir/roundtrip-relay"
scripts/verify-pre-notarization.sh \
  "$scratch_dir/roundtrip-app/WebKitUI MCP.app" "$expected_team"
roundtrip_relay="$scratch_dir/roundtrip-relay/webkitui-mcp-relay-$release_version/webkitui-mcp-relay"
codesign --verify --strict --all-architectures --verbose=2 "$roundtrip_relay"
roundtrip_relay_details=$(codesign -dv --verbose=4 "$roundtrip_relay" 2>&1)
printf '%s\n' "$roundtrip_relay_details" | grep -q "TeamIdentifier=$expected_team"
printf '%s\n' "$roundtrip_relay_details" | grep -q 'Authority=Developer ID Application:'
printf '%s\n' "$roundtrip_relay_details" | grep -Eq 'flags=.*runtime'
printf '%s\n' "$roundtrip_relay_details" | grep -Eq '^Timestamp='

(
  cd "$output_dir"
  shasum -a 256 "$(basename "$app_archive")" "$(basename "$relay_archive")" \
    > SHA256SUMS.signed-local
  cat SHA256SUMS.signed-local
)

printf '%s\n' \
  "Signed local artifacts created and verified. No notarization or publication was performed."
