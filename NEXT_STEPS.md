# Next steps

Follow these in order to go from zero to a working OpenCode sandbox on Coder. The flow is **e2e automated**: our Terraform template and our GHCR Docker image are the single source of truth; one script registers the template in Coder.

**Template via CI (recommended):** [docs/TEMPLATE_CI.md](docs/TEMPLATE_CI.md) · **Coolify:** [docs/COOLIFY_E2E.md](docs/COOLIFY_E2E.md) · **Overview:** [docs/E2E_AUTOMATION.md](docs/E2E_AUTOMATION.md)

## 1. Image (automated by CI)

On every push to `main`, [GitHub Actions](.github/workflows/build-push-image.yml) builds [image/Dockerfile](image/Dockerfile) and pushes to GHCR. The template [template/main.tf](template/main.tf) defaults **sandbox_image** to that image:

```text
ghcr.io/zanzythebar/coder-opencode-sandbox:latest
```

No local build needed. After the first workflow run, set the package to **Public** in the repo's Packages settings.

## 2. Deploy Coder and configure Authentik

- Deploy from repo root [docker-compose.yml](docker-compose.yml) (`docker compose up` locally), or Coolify with **Base directory** **`.`** (repo root) so `template/` and `coder-deployment/` bind-mount correctly. The stack includes a **dedicated Postgres** service — set **`POSTGRES_PASSWORD`** (and optional **`POSTGRES_USER`** / **`POSTGRES_DB`**) for production; see [docs/COOLIFY_E2E.md](docs/COOLIFY_E2E.md).
- Set **CODER_ACCESS_URL** and OIDC env vars; see [docs/authentik/OIDC_SETUP.md](docs/authentik/OIDC_SETUP.md). Run [scripts/create_authentik_oidc_coder.py](scripts/create_authentik_oidc_coder.py) once if using Authentik.
- Ensure Coder's provisioner can reach Docker (socket or DOCKER_HOST).

## 3. Register the template

**Option A — GitHub Actions (recommended):** Add repository secrets **`CODER_URL`** and **`CODER_TOKEN`**. Each push to `main` that changes `template/` runs [`.github/workflows/push-coder-template.yml`](.github/workflows/push-coder-template.yml). The template in Coder **always** matches git — independent of Coolify’s preserved repo. See [docs/TEMPLATE_CI.md](docs/TEMPLATE_CI.md).

**Option B — Coolify post-deploy:** Set **Post-deployment command** to `sh /deploy/post-deploy.sh` and **CODER_TOKEN** in Coolify env. See [docs/COOLIFY_E2E.md](docs/COOLIFY_E2E.md).

**Option C — Manual:** `CODER_URL=https://coder.example.com CODER_TOKEN=<token> ./scripts/bootstrap-template.sh`

## 4. Smoke-test

1. Log in via OIDC at your Coder URL.
2. Create a workspace from the **OpenCode sandbox** template and start it.
3. Open the **OpenCode** app and the **Terminal**; confirm the UI loads and you have a shell.
4. In the terminal, create a file under `/home/coder`; stop the workspace, then start it again and confirm the file is still there (persistence).

---

See [docs/OPERATOR.md](docs/OPERATOR.md) for full operator guidance and [docs/USER.md](docs/USER.md) for end-user instructions. For backup, wildcard URLs, versioning, and other improvements, see [docs/IMPROVEMENTS.md](docs/IMPROVEMENTS.md) and [docs/SAVE_STATE_AND_BACKLOG.md](docs/SAVE_STATE_AND_BACKLOG.md).
