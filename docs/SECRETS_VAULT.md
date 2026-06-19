# Vault Secrets Baseline

Vault is the platform secret boundary for external-user OpenCode.

## Secret Classes

| Class | Example path pattern |
| --- | --- |
| Platform | `kv/platform/opencode/*` |
| Coder | `kv/platform/coder/*` |
| Registry/builder | `kv/platform/images/*` |
| Backups | `kv/platform/backups/*` |
| Workspace Git | `kv/workspaces/<workspace_id>/git/*` |

## Rules

- Enable audit logging before onboarding external users.
- Never store secrets in Terraform files, Coder parameters, Docker labels, or
  Kubernetes annotations.
- Prefer short-lived or wrapped delivery to pods/jobs.
- Mount secrets as files when possible.
- Keep break-glass access operator-only and audited.
- Never attach platform policies to workspace pods.
- Workspace pod policies must be scoped to one opaque workspace ID. A shared
  wildcard policy over all workspace secrets is not allowed.
