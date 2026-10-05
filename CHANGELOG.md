# Changelog

All notable changes to OpenMetadata Auth Toolkit are documented here.

## v0.1.0 — 2026-10-06

Initial release.

### Authentication workflow

- Back up the persisted OpenMetadata authentication and authorization configuration.
- Configure Microsoft Entra ID / OIDC using an interactive, secret-safe workflow.
- Preserve the existing `authorizerConfiguration` while changing authentication.
- Request `openid email profile offline_access` for the Entra OIDC flow.
- Restart OpenMetadata and verify health and the active authentication configuration.
- Restore a prior security configuration with an explicit rollback workflow.
- Accept a backup filename directly with `om-auth restore`, resolving it from the configured backup directory.

### Safety and diagnostics

- Automatic rollback backup before applying Entra configuration.
- Explicit `CONFIRM` / `RESTORE` gates before security changes.
- UUID and HTTPS input validation.
- Entra discovery-endpoint validation.
- Restrictive permissions for backup and log directories/files.
- Clean terminal output with suppressed Docker/OpenMetadata administrative output saved to per-run logs.
- Failure messages point to the retained log instead of dumping noisy command output.
- Warning when OpenMetadata reports `forceSecureSessionCookie=false` after the generated configuration requested `true`.

### Installation and command UX

- User-level installer with Compose-file auto-detection.
- Installed `om-auth` command with:
  - `backup`
  - `entra`
  - `restore`
  - `backups`
  - `logs`
  - `config`
  - `set-compose`
  - `uninstall`
  - `help`
- Saved Compose-path configuration so normal commands do not require repeated `COMPOSE_FILE=...` prefixes.
- Bash/Zsh PATH setup for `~/.local/bin` when needed.
- Uninstaller preserves backups and logs while removing the installed command, scripts, and configuration.

### Documentation and CI

- Installation guide.
- Complete `om-auth` command reference.
- Microsoft Entra ID app-registration and troubleshooting guide.
- MIT license.
- GitHub Actions Bash syntax validation for all shell entrypoints.

### Validation

Validated on OpenMetadata 2.0.3 with Docker Compose using this end-to-end flow:

```text
Basic authentication
→ backup
→ configure Microsoft Entra ID
→ restart and health verification
→ real Microsoft Entra browser login
→ list rollback backups
→ restore by backup filename
→ Basic authentication restored
```

The installer was also validated from a clean VM snapshot, including Compose auto-detection, PATH setup, installed configuration, backup, Entra configuration, and restore.
