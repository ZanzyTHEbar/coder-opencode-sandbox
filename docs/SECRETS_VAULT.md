# Vault Secrets Baseline

Vault is the platform secret boundary for external-user OpenCode.

## Secret Classes

| Class | Example path pattern |
| --- | --- |
| Platform | `kv/platform/opencode/*` |
| Coder | `kv/platform/coder/*` |
| Registry/builder | `kv/platform/images/*` |
| Backups | `kv/platform/backups/*` |
| Workspace Git | `kv/data/workspaces/<workspace_slug>/git/*` |

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

## Minimal Delivery Baseline

`template-kubernetes/` supports disabled-by-default Vault Agent injection for Git
secrets:

- `vault_git_secret_path = ""` means no Vault annotations are emitted.
- Set `vault_git_secret_path` only after rendering a per-workspace Vault policy
  and Kubernetes auth role.
- Use the same `workspace_slug` as the Kubernetes namespace suffix, for example
  `opencode-<workspace_slug>` and `kv/data/workspaces/<workspace_slug>/git/...`.
- The injected file path is `/vault/secrets/git`.
- When enabled, the template mounts a workspace service-account token and opens
  egress to `vault_namespace:vault_port`.
- The Vault Agent Kubernetes auth audience is `vault`; keep
  `vault.hashicorp.com/auth-config-audience` aligned with the role example.
- The template projects a dedicated service-account token volume named
  `vault-token` with audience `vault` when Vault injection is enabled; the
  injector is configured to use that projected token instead of the default
  Kubernetes audience token.
- The default role is `opencode-workspace`; use a per-workspace role for real
  tenant secrets.

Checked-in examples:

- `infra/vault/policies/opencode-workspace-git.example.hcl`
- `infra/vault/auth/kubernetes-workspace-role.example.hcl`

Batch P validated this path on VM100 with temporary Vault + injector: injected
`/vault/secrets/git`, same-workspace read, sibling-path denial, app health, and
NetworkPolicy probes all passed.

Batch P's Vault deployment was disposable and removed after the test. Production
still needs durable Vault deployment, audit logging, backup, and policy lifecycle
automation before external users receive real secrets.
