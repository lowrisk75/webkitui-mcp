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
siliconpass_sha=$(plutil -extract SiliconPassMCPInputSHA256 raw "$provenance")
# The SBOM component is the connector binary, so it carries the connector's own
# version; the manager version that ships it is a separate pin in provenance.
siliconpass_version=$(plutil -extract SiliconPassConnectorVersion raw "$provenance")
version=$(plutil -extract Version raw "$provenance")

jq \
  --arg timestamp "$timestamp" \
  --arg broker_sha "$broker_sha" \
  --arg helper_sha "$helper_sha" \
  --arg relay_sha "$relay_sha" \
  --arg siliconpass_sha "$siliconpass_sha" \
  --arg siliconpass_version "$siliconpass_version" \
  --arg version "$version" \
  '
    walk(
      if type == "string" then
        gsub("@[0-9]+\\.[0-9]+\\.[0-9]+"; "@" + $version)
      else . end
    )
    | .metadata.timestamp = $timestamp
    | .metadata.component.version = $version
    | .metadata.supplier = {"name": "LorisLabs"}
    | .metadata.tools = {"components": [{
        "type": "application",
        "name": "generate-release-sbom.sh",
        "version": "1"
      }]}
    | .components[].version = $version
    | .components[0].hashes = [{"alg": "SHA-256", "content": $broker_sha}]
    | .components[1].hashes = [{"alg": "SHA-256", "content": $helper_sha}]
    | .components[2].hashes = [{"alg": "SHA-256", "content": $relay_sha}]
    | .components[3]["bom-ref"] = "pkg:generic/siliconpass-vault-mcp@" + $siliconpass_version
    | .components[3].version = $siliconpass_version
    | .components[3].hashes = [{"alg": "SHA-256", "content": $siliconpass_sha}]
    | .dependencies[0].dependsOn[3] = .components[3]["bom-ref"]
    | .dependencies[4].ref = .components[3]["bom-ref"]
  ' "$template" > "$output"

jq -e '.bomFormat == "CycloneDX" and .specVersion == "1.6"' "$output" >/dev/null
