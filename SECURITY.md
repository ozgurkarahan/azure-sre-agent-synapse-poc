# Security Policy

## Reporting a vulnerability

This is an example template repository — it is **not** a production service. The "vulnerabilities" most likely to surface here are:

- Bicep / IaC misconfigurations that would expose data if deployed as-is to a production tenant
- Hard-coded credentials, secrets, SAS tokens, or connection strings in any tracked file
- Outdated dependencies (e.g., a vulnerable Python package in a sample notebook) with a known CVE
- KQL queries that exfiltrate sensitive fields by accident

If you find something in any of those categories, **please open a private GitHub Security Advisory** on this repository:

1. Go to the **Security** tab → **Advisories** → **Report a vulnerability**
2. Describe the issue, the file path, and (if applicable) a suggested fix
3. We will respond within a reasonable time

Please **do not** open a public GitHub Issue for security reports — wait until the advisory is acknowledged.

## Supported versions

This repository tracks the `main` branch only. Tagged releases (if any) get fixes on a best-effort basis.

## Scope

In scope:
- Files in this repository (`infra/`, `runbooks/`, `demos/`, `docs/`)

Out of scope:
- Azure platform vulnerabilities (report those to Microsoft via [https://msrc.microsoft.com](https://msrc.microsoft.com))
- Vulnerabilities in any external service this template references (Azure SRE Agent, Synapse Analytics, Log Analytics, etc.)

## Secrets and credentials

This template is designed so that **no secrets are ever committed** to the repository:

- Synapse SQL admin password is generated at deploy time and stored in `infra/.synapse-admin-pwd.txt` (gitignored)
- Subscription IDs, principal IDs, and resource names are placeholders — replace them at deploy time
- Logic App webhook URLs and SAS signatures in the demo "broken receivers" are intentional placeholders that do not authenticate against any real resource (`bad@invalid.invalid` uses an RFC 2606 reserved TLD; `sig=invalid_revoked_signature_for_demo_purposes_only` is a clearly fake SAS)

If you find a real secret in the repository's history, please report via the process above.
