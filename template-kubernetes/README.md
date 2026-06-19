# Kubernetes OpenCode Template

This template is the external-user replacement for the Docker-provider template.
It is scaffolded to keep the provider contract visible before live k3s variables
are wired.

It is not external-beta complete yet. The Docker template still has features this
scaffold does not: Git repo cloning, OpenCode config bootstrap, workspace
bootstrap commands, Linux dotfiles, per-workspace Git SSH keys, and Vault-backed
secret delivery.

## Creates

- Coder agent.
- OpenCode Coder app with `subdomain = true`.
- Per-workspace Kubernetes namespace.
- PVC `home` at `/home/coder`.
- PVC `workspace` at `/home/coder/workspace`.
- OpenCode deployment reached only through the Coder agent-local app proxy.
- Default-deny NetworkPolicies with DNS plus public egress minus internal CIDRs.

## Defaults

- App share: `owner`.
- Healthcheck: `/doc`.
- Non-root user: UID/GID `1800`.
- Runtime image: approved external base image by digest or tag.
- No ClusterIP service for OpenCode.
- No public attach mode yet; add it only with generated password handling and E2E.

Run `terraform fmt template-kubernetes` after edits.

## External Beta Blockers

- GitHub and generic Git SSH clone UX.
- Per-workspace SSH key generation and public-key display.
- Vault-rendered per-workspace policies and secret mounts.
- OpenCode config bootstrap parity with `template/`.
- Workspace bootstrap and Linux dotfiles parity with `template/`.
- Full public-route E2E matrix in `docs/E2E_MULTI_TENANT.md`.
