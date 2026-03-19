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
| `template/` | Terraform template (volume, container, agent, OpenCode app). |
| `image/` | Dockerfile and scripts for the sandbox image (Linux + OpenCode + Coder agent). |
| `coder-deployment/` | Reference Coder deployment (Compose + env). |
| `docs/` | Operator and user guides; Authentik OIDC setup. |

## Pre-built image (GHCR)

A public image is built and published via [GitHub Actions](.github/workflows/build-push-image.yml) on every push to `main`:

- **`ghcr.io/<owner>/coder-opencode-sandbox:latest`** — use this as the template variable `sandbox_image` to skip building locally.
- Tags: `latest`, `<short_sha>`, `v<opencode_version>` (e.g. `v1.2.27`).

After the first workflow run, set the package to **Public**: repo → **Packages** → **coder-opencode-sandbox** → **Package settings** → **Change visibility**.

## Quick start (operators)

1. Deploy Coder and configure OIDC (Authentik). See [docs/OPERATOR.md](docs/OPERATOR.md) and [docs/authentik/OIDC_SETUP.md](docs/authentik/OIDC_SETUP.md).
2. Use the [pre-built image](#pre-built-image-ghcr) from GHCR or build from `image/`.
3. Create the template from `template/` (e.g. `coder templates create opencode-sandbox --directory template`); set `sandbox_image` to `ghcr.io/<owner>/coder-opencode-sandbox:latest` or your own image.
4. Users create a workspace from the template and use the **OpenCode** app and **Terminal**. See [docs/USER.md](docs/USER.md).

## Persistence

- **Across stop/start**: Everything under `/home/coder` (OpenCode DB, config, code, shell history) is on a persistent volume; it survives workspace stop and is back when the workspace starts again.
- **Across delete**: Deleting a workspace runs `terraform destroy` and removes the volume. For long-term retention, use "stop" instead of "delete," or implement a backup strategy (see handoff doc).

## License

Same as parent project.
