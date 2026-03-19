# End-to-end automation

**Template registration (recommended):** GitHub Actions pushes the Coder template on every change to `template/` on **`main`** — the registered Terraform **always** matches the git commit. See **[TEMPLATE_CI.md](TEMPLATE_CI.md)** (secrets: `CODER_URL`, `CODER_TOKEN`). This avoids relying on Coolify’s preserved checkout for `coder templates push`.

**Server deployment:** Coder + Postgres run on **your** infrastructure (e.g. Coolify). The sandbox image is built in CI and published to GHCR.

## What is automated

| Step | Where | How |
|------|--------|-----|
| **1. Sandbox image** | GitHub Actions | [.github/workflows/build-push-image.yml](../.github/workflows/build-push-image.yml) builds `image/Dockerfile` and pushes to GHCR. |
| **2. Terraform template in Coder** | GitHub Actions | [.github/workflows/push-coder-template.yml](../.github/workflows/push-coder-template.yml) runs `coder templates push` from the workflow checkout. |
| **3. Terraform + defaults** | Repo | `template/` is the Coder template; default `sandbox_image` is the GHCR image. |
| **4. Coder deployment** | Coolify / Compose | Deploy from this repo with build-pack **dockercompose**, base-directory **`.`** (repo root; root [`docker-compose.yml`](../docker-compose.yml)). |
| **5. Template (optional second path)** | Coolify post-deploy | A **post-deployment command** can also run `sh /deploy/post-deploy.sh` — redundant if CI is enabled; useful before CI secrets exist. |
| **6. Authentik OIDC** | One-time | Run [scripts/create_authentik_oidc_coder.py](../scripts/create_authentik_oidc_coder.py) once. |

## Coolify e2e

**Full guide:** [COOLIFY_E2E.md](COOLIFY_E2E.md)

1. Create the Coder app in Coolify from this repo (dockercompose, base-directory **`.`** / repo root).
2. Set env vars (OIDC, `CODER_ACCESS_URL`, etc.).
3. Add **GitHub Actions secrets** `CODER_URL` and `CODER_TOKEN` so [push-coder-template workflow](../.github/workflows/push-coder-template.yml) registers the template on each push — **independent** of Coolify’s “preserve repo” behavior.
4. Optionally set **Post-deployment command** to `sh /deploy/post-deploy.sh` if you want a deploy-time push from the bind mount as well.

## Manual template registration (alternative)

```bash
export CODER_URL=https://coder.example.com
export CODER_TOKEN=<token>
./scripts/bootstrap-template.sh
```

See [bootstrap-template.sh](../scripts/bootstrap-template.sh).

## Summary

- **Single source of truth for template contents in Coder:** the **git commit** pushed through **CI** (or manual `bootstrap-template.sh`).
- **Coolify** runs the Coder server; it does **not** have to be the only path that runs `coder templates push`.
