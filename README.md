# Coder + OpenCode Sandbox

Per-user OpenCode sandboxes behind OIDC. Users log in via Authentik and get a dedicated workspace with the OpenCode web UI, terminal access, and persistent state.

## Architecture

- **Coder**: Control plane, OIDC login, workspace lifecycle (start/stop/delete), template provisioning.
- **Authentik**: OIDC IdP; no Coder password auth.
- **Template**: One workspace = one container + one persistent volume at `/home/coder`. Template registration is handled by Coolify post-deploy with `POST_DEPLOY_TEMPLATE_SOURCE=deployed_commit` by default. See [docs/TEMPLATE_REGISTRATION.md](docs/TEMPLATE_REGISTRATION.md).
- **OpenCode**: Runs unchanged inside the container; state under `~/.local/share/opencode` and `~/.config/opencode` (on the volume). Workspaces can also provision a linked `~/workspace/.opencode` from a user-supplied Git or GitHub URL at creation time.

## Repository layout

| Path | Purpose |
|------|--------|
| `docker-compose.yml` | Coder deployment stack. Keep Coolify base directory at `.` so `template/` and `coder-deployment/` bind-mount correctly. |
| `template/` | Terraform template for the workspace volume, container, agent, and OpenCode app. |
| `image/` | Dockerfile for the sandbox image; built by CI to GHCR. |
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
4. Create a workspace from the template, optionally supply an OpenCode config URL, and use the OpenCode app and terminal. See [docs/USER.md](docs/USER.md).

## Persistence

- **Across stop/start**: Everything under `/home/coder` (OpenCode DB, config, code, shell history, and any provisioned OpenCode profile cache) is on a persistent volume; it survives workspace stop and is back when the workspace starts again.
- **Across delete**: Deleting a workspace runs `terraform destroy` and removes the volume. For long-term retention, stop the workspace instead of deleting it, or run a [backup before delete](docs/BACKUP.md).

## Optional and improvements

- **Stable app URLs:** [Wildcard app URLs](docs/WILDCARD_APP_URLS.md) (DNS + TLS + `CODER_WILDCARD_ACCESS_URL`).
- **Template versioning:** See [OPERATOR.md](docs/OPERATOR.md#9-template-versioning-and-upgrades) and the root `VERSION` file.
- **Backlog and future improvements:** [docs/IMPROVEMENTS.md](docs/IMPROVEMENTS.md).

## License

Same as parent project.
