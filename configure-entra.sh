#!/usr/bin/env bash
set -euo pipefail

EXIT_GENERAL=1
EXIT_MISSING_DEP=2
EXIT_INVALID_INPUT=3
EXIT_APPLY=4
EXIT_VERIFY=5

SERVICE="${OM_SERVICE:-openmetadata-server}"
OPS_PATH="${OM_OPS_PATH:-/opt/openmetadata/bootstrap/openmetadata-ops.sh}"
LOCAL_URL="${OM_LOCAL_URL:-http://127.0.0.1:8585}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { local code="$1"; shift; printf 'ERROR: %s\n' "$*" >&2; exit "$code"; }
need() { command -v "$1" >/dev/null 2>&1 || die "$EXIT_MISSING_DEP" "Required command '$1' was not found."; }
uuid_ok() { [[ "$1" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; }
yaml_escape() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; printf '%s' "$s"; }

detect_compose() {
  if [[ -n "${COMPOSE_FILE:-}" ]]; then
    [[ -f "$COMPOSE_FILE" ]] || die "$EXIT_INVALID_INPUT" "COMPOSE_FILE does not exist: $COMPOSE_FILE"
    return
  fi

  local f
  for f in docker-compose-postgres.yml compose.yml compose.yaml docker-compose.yml docker-compose.yaml; do
    if [[ -f "$f" ]]; then
      COMPOSE_FILE="$f"
      return
    fi
  done

  die "$EXIT_INVALID_INPUT" "No Compose file found. Set COMPOSE_FILE or run from the OpenMetadata Docker directory."
}

preflight() {
  local c
  for c in sudo docker grep awk curl mktemp chmod rm sleep dirname seq; do need "$c"; done

  sudo -v || die "$EXIT_MISSING_DEP" "sudo authentication failed."
  docker compose version >/dev/null 2>&1 || die "$EXIT_MISSING_DEP" "'docker compose' is unavailable."

  detect_compose

  sudo docker compose -f "$COMPOSE_FILE" config --services | grep -Fxq "$SERVICE" \
    || die "$EXIT_INVALID_INPUT" "Compose service '$SERVICE' was not found in $COMPOSE_FILE."

  sudo docker compose -f "$COMPOSE_FILE" ps --services --status running | grep -Fxq "$SERVICE" \
    || die "$EXIT_INVALID_INPUT" "Compose service '$SERVICE' is not running."

  sudo docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" test -x "$OPS_PATH" \
    || die "$EXIT_INVALID_INPUT" "OpenMetadata operations tool not found at $OPS_PATH."

  [[ -x "$SCRIPT_DIR/backup-security-config.sh" ]] \
    || die "$EXIT_INVALID_INPUT" "backup-security-config.sh must exist and be executable beside this script."
}

wait_for_health() {
  local i
  for i in $(seq 1 45); do
    if curl -fsS --max-time 3 "$LOCAL_URL/healthcheck" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

preflight

printf 'OpenMetadata Microsoft Entra ID configuration\n'
printf '%s\n' '---------------------------------------------'

read -r -p "Public OpenMetadata URL (for example https://metadata.example.com): " PUBLIC_URL
PUBLIC_URL="${PUBLIC_URL%/}"
[[ "$PUBLIC_URL" =~ ^https://[^[:space:]]+$ ]] \
  || die "$EXIT_INVALID_INPUT" "Public URL must be an https:// URL without spaces."

read -r -p "Microsoft Entra tenant ID: " TENANT_ID
uuid_ok "$TENANT_ID" || die "$EXIT_INVALID_INPUT" "Tenant ID does not look like a UUID."

read -r -p "Microsoft Entra application (client) ID: " CLIENT_ID
uuid_ok "$CLIENT_ID" || die "$EXIT_INVALID_INPUT" "Client ID does not look like a UUID."

read -r -s -p "Microsoft Entra client secret VALUE: " CLIENT_SECRET
printf '\n'
[[ -n "$CLIENT_SECRET" ]] || die "$EXIT_INVALID_INPUT" "Client secret may not be empty."

CALLBACK_URL="$PUBLIC_URL/callback"
DISCOVERY_URI="https://login.microsoftonline.com/$TENANT_ID/v2.0/.well-known/openid-configuration"
AUTHORITY="https://login.microsoftonline.com/$TENANT_ID"
JWKS_URL="https://login.microsoftonline.com/$TENANT_ID/discovery/v2.0/keys"
SELF_JWKS="$PUBLIC_URL/api/v1/system/config/jwks"

printf 'Checking Entra discovery endpoint...\n'
curl -fsS --max-time 10 "$DISCOVERY_URI" >/dev/null \
  || die "$EXIT_VERIFY" "Could not reach the Entra OpenID discovery endpoint."

printf 'Creating a rollback backup before making changes...\n'
backup="$(COMPOSE_FILE="$COMPOSE_FILE" OM_SERVICE="$SERVICE" OM_OPS_PATH="$OPS_PATH" \
  "$SCRIPT_DIR/backup-security-config.sh" --quiet)" \
  || die "$EXIT_APPLY" "Could not create the required rollback backup."

[[ -f "$backup" ]] || die "$EXIT_VERIFY" "Backup script reported a path that does not exist: $backup"

tmp="$(mktemp)"
secret_tmp="$(mktemp)"
trap 'rm -f "$tmp" "$secret_tmp"' EXIT
chmod 600 "$tmp" "$secret_tmp"
printf '%s' "$(yaml_escape "$CLIENT_SECRET")" > "$secret_tmp"
unset CLIENT_SECRET

export PUBLIC_URL TENANT_ID CLIENT_ID CALLBACK_URL DISCOVERY_URI AUTHORITY JWKS_URL SELF_JWKS SECRET_FILE="$secret_tmp"

awk '
BEGIN {
  in_oidc=0
  skip_pubkeys=0
  if ((getline secret < ENVIRON["SECRET_FILE"]) < 0) exit 90
  close(ENVIRON["SECRET_FILE"])
}
function emit_oidc() {
  print "  oidcConfiguration:"
  print "    type: \"azure\""
  print "    id: \"" ENVIRON["CLIENT_ID"] "\""
  print "    secret: \"" secret "\""
  print "    scope: \"openid email profile offline_access\""
  print "    discoveryUri: \"" ENVIRON["DISCOVERY_URI"] "\""
  print "    useNonce: \"true\""
  print "    preferredJwsAlgorithm: \"RS256\""
  print "    responseType: \"code\""
  print "    disablePkce: true"
  print "    maxClockSkew: \"\""
  print "    clientAuthenticationMethod: \"client_secret_post\""
  print "    tokenValidity: 3600"
  print "    customParams: {}"
  print "    tenant: \"" ENVIRON["TENANT_ID"] "\""
  print "    serverUrl: \"" ENVIRON["PUBLIC_URL"] "\""
  print "    callbackUrl: \"" ENVIRON["CALLBACK_URL"] "\""
  print "    maxAge: \"0\""
  print "    prompt: \"consent\""
  print "    sessionExpiry: 604800"
}
{
  if (in_oidc) {
    if ($0 ~ /^  [A-Za-z][A-Za-z0-9]*:/) {
      in_oidc=0
    } else {
      next
    }
  }

  if (skip_pubkeys) {
    if ($0 ~ /^  - /) next
    skip_pubkeys=0
  }

  if ($0 ~ /^  clientType:/) { print "  clientType: \"confidential\""; next }
  if ($0 ~ /^  provider:/) { print "  provider: \"azure\""; next }
  if ($0 ~ /^  responseType:/) { print "  responseType: \"code\""; next }
  if ($0 ~ /^  providerName:/) { print "  providerName: \"Azure\""; next }
  if ($0 ~ /^  publicKeyUrls:/) {
    print "  publicKeyUrls:"
    print "  - \"" ENVIRON["SELF_JWKS"] "\""
    print "  - \"" ENVIRON["JWKS_URL"] "\""
    skip_pubkeys=1
    next
  }
  if ($0 ~ /^  authority:/) { print "  authority: \"" ENVIRON["AUTHORITY"] "\""; next }
  if ($0 ~ /^  clientId:/) { print "  clientId: \"" ENVIRON["CLIENT_ID"] "\""; next }
  if ($0 ~ /^  callbackUrl:/) { print "  callbackUrl: \"" ENVIRON["CALLBACK_URL"] "\""; next }
  if ($0 ~ /^  oidcConfiguration:/) { emit_oidc(); in_oidc=1; next }
  if ($0 ~ /^  forceSecureSessionCookie:/) { print "  forceSecureSessionCookie: true"; next }

  print
}
' "$backup" > "$tmp" || die "$EXIT_APPLY" "Could not generate the Entra security configuration."

grep -q '^  provider: "azure"$' "$tmp" || die "$EXIT_VERIFY" "Generated config is missing provider=azure."
grep -q '^  clientType: "confidential"$' "$tmp" || die "$EXIT_VERIFY" "Generated config is missing confidential client type."
grep -Fq "    discoveryUri: \"$DISCOVERY_URI\"" "$tmp" || die "$EXIT_VERIFY" "Generated config has an unexpected discovery URI."
grep -Fq '    scope: "openid email profile offline_access"' "$tmp" || die "$EXIT_VERIFY" "Generated config is missing offline_access."
grep -q '^authorizerConfiguration:' "$tmp" || die "$EXIT_VERIFY" "Generated config lost authorizerConfiguration."

printf '\nReady to apply:\n'
printf '  Compose file : %s\n' "$COMPOSE_FILE"
printf '  Service      : %s\n' "$SERVICE"
printf '  Public URL   : %s\n' "$PUBLIC_URL"
printf '  Tenant ID    : %s\n' "$TENANT_ID"
printf '  Client ID    : %s\n' "$CLIENT_ID"
printf '  Callback URL : %s\n' "$CALLBACK_URL"
printf '  Backup       : %s\n' "$backup"
printf '  Secret       : [hidden]\n\n'

read -r -p "Type CONFIRM to update OpenMetadata authentication: " answer
[[ "$answer" == "CONFIRM" ]] || { printf 'Cancelled. Backup remains at %s\n' "$backup"; exit 0; }

remote="/tmp/security-config-entra-$$.yaml"

sudo docker compose -f "$COMPOSE_FILE" cp "$tmp" "$SERVICE:$remote" >/dev/null \
  || die "$EXIT_APPLY" "Could not copy generated config into the OpenMetadata container."

printf 'CONFIRM\n' | sudo docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" \
  "$OPS_PATH" update-security-config --config-file "$remote" \
  || die "$EXIT_APPLY" "OpenMetadata rejected the generated Entra configuration."

sudo docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" rm -f "$remote" >/dev/null 2>&1 || true

sudo docker compose -f "$COMPOSE_FILE" restart "$SERVICE" >/dev/null \
  || die "$EXIT_APPLY" "Failed to restart '$SERVICE'."

printf 'Waiting for OpenMetadata to become healthy...\n'
wait_for_health \
  || die "$EXIT_VERIFY" "OpenMetadata did not become healthy within 90 seconds. Restore with: ./restore-security-config.sh '$backup'"

auth="$(curl -fsS --max-time 10 "$LOCAL_URL/api/v1/system/config/auth")" \
  || die "$EXIT_VERIFY" "Could not read the auth endpoint after restart. Restore with: ./restore-security-config.sh '$backup'"

printf '%s' "$auth" | grep -Fq '"provider":"azure"' \
  || die "$EXIT_VERIFY" "Auth endpoint does not report provider=azure. Restore with: ./restore-security-config.sh '$backup'"
printf '%s' "$auth" | grep -Fq '"clientType":"confidential"' \
  || die "$EXIT_VERIFY" "Auth endpoint does not report clientType=confidential."
printf '%s' "$auth" | grep -Fq "\"callbackUrl\":\"$CALLBACK_URL\"" \
  || die "$EXIT_VERIFY" "Auth endpoint callback URL does not match $CALLBACK_URL."

printf '\nSUCCESS: Microsoft Entra ID authentication is configured.\n'
printf 'Rollback backup: %s\n' "$backup"

if printf '%s' "$auth" | grep -Fq '"forceSecureSessionCookie":false'; then
  printf 'WARNING: OpenMetadata reports forceSecureSessionCookie=false even though the generated YAML requested true.\n' >&2
fi
