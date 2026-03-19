# Coder + OpenCode Sandbox

Per-user, isolated OpenCode sandboxes behind OIDC. Users log in via Authentik and get a dedicated workspace with OpenCode web UI, terminal, and persistent state.

## Architecture

- **Coder**: Control plane, OIDC login, workspace lifecycle (start/stop/delete), template provisioning.
- **Authentik**: OIDC IdP; no Coder password auth.
- **Template**: One workspace = one container + one persistent volume at `/home/coder`.
- **OpenCode**: Runs unchanged inside the container; state under `~/.local/share/opencode` and `~/.config/opencode` (on the volume).

## Repository layout

| Path | Purpose |
|------|--------|
| `template/` | Terraform template (volume, container, agent, OpenCode app). Default `sandbox_image` = GHCR image. |
| `image/` | Dockerfile for the sandbox image (Linux + OpenCode + Coder agent); built by CI to GHCR. |
| `coder-deployment/` | Reference Coder deployment (Compose + env). |
| `scripts/` | [bootstrap-template.sh](scripts/bootstrap-template.sh) (register template in Coder), [create_authentik_oidc_coder.py](scripts/create_authentik_oidc_coder.py) (Authentik OIDC). |
| `docs/` | Operator and user guides; [E2E_AUTOMATION](docs/E2E_AUTOMATION.md), Authentik OIDC, [BACKUP](docs/BACKUP.md), [WILDCARD_APP_URLS](docs/WILDCARD_APP_URLS.md), [IMPROVEMENTS](docs/IMPROVEMENTS.md). |
| `VERSION` | Template version (e.g. 1.0.0); see OPERATOR §9. |

## Pre-built image (GHCR)

A public image is built and published via [GitHub Actions](.github/workflows/build-push-image.yml) on every push to `main`:

- **`ghcr.io/<owner>/coder-opencode-sandbox:latest`** — use this as the template variable `sandbox_image` to skip building locally.
- Tags: `latest`, `<short_sha>`, `v<opencode_version>` (e.g. `v1.2.27`).

After the first workflow run, set the package to **Public**: repo → **Packages** → **coder-opencode-sandbox** → **Package settings** → **Change visibility**.

## Quick start (operators)

1. Deploy Coder and configure OIDC (Authentik). See [docs/OPERATOR.md](docs/OPERATOR.md) and [docs/authentik/OIDC_SETUP.md](docs/authentik/OIDC_SETUP.md).
2. Image is built by CI to GHCR; the template defaults to it. No local build needed.
3. Register the template: use Coolify post-deploy `/deploy/post-deploy.sh` (see [docs/COOLIFY_E2E.md](docs/COOLIFY_E2E.md)) or run `./scripts/bootstrap-template.sh` manually.
4. Users create a workspace from the template and use the **OpenCode** app and **Terminal**. See [docs/USER.md](docs/USER.md).

## Persistence

- **Across stop/start**: Everything under `/home/coder` (OpenCode DB, config, code, shell history) is on a persistent volume; it survives workspace stop and is back when the workspace starts again.
- **Across delete**: Deleting a workspace runs `terraform destroy` and removes the volume. For long-term retention, use "stop" instead of "delete," or run a [backup before delete](docs/BACKUP.md).

## Optional and improvements

- **Stable app URLs:** [Wildcard app URLs](docs/WILDCARD_APP_URLS.md) (DNS + TLS + `CODER_WILDCARD_ACCESS_URL`).
- **Template versioning:** See [OPERATOR.md](docs/OPERATOR.md#9-template-versioning-and-upgrades) and the root `VERSION` file.
- **What we're missing / how to do better:** [docs/IMPROVEMENTS.md](docs/IMPROVEMENTS.md) (backup, wildcard, versioning, CI, resource limits, smoke-test, etc.).

## License

Same as parent project.
