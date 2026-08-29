#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  printf '%s\n' "usage: $0 RELEASE_PROVENANCE_PLIST OUTPUT_SBOM_JSON" >&2
  exit 64
fi

provenance=$1
output=$2
workspace_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
template="$workspace_dir/Support/Packaging/sbom.cdx.json"

test -s "$provenance"
test -s "$template"
epoch=$(plutil -extract SourceEpoch raw "$provenance")
timestamp=$(date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ')
broker_sha=$(plutil -extract UnsignedBrokerSHA256 raw "$provenance")
helper_sha=$(plutil -extract UnsignedConfirmationHelperSHA256 raw "$provenance")
relay_sha=$(plutil -extract UnsignedEmbeddedRelaySHA256 raw "$provenance")

jq \
  --arg timestamp "$timestamp" \
  --arg broker_sha "$broker_sha" \
  --arg helper_sha "$helper_sha" \
  --arg relay_sha "$relay_sha" \
  '
    .metadata.timestamp = $timestamp
    | .metadata.supplier = {"name": "LorisLabs"}
    | .metadata.tools = {"components": [{
        "type": "application",
        "name": "generate-release-sbom.sh",
        "version": "1"
      }]}
    | .components[0].hashes = [{"alg": "SHA-256", "content": $broker_sha}]
    | .components[1].hashes = [{"alg": "SHA-256", "content": $helper_sha}]
    | .components[2].hashes = [{"alg": "SHA-256", "content": $relay_sha}]
  ' "$template" > "$output"

jq -e '.bomFormat == "CycloneDX" and .specVersion == "1.6"' "$output" >/dev/null
