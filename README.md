# OpenMetadata Auth Toolkit

Small, dependency-light Bash utilities for safely backing up, configuring, and restoring OpenMetadata authentication settings.

The first release targets **Microsoft Entra ID (OIDC)** on OpenMetadata deployments managed with Docker Compose.

> Status: pre-release. The current foundation has been functionally validated against OpenMetadata 2.0.3 and is undergoing final installation/documentation testing before v0.1.0 is published.

## Why this exists

Changing OpenMetadata authentication involves several easy-to-miss steps: exporting the persisted security configuration, preserving the authorization block, supplying the correct OIDC values, restarting the service, verifying the active provider, and keeping a working rollback path.

This toolkit makes that flow repeatable without requiring Python, jq, or a YAML package.

## Scripts

- `backup-security-config.sh` — exports the current persisted authentication and authorization configuration to a timestamped, permission-restricted backup.
- `configure-entra.sh` — performs preflight checks, creates a rollback backup, prompts for Entra settings, applies the OIDC configuration, restarts OpenMetadata, and verifies the auth endpoint.
- `restore-security-config.sh` — validates and restores a previously exported security configuration, restarts OpenMetadata, and reports the active provider.
- `install.sh` — installs the toolkit for the current user and configures the `om-auth` command.
- `om-auth` — friendly command wrapper for backup, Entra configuration, restore, logs, and configuration.

## Runtime requirements

The scripts use Bash and common OS utilities. No extra parser/runtime is required.

Required deployment components:

- Bash
- `sudo`
- Docker
- Docker Compose v2 (`docker compose`)
- `curl`
- standard utilities such as `grep`, `awk`, `sed`, `date`, and `mktemp`

The OpenMetadata container must include:

```text
/opt/openmetadata/bootstrap/openmetadata-ops.sh
```

## Quick start

For the easiest installation, run the installer from a cloned checkout:

```bash
./install.sh
```

The installer:

- installs a single `om-auth` command in `~/.local/bin`
- installs the toolkit scripts under `~/.local/share/openmetadata-auth-toolkit`
- auto-detects common OpenMetadata Compose locations
- stores the selected Compose path in `~/.config/openmetadata-auth-toolkit/config`
- keeps backups and logs in the toolkit data directory with restrictive permissions

Then use:

```bash
om-auth backup
om-auth entra
om-auth backups
om-auth logs
```

To restore a backup:

```bash
om-auth restore ~/.local/share/openmetadata-auth-toolkit/backups/security-config-YYYYMMDD-HHMMSS.yaml
```

If the Compose file is not auto-detected:

```bash
om-auth set-compose /path/to/docker-compose.yml
```

Show the current toolkit configuration:

```bash
om-auth config
```

Uninstall the command and installed scripts while preserving backups and logs:

```bash
om-auth uninstall
```

Once the repository is public on `main`, the installer is also designed for a one-line install:

```bash
curl -fsSL https://raw.githubusercontent.com/webbytenchi/openmetadata-auth-toolkit/main/install.sh | bash
```

If automatic Compose detection is not possible in a piped install, pass it explicitly:

```bash
curl -fsSL https://raw.githubusercontent.com/webbytenchi/openmetadata-auth-toolkit/main/install.sh | \
  bash -s -- --compose-file /path/to/docker-compose.yml
```

## Toolkit and OpenMetadata in separate directories

A common layout is to keep the toolkit repository separate from the OpenMetadata Docker deployment, for example:

```text
~/openmetadata-auth-toolkit/
~/openmetadata-docker/
```

Clone the toolkit:

```bash
cd ~
git clone https://github.com/webbytenchi/openmetadata-auth-toolkit.git
cd openmetadata-auth-toolkit
chmod +x backup-security-config.sh configure-entra.sh restore-security-config.sh
```

During pre-release testing, switch to the current test branch:

```bash
git switch emma/v0.1.0-foundation
```

Then point the toolkit at the OpenMetadata Compose file explicitly:

```bash
COMPOSE_FILE=~/openmetadata-docker/docker-compose-postgres.yml \
./backup-security-config.sh
```

The same override can be used with the configuration and restore scripts:

```bash
COMPOSE_FILE=~/openmetadata-docker/docker-compose-postgres.yml \
./configure-entra.sh

COMPOSE_FILE=~/openmetadata-docker/docker-compose-postgres.yml \
./restore-security-config.sh backups/security-config-YYYYMMDD-HHMMSS.yaml
```

Once v0.1.0 is released on `main`, the pre-release branch switch above will no longer be needed.

## Defaults and overrides

The scripts auto-detect these common Compose filenames:

```text
docker-compose-postgres.yml
compose.yml
compose.yaml
docker-compose.yml
docker-compose.yaml
```

Defaults:

```text
OpenMetadata Compose service: openmetadata-server
OpenMetadata operations tool: /opt/openmetadata/bootstrap/openmetadata-ops.sh
Local OpenMetadata URL: http://127.0.0.1:8585
Backup directory: ./backups
Log directory: ./logs
```

Override them when needed:

```bash
COMPOSE_FILE=/path/to/compose.yml \
OM_SERVICE=openmetadata-server \
OM_LOCAL_URL=http://127.0.0.1:8585 \
./configure-entra.sh
```

For backup location:

```bash
OM_BACKUP_DIR=/secure/path ./backup-security-config.sh
```

## Safety behavior

The toolkit is intentionally conservative:

- verifies required commands and the Compose service before making changes
- validates tenant/client IDs as UUIDs
- checks the Microsoft OIDC discovery endpoint
- creates a rollback backup before Entra configuration
- preserves the existing OpenMetadata authorization configuration
- requires explicit confirmation before authentication changes
- waits for OpenMetadata health after restart
- verifies `provider=azure`, confidential client mode, and callback URL
- prints clear errors and non-zero exit codes on failure
- stores backups with restrictive permissions
- saves suppressed Docker/OpenMetadata command output to permission-restricted per-run log files

Exit codes:

| Code | Meaning |
| ---: | --- |
| 0 | Success |
| 1 | General failure |
| 2 | Missing dependency |
| 3 | Invalid input/deployment state |
| 4 | Apply/restart failure |
| 5 | Verification failure |

## Microsoft Entra setup

See [docs/entra-setup.md](docs/entra-setup.md) for the application registration and redirect URI requirements.

## Security notes

- Use the Entra **client secret value**, not the Secret ID.
- Do not commit security backups. They may contain secrets, certificates, or other sensitive configuration.
- The toolkit adds `offline_access` to the OIDC scope so OpenMetadata can obtain a refresh token.
- `configure-entra.sh` requests `forceSecureSessionCookie: true`. Some OpenMetadata versions may still report a different value through the public auth endpoint; the script emits a warning rather than silently ignoring that condition.
- Review and test this toolkit in a non-production environment before using it on production systems.

## License

MIT. See [LICENSE](LICENSE).
