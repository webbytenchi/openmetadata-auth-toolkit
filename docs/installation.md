# Installation

This guide covers installing OpenMetadata Auth Toolkit and the `om-auth` command.

## Supported deployment model

The current release targets OpenMetadata deployments managed with Docker Compose.

Validated baseline:

- OpenMetadata 2.0.3
- Docker Compose v2
- OpenMetadata service name `openmetadata-server`
- OpenMetadata operations tool at `/opt/openmetadata/bootstrap/openmetadata-ops.sh`

The toolkit is intentionally dependency-light and does not require Python, `jq`, or a YAML library.

## Requirements

The OpenMetadata host must have:

- Bash
- `sudo`
- Docker
- Docker Compose v2 (`docker compose`)
- `curl`
- common Unix tools such as `grep`, `awk`, `date`, `mktemp`, `chmod`, and `install`

The OpenMetadata container must provide:

```text
/opt/openmetadata/bootstrap/openmetadata-ops.sh
```

## Recommended installation

Clone the repository and run the installer:

```bash
git clone https://github.com/webbytenchi/openmetadata-auth-toolkit.git
cd openmetadata-auth-toolkit
./install.sh
```


The installer will:

1. install `om-auth` into `~/.local/bin`
2. install the toolkit scripts into `~/.local/share/openmetadata-auth-toolkit`
3. try to find the OpenMetadata Compose file automatically
4. save the Compose path in `~/.config/openmetadata-auth-toolkit/config`
5. create secure backup and log directories
6. add `~/.local/bin` to the user's shell PATH when needed

If the installer changes `~/.bashrc` or `~/.zshrc`, reload the current shell once:

```bash
source ~/.bashrc
```

A new terminal session will load the PATH automatically.

## Compose file auto-detection

The installer checks common Compose filenames in the current directory and under `~/openmetadata-docker`:

```text
docker-compose-postgres.yml
compose.yml
compose.yaml
docker-compose.yml
docker-compose.yaml
```

If a Compose file is found, no additional setup is required.

Verify the saved configuration with:

```bash
om-auth config
```

## If the Compose file is not found

`set-compose` is a fallback command. It is only needed when the installer cannot find the OpenMetadata Compose file automatically, when the Compose file is moved, or when the toolkit should point to a different OpenMetadata deployment.

Example:

```bash
om-auth set-compose ~/openmetadata-docker/docker-compose-postgres.yml
```

The path is saved so future commands do not need a `COMPOSE_FILE=...` prefix.

## Install with an explicit Compose file

You can provide the Compose file directly to the installer:

```bash
./install.sh --compose-file ~/openmetadata-docker/docker-compose-postgres.yml
```

## One-line installation

The installer supports:

```bash
curl -fsSL https://raw.githubusercontent.com/webbytenchi/openmetadata-auth-toolkit/main/install.sh | bash
```

For a piped install where auto-detection is not suitable, pass the Compose path explicitly:

```bash
curl -fsSL https://raw.githubusercontent.com/webbytenchi/openmetadata-auth-toolkit/main/install.sh | \
  bash -s -- --compose-file /path/to/docker-compose.yml
```

## Installed locations

Default installation layout:

```text
~/.local/bin/om-auth
~/.local/share/openmetadata-auth-toolkit/
~/.config/openmetadata-auth-toolkit/config
```

Runtime data:

```text
~/.local/share/openmetadata-auth-toolkit/backups/
~/.local/share/openmetadata-auth-toolkit/logs/
```

The toolkit data and configuration directories use restrictive permissions. Backup and log files are also written with restrictive permissions.

## Environment overrides

Advanced users may override installation paths:

```text
OM_AUTH_BIN_DIR
OM_AUTH_INSTALL_DIR
OM_AUTH_CONFIG_DIR
OM_AUTH_TOOLKIT_REF
```

Runtime script overrides include:

```text
COMPOSE_FILE
OM_SERVICE
OM_OPS_PATH
OM_LOCAL_URL
OM_BACKUP_DIR
OM_LOG_DIR
```

## Uninstall

Run:

```bash
om-auth uninstall
```

The uninstaller removes the installed command, installed scripts, and toolkit configuration.

Backups and logs are preserved intentionally.

## Verify the installation

Check the saved configuration:

```bash
om-auth config
```

Then create a backup:

```bash
om-auth backup
```

A successful run should report both a backup file and a log file.
