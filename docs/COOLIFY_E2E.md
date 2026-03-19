# E2E automation via Coolify (no public CI)

End-to-end automation runs on **your Coolify infrastructure** using a post-deployment command. No GitHub Actions (or other public CI) are used for template registration.

## Recommended: Compose at repo root

Set Coolify **Base directory** to **`.`** (repository root — leave empty if Coolify defaults to root). The deployment checkout then includes **`template/`** and **`coder-deployment/`**, so the root [`docker-compose.yml`](../docker-compose.yml) can bind-mount:

- `./template` → `/templates` (default `TEMPLATE_DIR` in `post-deploy.sh`)
- `./coder-deployment` → `/deploy` (`post-deploy.sh` at `/deploy/post-deploy.sh`)

**No GitHub fetch is required** for post-deploy when using this layout.

### Why a subfolder base directory broke mounts

If **Base directory** is `coder-deployment`, Coolify’s deployment root is **only** that folder. The host path does not contain `../template` or a usable repo tree, so `./template` and `./coder-deployment` mounts **cannot** resolve. Use repo root as base directory, or use the fetch-and-run fallback below.

## Flow

1. **Image** — Built and pushed to GHCR by GitHub Actions (or your own registry). The template defaults to `ghcr.io/zanzythebar/coder-opencode-sandbox:latest`.
2. **Deploy Coder** — Coolify deploys with build-pack **Docker Compose** and **Base directory** **`.`** (repo root), using root `docker-compose.yml`.
3. **Post-deploy** — Run `sh /deploy/post-deploy.sh` inside the Coder container (see §3).

## Coolify setup

### 1. Create the app

- **Source:** This git repo.
- **Build pack:** Docker Compose.
- **Base directory:** `.` (repo root).
- **Expose port:** 4099.

### 2. Environment variables

Set in Coolify for the Coder app:

- **Coder and OIDC:** `CODER_ACCESS_URL`, `CODER_OIDC_ISSUER_URL`, `CODER_OIDC_CLIENT_ID`, `CODER_OIDC_CLIENT_SECRET`, `CODER_OIDC_EMAIL_FIELD`, `CODER_OIDC_USERNAME_FIELD`, `CODER_DISABLE_PASSWORD_AUTH`, `CODER_PROVISIONER_DAEMON`, `DOCKER_HOST` (and any others from `coder-deployment/.env.example`).
- **For post-deploy template push:**
  - **CODER_URL** — `http://127.0.0.1:4099` (Coder inside the same container).
  - **CODER_TOKEN** — A Coder session or API token. Create it after first deploy: log in to Coder (e.g. via OIDC), then **User menu → Tokens → Create token**, and paste the value into Coolify as a secret.
- **SANDBOX_IMAGE** (optional) — Override the workspace sandbox image (default in compose: `ghcr.io/zanzythebar/coder-opencode-sandbox:latest`).

### 3. Post-deployment command

**Recommended (repo root base directory):**

```bash
sh /deploy/post-deploy.sh
```

**Fallback** — only if you **cannot** set base directory to repo root (e.g. policy restricts context). Downloads template + script from GitHub inside the container:

**Using curl:**

```bash
sh -c 'cd /tmp && curl -sSL -o r.tar.gz "https://github.com/ZanzyTHEbar/coder-opencode-sandbox/archive/refs/heads/main.tar.gz" && EXTRACTED=$(tar -tzf r.tar.gz | head -1 | cut -d/ -f1) && tar -xzf r.tar.gz && export TEMPLATE_DIR="/tmp/$EXTRACTED/template" && curl -sSL "https://raw.githubusercontent.com/ZanzyTHEbar/coder-opencode-sandbox/main/coder-deployment/post-deploy.sh" | sh'
```

**Using wget:**

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
| Deploy Coder             | Coolify               | Root `docker-compose.yml`, base **`.`**. |
| Register/update template | Coolify              | Post-deploy: `sh /deploy/post-deploy.sh` (or fetch fallback). |
| Authentik OIDC           | One-time              | Run `scripts/create_authentik_oidc_coder.py` once. |

## Troubleshooting

- **`templates not found` / `post-deploy not found`** — Ensure **Base directory** is repo root (`.`) so mounts exist. If you must use `coder-deployment` only, use the **fetch-and-run** commands in §3.
- **`curl: not found`** — Use the **wget** fetch variant in §3 (fallback only).
- **Template not updated after deploy** — Ensure `CODER_TOKEN` is set in Coolify. Check Coolify logs for the post-deploy step; the script logs “Template opencode-sandbox pushed successfully.” on success.
- **Post-deploy fails: “connection refused”** — Coder server may not be ready yet. The script retries for up to ~1 minute.
