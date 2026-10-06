# Security Policy

## Reporting a vulnerability

Please do not report suspected security vulnerabilities, leaked credentials, client secrets, private keys, or other sensitive material in a public GitHub issue.

Use GitHub's private vulnerability-reporting mechanism for this repository when available. If private reporting is unavailable, contact the repository owner privately before disclosing sensitive details.

When reporting a vulnerability, include:

- the affected toolkit version or commit;
- the affected script or command;
- the OpenMetadata version and deployment mode, if relevant;
- a concise description of the security impact;
- safe reproduction steps that do not contain real credentials or private configuration.

## Sensitive data

This toolkit can export OpenMetadata security configuration, and those exports may contain secrets, certificates, tokens, or other sensitive settings.

Never commit:

- `backups/`;
- `security-config-*.yaml`;
- runtime logs;
- Entra client-secret values;
- private keys or certificates;
- production configuration containing credentials.

The repository `.gitignore` excludes the generated backup and log paths, but users are responsible for keeping their local OpenMetadata configuration and backups secure.

## Supported release policy

Security fixes are developed against the current supported release. Users should prefer tagged releases for reproducible installation rather than mutable development branches.

## Scope

This project is a Bash toolkit for managing OpenMetadata authentication configuration. It does not replace OpenMetadata's own security controls, Microsoft Entra security practices, Docker host hardening, or operational backup policies.
