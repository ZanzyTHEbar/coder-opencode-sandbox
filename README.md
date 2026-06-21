# Coder + OpenCode Sandbox

Per-user OpenCode sandboxes behind OIDC. Users log in via Authentik and get a dedicated workspace with the OpenCode web UI, terminal access, and persistent state.

## Architecture

- **Coder**: Control plane, OIDC login, workspace lifecycle (start/stop/delete), template provisioning.
- **Authentik**: OIDC IdP; no Coder password auth.
- **Template**: One workspace = one container + one persistent volume at `/home/coder`. Template registration is handled by Coolify post-deploy with `POST_DEPLOY_TEMPLATE_SOURCE=deployed_commit` by default. See [docs/TEMPLATE_REGISTRATION.md](docs/TEMPLATE_REGISTRATION.md).
- **OpenCode**: Runs unchanged inside the container; state under `~/.local/share/opencode` and `~/.config/opencode` (on the volume). Workspaces can also provision a managed global OpenCode config under `~/.config/opencode` from a user-supplied Git URL or GitHub repo/tree/blob URL at creation time, clone one or more repos into `~/workspace`, run an optional generic workspace bootstrap command, and optionally cache/apply Linux dotfiles from a Git-backed source. Repo-local `.opencode` paths remain available for project-specific overrides. Workspaces can opt into password-protected public app routing so `opencode attach https://<app-url>` works from local machines without exposing sessions unauthenticated.

For external multi-tenant users, the accepted architecture is Coder backed by a dedicated Kubernetes runtime plane, not the single-container personal runtime. Start at [ADR 0001](docs/adr/0001-multi-tenant-opencode-runtime.md) and [Multi-Tenant Architecture](docs/MULTI_TENANT_ARCHITECTURE.md).

The Kubernetes path is currently a scaffold, not external-beta ready. It has
partial Git SSH repo onboarding and validated VM100 Vault secret delivery, but
still needs a provider-ready Git key registration flow, OpenCode config
bootstrap, workspace bootstrap, Linux dotfiles, production runtime codification,
and backup/custom-image release gates before external users should be onboarded.
The LXC proof-of-life runtime fails internal egress denial; the VM `100` runtime
passed isolation, fresh Coder workspace/app access, and Vault secret-read
validation. Track the release decision in
[External Beta Gate](docs/EXTERNAL_BETA_GATE.md).

## Repository layout

| Path | Purpose |
|------|--------|
| `docker-compose.yml` | Coder deployment stack. Keep Coolify base directory at `.` so `template/` and `coder-deployment/` bind-mount correctly. |
| `template/` | Terraform template for the workspace volume, container, agent, and OpenCode app. |
| `template-kubernetes/` | Kubernetes/Coder template scaffold for external multi-tenant workspaces. |
| `image/` | Dockerfile for the sandbox image; built by CI to GHCR. |
| `image-external/` | Hardened external-user OpenCode base image scaffold. |
| `infra/` | Terraform, Packer, and Vault scaffolds for the dedicated runtime plane. |
| `coder-deployment/` | Deployment helpers, including `.env.example` and `post-deploy.sh`. |
| `scripts/` | Manual helpers such as `bootstrap-template.sh` and the Authentik OIDC setup script. |
| `docs/` | Operator and user guides, deployment notes, wildcard app URL docs, and improvement backlog. |
| `VERSION` | Template version marker. |

## Pre-built image (GHCR)

A public image is built and published via [GitHub Actions](.github/workflows/build-push-image.yml) on every push to `main`. The template defaults to that image, so local builds are optional.

## Quick start (operators)

1. Deploy Coder and configure OIDC. See [docs/OPERATOR.md](docs/OPERATOR.md), [docs/CODER_OFFICIAL_DEPLOYMENT.md](docs/CODER_OFFICIAL_DEPLOYMENT.md), and [docs/authentik/OIDC_SETUP.md](docs/authentik/OIDC_SETUP.md).
2. Use the default GHCR sandbox image or build your own.
3. Register the template with Coolify post-deploy (`sh /deploy/post-deploy.sh`) or run `./scripts/bootstrap-template.sh` manually. See [docs/COOLIFY_E2E.md](docs/COOLIFY_E2E.md) and [docs/TEMPLATE_REGISTRATION.md](docs/TEMPLATE_REGISTRATION.md).
4. Create one long-lived workspace from the template, optionally supply an OpenCode config URL, workspace repo URLs, workspace bootstrap settings, or Linux dotfiles settings, then use the OpenCode app, Coder terminal, `coder ssh`, or `opencode attach`. If `~/.config/opencode` already exists outside the managed cache, the startup script leaves it in place and logs a warning instead of replacing it. See [docs/USER.md](docs/USER.md).

## Persistence

- **Across stop/start**: Everything under `/home/coder` (OpenCode DB, config, code, shell history, and any provisioned OpenCode profile cache) is on a persistent volume; it survives workspace stop and is back when the workspace starts again.
- **Across delete**: Deleting a workspace runs `terraform destroy` and removes the volume. For long-term retention, stop the workspace instead of deleting it, or run a [backup before delete](docs/BACKUP.md).

## License

Same as parent project.
