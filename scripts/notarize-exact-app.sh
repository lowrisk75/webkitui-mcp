#!/bin/sh
set -eu

if [ "$#" -ne 5 ]; then
  printf '%s\n' \
    "usage: $0 SIGNED_ZIP EXPECTED_SHA256 OUTPUT_DIRECTORY KEYCHAIN_PROFILE EXPECTED_TEAM_ID" \
    >&2
  exit 64
fi

input_archive=$1
expected_sha=$2
output_dir=$3
keychain_profile=$4
expected_team=$5
workspace_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
approval="WebKitUI-MCP-0.6.0-600-$expected_sha"

if [ "${WEBKITUI_NOTARIZATION_APPROVAL:-}" != "$approval" ]; then
  printf '%s\n' \
    "refusing Apple upload: set WEBKITUI_NOTARIZATION_APPROVAL=$approval only after exact approval" \
    >&2
  exit 65
fi

actual_sha=$(shasum -a 256 "$input_archive" | awk '{print $1}')
if [ "$actual_sha" != "$expected_sha" ]; then
  printf '%s\n' \
    "refusing Apple upload: expected SHA-256 $expected_sha, got $actual_sha" >&2
  exit 66
fi

scratch_dir=$(mktemp -d /private/tmp/webkitui-notarization.XXXXXX)
trap 'rm -rf "$scratch_dir"' EXIT HUP INT TERM
ditto -x -k "$input_archive" "$scratch_dir/input"
app="$scratch_dir/input/WebKitUI MCP.app"
"$workspace_dir/scripts/verify-pre-notarization.sh" "$app" "$expected_team"

mkdir -p "$output_dir"
request="$output_dir/notarization-request.plist"
submission="$output_dir/notarytool-submission.json"
status_file="$output_dir/notarytool-status.json"
developer_log="$output_dir/notarytool-developer-log.json"
final_archive="$output_dir/WebKitUI-MCP-0.6.0-notarized.zip"

if [ -e "$request" ]; then
  test "$(plutil -extract InputSHA256 raw "$request")" = "$expected_sha"
  test "$(plutil -extract TeamIdentifier raw "$request")" = "$expected_team"
else
  if [ -e "$submission" ] || [ -e "$status_file" ] || [ -e "$developer_log" ]; then
    printf '%s\n' "notarization evidence exists without its exact request anchor" >&2
    exit 67
  fi
  plutil -create xml1 "$request"
  plutil -insert SchemaVersion -integer 1 "$request"
  plutil -insert Product -string "WebKitUI MCP" "$request"
  plutil -insert Version -string "0.6.0" "$request"
  plutil -insert Build -string "600" "$request"
  plutil -insert InputSHA256 -string "$expected_sha" "$request"
  plutil -insert TeamIdentifier -string "$expected_team" "$request"
  chmod 0600 "$request"
fi

if [ ! -e "$submission" ]; then
  printf '%s\n' \
    "Uploading WebKitUI MCP 0.6.0 (600), Team $expected_team, SHA-256 $expected_sha to Apple Notary Service."
  submission_tmp="$scratch_dir/notarytool-submission.json"
  xcrun notarytool submit "$input_archive" \
    --keychain-profile "$keychain_profile" \
    --no-wait \
    --output-format json > "$submission_tmp"
  plutil -extract id raw "$submission_tmp" >/dev/null
  mv "$submission_tmp" "$submission"
fi

submission_id=$(plutil -extract id raw "$submission")
status_tmp="$scratch_dir/notarytool-status.json"
if ! xcrun notarytool wait "$submission_id" \
  --keychain-profile "$keychain_profile" \
  --timeout 30m \
  --output-format json > "$status_tmp"; then
  printf '%s\n' \
    "notarization is still resumable: id=$submission_id evidence=$output_dir" >&2
  exit 69
fi
plutil -extract status raw "$status_tmp" >/dev/null
mv "$status_tmp" "$status_file"
status=$(plutil -extract status raw "$status_file")
if [ ! -e "$developer_log" ]; then
  developer_log_tmp="$scratch_dir/notarytool-developer-log.json"
  xcrun notarytool log "$submission_id" \
    --keychain-profile "$keychain_profile" \
    "$developer_log_tmp"
  mv "$developer_log_tmp" "$developer_log"
fi
if [ "$status" != "Accepted" ]; then
  printf '%s\n' "notarization did not succeed: status=$status id=$submission_id" >&2
  exit 68
fi

if [ -e "$final_archive" ]; then
  printf '%s\n' "refusing to overwrite notarized artifact: $final_archive" >&2
  exit 67
fi
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=4 "$app"
codesign --verify --deep --strict --all-architectures --verbose=2 "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$final_archive"
final_sha=$(shasum -a 256 "$final_archive" | awk '{print $1}')
printf '%s\n' \
  "Notarized artifact verified: id=$submission_id SHA-256=$final_sha path=$final_archive"
