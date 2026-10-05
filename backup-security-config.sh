#!/usr/bin/env bash
set -euo pipefail

EXIT_GENERAL=1
EXIT_MISSING_DEP=2
EXIT_INVALID_INPUT=3
EXIT_APPLY=4
EXIT_VERIFY=5

SERVICE="${OM_SERVICE:-openmetadata-server}"
OPS_PATH="${OM_OPS_PATH:-/opt/openmetadata/bootstrap/openmetadata-ops.sh}"
BACKUP_DIR="${OM_BACKUP_DIR:-./backups}"
LOG_DIR="${OM_LOG_DIR:-./logs}"
QUIET=0
LOG_FILE=""

log() { [[ "$QUIET" -eq 1 ]] || printf '%s\n' "$*"; }
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
  [[ -n "${BASH_VERSION:-}" ]] || die "$EXIT_MISSING_DEP" "This script requires Bash."
  local c
  for c in sudo docker grep date mkdir chmod rm mktemp cat id chown; do need "$c"; done

  sudo -v >/dev/null 2>&1 || die "$EXIT_MISSING_DEP" "sudo authentication failed."
  docker compose version >/dev/null 2>&1 || die "$EXIT_MISSING_DEP" "'docker compose' is unavailable."

  detect_compose

  sudo docker compose -f "$COMPOSE_FILE" config --services 2>/dev/null | grep -Fxq "$SERVICE" \
    || die "$EXIT_INVALID_INPUT" "Compose service '$SERVICE' was not found in $COMPOSE_FILE."

  sudo docker compose -f "$COMPOSE_FILE" ps --services --status running 2>/dev/null | grep -Fxq "$SERVICE" \
    || die "$EXIT_INVALID_INPUT" "Compose service '$SERVICE' is not running."

  sudo docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" test -x "$OPS_PATH" >/dev/null 2>&1 \
    || die "$EXIT_INVALID_INPUT" "OpenMetadata operations tool not found or not executable at $OPS_PATH."
}

if [[ "${1:-}" == "--quiet" ]]; then
  QUIET=1
  shift
fi

[[ $# -eq 0 ]] || die "$EXIT_INVALID_INPUT" "Usage: $0 [--quiet]"

preflight

mkdir -p "$BACKUP_DIR" "$LOG_DIR"
chmod 700 "$BACKUP_DIR" "$LOG_DIR"

stamp="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR%/}/backup-security-config-${stamp}.log"
: >"$LOG_FILE"
chmod 600 "$LOG_FILE"
remote="/tmp/openmetadata-security-${stamp}-$$.yaml"
backup="${BACKUP_DIR%/}/security-config-${stamp}.yaml"

log "[1/3] Exporting security configuration..."

printf '%s\n' '=== Export security configuration ===' >>"$LOG_FILE"
if ! sudo docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" \
  "$OPS_PATH" get-security-config --output-file "$remote" >>"$LOG_FILE" 2>&1; then
  show_failure "$EXIT_APPLY" "OpenMetadata security configuration export failed."
fi
log "[1/3] Exporting security configuration... OK"

printf '%s\n' '=== Copy exported configuration ===' >>"$LOG_FILE"
log "[2/3] Saving backup..."
if ! sudo docker compose -f "$COMPOSE_FILE" cp "$SERVICE:$remote" "$backup" >>"$LOG_FILE" 2>&1; then
  show_failure "$EXIT_APPLY" "Could not copy exported security configuration to $backup."
fi

sudo docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" rm -f "$remote" >/dev/null 2>&1 || true

if ! sudo chown "$(id -u):$(id -g)" "$backup" >>"$LOG_FILE" 2>&1; then
  show_failure "$EXIT_APPLY" "Could not set backup ownership on $backup."
fi
chmod 600 "$backup"
log "[2/3] Saving backup... OK"

log "[3/3] Verifying backup..."
grep -q '^authenticationConfiguration:' "$backup" \
  || die "$EXIT_VERIFY" "Backup is missing authenticationConfiguration."
grep -q '^authorizerConfiguration:' "$backup" \
  || die "$EXIT_VERIFY" "Backup is missing authorizerConfiguration."
log "[3/3] Verifying backup... OK"

if [[ "$QUIET" -eq 1 ]]; then
  printf '%s\n' "$backup"
else
  printf '\nSUCCESS: Security configuration backup created.\n'
  printf 'Backup: %s\n' "$backup"
  printf 'Log: %s\n' "$LOG_FILE"
fi
