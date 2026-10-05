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
LOG_DIR="${OM_LOG_DIR:-./logs}"
LOG_FILE=""

die() { local code="$1"; shift; printf 'ERROR: %s\n' "$*" >&2; exit "$code"; }
need() { command -v "$1" >/dev/null 2>&1 || die "$EXIT_MISSING_DEP" "Required command '$1' was not found."; }

show_failure() {
  local code="$1" message="$2"
  printf 'ERROR: %s\n' "$message" >&2
  [[ -n "$LOG_FILE" ]] && printf 'Log: %s\n' "$LOG_FILE" >&2
  exit "$code"
}

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
  for c in sudo docker grep awk curl basename sleep seq head cut mktemp cat rm date mkdir chmod; do need "$c"; done

  sudo -v >/dev/null 2>&1 || die "$EXIT_MISSING_DEP" "sudo authentication failed."
  docker compose version >/dev/null 2>&1 || die "$EXIT_MISSING_DEP" "'docker compose' is unavailable."

  detect_compose

  sudo docker compose -f "$COMPOSE_FILE" config --services 2>/dev/null | grep -Fxq "$SERVICE" \
    || die "$EXIT_INVALID_INPUT" "Compose service '$SERVICE' was not found."

  sudo docker compose -f "$COMPOSE_FILE" ps --services --status running 2>/dev/null | grep -Fxq "$SERVICE" \
    || die "$EXIT_INVALID_INPUT" "Compose service '$SERVICE' is not running."

  sudo docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" test -x "$OPS_PATH" >/dev/null 2>&1 \
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

printf '[1/5] Preflight checks... '
preflight
printf 'OK\n'

mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR"
run_stamp="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR%/}/restore-security-config-${run_stamp}.log"
: >"$LOG_FILE"
chmod 600 "$LOG_FILE"

grep -q '^authenticationConfiguration:' "$backup" \
  || die "$EXIT_VERIFY" "Backup is missing authenticationConfiguration."
grep -q '^authorizerConfiguration:' "$backup" \
  || die "$EXIT_VERIFY" "Backup is missing authorizerConfiguration."

provider="$(awk -F': *' '/^  provider:/ {gsub(/"/,"",$2); print $2; exit}' "$backup")"

printf '\nBackup: %s\n' "$backup"
printf 'Authentication provider to restore: %s\n' "${provider:-unknown}"
printf '\nThis replaces the current OpenMetadata authentication and authorization configuration.\n'
read -r -p "Type RESTORE to continue: " answer
[[ "$answer" == "RESTORE" ]] || { printf 'Cancelled.\n'; exit 0; }

remote="/tmp/restore-security-$(basename "$backup")"

printf '[2/5] Copying backup into OpenMetadata... '
printf '%s\n' '=== Copy backup into OpenMetadata ===' >>"$LOG_FILE"
if ! sudo docker compose -f "$COMPOSE_FILE" cp "$backup" "$SERVICE:$remote" >>"$LOG_FILE" 2>&1; then
  printf 'FAILED\n'
  show_failure "$EXIT_APPLY" "Could not copy backup into the OpenMetadata container."
fi
printf 'OK\n'

printf '%s\n' '=== Apply restored security configuration ===' >>"$LOG_FILE"
printf '[3/5] Applying security configuration... '
if ! { printf 'CONFIRM\n' | sudo docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" \
  "$OPS_PATH" update-security-config --config-file "$remote"; } >>"$LOG_FILE" 2>&1; then
  printf 'FAILED\n'
  show_failure "$EXIT_APPLY" "OpenMetadata rejected the backup configuration."
fi
printf 'OK\n'

sudo docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" rm -f "$remote" >/dev/null 2>&1 || true

printf '%s\n' '=== Restart OpenMetadata ===' >>"$LOG_FILE"
printf '[4/5] Restarting OpenMetadata... '
if ! sudo docker compose -f "$COMPOSE_FILE" restart "$SERVICE" >>"$LOG_FILE" 2>&1; then
  printf 'FAILED\n'
  show_failure "$EXIT_APPLY" "Failed to restart '$SERVICE'."
fi
printf 'OK\n'

printf '[5/5] Verifying restored authentication... '
if ! wait_for_health; then
  printf 'FAILED\n'
  show_failure "$EXIT_VERIFY" "OpenMetadata did not become healthy within 90 seconds."
fi

auth="$(curl -fsS --max-time 10 "$LOCAL_URL/api/v1/system/config/auth")" \
  || { printf 'FAILED\n'; die "$EXIT_VERIFY" "Could not read the authentication configuration after restore."; }

actual="$(printf '%s' "$auth" | grep -o '"provider":"[^"]*"' | head -n1 | cut -d'"' -f4 || true)"
[[ -n "$actual" ]] || { printf 'FAILED\n'; die "$EXIT_VERIFY" "Could not determine the active authentication provider."; }
printf 'OK\n'

printf '\nSUCCESS: Security configuration restored.\n'
printf 'Active provider: %s\n' "$actual"
printf 'Log: %s\n' "$LOG_FILE"
