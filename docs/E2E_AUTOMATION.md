# End-to-end automation

E2E automation runs on **your infrastructure** (Coolify), not in public CI. The image may be built by GitHub Actions and published to GHCR; template registration happens during **Coolify deployment** via a post-deployment command.

## What is automated

| Step | Where | How |
|------|--------|-----|
| **1. Sandbox image** | GitHub Actions (optional) | [.github/workflows/build-push-image.yml](../.github/workflows/build-push-image.yml) builds `image/Dockerfile` and pushes to GHCR. Use that image or your own registry. |
| **2. Terraform template** | Repo | `template/` is the Coder template; default `sandbox_image` is the GHCR image. |
| **3. Coder deployment** | Coolify | Deploy from this repo with build-pack **dockercompose**, base-directory **coder-deployment**. |
| **4. Template in Coder** | Coolify post-deploy | A **post-deployment command** runs inside the Coder container and pushes the template. No public CI. |
| **5. Authentik OIDC** | One-time | Run [scripts/create_authentik_oidc_coder.py](../scripts/create_authentik_oidc_coder.py) once. |

## Coolify e2e (recommended)

**Full guide:** [COOLIFY_E2E.md](COOLIFY_E2E.md)

1. Create the Coder app in Coolify from this repo (dockercompose, base-directory `coder-deployment`).
2. Set env vars (OIDC, `CODER_ACCESS_URL`, etc.). For template auto-push, set **CODER_TOKEN** (create in Coder UI after first deploy, then add to Coolify).
3. Set **Post-deployment command** to: `/deploy/post-deploy.sh`
4. Every deploy: Coder starts, then the post-deploy script runs inside the container and runs `coder templates push opencode-sandbox` from the mounted `template/` dir. Template is always in sync with the repo.

No GitHub secrets or public CI are used for template registration; everything runs on your Coolify server.

## Manual template registration (alternative)

If you are not using Coolify post-deploy, you can register the template once from your machine:

```bash
export CODER_URL=https://coder.example.com
export CODER_TOKEN=<token>   # optional
./scripts/bootstrap-template.sh
```

See [bootstrap-template.sh](../scripts/bootstrap-template.sh). This is not part of the Coolify e2e flow.

## Summary

- **Terraform** and **image** are the single source of truth in this repo.
- **E2E** = deploy Coder via Coolify + post-deploy command; template is pushed automatically on each deploy. No public CI for template push.
- **Authentik:** run the OIDC script once. Then users log in via OIDC and create workspaces from the **OpenCode sandbox** template.
