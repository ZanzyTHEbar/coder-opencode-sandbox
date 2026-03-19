# E2E automation via Coolify (no public CI)

End-to-end automation runs on **your Coolify infrastructure** using a post-deployment command. No GitHub Actions (or other public CI) are used for template registration.

## Why bind mounts do not work

When you set **Base directory** to `coder-deployment`, Coolify uses **only that folder** as the deployment root. The host path (e.g. `/data/coolify/applications/<uuid>/`) contains only what’s inside `coder-deployment/` (typically just `docker-compose.yml`; Coolify does not copy the rest of the repo or sibling directories). So:

- **`../template`** does not exist on the host (template is outside the base directory).
- **`./post-deploy.sh`** and **`.:/deploy`** — even if Coolify copies files from the base dir, the compose project directory is only that folder; there is no `template/` sibling.

So **`/templates` and `/deploy` are never valid** in the Coder container when using Coolify with base-directory `coder-deployment`. The compose file no longer mounts them. The **only** way to run the template push is to **download the script and template from GitHub inside the container** (fetch-and-run).

## Flow

1. **Image** — Built and pushed to GHCR by GitHub Actions (or your own registry). The template defaults to `ghcr.io/zanzythebar/coder-opencode-sandbox:latest`.
2. **Deploy Coder** — Coolify deploys the Coder app from this repo with build-pack **Docker Compose** and **Base directory** `coder-deployment`.
3. **Post-deploy** — Coolify runs the **fetch-and-run** command (below) inside the Coder container. That command downloads the repo tarball and the script from GitHub, then runs the script so the **opencode-sandbox** template is pushed to Coder.

## Coolify setup

### 1. Create the app

- **Source:** This git repo.
- **Build pack:** Docker Compose.
- **Base directory:** `coder-deployment`.
- **Expose port:** 4099.

### 2. Environment variables

Set in Coolify for the Coder app:

- **Coder and OIDC:** `CODER_ACCESS_URL`, `CODER_OIDC_ISSUER_URL`, `CODER_OIDC_CLIENT_ID`, `CODER_OIDC_CLIENT_SECRET`, `CODER_OIDC_EMAIL_FIELD`, `CODER_OIDC_USERNAME_FIELD`, `CODER_DISABLE_PASSWORD_AUTH`, `CODER_PROVISIONER_DAEMON`, `DOCKER_HOST` (and any others from `.env.example`).
- **For post-deploy template push:**
  - **CODER_URL** — `http://127.0.0.1:4099` (Coder inside the same container).
  - **CODER_TOKEN** — A Coder session or API token. Create it after first deploy: log in to Coder (e.g. via OIDC), then **User menu → Tokens → Create token**, and paste the value into Coolify as a secret.
- **SANDBOX_IMAGE** (optional) — Override the workspace sandbox image (default in compose: `ghcr.io/zanzythebar/coder-opencode-sandbox:latest`).

### 3. Post-deployment command (required)

In Coolify, open the Coder app → **Advanced** (or the section where pre/post-deploy commands are configured) and set the post-deployment command to **exactly** one of the following. There is no alternative; `/deploy/post-deploy.sh` and `/templates` do not exist in the container.

**Using curl (Coder image has it):**

```bash
sh -c 'cd /tmp && curl -sSL -o r.tar.gz "https://github.com/ZanzyTHEbar/coder-opencode-sandbox/archive/refs/heads/main.tar.gz" && EXTRACTED=$(tar -tzf r.tar.gz | head -1 | cut -d/ -f1) && tar -xzf r.tar.gz && export TEMPLATE_DIR="/tmp/$EXTRACTED/template" && curl -sSL "https://raw.githubusercontent.com/ZanzyTHEbar/coder-opencode-sandbox/main/coder-deployment/post-deploy.sh" | sh'
```

**Using wget (if curl is not available):**

```bash
sh -c 'cd /tmp && wget -q -O r.tar.gz "https://github.com/ZanzyTHEbar/coder-opencode-sandbox/archive/refs/heads/main.tar.gz" && EXTRACTED=$(tar -tzf r.tar.gz | head -1 | cut -d/ -f1) && tar -xzf r.tar.gz && export TEMPLATE_DIR="/tmp/$EXTRACTED/template" && wget -qO- "https://raw.githubusercontent.com/ZanzyTHEbar/coder-opencode-sandbox/main/coder-deployment/post-deploy.sh" | sh'
```

The script reads `CODER_URL`, `CODER_TOKEN`, and `SANDBOX_IMAGE` from the container environment, waits for the Coder API to be ready, then runs `coder templates push opencode-sandbox -d "$TEMPLATE_DIR" --variable sandbox_image=... -y`.

### 4. First deploy (token bootstrap)

1. Deploy once **without** `CODER_TOKEN`. Coder will start; the post-deploy script will skip the push (exits 0 when `CODER_TOKEN` is unset).
2. Log in to Coder via OIDC (Authentik).
3. Create a token in Coder (User menu → Tokens).
4. Add `CODER_TOKEN` to the app’s environment in Coolify (as a secret).
5. Redeploy. The post-deploy script will run again and push the template.

After that, every deploy will refresh the template automatically.

## What runs where

| Step                     | Where it runs         | How |
|--------------------------|------------------------|-----|
| Build sandbox image      | GitHub (or your CI)   | Use GHCR image or your registry. |
| Deploy Coder             | Coolify               | Compose from `coder-deployment/`. |
| Register/update template | Coolify                | Post-deploy: fetch-and-run command above. |
| Authentik OIDC           | One-time              | Run `scripts/create_authentik_oidc_coder.py` once. |

## Troubleshooting

- **`templates not found` / `post-deploy not found`** — You must use the fetch-and-run command from §3. Do not use `/deploy/post-deploy.sh` or `./post-deploy.sh`; those paths do not exist when using Coolify with base-directory `coder-deployment`.
- **`curl: not found`** — Use the **wget** version of the command in §3.
- **`wget: not found`** — The Coder image should include curl or wget (Alpine base). If neither exists, use a custom image that includes one, or open an issue.
- **Template not updated after deploy** — Ensure `CODER_TOKEN` is set in Coolify. Check Coolify logs for the post-deploy step; the script logs “Template opencode-sandbox pushed successfully.” on success.
- **Post-deploy fails: “connection refused”** — Coder server may not be ready yet. The script retries for up to ~1 minute.
