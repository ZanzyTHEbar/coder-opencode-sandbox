# End-to-end automation

**Template registration:** Coolify **post-deploy** runs **`coder templates push`** with **`POST_DEPLOY_TEMPLATE_SOURCE=auto`** by default — use the bind-mounted `template/` when it passes checks, **otherwise** fetch the same ref from GitHub inside the container. That avoids stale Terraform when **“preserve repo during deployment”** leaves an old checkout. See **[TEMPLATE_REGISTRATION.md](TEMPLATE_REGISTRATION.md)**.

**Server deployment:** Coder + Postgres run on **your** infrastructure (e.g. Coolify). The sandbox image is built in CI and published to GHCR.

## What is automated

| Step | Where | How |
|------|--------|-----|
| **1. Sandbox image** | GitHub Actions | [.github/workflows/build-push-image.yml](../.github/workflows/build-push-image.yml) builds `image/Dockerfile` and pushes to GHCR. |
| **2. Terraform template in Coder** | Coolify post-deploy | [`post-deploy.sh`](../coder-deployment/post-deploy.sh) runs `coder templates push` (`auto` / `github` / `mount`). |
| **3. Terraform + defaults** | Repo | `template/` is the Coder template; default `sandbox_image` is the GHCR image. |
| **4. Coder deployment** | Coolify / Compose | Deploy from this repo with build-pack **dockercompose**, base-directory **`.`** (repo root; root [`docker-compose.yml`](../docker-compose.yml)). |
| **5. Authentik OIDC** | One-time | Run [scripts/create_authentik_oidc_coder.py](../scripts/create_authentik_oidc_coder.py) once. |

## Coolify e2e

**Full guide:** [COOLIFY_E2E.md](COOLIFY_E2E.md)

1. Create the Coder app in Coolify from this repo (dockercompose, base-directory **`.`** / repo root).
2. Set env vars (OIDC, `CODER_ACCESS_URL`, etc.).
3. Set **Post-deployment command** to `sh /deploy/post-deploy.sh` and set **CODER_TOKEN**.
4. Leave **`POST_DEPLOY_TEMPLATE_SOURCE=auto`** (default) unless you need **`github`** (always fetch) or **`mount`** (strict local only).

## Manual template registration (alternative)

```bash
export CODER_URL=https://coder.example.com
export CODER_TOKEN=<token>
./scripts/bootstrap-template.sh
```

See [bootstrap-template.sh](../scripts/bootstrap-template.sh).

## Summary

- **Template in Coder** is updated by **post-deploy** (or manual bootstrap), with **`auto`** self-healing from GitHub when the bind mount is stale. **No** GitHub Actions workflow is required for template registration.
