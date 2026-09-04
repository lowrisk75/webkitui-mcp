#!/bin/zsh
set -euo pipefail

project_root=${0:A:h:h}
loop="$project_root/scripts/v6-release-loop.sh"
test_root=$(mktemp -d /private/tmp/webkitui-v6-loop-tests.XXXXXX)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

export WEBKITUI_V6_STATE_DIR="$test_root/state"

fail() {
  print -u2 -- "FAIL: $*"
  exit 1
}

expect_failure() {
  local expected=$1
  shift
  local output
  if output=$("$@" 2>&1); then
    fail "command unexpectedly succeeded: $*"
  fi
  [[ "$output" == *"$expected"* ]] || fail "missing failure text '$expected': $output"
}

expect_output() {
  local expected=$1
  shift
  local output
  output=$("$@")
  [[ "$output" == *"$expected"* ]] || fail "missing output '$expected': $output"
}

expect_output "next=local_artifact" "$loop" status
expect_failure "out of order" "$loop" prepare commerce_test

expect_output "PASS local_artifact" "$loop" verify-local
expect_output "next=credential_rotation" "$loop" status
expect_failure "exact WEBKITUI_V6_GATE_APPROVAL" "$loop" resume credential_rotation

packet=$("$loop" prepare credential_rotation)
[[ -f "$packet" ]] || fail "approval packet was not created"
token=$(sed -n 's/^`\(GO-WEBKITUI-V6-credential_rotation-.*\)`$/\1/p' "$packet")
[[ -n "$token" ]] || fail "approval token was not found"

output=$(WEBKITUI_V6_GATE_APPROVAL="$token" "$loop" resume credential_rotation)
[[ "$output" == *"AUTHORIZED credential_rotation"* ]] \
  || fail "credential rotation was not authorized: $output"

anchor=$(jq -r '.gates.credential_rotation.anchor_sha256' "$WEBKITUI_V6_STATE_DIR/state.json")
bad_receipt="$test_root/bad.json"
jq -n --arg gate credential_rotation '{
  schema_version: 1,
  gate: $gate,
  result: "PASS",
  anchor_sha256: "wrong",
  evidence_class: "CURRENT-OBSERVED",
  summary: "Synthetic receipt for a negative test.",
  completed_at: "2026-08-31T00:00:00Z"
}' > "$bad_receipt"
expect_failure "does not match" "$loop" record credential_rotation "$bad_receipt"

secret_receipt="$test_root/secret.json"
jq -n --arg gate credential_rotation --arg anchor "$anchor" '{
  schema_version: 1,
  gate: $gate,
  result: "PASS",
  anchor_sha256: $anchor,
  evidence_class: "CURRENT-OBSERVED",
  summary: "Synthetic receipt for a negative test.",
  completed_at: "2026-08-31T00:00:00Z",
  api_key: "must-not-be-imported"
}' > "$secret_receipt"
expect_failure "forbidden secret-bearing" "$loop" record credential_rotation "$secret_receipt"

good_receipt="$test_root/good.json"
jq -n --arg gate credential_rotation --arg anchor "$anchor" '{
  schema_version: 1,
  gate: $gate,
  result: "PASS",
  anchor_sha256: $anchor,
  evidence_class: "CURRENT-OBSERVED",
  summary: "Synthetic redacted receipt for controller validation only.",
  completed_at: "2026-08-31T00:00:00Z",
  old_credentials_rejected: true,
  new_credentials_working: true,
  global_inheritance_removed: true,
  rotated_targets: [
    "apple_portal_app_store_connect",
    "cloudflare",
    "cloudkit_management",
    "github",
    "hostinger",
    "mailcow",
    "local_mcp",
    "postgresql_jwt",
    "proxmox",
    "tailscale",
    "tavily",
    "x_twitter",
    "bmc",
    "opnsense",
    "zyxel"
  ]
}' > "$good_receipt"
expect_output "next=commerce_test" "$loop" record credential_rotation "$good_receipt"

expect_output "next=commerce_test" "$loop" status

commerce_packet=$("$loop" prepare commerce_test)
commerce_token=$(sed -n 's/^`\(GO-WEBKITUI-V6-commerce_test-.*\)`$/\1/p' "$commerce_packet")
[[ -n "$commerce_token" ]] || fail "commerce approval token was not found"
WEBKITUI_V6_GATE_APPROVAL="$commerce_token" "$loop" resume commerce_test >/dev/null

commerce_bad="$test_root/commerce-bad.json"
commerce_anchor=$(jq -r '.gates.commerce_test.anchor_sha256' "$WEBKITUI_V6_STATE_DIR/state.json")
jq -n --arg anchor "$commerce_anchor" '{
  schema_version: 1,
  gate: "commerce_test",
  result: "PASS",
  anchor_sha256: $anchor,
  evidence_class: "CURRENT-OBSERVED",
  summary: "Synthetic non-zero receipt for a negative test.",
  completed_at: "2026-08-31T00:00:00Z",
  stripe_livemode: false,
  currency: "eur",
  amount_total: 1,
  amount_due: 0,
  payment_status: "no_payment_required",
  payment_method_collected: false,
  synthetic_customer_only: true,
  brevo_synthetic_recipient_only: true,
  live_price_created: false,
  live_payment_link_created: false,
  checkout_completed: true,
  webhook_verified: true,
  license_delivered: true,
  activation_passed: true,
  refresh_passed: true,
  deactivation_passed: true,
  cancellation_passed: true,
  refund_evidence_class: "STRIPE_TEST_SIMULATION",
  dispute_evidence_class: "STRIPE_TEST_SIMULATION"
}' > "$commerce_bad"
expect_failure "zero-total contract" "$loop" record commerce_test "$commerce_bad"

print -- "PASS v6-release-loop fail-closed tests"
