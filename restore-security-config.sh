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

die() { local code="$1"; shift; printf 'ERROR: %s\n' "$*" >&2; exit "$code"; }
need() { command -v "$1" >/dev/null 2>&1 || die "$EXIT_MISSING_DEP" "Required command '$1' was not found."; }

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
  for c in sudo docker grep awk curl basename sleep seq head cut; do need "$c"; done

  sudo -v || die "$EXIT_MISSING_DEP" "sudo authentication failed."
  docker compose version >/dev/null 2>&1 || die "$EXIT_MISSING_DEP" "'docker compose' is unavailable."

  detect_compose

  sudo docker compose -f "$COMPOSE_FILE" config --services | grep -Fxq "$SERVICE" \
    || die "$EXIT_INVALID_INPUT" "Compose service '$SERVICE' was not found."

  sudo docker compose -f "$COMPOSE_FILE" ps --services --status running | grep -Fxq "$SERVICE" \
    || die "$EXIT_INVALID_INPUT" "Compose service '$SERVICE' is not running."

  sudo docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" test -x "$OPS_PATH" \
    || die "$EXIT_INVALID_INPUT" "OpenMetadata operations tool not found at $OPS_PATH."
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

[[ $# -eq 1 ]] || die "$EXIT_INVALID_INPUT" "Usage: $0 <security-config-backup.yaml>"
backup="$1"
[[ -f "$backup" ]] || die "$EXIT_INVALID_INPUT" "Backup file not found: $backup"

preflight

grep -q '^authenticationConfiguration:' "$backup" \
  || die "$EXIT_VERIFY" "Backup is missing authenticationConfiguration."
grep -q '^authorizerConfiguration:' "$backup" \
  || die "$EXIT_VERIFY" "Backup is missing authorizerConfiguration."

provider="$(awk -F': *' '/^  provider:/ {gsub(/"/,"",$2); print $2; exit}' "$backup")"

printf 'Backup: %s\n' "$backup"
printf 'Authentication provider to restore: %s\n' "${provider:-unknown}"
printf '\nThis replaces the current OpenMetadata authentication and authorization configuration.\n'
read -r -p "Type RESTORE to continue: " answer
[[ "$answer" == "RESTORE" ]] || { printf 'Cancelled.\n'; exit 0; }

remote="/tmp/restore-security-$(basename "$backup")"

sudo docker compose -f "$COMPOSE_FILE" cp "$backup" "$SERVICE:$remote" >/dev/null \
  || die "$EXIT_APPLY" "Could not copy backup into the OpenMetadata container."

printf 'CONFIRM\n' | sudo docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" \
  "$OPS_PATH" update-security-config --config-file "$remote" \
  || die "$EXIT_APPLY" "OpenMetadata rejected the backup configuration."

sudo docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" rm -f "$remote" >/dev/null 2>&1 || true

sudo docker compose -f "$COMPOSE_FILE" restart "$SERVICE" >/dev/null \
  || die "$EXIT_APPLY" "Failed to restart '$SERVICE'."

printf 'Waiting for OpenMetadata to become healthy...\n'
wait_for_health || die "$EXIT_VERIFY" "OpenMetadata did not become healthy within 90 seconds."

auth="$(curl -fsS --max-time 10 "$LOCAL_URL/api/v1/system/config/auth")" \
  || die "$EXIT_VERIFY" "Could not read the authentication configuration after restore."

actual="$(printf '%s' "$auth" | grep -o '"provider":"[^"]*"' | head -n1 | cut -d'"' -f4 || true)"
printf 'Restore complete. Active provider: %s\n' "${actual:-unknown}"
