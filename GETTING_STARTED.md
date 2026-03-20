# Setup and Getting Started

Use this guide to go from a fresh checkout to a working OpenCode sandbox on Coder.

**Template registration:** [docs/TEMPLATE_REGISTRATION.md](docs/TEMPLATE_REGISTRATION.md) · **Coolify:** [docs/COOLIFY_E2E.md](docs/COOLIFY_E2E.md) · **Overview:** [docs/E2E_AUTOMATION.md](docs/E2E_AUTOMATION.md)

## 1. Image

On every push to `main`, [GitHub Actions](.github/workflows/build-push-image.yml) builds [image/Dockerfile](image/Dockerfile) and pushes to GHCR. The template defaults `sandbox_image` to:

```text
ghcr.io/zanzythebar/coder-opencode-sandbox:latest
```

## 2. Deploy Coder and configure Authentik

- Deploy from repo root using [docker-compose.yml](docker-compose.yml), or use Coolify with base directory `.` so `template/` and `coder-deployment/` bind-mount correctly.
- Set **`POSTGRES_PASSWORD`** for production, and optionally **`POSTGRES_USER`** / **`POSTGRES_DB`**. See [docs/COOLIFY_E2E.md](docs/COOLIFY_E2E.md).
- Set **`CODER_ACCESS_URL`** and the OIDC env vars. See [docs/authentik/OIDC_SETUP.md](docs/authentik/OIDC_SETUP.md).
- If you use Authentik, run [scripts/create_authentik_oidc_coder.py](scripts/create_authentik_oidc_coder.py) once.
- Ensure Coder's provisioner can reach Docker through the socket or `DOCKER_HOST`.

## 3. Register the template

**Option A — Coolify post-deploy (recommended):** Set **Post-deployment command** to `sh /deploy/post-deploy.sh` and set **`CODER_TOKEN`** in Coolify env. The default `POST_DEPLOY_TEMPLATE_SOURCE=deployed_commit` fetches the exact deployed `SOURCE_COMMIT` from GitHub. See [docs/TEMPLATE_REGISTRATION.md](docs/TEMPLATE_REGISTRATION.md) and [docs/COOLIFY_E2E.md](docs/COOLIFY_E2E.md).

**Option B — Manual:** `CODER_URL=https://coder.example.com CODER_TOKEN=<token> ./scripts/bootstrap-template.sh`

## 4. Smoke test

1. Log in via OIDC at your Coder URL.
2. Create a workspace from the **OpenCode sandbox** template. If you have a custom OpenCode config repo, paste its Git or GitHub URL into **OpenCode config URL**. Start the workspace.
3. Open the **OpenCode** app and the **Terminal**; confirm the UI loads and you have a shell.
4. If you set **OpenCode config URL**, confirm `~/workspace/.opencode` exists and resolves to the provisioned profile.
5. In the terminal, create a file under `/home/coder`; stop the workspace, then start it again and confirm the file is still there.

---

See [docs/OPERATOR.md](docs/OPERATOR.md) for full operator guidance and [docs/USER.md](docs/USER.md) for end-user instructions. For backup, wildcard URLs, versioning, and other future work, see [docs/IMPROVEMENTS.md](docs/IMPROVEMENTS.md) and [docs/SAVE_STATE_AND_BACKLOG.md](docs/SAVE_STATE_AND_BACKLOG.md).
