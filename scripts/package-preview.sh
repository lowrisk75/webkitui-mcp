#!/bin/sh
set -eu

workspace_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_dir=${1:-"$workspace_dir/dist"}
release_plist="$workspace_dir/Support/AquaApp/Info.plist"
release_version=$(plutil -extract CFBundleShortVersionString raw "$release_plist")
scratch_dir=$(mktemp -d /private/tmp/webkitui-package.XXXXXX)
trap 'rm -rf "$scratch_dir"' EXIT HUP INT TERM

cd "$workspace_dir"
mkdir -p "$scratch_dir/provenance-before" "$scratch_dir/provenance-after"
scripts/generate-release-provenance.sh "$scratch_dir/provenance-before" >/dev/null
swift build -c release --arch arm64 --scratch-path "$scratch_dir/build"
release_dir=$(swift build -c release --arch arm64 --scratch-path "$scratch_dir/build" --show-bin-path)
scripts/generate-release-provenance.sh "$scratch_dir/provenance-after" >/dev/null
cmp "$scratch_dir/provenance-before/SOURCE-MANIFEST.sha256" \
  "$scratch_dir/provenance-after/SOURCE-MANIFEST.sha256"
app_dir="$scratch_dir/WebKitUI MCP.app"
relay_dir="$scratch_dir/webkitui-mcp-relay-$release_version"

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$relay_dir" "$output_dir"
install -m 0755 "$release_dir/webkitui-mcp-aqua-broker" \
  "$app_dir/Contents/MacOS/webkitui-mcp-aqua-broker"
install -m 0755 "$release_dir/webkitui-mcp-confirm" \
  "$app_dir/Contents/MacOS/webkitui-mcp-confirm"
install -m 0755 "$release_dir/webkitui-mcp-relay" \
  "$app_dir/Contents/MacOS/webkitui-mcp-relay"
cp -R "$release_dir/WebKitUIMCP_WebKitUIMCPLicensing.bundle" \
  "$app_dir/Contents/Resources/"
install -m 0644 Support/AquaApp/Info.plist "$app_dir/Contents/Info.plist"
install -m 0644 Support/AquaApp/AppIcon.icns \
  "$app_dir/Contents/Resources/AppIcon.icns"
install -m 0644 Support/AquaApp/PrivacyInfo.xcprivacy \
  "$app_dir/Contents/Resources/PrivacyInfo.xcprivacy"
cp -R Support/AquaApp/en.lproj Support/AquaApp/fr.lproj "$app_dir/Contents/Resources/"
install -m 0644 LICENSE LICENSING.md THIRD_PARTY_NOTICES.md \
  "$app_dir/Contents/Resources/"
install -m 0644 docs/release-maintenance-policy.md \
  "$app_dir/Contents/Resources/RELEASE-MAINTENANCE.md"
install -m 0644 docs/network-boundary.md \
  "$app_dir/Contents/Resources/NETWORK-BOUNDARY.md"
install -m 0644 \
  "$scratch_dir/provenance-before/ReleaseProvenance.plist" \
  "$scratch_dir/provenance-before/SOURCE-MANIFEST.sha256" \
  "$app_dir/Contents/Resources/"
broker_sha=$(shasum -a 256 "$app_dir/Contents/MacOS/webkitui-mcp-aqua-broker" | awk '{print $1}')
helper_sha=$(shasum -a 256 "$app_dir/Contents/MacOS/webkitui-mcp-confirm" | awk '{print $1}')
relay_sha=$(shasum -a 256 "$app_dir/Contents/MacOS/webkitui-mcp-relay" | awk '{print $1}')
plutil -insert UnsignedBrokerSHA256 -string "$broker_sha" \
  "$app_dir/Contents/Resources/ReleaseProvenance.plist"
plutil -insert UnsignedConfirmationHelperSHA256 -string "$helper_sha" \
  "$app_dir/Contents/Resources/ReleaseProvenance.plist"
plutil -insert UnsignedEmbeddedRelaySHA256 -string "$relay_sha" \
  "$app_dir/Contents/Resources/ReleaseProvenance.plist"
scripts/generate-release-sbom.sh \
  "$app_dir/Contents/Resources/ReleaseProvenance.plist" \
  "$app_dir/Contents/Resources/sbom.cdx.json"
install -m 0755 "$release_dir/webkitui-mcp-relay" "$relay_dir/webkitui-mcp-relay"
install -m 0644 LICENSE LICENSING.md THIRD_PARTY_NOTICES.md "$relay_dir/"
install -m 0644 docs/release-maintenance-policy.md \
  "$relay_dir/RELEASE-MAINTENANCE.md"
install -m 0644 docs/network-boundary.md "$relay_dir/NETWORK-BOUNDARY.md"
install -m 0644 "$app_dir/Contents/Resources/sbom.cdx.json" "$relay_dir/sbom.cdx.json"
install -m 0644 \
  "$app_dir/Contents/Resources/ReleaseProvenance.plist" \
  "$app_dir/Contents/Resources/SOURCE-MANIFEST.sha256" \
  "$relay_dir/"

plutil -lint \
  "$app_dir/Contents/Info.plist" \
  "$app_dir/Contents/Resources/PrivacyInfo.xcprivacy" \
  "$app_dir/Contents/Resources/ReleaseProvenance.plist"
file "$app_dir/Contents/MacOS/webkitui-mcp-aqua-broker" | grep -q 'arm64'
file "$relay_dir/webkitui-mcp-relay" | grep -q 'arm64'
plutil -extract CFBundleShortVersionString raw "$app_dir/Contents/Info.plist" \
  | grep -Fqx "$release_version"
plutil -extract CFBundleIconFile raw "$app_dir/Contents/Info.plist" | grep -qx 'AppIcon'
file "$app_dir/Contents/Resources/AppIcon.icns" | grep -q 'Mac OS X icon'

artifact="$output_dir/WebKitUI-MCP-$release_version-preview.zip"
relay_artifact="$output_dir/webkitui-mcp-relay-$release_version.zip"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --keepParent "$app_dir" "$artifact"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --keepParent \
  "$relay_dir" "$relay_artifact"

(
  cd "$output_dir"
  shasum -a 256 "$(basename "$artifact")" "$(basename "$relay_artifact")" > SHA256SUMS
  cat SHA256SUMS
)

printf '%s\n' "Unsigned preview artifacts created. Signing, notarization, installation and publication remain separate gates."
