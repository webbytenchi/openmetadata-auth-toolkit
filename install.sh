#!/usr/bin/env bash
set -euo pipefail

REPO="webbytenchi/openmetadata-auth-toolkit"
REF="${OM_AUTH_TOOLKIT_REF:-main}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN_HOME="${OM_AUTH_BIN_DIR:-$HOME/.local/bin}"
INSTALL_DIR="${OM_AUTH_INSTALL_DIR:-$DATA_HOME/openmetadata-auth-toolkit}"
CONFIG_DIR="${OM_AUTH_CONFIG_DIR:-$CONFIG_HOME/openmetadata-auth-toolkit}"
CONFIG_FILE="$CONFIG_DIR/config"
COMPOSE_ARG=""
SOURCE_DIR=""
TMP_DIR=""

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' was not found."; }

usage() {
  cat <<'EOF'
Usage: ./install.sh [--compose-file /path/to/compose.yml]

Installs:
  ~/.local/bin/om-auth
  ~/.local/share/openmetadata-auth-toolkit/
  ~/.config/openmetadata-auth-toolkit/config

Environment overrides:
  OM_AUTH_BIN_DIR
  OM_AUTH_INSTALL_DIR
  OM_AUTH_CONFIG_DIR
  OM_AUTH_TOOLKIT_REF
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --compose-file)
      [[ $# -ge 2 ]] || die "--compose-file requires a path."
      COMPOSE_ARG="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

for c in mkdir chmod cp install printf; do need "$c"; done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [[ -n "$SCRIPT_DIR"    && -f "$SCRIPT_DIR/backup-security-config.sh"    && -f "$SCRIPT_DIR/configure-entra.sh"    && -f "$SCRIPT_DIR/restore-security-config.sh"    && -f "$SCRIPT_DIR/om-auth" ]]; then
  SOURCE_DIR="$SCRIPT_DIR"
else
  need curl
  need mktemp
  TMP_DIR="$(mktemp -d)"
  trap '[[ -n "$TMP_DIR" ]] && rm -rf "$TMP_DIR"' EXIT
  RAW_BASE="https://raw.githubusercontent.com/$REPO/$REF"

  printf 'Downloading OpenMetadata Auth Toolkit...\n'
  for file in backup-security-config.sh configure-entra.sh restore-security-config.sh uninstall.sh om-auth; do
    curl -fsSL "$RAW_BASE/$file" -o "$TMP_DIR/$file"       || die "Could not download $file from $REPO ($REF)."
  done
  SOURCE_DIR="$TMP_DIR"
fi

detect_compose() {
  local candidate

  if [[ -n "$COMPOSE_ARG" ]]; then
    [[ -f "$COMPOSE_ARG" ]] || die "Compose file does not exist: $COMPOSE_ARG"
    printf '%s\n' "$(cd "$(dirname "$COMPOSE_ARG")" && pwd)/$(basename "$COMPOSE_ARG")"
    return
  fi

  if [[ -n "${COMPOSE_FILE:-}" && -f "$COMPOSE_FILE" ]]; then
    printf '%s\n' "$(cd "$(dirname "$COMPOSE_FILE")" && pwd)/$(basename "$COMPOSE_FILE")"
    return
  fi

  for candidate in     "$PWD/docker-compose-postgres.yml"     "$PWD/compose.yml"     "$PWD/compose.yaml"     "$PWD/docker-compose.yml"     "$PWD/docker-compose.yaml"     "$HOME/openmetadata-docker/docker-compose-postgres.yml"     "$HOME/openmetadata-docker/compose.yml"     "$HOME/openmetadata-docker/compose.yaml"     "$HOME/openmetadata-docker/docker-compose.yml"     "$HOME/openmetadata-docker/docker-compose.yaml"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  if [[ -t 0 ]]; then
    printf 'OpenMetadata Compose file was not auto-detected.\n' >&2
    read -r -p "Compose file path (leave blank to configure later): " candidate
    if [[ -n "$candidate" ]]; then
      [[ -f "$candidate" ]] || die "Compose file does not exist: $candidate"
      printf '%s\n' "$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")"
      return
    fi
  fi

  printf '\n'
}

printf '[1/4] Installing toolkit files... '
mkdir -p "$INSTALL_DIR" "$BIN_HOME" "$CONFIG_DIR"
chmod 700 "$INSTALL_DIR" "$CONFIG_DIR"

for file in backup-security-config.sh configure-entra.sh restore-security-config.sh uninstall.sh; do
  install -m 0755 "$SOURCE_DIR/$file" "$INSTALL_DIR/$file"
done
install -m 0755 "$SOURCE_DIR/om-auth" "$BIN_HOME/om-auth"
printf 'OK\n'

printf '[2/4] Detecting OpenMetadata deployment... '
COMPOSE_PATH="$(detect_compose)"
if [[ -n "$COMPOSE_PATH" ]]; then
  printf 'OK\n'
else
  printf 'NOT SET\n'
fi

printf '[3/4] Writing configuration... '
{
  printf '# OpenMetadata Auth Toolkit\n'
  if [[ -n "$COMPOSE_PATH" ]]; then
    printf 'COMPOSE_FILE=%q\n' "$COMPOSE_PATH"
  fi
  printf 'OM_AUTH_INSTALL_DIR=%q\n' "$INSTALL_DIR"
} > "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"
printf 'OK\n'

printf '[4/4] Preparing secure data directories... '
mkdir -p "$INSTALL_DIR/backups" "$INSTALL_DIR/logs"
chmod 700 "$INSTALL_DIR/backups" "$INSTALL_DIR/logs"
printf 'OK\n'

printf '\nSUCCESS: OpenMetadata Auth Toolkit installed.\n'
printf 'Command: %s/om-auth\n' "$BIN_HOME"
if [[ -n "$COMPOSE_PATH" ]]; then
  printf 'Compose: %s\n' "$COMPOSE_PATH"
fi
printf 'Backups: %s/backups\n' "$INSTALL_DIR"
printf 'Logs: %s/logs\n' "$INSTALL_DIR"

case ":$PATH:" in
  *":$BIN_HOME:"*)
    printf '\nTry: om-auth backup\n'
    ;;
  *)
    printf '\nNOTE: %s is not currently in PATH.\n' "$BIN_HOME"
    printf 'Run now: %s/om-auth backup\n' "$BIN_HOME"
    printf 'Or add this to your shell profile: export PATH="%s:$PATH"\n' "$BIN_HOME"
    ;;
esac

if [[ -z "$COMPOSE_PATH" ]]; then
  printf '\nSet the Compose file before first use:\n'
  printf '  %s/om-auth set-compose /path/to/docker-compose.yml\n' "$BIN_HOME"
fi
