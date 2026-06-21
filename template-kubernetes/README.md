# Kubernetes OpenCode Template

This template is the external-user replacement for the Docker-provider template.
It is not external-beta complete yet. The Docker template still has full
onboarding features this scaffold does not: OpenCode config bootstrap, workspace
bootstrap commands, and Linux dotfiles.

VM100 E2E has live-tested restricted PodSecurity, NetworkPolicy isolation,
owner-only app routing, private Git SSH clone, and temporary Vault Agent
secret-read with sibling-path denial. Production Vault still needs durable
deployment, audit logging, backups, and policy lifecycle automation before real
external-user secrets.

## Creates

- Coder agent.
- OpenCode Coder app with `subdomain = true`.
- Optional comma-separated `workspace_repo_urls` cloning into `~/workspace`.
- Per-workspace Kubernetes namespace.
- PVC `home` at `/home/coder`.
- PVC `workspace` at `/home/coder/workspace`.
- OpenCode deployment reached only through the Coder agent-local app proxy.
- Default-deny NetworkPolicies with DNS plus public egress minus internal CIDRs.
- CPU, memory, and ephemeral-storage requests/limits on the workspace pod.

## Defaults

- App share: `owner`.
- Healthcheck: `/doc`.
- Non-root user: UID/GID `1001`, matching the image's `coder` user.
- CPU/memory/ephemeral limits: `2` CPU, `4Gi` memory, `4Gi` ephemeral storage.
- Workspace namespace PodSecurity: `restricted` enforce/audit/warn.
- Vault Agent injection: disabled unless `vault_git_secret_path` is set.
- Runtime image: approved external base image pinned by digest.
- No ClusterIP service for OpenCode.
- No public attach mode yet; add it only with generated password handling and E2E.

## Storage Preconditions

The template runs under restricted PodSecurity and does not use a root `chown`
init container. It relies on `fsGroup=1001` and the image's existing `coder`
passwd entry. Do not switch to a synthetic UID unless the image also includes a
matching `/etc/passwd` entry; `ssh-keygen` fails without one.

`local-path` uses `WaitForFirstConsumer`, so the template sets
`wait_until_bound = false` on PVC resources. Otherwise Terraform waits for PVC
binding before it creates the first consumer pod.

Run `terraform fmt template-kubernetes` after edits.

## External Beta Blockers

- Provider-side Git SSH key registration UX. Private repo clones may warn on
  first startup, then retry after the generated public key is registered and the
  workspace is restarted. Repo URLs with embedded credentials are rejected.
- Pinned Git provider host keys. Current startup uses `ssh-keyscan` as a TOFU
  convenience only.
- Durable production Vault deployment, audit logging, backup, and policy
  lifecycle automation.
- OpenCode config bootstrap parity with `template/`.
- Workspace bootstrap and Linux dotfiles parity with `template/`.
- Real external-user secret lifecycle: registration, rotation, revocation, and
  restore drills.
- Dedicated VM runtime provisioning/firewall codified in Terraform/Packer; the
  current LXC proof-of-life runtime fails the internal-egress gate.
- Full public-route E2E matrix in `docs/E2E_MULTI_TENANT.md`.
