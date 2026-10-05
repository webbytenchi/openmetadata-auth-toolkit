# Command reference

The installed command is `om-auth`.

Run:

```bash
om-auth help
```

to display the built-in command list.

## `om-auth backup`

Creates a timestamped backup of the persisted OpenMetadata authentication and authorization configuration.

```bash
om-auth backup
```

The backup is stored under the configured backup directory. With the default installer layout:

```text
~/.local/share/openmetadata-auth-toolkit/backups/
```

The corresponding suppressed Docker/OpenMetadata output is stored in:

```text
~/.local/share/openmetadata-auth-toolkit/logs/
```

The backup contains both top-level sections:

```text
authenticationConfiguration:
authorizerConfiguration:
```

Because the exported configuration may contain secrets, backup files use restrictive permissions and should never be committed to source control.

## `om-auth entra`

Configures Microsoft Entra ID authentication.

```bash
om-auth entra
```

The command prompts for:

- public OpenMetadata HTTPS URL
- Microsoft Entra tenant ID
- Microsoft Entra application/client ID
- Microsoft Entra client secret value

The secret prompt does not echo the value to the terminal.

Before making changes, the toolkit creates a rollback backup automatically.

The command then:

1. checks the Entra OpenID discovery endpoint
2. creates the rollback backup
3. generates the OpenMetadata Entra/OIDC security configuration
4. shows a non-secret summary
5. requires the user to type `CONFIRM`
6. applies the persisted security configuration
7. restarts the OpenMetadata server
8. waits for OpenMetadata health
9. verifies the active auth provider, confidential client mode, and callback URL

The generated scope is:

```text
openid email profile offline_access
```

See [entra-setup.md](entra-setup.md) for Microsoft Entra app-registration requirements.

## `om-auth restore <backup.yaml>`

Restores a previously exported security configuration.

```bash
om-auth restore ~/.local/share/openmetadata-auth-toolkit/backups/security-config-YYYYMMDD-HHMMSS.yaml
```

The command:

1. validates the backup
2. shows the provider contained in the backup
3. requires the user to type `RESTORE`
4. applies the saved authentication and authorization configuration
5. restarts OpenMetadata
6. waits for health
7. reports the active provider

Use the rollback backup created by `om-auth entra` if an Entra change needs to be reversed. If you pass only a filename, `om-auth` automatically looks for it in the configured backup directory. Full paths are also accepted.

## `om-auth backups`

Lists available toolkit backups:

```bash
om-auth backups
```

## `om-auth logs`

Lists saved runtime logs:

```bash
om-auth logs
```

The scripts intentionally keep successful terminal output concise. Suppressed Docker Compose and OpenMetadata administrative output is saved to per-run log files for troubleshooting and auditability.

The client secret itself is not intentionally written to the log.

## `om-auth config`

Displays the current toolkit paths:

```bash
om-auth config
```

Typical output:

```text
Compose: /home/user/openmetadata-docker/docker-compose-postgres.yml
Install: /home/user/.local/share/openmetadata-auth-toolkit
Backups: /home/user/.local/share/openmetadata-auth-toolkit/backups
Logs: /home/user/.local/share/openmetadata-auth-toolkit/logs
```

## `om-auth set-compose <compose.yml>`

Stores the OpenMetadata Compose file path used by future toolkit commands.

Most users do not need this command because the installer attempts to locate the Compose file automatically.

Use it when:

- the installer could not locate the Compose file
- the Compose file was moved
- the toolkit should target a different OpenMetadata deployment

Example:

```bash
om-auth set-compose ~/openmetadata-docker/docker-compose-postgres.yml
```

After saving the path, commands such as `om-auth backup` and `om-auth entra` do not need a `COMPOSE_FILE=...` prefix.

## `om-auth uninstall`

Removes the installed command, installed scripts, and toolkit configuration:

```bash
om-auth uninstall
```

The command asks for explicit confirmation.

Backups and logs are preserved.

## `om-auth help`

Displays the built-in command list:

```bash
om-auth help
```

## Exit codes

The underlying scripts use these exit codes:

| Code | Meaning |
| ---: | --- |
| 0 | Success |
| 1 | General failure |
| 2 | Missing dependency |
| 3 | Invalid input or deployment state |
| 4 | Apply or restart failure |
| 5 | Verification failure |
