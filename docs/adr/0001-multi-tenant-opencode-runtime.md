# ADR 0001: Multi-Tenant OpenCode Runtime

Status: Accepted
Date: 2026-06-17

## Context

The existing `opencode-docker/` runtime is a working personal runtime: one
OpenCode process, one home directory, one workspace mount, one SQLite state tree,
and one generated server password. That shape is not a security boundary for
external users.

The existing Coder template already models the right product boundary: users log
in with OIDC, Coder owns workspace lifecycle, and a workspace exposes OpenCode as
an app. The current Docker-provider template is useful for trusted beta users,
but hostile multi-tenant use needs a stronger runtime plane than Docker-in-LXC.

## Decision

Use Coder as the OpenCode control plane and user portal. Run external-user
workspaces on a dedicated Kubernetes/k3s runtime plane inside a separate Proxmox
VM. Each Coder workspace provisions one OpenCode pod plus per-workspace PVCs for
home and workspace data.

Public access goes through Pangolin/Newt/Traefik to Coder. Workspace apps use
Coder wildcard app URLs because OpenCode expects root-host SPA routing.

Do not build a custom portal/gateway/worker first. Only add custom platform
modules where Coder does not solve the problem: runtime VM lifecycle, secrets,
custom image builds, retention, backups, and audit.

## Requirements

- Many external users with hostile multi-tenant assumptions.
- 100+ active users target.
- Authentik OIDC and group-gated access.
- Portal lifecycle plus stable direct app routes.
- Per-workspace persisted OpenCode config, sessions, repos, and files.
- GitHub first plus generic Git SSH URLs.
- Suspend immediately on access removal; retain data for 30 days.
- Default egress: public internet allowed, LAN/internal networks denied.
- Users may customize runtime images only by inheriting from the approved base.

## Consequences

Positive:

- Avoids reimplementing Coder ownership, lifecycle, app proxying, SSH, and UI.
- Preserves the current template investment.
- Moves hostile workloads out of the personal LXC/Coolify runtime.
- Gives a clear path to quotas, NetworkPolicies, RuntimeClass, and node growth.

Negative:

- Requires dedicated runtime VM operations.
- Requires Kubernetes/k3s operations.
- Requires a Kubernetes template beside the current Docker template.
- Custom images need a registry, builder hardening, scanning, and audit.

## Rejected Alternatives

- Shared OpenCode container with per-user directories: rejected because process,
  SQLite, config, and filesystem state are shared.
- One Coolify app per user: rejected for external scale and isolation; useful only
  for trusted internal experiments.
- Custom portal plus Docker worker first: rejected because it rebuilds Coder's
  core product before proving Coder is insufficient.
- MCP edge as browser workspace control plane: rejected because MCP edge is for
  MCP OAuth/proxying, not browser IDE lifecycle.

## Implementation Phases

1. Repo-owned ADR/security docs.
2. Dedicated runtime VM image and Terraform-managed k3s plane.
3. Vault baseline for platform, Git, builder, and backup secrets.
4. Internal VM orchestrator module for image rollout and node lifecycle.
5. Coder deployment on/against Kubernetes with preserved Authentik OIDC.
6. Kubernetes OpenCode template with `share = owner` by default.
7. External-user base image and controlled custom image builder.
8. Encryption, retention, backup, and public-route E2E tests.
