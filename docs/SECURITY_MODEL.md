# Security Model

## Trust Boundaries

| Boundary | Rule |
| --- | --- |
| Public edge | Only Coder portal/app hosts are public. |
| Coder | Owns identity, workspace ownership, and app sharing. |
| Runtime plane | Hosts hostile user code; isolated from platform services. |
| Workspace pod | One user workspace; no shared home, workspace, or OpenCode DB. |
| Vault | Source for secrets; no raw long-lived secrets in manifests. |

## Runtime Hardening

- `runAsNonRoot`.
- Drop all capabilities by default.
- `allowPrivilegeEscalation: false`.
- Seccomp/AppArmor enabled.
- No privileged pods.
- No hostPath mounts.
- No Docker socket mounts.
- Resource limits for CPU, memory, PIDs where supported, and disk.
- Default deny ingress.
- Egress denied to LAN/internal/reserved networks.
- Public egress is limited to approved ports first: HTTPS and Git SSH.

## Identity Rules

- Use Authentik `sub` as the stable user key.
- Do not key users or host paths by email.
- Coder app sharing defaults to `owner`.
- Admin/operator access uses explicit groups and audit events.

## Secrets Rules

- Prefer generated per-workspace SSH keys for Git.
- Store private keys in Vault or Vault-backed secret mounts.
- Mount secrets as read-only files when possible.
- Never bake secrets into images.
- Never log tokens, private keys, generated OpenCode passwords, or raw OIDC data.

## MVP Non-Goals

- No shared OpenCode runtime for external users.
- No direct public routes to user pods.
- No arbitrary PAT storage.
- No full user-held E2EE requirement before platform encryption at rest works.

## External Beta Blockers

- Per-workspace Vault policies and secret delivery.
- Per-workspace Git SSH keys without PAT storage.
- E2E proof that user pods cannot reach internal networks.
- E2E proof that one user cannot see another user's files, sessions, app URL, or
  secrets.
