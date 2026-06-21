# Multi-Tenant OpenCode Architecture

This is the external-user architecture. It does not replace the personal
`opencode-docker/` runtime until the Kubernetes path is verified.

## Shape

```text
Browser or CLI
  -> Pangolin / Newt / Traefik
  -> Coder portal and wildcard app proxy
  -> Authentik OIDC
  -> dedicated k3s runtime VM
  -> one OpenCode pod per Coder workspace
  -> per-workspace PVCs
```

## Components

| Component | Responsibility |
| --- | --- |
| Authentik | OIDC identity, groups, access policy. |
| Pangolin/Newt/Traefik | Public TLS and wildcard routing to Coder only. |
| Coder | Portal, ownership, lifecycle, app proxy, SSH, terminal, templates. |
| Postgres | Durable Coder state. |
| k3s runtime VM | Isolated scheduler for untrusted OpenCode pods. |
| OpenCode pod | Per-workspace runtime, no public ingress. |
| PVCs | Per-workspace `/home/coder` and `/home/coder/workspace`. |
| Vault | Platform, Git, builder, backup, and audit secrets. |
| Internal registry | Approved base image and custom image digests. |

## Request Flow

1. User logs into Coder via Authentik.
2. Coder creates or starts a workspace from the Kubernetes template.
3. The template creates PVCs, a pod, a private service, a Coder agent, and the
   OpenCode app.
4. The browser opens a wildcard app URL at the host root.
5. Coder checks app ownership and proxies to the workspace pod.

## Boundaries

- User pods are never public Traefik/Pangolin targets.
- Coder app share defaults to `owner`.
- The OpenCode generated password is only for explicit public `opencode attach`
  workflows.
- The runtime VM is separate from the personal LXC/Coolify path.
- The Docker-provider `template/` remains for trusted beta use until the
  Kubernetes template passes E2E.

## Current Scaffold Gaps

The Kubernetes template intentionally starts with the runtime/security contract.
Before external beta it still needs:

- provider-ready Git SSH key registration and repo onboarding,
- OpenCode config bootstrap,
- workspace bootstrap commands,
- Linux dotfiles support,
- durable Vault deployment, audit logging, and policy lifecycle automation,
- retention and backup workers,
- custom image builder jobs.
