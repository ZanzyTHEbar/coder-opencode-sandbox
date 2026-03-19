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

**Deadlock:** If OIDC does not work, you cannot complete step 2, so you never get `CODER_TOKEN` and **no template is ever pushed**. Fix OIDC first (§ troubleshooting below), or temporarily set **`CODER_DISABLE_PASSWORD_AUTH=false`**, redeploy, create the first admin user / log in with password, create a token, set `CODER_TOKEN`, then turn password auth off again if you want OIDC-only.

## What runs where

| Step                     | Where it runs         | How |
|--------------------------|------------------------|-----|
| Build sandbox image      | GitHub (or your CI)   | Use GHCR image or your registry. |
| Deploy Coder             | Coolify               | Root `docker-compose.yml`, base **`.`**. |
| Register/update template | Coolify              | Post-deploy: `sh /deploy/post-deploy.sh` (or fetch fallback). |
| Authentik OIDC           | One-time              | Run `scripts/create_authentik_oidc_coder.py` once. |

## Troubleshooting

### No templates at all

1. **Coolify post-deploy logs** — Look for `CODER_TOKEN not set` (expected until you add a token), `FATAL: no readable /templates/main.tf` (wrong base directory / mount), or `coder templates push` errors (permissions, API down).
2. **`CODER_TOKEN`** — Must be a valid API token for a user who can manage templates. If OIDC never worked, you never created one; see **Deadlock** in §4.
3. **Base directory** — Must be repo root (`.`) so `/templates` contains your Terraform template. If you see the FATAL line above, fix base directory and redeploy.
4. **Manual push (bypass post-deploy)** — From any machine with `coder` CLI:  
   `CODER_URL=https://<your-coder-host> CODER_SESSION_TOKEN=<token> coder templates push opencode-sandbox -d ./template --variable sandbox_image=ghcr.io/zanzythebar/coder-opencode-sandbox:latest -y`  
   (Use your real URL, token, and image.)

### OIDC / Authentik not working at all

1. **Confirm env vars reach the container** — In Coolify or on the host: `docker exec <coder-container> env | grep CODER_`  
   Empty `CODER_OIDC_ISSUER_URL` / `CLIENT_ID` / `SECRET` means Coolify did not inject them (wrong variable names, not marked for runtime, or not saved).
2. **`CODER_ACCESS_URL`** — Must be exactly the URL users type in the browser (scheme + host, no path), e.g. `https://coder.example.com`. It must match the **redirect URI** registered in Authentik:  
   `https://<same-host>/api/v2/users/oidc/callback` — no trailing slash on the callback path.
3. **`CODER_OIDC_ISSUER_URL`** — Must be Authentik’s **issuer** for that provider, usually:  
   `https://<authentik-host>/application/o/<application-slug>/`  
   (Trailing slash is fine; wrong slug or using provider *name* instead of *application* slug breaks discovery.) Open in a browser:  
   `<ISSUER_URL>.well-known/openid-configuration` — it must return JSON.
4. **Network** — The Coder container must reach Authentik over HTTPS (DNS, firewall, correct internal vs public URL).
5. **Recovery** — Set `CODER_DISABLE_PASSWORD_AUTH=false`, redeploy, sign up / log in with a local password if Coder allows first-user bootstrap, create `CODER_TOKEN`, push template, then fix OIDC and revert to `true` if desired.

### Other

- **`templates not found` / `post-deploy not found`** — Ensure **Base directory** is repo root (`.`) so mounts exist. If you must use `coder-deployment` only, use the **fetch-and-run** commands in §3.
- **`curl: not found`** — Use the **wget** fetch variant in §3 (fallback only).
- **Template not updated after deploy** — Ensure `CODER_TOKEN` is set in Coolify. Check Coolify logs for the post-deploy step; the script logs “Template opencode-sandbox pushed successfully.” on success.
- **Post-deploy fails: “connection refused”** — Coder server may not be ready yet. The script retries for up to ~1 minute.
