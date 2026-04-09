#!/usr/bin/env bash
set -euo pipefail

MASTER_TOKEN_FILE="$HOME/.config/cloudflare/master-token"
API="https://api.cloudflare.com/client/v4"

die() { echo "ERROR: $*" >&2; exit 1; }

[[ -f "$MASTER_TOKEN_FILE" ]] || die "Master token not found at $MASTER_TOKEN_FILE"
MASTER_TOKEN="$(cat "$MASTER_TOKEN_FILE")"
[[ -n "$MASTER_TOKEN" ]] || die "Master token is empty"

auth_header="Authorization: Bearer $MASTER_TOKEN"

usage() {
  cat <<EOF
Usage:
  cf-token create <token-name> --permissions <permissions> --zone <zone>
  cf-token list
  cf-token verify <token>
  cf-token delete <token-id>
EOF
  exit 1
}

cmd_list() {
  curl -sf -H "$auth_header" -H "Content-Type: application/json" \
    "$API/user/tokens" | jq -r '.result[] | "\(.id)  \(.name)  \(.status)"'
}

cmd_verify() {
  local token="${1:?missing token}"
  curl -sf -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
    "$API/user/tokens/verify" | jq .
}

cmd_delete() {
  local token_id="${1:?missing token-id}"
  curl -sf -X DELETE -H "$auth_header" -H "Content-Type: application/json" \
    "$API/user/tokens/$token_id" | jq .
}

cmd_create() {
  local name="${1:?missing token-name}"
  shift
  local permissions="" zone=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --permissions) permissions="$2"; shift 2 ;;
      --zone) zone="$2"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done
  [[ -n "$permissions" ]] || die "--permissions required"
  [[ -n "$zone" ]] || die "--zone required"

  # Resolve zone ID (master token may lack zone:read, fall back to all-zones wildcard)
  local zone_id zone_resource
  zone_id=$(curl -sf -H "$auth_header" -H "Content-Type: application/json" \
    "$API/zones?name=$zone" | jq -r '.result[0].id // empty' 2>/dev/null || true)
  if [[ -n "$zone_id" ]]; then
    zone_resource="com.cloudflare.api.account.zone.$zone_id"
  else
    echo "WARN: Cannot resolve zone ID for '$zone' (token may lack zone:read). Granting access to all zones." >&2
    zone_resource="com.cloudflare.api.account.zone.*"
  fi

  # Parse permissions: format "resource:level" e.g. "zone.dns:edit"
  local resource level perm_key
  IFS=':' read -r resource level <<< "$permissions"
  # Convert dot notation: zone.dns -> #zone:dns
  # Cloudflare permission key format: com.cloudflare.api.account.zone.dns
  case "$resource" in
    zone.dns) perm_key="com.cloudflare.api.token.permission.zone.dns" ;;
    zone.*) perm_key="com.cloudflare.api.token.permission.${resource}" ;;
    *) perm_key="com.cloudflare.api.token.permission.${resource}" ;;
  esac

  # Map level to permission group ID via known IDs
  # We'll use the permissions_groups API to find the right one
  local pg_id
  pg_id=$(curl -sf -H "$auth_header" -H "Content-Type: application/json" \
    "$API/user/tokens/permission_groups" | jq -r --arg r "$resource" --arg l "$level" '
    .result[] | select(
      (.name | ascii_downcase | test("dns")) and
      (.name | ascii_downcase | test($l))
    ) | .id' | head -1)
  [[ -n "$pg_id" ]] || die "Could not find permission group for $permissions"

  local payload
  payload=$(jq -n \
    --arg name "$name" \
    --arg pg_id "$pg_id" \
    --arg zone_resource "$zone_resource" \
    '{
      name: $name,
      policies: [{
        effect: "allow",
        resources: { ($zone_resource): "*" },
        permission_groups: [{ id: $pg_id }]
      }]
    }')

  local result
  result=$(curl -sf -X POST -H "$auth_header" -H "Content-Type: application/json" \
    -d "$payload" "$API/user/tokens")

  local success
  success=$(echo "$result" | jq -r '.success')
  if [[ "$success" == "true" ]]; then
    local token_value token_id token_name
    token_value=$(echo "$result" | jq -r '.result.value')
    token_id=$(echo "$result" | jq -r '.result.id')
    token_name=$(echo "$result" | jq -r '.result.name')
    echo "TOKEN_CREATED"
    echo "ID: $token_id"
    echo "NAME: $token_name"
    echo "VALUE: $token_value"
  else
    echo "$result" | jq .
    exit 1
  fi
}

[[ $# -ge 1 ]] || usage

case "$1" in
  create) shift; cmd_create "$@" ;;
  list) cmd_list ;;
  verify) shift; cmd_verify "$@" ;;
  delete) shift; cmd_delete "$@" ;;
  *) usage ;;
esac
