#!/usr/bin/env bash
set -euo pipefail

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN_HOME="${OM_AUTH_BIN_DIR:-$HOME/.local/bin}"
INSTALL_DIR="${OM_AUTH_INSTALL_DIR:-$DATA_HOME/openmetadata-auth-toolkit}"
CONFIG_DIR="${OM_AUTH_CONFIG_DIR:-$CONFIG_HOME/openmetadata-auth-toolkit}"

printf 'This removes the installed command and scripts.\n'
printf 'Backups and logs in %s will be preserved.\n' "$INSTALL_DIR"
read -r -p "Type UNINSTALL to continue: " answer
[[ "$answer" == "UNINSTALL" ]] || { printf 'Cancelled.\n'; exit 0; }

rm -f "$BIN_HOME/om-auth"
rm -f \
  "$INSTALL_DIR/backup-security-config.sh" \
  "$INSTALL_DIR/configure-entra.sh" \
  "$INSTALL_DIR/restore-security-config.sh" \
  "$INSTALL_DIR/uninstall.sh"
rm -rf "$CONFIG_DIR"

printf 'OpenMetadata Auth Toolkit uninstalled.\n'
printf 'Preserved data: %s\n' "$INSTALL_DIR"
