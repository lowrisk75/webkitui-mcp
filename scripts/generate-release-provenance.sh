#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  printf '%s\n' "usage: $0 OUTPUT_DIRECTORY" >&2
  exit 64
fi

workspace_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_dir=$1
manifest="$output_dir/SOURCE-MANIFEST.sha256"
provenance="$output_dir/ReleaseProvenance.plist"
inputs=$(mktemp /private/tmp/webkitui-provenance-inputs.XXXXXX)
trap 'rm -f "$inputs"' EXIT HUP INT TERM

cd "$workspace_dir"
mkdir -p "$output_dir"

find \
  Package.swift package.json package-lock.json \
  README.md LICENSE LICENSING.md THIRD_PARTY_NOTICES.md \
  Sources Tests Support/AquaApp Support/Packaging scripts \
  \( -type f -o -type l \) ! -name '.DS_Store' -print0 \
  | LC_ALL=C sort -zu > "$inputs"

: > "$manifest"
while IFS= read -r -d '' path; do
  case "$path" in
    *'
'*)
      printf '%s\n' "release input path contains a forbidden newline" >&2
      exit 70
      ;;
  esac
  if [ -L "$path" ]; then
    target=$(readlink "$path")
    digest=$(printf 'symlink\000%s' "$target" | shasum -a 256 | awk '{print $1}')
  else
    digest=$(shasum -a 256 "$path" | awk '{print $1}')
  fi
  printf '%s  %s\n' "$digest" "$path" >> "$manifest"
done < "$inputs"

revision=$(git rev-parse HEAD)
branch=$(git branch --show-current)
tracked_diff_sha=$(git diff --binary --no-ext-diff HEAD -- | shasum -a 256 | awk '{print $1}')
index_diff_sha=$(git diff --binary --no-ext-diff --cached -- | shasum -a 256 | awk '{print $1}')
status_sha=$(git status --short --untracked-files=all -- | shasum -a 256 | awk '{print $1}')
source_manifest_sha=$(shasum -a 256 "$manifest" | awk '{print $1}')
source_epoch=$(xargs -0 stat -f '%m' < "$inputs" | LC_ALL=C sort -nr | sed -n '1p')
swift_version=$(swift --version 2>&1 | tr '\n' ' ' | sed 's/[[:space:]]*$//')
xcode_version=$(xcodebuild -version | tr '\n' ' ' | sed 's/[[:space:]]*$//')
sdk_version=$(xcrun --sdk macosx --show-sdk-version)

if git diff --quiet HEAD -- && git diff --quiet --cached -- \
  && test -z "$(git ls-files --others --exclude-standard)"; then
  tree_state=clean
else
  tree_state=dirty
fi

plutil -create xml1 "$provenance"
plutil -insert SchemaVersion -integer 2 "$provenance"
plutil -insert Product -string 'WebKitUI MCP' "$provenance"
plutil -insert Version -string '0.6.0' "$provenance"
plutil -insert Build -string '600' "$provenance"
plutil -insert GitRevision -string "$revision" "$provenance"
plutil -insert GitBranch -string "$branch" "$provenance"
plutil -insert SourceTreeState -string "$tree_state" "$provenance"
plutil -insert TrackedDiffSHA256 -string "$tracked_diff_sha" "$provenance"
plutil -insert IndexDiffSHA256 -string "$index_diff_sha" "$provenance"
plutil -insert GitStatusSHA256 -string "$status_sha" "$provenance"
plutil -insert SourceManifestSHA256 -string "$source_manifest_sha" "$provenance"
plutil -insert SourceEpoch -integer "$source_epoch" "$provenance"
plutil -insert SwiftVersion -string "$swift_version" "$provenance"
plutil -insert XcodeVersion -string "$xcode_version" "$provenance"
plutil -insert SDKVersion -string "$sdk_version" "$provenance"
plutil -insert BuildConfiguration -string 'Release' "$provenance"
plutil -insert Architecture -string 'arm64' "$provenance"

chmod 0644 "$manifest" "$provenance"
plutil -lint "$provenance" >/dev/null
printf '%s\n' "$source_manifest_sha"
