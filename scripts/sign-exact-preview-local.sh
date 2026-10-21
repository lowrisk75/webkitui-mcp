#!/bin/sh
set -eu

if [ "$#" -ne 5 ]; then
  printf '%s\n' \
    "usage: $0 INPUT_PREVIEW_ZIP EXPECTED_SHA256 OUTPUT_DIRECTORY SIGNING_IDENTITY_SHA1 EXPECTED_TEAM_ID" >&2
  exit 64
fi

input_archive=$1
expected_sha=$2
output_dir=$3
signing_identity=$4
expected_team=$5
workspace_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
release_version=$(plutil -extract CFBundleShortVersionString raw \
  "$workspace_dir/Support/AquaApp/Info.plist")
scratch_dir=$(mktemp -d /private/tmp/webkitui-exact-sign.XXXXXX)
printf 'RESOURCE_CREATED=signing-stage:%s\n' "$scratch_dir"
trap 'rm -rf "$scratch_dir"; printf "RESOURCE_REMOVED=signing-stage:%s\n" "$scratch_dir"' EXIT HUP INT TERM

actual_sha=$(shasum -a 256 "$input_archive" | awk '{print $1}')
if [ "$actual_sha" != "$expected_sha" ]; then
  printf '%s\n' \
    "refusing to sign: expected SHA-256 $expected_sha, got $actual_sha" >&2
  exit 65
fi

ditto -x -k "$input_archive" "$scratch_dir/input"
app="$scratch_dir/input/WebKitUI MCP.app"
helper="$app/Contents/MacOS/webkitui-mcp-confirm"
relay="$app/Contents/MacOS/webkitui-mcp-relay"
siliconpass_connector="$app/Contents/Resources/CredentialBroker/siliconpass-vault-mcp"
siliconpass_bundle="$app/Contents/Resources/CredentialBroker/SiliconPass_SiliconPassCredentialBroker.bundle"
siliconpass_policy="$app/Contents/Resources/SiliconPassVaultMCP.plist"

test -d "$app"
test -x "$helper"
test -x "$relay"
test -x "$siliconpass_connector"
mkdir -p "$output_dir"
output_archive="$output_dir/WebKitUI-MCP-$release_version-signed-local.zip"
attestation="$output_dir/SigningAttestation.plist"
for output in "$output_archive" "$attestation"; do
  if [ -e "$output" ]; then
    printf '%s\n' "refusing to overwrite existing signing output: $output" >&2
    exit 66
  fi
done

codesign --force --sign "$signing_identity" \
  --identifier com.lorislab.webkitui-mcp.confirm \
  --options runtime --timestamp "$helper"
codesign --force --sign "$signing_identity" \
  --identifier com.lorislab.webkitui-mcp.relay \
  --options runtime --timestamp "$relay"
codesign --force --sign "$signing_identity" \
  --identifier "$(plutil -extract ConnectorIdentifier raw "$siliconpass_policy")" \
  --options runtime --timestamp "$siliconpass_connector"
codesign --force --sign "$signing_identity" \
  --options runtime --timestamp "$app"

"$workspace_dir/scripts/verify-pre-notarization.sh" "$app" "$expected_team"

COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --keepParent \
  "$app" "$output_archive"
if zipinfo -1 "$output_archive" | grep -Eq '(^__MACOSX/|(^|/)\._)'; then
  printf '%s\n' "signed archive contains forbidden AppleDouble metadata" >&2
  exit 1
fi
mkdir -p "$scratch_dir/roundtrip"
ditto -x -k "$output_archive" "$scratch_dir/roundtrip"
"$workspace_dir/scripts/verify-pre-notarization.sh" \
  "$scratch_dir/roundtrip/WebKitUI MCP.app" "$expected_team"
archive_sha=$(shasum -a 256 "$output_archive" | awk '{print $1}')
plutil -create xml1 "$attestation"
plutil -insert SchemaVersion -integer 1 "$attestation"
plutil -insert InputArchiveSHA256 -string "$expected_sha" "$attestation"
plutil -insert SignedArchiveSHA256 -string "$archive_sha" "$attestation"
plutil -insert TeamIdentifier -string "$expected_team" "$attestation"
plutil -insert SignedBrokerSHA256 -string \
  "$(shasum -a 256 "$app/Contents/MacOS/webkitui-mcp-aqua-broker" | awk '{print $1}')" \
  "$attestation"
plutil -insert SignedConfirmationHelperSHA256 -string \
  "$(shasum -a 256 "$helper" | awk '{print $1}')" "$attestation"
plutil -insert SignedEmbeddedRelaySHA256 -string \
  "$(shasum -a 256 "$relay" | awk '{print $1}')" "$attestation"
plutil -insert SignedSiliconPassMCPConnectorSHA256 -string \
  "$(shasum -a 256 "$siliconpass_connector" | awk '{print $1}')" "$attestation"
chmod 0644 "$attestation"
printf '%s  %s\n' "$archive_sha" "$output_archive"
printf '%s\n' \
  "Exact preview signed and verified locally. No installation, notarization or publication was performed."
