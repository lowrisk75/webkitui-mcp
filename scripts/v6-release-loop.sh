#!/bin/zsh
set -euo pipefail

umask 077

script_path=${0:A}
project_root=${script_path:h:h}
state_dir=${WEBKITUI_V6_STATE_DIR:-"$project_root/audit-output/v6-release-loop"}
state_file="$state_dir/state.json"
approval_dir="$state_dir/approvals"
receipt_dir="$state_dir/receipts"

app_commit=fa35c9f2c4d798c237cbbdec77db86a83e972948
worker_commit=4a8cd1aa2b840fc4436163b7068ec6536820ff7b
site_commit=db9c67c6485ad034c6014f15a5ae5950ea478abe
notarized_sha=1bf0814efb2d38644da6df209cce830137c1997410a54f8a18ee3190bbc43849
installed_broker_sha=2c4a5fcd87dfbad74984c171e944e3bbf1d71383edf7167addc2c763c052f76d

notarized_zip="$project_root/audit-output/notarized-v6-fa35c9f-d784ca69/WebKitUI-MCP-0.6.0-notarized.zip"
installed_app="$HOME/Applications/WebKitUI MCP.app"
installed_broker="$installed_app/Contents/MacOS/webkitui-mcp-aqua-broker"
broker_socket="$HOME/Library/Application Support/WebkitUIMCP/mcp.sock"
worker_repo=${WEBKITUI_V6_WORKER_REPO:-$HOME/GitHub/throttle-license-worker}
site_repo=${WEBKITUI_V6_SITE_REPO:-$HOME/GitHub/lorislab-website}

gates=(
  local_artifact
  credential_rotation
  commerce_test
  physical_validation
  public_release
  website_publication
  final_g9
  owned_promotion
)

external_gates=(
  credential_rotation
  commerce_test
  physical_validation
  public_release
  website_publication
  owned_promotion
)

credential_targets=(
  apple_portal_app_store_connect
  cloudflare
  cloudkit_management
  github
  hostinger
  mailcow
  local_mcp
  postgresql_jwt
  proxmox
  tailscale
  tavily
  x_twitter
  bmc
  opnsense
  zyxel
)

die() {
  print -u2 -- "$*"
  exit 65
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

sha_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

sha_text() {
  print -rn -- "$1" | shasum -a 256 | awk '{print $1}'
}

is_gate() {
  (( ${gates[(Ie)$1]} != 0 ))
}

is_external_gate() {
  (( ${external_gates[(Ie)$1]} != 0 ))
}

anchor_for() {
  case "$1" in
    local_artifact)
      sha_text "$app_commit|$notarized_sha|$installed_broker_sha"
      ;;
    credential_rotation)
      local source="$project_root/audit-output/secret-rotation-gate-20260830.md"
      [[ -f "$source" ]] || die "missing credential-rotation evidence: $source"
      sha_file "$source"
      ;;
    commerce_test)
      sha_text "$worker_commit|stripe-sandbox|checkout-zero-eur|brevo-synthetic-only|no-live-sales"
      ;;
    physical_validation)
      sha_text "$app_commit|$notarized_sha|voiceover-keyboard|receipt-reset|guided-logout-login"
      ;;
    public_release)
      sha_text "$app_commit|$notarized_sha|v0.6.0|lowrisk75/webkitui-mcp"
      ;;
    website_publication)
      sha_text "$site_commit|lorislab.fr/developers/webkitui-mcp|access-on-request|no-live-checkout"
      ;;
    final_g9)
      sha_text "$app_commit|$worker_commit|$site_commit|$notarized_sha|fresh-independent-g9"
      ;;
    owned_promotion)
      sha_text "$app_commit|$site_commit|github-and-lorislabs-only|no-reddit|no-email|no-ads"
      ;;
    *) die "unknown gate: $1" ;;
  esac
}

init_state() {
  need jq
  mkdir -p "$approval_dir" "$receipt_dir"
  if [[ -e "$state_file" ]]; then
    jq -e '.schema_version == 1 and (.gates | type == "object")' "$state_file" >/dev/null \
      || die "invalid state file: $state_file"
    return
  fi

  local gates_json='{}'
  local gate anchor
  for gate in $gates; do
    anchor=$(anchor_for "$gate")
    gates_json=$(jq -cn \
      --argjson current "$gates_json" \
      --arg gate "$gate" \
      --arg anchor "$anchor" \
      '$current + {($gate): {status: "PENDING", anchor_sha256: $anchor}}')
  done

  jq -n \
    --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg app_commit "$app_commit" \
    --arg worker_commit "$worker_commit" \
    --arg site_commit "$site_commit" \
    --arg notarized_sha "$notarized_sha" \
    --argjson gates "$gates_json" \
    '{
      schema_version: 1,
      created_at: $created_at,
      updated_at: $created_at,
      release: {
        version: "0.6.0",
        build: "600",
        app_commit: $app_commit,
        worker_commit: $worker_commit,
        site_commit: $site_commit,
        notarized_zip_sha256: $notarized_sha,
        sales_mode: "access_on_request",
        stripe_mode: "sandbox_zero_total_only",
        promotion_scope: "github_and_lorislabs_site_only"
      },
      gates: $gates
    }' > "$state_file"
}

gate_status() {
  jq -r --arg gate "$1" '.gates[$gate].status' "$state_file"
}

set_gate_status() {
  local gate=$1
  local new_status=$2
  local receipt=${3:-}
  local tmp="$state_file.tmp.$$"
  jq \
    --arg gate "$gate" \
    --arg status "$new_status" \
    --arg receipt "$receipt" \
    --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.updated_at = $updated_at
      | .gates[$gate].status = $status
      | if $receipt == "" then . else .gates[$gate].receipt = $receipt end' \
    "$state_file" > "$tmp"
  mv "$tmp" "$state_file"
}

first_incomplete_gate() {
  local gate
  for gate in $gates; do
    if [[ "$(gate_status "$gate")" != PASS ]]; then
      print -- "$gate"
      return
    fi
  done
  print -- COMPLETE
}

require_prior_passes() {
  local requested=$1
  local gate
  for gate in $gates; do
    [[ "$gate" == "$requested" ]] && return
    [[ "$(gate_status "$gate")" == PASS ]] \
      || die "gate $requested is out of order; $gate is not PASS"
  done
  die "unknown gate: $requested"
}

write_receipt() {
  local gate=$1
  local evidence_class=$2
  local summary=$3
  local output="$receipt_dir/$gate.json"
  local anchor
  anchor=$(anchor_for "$gate")
  jq -n \
    --arg gate "$gate" \
    --arg anchor "$anchor" \
    --arg evidence_class "$evidence_class" \
    --arg summary "$summary" \
    --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      schema_version: 1,
      gate: $gate,
      result: "PASS",
      anchor_sha256: $anchor,
      evidence_class: $evidence_class,
      summary: $summary,
      completed_at: $completed_at
    }' > "$output"
  set_gate_status "$gate" PASS "$output"
  print -- "$output"
}

verify_commit() {
  local repo=$1
  local expected=$2
  [[ -d "$repo" ]] || die "missing repository: $repo"
  git -C "$repo" cat-file -e "$expected^{commit}" 2>/dev/null \
    || die "commit $expected is missing from $repo"
}

verify_local() {
  init_state
  verify_commit "$project_root" "$app_commit"
  verify_commit "$worker_repo" "$worker_commit"
  verify_commit "$site_repo" "$site_commit"

  [[ -f "$notarized_zip" ]] || die "missing notarized ZIP: $notarized_zip"
  [[ "$(sha_file "$notarized_zip")" == "$notarized_sha" ]] \
    || die "notarized ZIP hash mismatch"
  [[ -x "$installed_broker" ]] || die "missing installed broker: $installed_broker"
  [[ "$(sha_file "$installed_broker")" == "$installed_broker_sha" ]] \
    || die "installed broker hash mismatch"
  [[ -S "$broker_socket" ]] || die "installed broker socket is not active"
  [[ "$(plutil -extract CFBundleShortVersionString raw "$installed_app/Contents/Info.plist")" == 0.6.0 ]] \
    || die "installed app version mismatch"
  [[ "$(plutil -extract CFBundleVersion raw "$installed_app/Contents/Info.plist")" == 600 ]] \
    || die "installed app build mismatch"

  local receipt
  receipt=$(write_receipt local_artifact CURRENT-OBSERVED \
    "Exact V6 commits, notarized ZIP, installed broker, version/build and active socket verified locally.")
  print -- "PASS local_artifact"
  print -- "receipt=$receipt"
}

approval_token() {
  local gate=$1
  local anchor
  anchor=$(anchor_for "$gate")
  print -- "GO-WEBKITUI-V6-${gate}-${anchor}"
}

gate_details() {
  case "$1" in
    credential_rotation)
      print -- "Rotate/revoke exactly these credential families: ${(j:, :)credential_targets}. Prove replacements work with least privilege, old credentials fail, global inheritance is removed, and no value enters evidence."
      ;;
    commerce_test)
      print -- "Deploy only Worker $worker_commit to an isolated Cloudflare test environment. Stripe must be sandbox, total EUR 0, payment_status no_payment_required, synthetic customer only, Brevo test recipient only, and no live Price or Payment Link."
      ;;
    physical_validation)
      print -- "Run guided VoiceOver, keyboard, receipt-reset and logout/login checks for app $app_commit and ZIP $notarized_sha. No reboot, Keychain reset or session erasure."
      ;;
    public_release)
      print -- "Push only app commit $app_commit, create tag v0.6.0 and one GitHub Release in lowrisk75/webkitui-mcp with exact asset SHA-256 $notarized_sha; independently read back public bytes."
      ;;
    website_publication)
      print -- "Publish only site commit $site_commit after binding evaluation CTAs to the verified GitHub asset. Keep EUR 299/year visible, access-on-request, and no live checkout."
      ;;
    final_g9)
      print -- "Run a fresh independent G9 audit over local, installed, provider-test and public evidence."
      ;;
    owned_promotion)
      print -- "Promote only through the verified GitHub Release and LorisLabs site. No Reddit, email, ads or outreach."
      ;;
    local_artifact)
      print -- "Verify the exact local V6 artifact chain."
      ;;
  esac
}

prepare_gate() {
  init_state
  local gate=${1:-$(first_incomplete_gate)}
  [[ "$gate" != COMPLETE ]] || die "all gates are already PASS"
  is_gate "$gate" || die "unknown gate: $gate"
  require_prior_passes "$gate"
  [[ "$(gate_status "$gate")" != PASS ]] || die "gate already PASS: $gate"

  local anchor token packet
  anchor=$(anchor_for "$gate")
  token=$(approval_token "$gate")
  packet="$approval_dir/$gate.md"
  {
    print -- "# WebKitUI MCP V6 approval packet — $gate"
    print -- ""
    print -- "- Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    print -- "- Gate anchor SHA-256: \`$anchor\`"
    print -- "- Current status: \`$(gate_status "$gate")\`"
    print -- "- Exact action: $(gate_details "$gate")"
    print -- "- Rollback/correction: stop after one failure, retain redacted evidence, and restore the gate-specific prior version where applicable."
    print -- "- Excluded: every account, artifact, provider, destination and publication not named above."
    print -- ""
    print -- "Exact approval token:"
    print -- ""
    print -- "\`$token\`"
  } > "$packet"
  print -- "$packet"
}

resume_gate() {
  init_state
  local gate=${1:-$(first_incomplete_gate)}
  [[ "$gate" != COMPLETE ]] || die "all gates are already PASS"
  is_gate "$gate" || die "unknown gate: $gate"
  require_prior_passes "$gate"

  if [[ "$gate" == local_artifact ]]; then
    verify_local
    return
  fi

  local expected
  expected=$(approval_token "$gate")
  [[ "${WEBKITUI_V6_GATE_APPROVAL:-}" == "$expected" ]] \
    || die "refusing $gate: prepare the gate and provide its exact WEBKITUI_V6_GATE_APPROVAL token"

  set_gate_status "$gate" AUTHORIZED
  print -- "AUTHORIZED $gate"
  print -- "$(gate_details "$gate")"
  print -- "No provider mutation is embedded in this repository controller. Execute this exact gate with its authorized connector/workflow, then import a redacted receipt with:"
  print -- "  $script_path record $gate RECEIPT.json"
}

record_gate() {
  init_state
  [[ $# -eq 2 ]] || die "usage: $0 record GATE RECEIPT.json"
  local gate=$1
  local input=$2
  is_gate "$gate" || die "unknown gate: $gate"
  require_prior_passes "$gate"
  [[ -f "$input" ]] || die "missing receipt: $input"

  if is_external_gate "$gate"; then
    [[ "$(gate_status "$gate")" == AUTHORIZED ]] \
      || die "external gate $gate has no exact authorization recorded"
  fi

  local expected_anchor
  expected_anchor=$(anchor_for "$gate")
  jq -e \
    --arg gate "$gate" \
    --arg anchor "$expected_anchor" \
    '.schema_version == 1
      and .gate == $gate
      and .result == "PASS"
      and .anchor_sha256 == $anchor
      and (.evidence_class == "CURRENT-OBSERVED" or .evidence_class == "HUMAN-ATTESTED")
      and (.summary | type == "string" and length > 0)
      and (.completed_at | type == "string" and length > 0)' \
    "$input" >/dev/null || die "receipt does not match gate $gate and anchor $expected_anchor"

  jq -e '
    [paths(scalars) as $p | ($p[-1] | tostring | ascii_downcase)]
    | all(.[]; test("password|secret|bearer|api.?key|private.?key|cookie|otp|license.?key") | not)
  ' "$input" >/dev/null || die "receipt contains a forbidden secret-bearing field name"

  validate_gate_receipt "$gate" "$input"

  local stored="$receipt_dir/$gate.json"
  install -m 0600 "$input" "$stored"
  set_gate_status "$gate" PASS "$stored"
  print -- "PASS $gate"
  print -- "receipt=$stored"
  print -- "next=$(first_incomplete_gate)"
}

validate_gate_receipt() {
  local gate=$1
  local input=$2
  case "$gate" in
    local_artifact)
      jq -e '.artifact_sha256_verified == true
        and .installed_broker_sha256_verified == true
        and .active_socket_verified == true' "$input" >/dev/null \
        || die "local artifact receipt is missing exact verification fields"
      ;;
    credential_rotation)
      local expected_targets
      expected_targets=$(printf '%s\n' $credential_targets | jq -R . | jq -s 'sort')
      jq -e --argjson expected "$expected_targets" '.old_credentials_rejected == true
        and .new_credentials_working == true
        and .global_inheritance_removed == true
        and (.rotated_targets | type == "array" and sort == $expected)' "$input" >/dev/null \
        || die "credential receipt must prove new credentials and rejection of old credentials"
      ;;
    commerce_test)
      jq -e '
        .stripe_livemode == false
        and .currency == "eur"
        and .amount_total == 0
        and .amount_due == 0
        and .payment_status == "no_payment_required"
        and .payment_method_collected == false
        and .synthetic_customer_only == true
        and .brevo_synthetic_recipient_only == true
        and .live_price_created == false
        and .live_payment_link_created == false
        and .checkout_completed == true
        and .webhook_verified == true
        and .license_delivered == true
        and .activation_passed == true
        and .refresh_passed == true
        and .deactivation_passed == true
        and .cancellation_passed == true
        and .refund_evidence_class == "STRIPE_TEST_SIMULATION"
        and .dispute_evidence_class == "STRIPE_TEST_SIMULATION"
      ' "$input" >/dev/null || die "commerce receipt violates the sandbox zero-total contract"
      ;;
    physical_validation)
      jq -e '
        .voiceover_passed == true
        and .keyboard_passed == true
        and .receipt_reset_passed == true
        and .logout_login_passed == true
        and .reboot_performed == false
        and .keychain_reset_performed == false
      ' "$input" >/dev/null || die "physical receipt is incomplete or exceeds the authorized boundary"
      ;;
    public_release)
      jq -e \
        --arg commit "$app_commit" \
        --arg sha "$notarized_sha" '
        .repository == "lowrisk75/webkitui-mcp"
        and .tag == "v0.6.0"
        and .target_commit == $commit
        and .uploaded_asset_sha256 == $sha
        and .downloaded_asset_sha256 == $sha
        and .public_readback_verified == true
        and .signature_verified == true
        and .notarization_ticket_verified == true
      ' "$input" >/dev/null || die "public release receipt does not prove the exact public artifact"
      ;;
    website_publication)
      jq -e \
        --arg commit "$site_commit" '
        .site_commit == $commit
        and .canonical_url == "https://lorislab.fr/developers/webkitui-mcp/"
        and .public_price_eur_per_year == 299
        and .sales_mode == "access_on_request"
        and .live_checkout_present == false
        and .release_cta_verified == true
        and .public_bytes_verified == true
        and .required_urls_http_200 == true
      ' "$input" >/dev/null || die "website receipt violates the approved price, sales mode or public-byte contract"
      ;;
    final_g9)
      jq -e '
        .independent_fresh_audit == true
        and .verdict == "GO"
        and .unresolved_p0 == 0
        and .unresolved_p1 == 0
      ' "$input" >/dev/null || die "G9 receipt is not an independent fresh GO"
      ;;
    owned_promotion)
      jq -e '
        .github_release == true
        and .lorislabs_site == true
        and .reddit == false
        and .email == false
        and .ads == false
        and .outreach == false
      ' "$input" >/dev/null || die "promotion receipt exceeds the approved owned-channel scope"
      ;;
  esac
}

show_status() {
  init_state
  print -- "WebKitUI MCP V6 release loop"
  print -- "state=$state_file"
  print -- "sales=access_on_request stripe=sandbox_zero_total_only promotion=github_and_lorislabs_site_only"
  local gate
  for gate in $gates; do
    printf '%-24s %s\n' "$gate" "$(gate_status "$gate")"
  done
  print -- "next=$(first_incomplete_gate)"
}

usage() {
  cat <<'EOF'
usage: scripts/v6-release-loop.sh COMMAND [ARGS]

Commands:
  status                       Show every gate and the first incomplete gate.
  verify-local                 Verify the exact local V6 artifact chain.
  prepare [GATE]               Write the exact approval packet for the next gate.
  resume [GATE]                Verify the exact approval token; never mutates a provider itself.
  record GATE RECEIPT.json     Import a redacted, anchor-bound PASS receipt.

For resume, set WEBKITUI_V6_GATE_APPROVAL to the exact token from prepare.
EOF
}

need jq
need shasum

command=${1:-status}
case "$command" in
  status) show_status ;;
  verify-local) verify_local ;;
  prepare) prepare_gate "${2:-}" ;;
  resume) resume_gate "${2:-}" ;;
  record) shift; record_gate "$@" ;;
  help|-h|--help) usage ;;
  *) usage >&2; exit 64 ;;
esac
