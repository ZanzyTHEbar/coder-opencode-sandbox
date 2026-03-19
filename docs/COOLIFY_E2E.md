# E2E automation via Coolify (no public CI)

End-to-end automation runs on **your Coolify infrastructure** using pre/post-deployment commands. No GitHub Actions (or other public CI) are used for template registration.

## Flow

1. **Image** — Built and pushed to GHCR by GitHub Actions (or your own registry). The template defaults to `ghcr.io/zanzythebar/coder-opencode-sandbox:latest`.
2. **Deploy Coder** — Coolify deploys the Coder app from this repo with build-pack **dockercompose** and **base-directory** `coder-deployment/`.
3. **Post-deploy** — Coolify runs a command **inside the Coder container** after deploy. That command pushes the **opencode-sandbox** template (our Terraform + our image) into Coder so the template is always in sync with the repo.

Result: one deploy in Coolify brings up Coder and registers the template; users get workspaces from our Terraform and our Docker image.

## Coolify setup

### 1. Create the app

- **Source:** This git repo.
- **Build pack:** Docker Compose.
- **Base directory:** `coder-deployment`.
- **Expose port:** 4099.

The compose file mounts `../template` and `./coder-deployment` (this dir) into the container so the post-deploy script and template are available inside the Coder container.

### 2. Environment variables

Set in Coolify for the Coder app:

- **Coder and OIDC:** `CODER_ACCESS_URL`, `CODER_OIDC_ISSUER_URL`, `CODER_OIDC_CLIENT_ID`, `CODER_OIDC_CLIENT_SECRET`, `CODER_OIDC_EMAIL_FIELD`, `CODER_OIDC_USERNAME_FIELD`, `CODER_DISABLE_PASSWORD_AUTH`, `CODER_PROVISIONER_DAEMON`, `DOCKER_HOST` (and any others from `.env.example`).
- **For post-deploy template push:**
  - **CODER_URL** — `http://127.0.0.1:4099` (Coder inside the same container). Coolify may inject this via the compose default; you can override if needed.
  - **CODER_TOKEN** — A Coder session or API token. Create it after first deploy: log in to Coder (e.g. via OIDC), then **User menu → Tokens → Create token**, and paste the value into Coolify as a secret. Once set, every subsequent deploy will run the post-deploy script and push the template.

Optional: **SANDBOX_IMAGE** to override the template’s image (default: `ghcr.io/zanzythebar/coder-opencode-sandbox:latest`).

### 3. Post-deployment command

In Coolify, open the Coder app → **Advanced** (or the section where pre/post-deploy commands are configured) and set:

**Post-deployment command:**

```bash
/deploy/post-deploy.sh
```

This script runs inside the Coder container. It uses `CODER_URL` and `CODER_TOKEN` from the container env, waits for the Coder API to be ready, then runs:

`coder templates push opencode-sandbox -d /templates --variable sandbox_image=... -y`

So the template in Coder is created or updated on every deploy.

### 4. First deploy (token bootstrap)

1. Deploy once **without** `CODER_TOKEN`. Coder will start; the post-deploy script will skip the push (it exits 0 when `CODER_TOKEN` is unset).
2. Log in to Coder via OIDC (Authentik).
3. Create a token in Coder (User menu → Tokens).
4. Add `CODER_TOKEN` to the app’s environment in Coolify (as a secret).
5. Redeploy (or trigger a new deployment). The post-deploy script will run again and push the template.

After that, every deploy will refresh the template automatically.

## What runs where

| Step                    | Where it runs        | How |
|-------------------------|----------------------|-----|
| Build sandbox image     | GitHub (or your CI) | Optional; use GHCR image or your registry. |
| Deploy Coder            | Coolify              | Compose from `coder-deployment/`. |
| Register/update template| Coolify              | Post-deploy command inside Coder container: `/deploy/post-deploy.sh`. |
| Authentik OIDC          | One-time             | Run `scripts/create_authentik_oidc_coder.py` once (e.g. in Authentik container). |

No public CI is used for template push; everything after “build image” runs on your Coolify infrastructure.

## Volume mounts (compose)

The compose file in `coder-deployment/docker-compose.yml` mounts:

- **`../template` → `/templates`** — So `coder templates push -d /templates` uses the repo’s Terraform template.
- **`.` (coder-deployment) → `/deploy`** — So the container can run `/deploy/post-deploy.sh`.

Coolify must run `docker compose` with the project root such that `../template` exists (i.e. the repo is cloned with both `coder-deployment/` and `template/`). Using **base-directory** `coder-deployment` and cloning the full repo satisfies that.

## Troubleshooting

- **Template not updated after deploy** — Ensure `CODER_TOKEN` is set in Coolify and the post-deploy command is exactly `/deploy/post-deploy.sh`. Check Coolify logs for the post-deploy step; the script logs “Template opencode-sandbox pushed successfully.” on success.
- **Post-deploy fails: “connection refused”** — Coder server may not be ready yet. The script retries for up to ~1 minute; if Coder starts slowly, increase the retry count in `post-deploy.sh` or add a longer initial sleep.
- **Permission denied: /deploy/post-deploy.sh** — Ensure `post-deploy.sh` is committed with execute bit (`chmod +x coder-deployment/post-deploy.sh`).
