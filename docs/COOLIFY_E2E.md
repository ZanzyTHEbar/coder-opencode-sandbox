# E2E automation via Coolify (no public CI)

End-to-end automation runs on **your Coolify infrastructure** using a post-deployment command. No GitHub Actions (or other public CI) are used for template registration.

**Upstream Coder deployment:** Root [`docker-compose.yml`](../docker-compose.yml) is aligned with [Coder’s official `compose.yaml`](https://github.com/coder/coder/blob/main/compose.yaml) (Postgres, health checks, Docker socket). See [CODER_OFFICIAL_DEPLOYMENT.md](CODER_OFFICIAL_DEPLOYMENT.md) for ports (`4099` vs upstream `7080`), **`coolify` network**, optional **`DOCKER_GID` / `group_add`**, and **`CODER_VERSION`** pinning.

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

- **Coder and OIDC:** `CODER_ACCESS_URL`, **`CODER_WILDCARD_ACCESS_URL`** (e.g. `*.dev.example.com` when the UI is `https://dev.example.com` — required for OpenCode SPA + VS Code SSH; see [WILDCARD_APP_URLS.md](WILDCARD_APP_URLS.md)), `CODER_OIDC_ISSUER_URL`, `CODER_OIDC_CLIENT_ID`, `CODER_OIDC_CLIENT_SECRET`, `CODER_OIDC_EMAIL_FIELD`, `CODER_OIDC_USERNAME_FIELD`, `CODER_DISABLE_PASSWORD_AUTH`, `CODER_PROVISIONER_DAEMON`, `DOCKER_HOST` (and any others from `coder-deployment/.env.example`).
- **PostgreSQL (dedicated service):** Root [`docker-compose.yml`](../docker-compose.yml) runs a **`database`** service (`postgres:17-alpine`) and sets **`CODER_PG_CONNECTION_URL`** for the Coder service. Set a strong secret in production:
  - **`POSTGRES_PASSWORD`** (required in practice; compose default `changeme` is dev-only).
  - Optional: **`POSTGRES_USER`**, **`POSTGRES_DB`** (defaults: `coder` / `coder`).
  - Optional: **`POSTGRES_DATA_VOLUME_NAME`** — host Docker volume name for Postgres data (default: `coder_opencode_sandbox_postgres_data`). Use a **unique** name per Coder app if several stacks share one Docker host. See **§ Where Coder stores data** below.
- **For post-deploy template push:**
  - **CODER_URL** — `http://127.0.0.1:4099` (Coder inside the same container).
  - **CODER_TOKEN** — A Coder **API token** (not a browser session cookie). Create after first login; store in Coolify as a secret. See **§ API tokens and 7-day expiry** below if the UI only allows short-lived tokens.
- **SANDBOX_IMAGE** (optional) — Override the workspace sandbox image (default in compose: `ghcr.io/zanzythebar/coder-opencode-sandbox:latest`).
- **Token lifetime (optional but recommended for automation)** — Root [`docker-compose.yml`](../docker-compose.yml) sets **`CODER_DEFAULT_TOKEN_LIFETIME`** and **`CODER_MAX_ADMIN_TOKEN_LIFETIME`** (default `8760h` ≈ one year) so tokens you create are allowed to last longer than Coder’s stock **7-day** default. Override in Coolify if your policy needs different values.
- **Coder image / port (optional)** — **`CODER_VERSION`** pins `ghcr.io/coder/coder:<tag>` (default `latest`). **`CODER_HOST_PORT`** maps the host port to container **4099** (upstream’s [official compose](https://github.com/coder/coder/blob/main/compose.yaml) uses **7080**). **`DOCKER_GID`** + uncommented **`group_add`** in compose if Docker workspaces fail with socket permission errors — see [CODER_OFFICIAL_DEPLOYMENT.md](CODER_OFFICIAL_DEPLOYMENT.md).

### API tokens and 7-day expiry

`coder templates push` (used by post-deploy) authenticates with **`CODER_SESSION_TOKEN` / `CODER_TOKEN`**. There is **no password or OIDC flow inside the post-deploy script** — the Coder CLI needs a token or an interactive login, which is why we use an API token in env.

Coder’s stock defaults cap many API tokens at **168 hours (7 days)** via:

- **`CODER_DEFAULT_TOKEN_LIFETIME`** — used when a token is created **without** an explicit lifetime (e.g. some UI flows).
- **`CODER_MAX_ADMIN_TOKEN_LIFETIME`** — cap when **admins** create tokens for automation.

**Fix (keep using `CODER_TOKEN` in Coolify):**

1. Set on the **Coder server** (already in root `docker-compose.yml`; ensure Coolify passes them through):
   - `CODER_DEFAULT_TOKEN_LIFETIME=8760h` (or `365d`, `1y` per [Coder duration format](https://coder.com/docs/reference/cli/tokens_create))
   - `CODER_MAX_ADMIN_TOKEN_LIFETIME=8760h`
2. **Redeploy Coder** so the new limits apply.
3. **Create a new token** with an explicit long lifetime (subject to the caps above), e.g. from your machine:
   ```bash
   coder login https://dev.example.com   # or your Coder URL
   coder tokens create --name coolify-post-deploy --lifetime 365d
   ```
   Optionally restrict scope to the minimum needed for template updates, e.g. `--scope template:*` (verify against your Coder version’s [scopes](https://coder.com/docs/admin/users/sessions-tokens)).
4. Put that token value in Coolify as **`CODER_TOKEN`**.

**Alternatives if you refuse any long-lived secret in Coolify:**

- **GitHub Actions (or other CI)** on push to `main`: run `coder templates push` using a short-lived or rotating token stored only in the CI secret store — the token still exists, but it is not on the Coder host and can be rotated by the pipeline.
- **Manual / scheduled `coder templates push`** from an operator machine when you change the template — no automation in Coolify.

There is **no** documented way to run `coder templates push` with **zero** API credentials; Coder’s model is API tokens with configurable lifetimes and scopes.

### 3. Post-deployment command

**Docker Compose — which container runs the command**

This stack has two services: **`database`** and **`coder`**. The script **`sh /deploy/post-deploy.sh`** must run inside the **`coder`** container (it needs the **`coder`** CLI, `CODER_TOKEN`, and bind mounts **`/templates`** and **`/deploy`**).

In Coolify **v4**, when you set a post-deployment command on a Compose application, select the **service** / **container** explicitly (often labeled **“Execute on service”**, **“Container”**, or similar). If the command runs on **`database`**, it will fail or do nothing useful, and the template will **not** update.

**“Restart” vs full deploy**

Some actions recycle containers **without** running lifecycle hooks. If the template did not refresh:

- Trigger a **full deployment** (redeploy / pull latest / deploy) from the Coolify UI and confirm the deployment log includes the post-deploy step.
- Check the log for `post-deploy: start host=` and `Template opencode-sandbox pushed successfully.`

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
2. Open Coder in the browser. You will see **“Welcome — create your first admin user”**. That screen **only shows GitHub and Email/Password** — OIDC does not appear there (see [OIDC_SETUP.md](authentik/OIDC_SETUP.md)). Create the first admin with **Email and Password** (ensure `CODER_DISABLE_PASSWORD_AUTH` is not `true` yet, or the form may not work).
3. After the first user is created, you are in. Create a token: **User menu → Tokens → Create token**.
4. Add `CODER_TOKEN` to the app’s environment in Coolify (as a secret).
5. Redeploy. The post-deploy script will run again and push the template.

After that, every deploy will refresh the template automatically. For **future logins**, use the normal **login** page — OIDC (Authentik) appears there; you can set `CODER_OIDC_SIGN_IN_TEXT="Sign in with Authentik"` and, if you want, `CODER_DISABLE_PASSWORD_AUTH=true` after the first user exists.

**Deadlock:** If you set `CODER_DISABLE_PASSWORD_AUTH=true` before creating the first user, the setup screen may not let you create an account. Use password once on the setup screen (step 2), then switch to OIDC-only on the login page if desired.

#### Where Coder stores data (dedicated PostgreSQL)

Application state (users, workspaces metadata, API tokens registry in Coder’s DB) lives in the **`database`** service’s data directory: the named volume **`postgres-data`** → `/var/lib/postgresql/data` (override volume **name** with **`POSTGRES_DATA_VOLUME_NAME`** if you need a stable host-side name across redeploys).

The Coder **container** does **not** use embedded Postgres under `~/.config/coderv2` in this stack — **`CODER_PG_CONNECTION_URL`** points at `database:5432`.

**Passwords with special characters:** If **`POSTGRES_PASSWORD`** contains `@`, `:`, `/`, etc., URL-encode it in **`CODER_PG_CONNECTION_URL`** or choose a password that is safe in a PostgreSQL connection URI (Coolify secrets).

**Migrating from embedded Postgres:** If you previously ran Coder with built-in DB on a volume under `/home/coder/.config/coderv2`, switching to external Postgres starts with an **empty** Coder DB unless you **dump/restore** from the old cluster. Plan a maintenance window: `pg_dump` from embedded (or copy data dir with compatible Postgres major version), restore into the new `database` service, then redeploy with **`CODER_PG_CONNECTION_URL`** only.

**Coolify:** If extra bind mounts in the UI **overwrite** the service `volumes` list, persistence can break ([coollabsio/coolify#5034](https://github.com/coollabsio/coolify/issues/5034)).

#### Browser session vs Coolify secret vs Coder DB

| What | Notes |
|------|--------|
| **Browser session** | May reset after redeploy — normal. |
| **`CODER_TOKEN` in Coolify** | Stored by Coolify; injected into the new container. |
| **Users + API tokens in Coder** | Stored in the **Postgres** service — keep the **`postgres-data`** volume (see **§ Where Coder stores data**). |

Post-deploy only needs the **`CODER_TOKEN` env var** in the container, not an open browser tab.

## What runs where

| Step                     | Where it runs         | How |
|--------------------------|------------------------|-----|
| Build sandbox image      | GitHub (or your CI)   | Use GHCR image or your registry. |
| Deploy Coder             | Coolify               | Root `docker-compose.yml`, base **`.`**. |
| Register/update template | Coolify              | Post-deploy: `sh /deploy/post-deploy.sh` (or fetch fallback). |
| Authentik OIDC           | One-time              | Run `scripts/create_authentik_oidc_coder.py` once. |

## Troubleshooting

### Setup wizard / admin / tokens reset on every redeploy

1. **Postgres volume missing or reset** — Ensure the **`database`** service keeps the **`postgres-data`** named volume (see **§ Where Coder stores data**). **`CODER_PG_CONNECTION_URL`** must match **`POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB`**.
2. **Empty DB after switching from embedded Postgres** — Expected unless you migrated data; see migration note in **§ Where Coder stores data**.
3. **Coolify:** If the **generated** compose drops volumes when bind mounts are merged, see [coollabsio/coolify#5034](https://github.com/coollabsio/coolify/issues/5034).

### No templates at all

1. **Coolify post-deploy logs** — Look for `CODER_TOKEN not set` (expected until you add a token), `FATAL: no readable /templates/main.tf` (wrong base directory / mount), or `coder templates push` errors (permissions, API down).
2. **`permission denied` on `/var/run/docker.sock` during `templates push`** — Template import runs Terraform against Docker; the Coder container must have **`group_add`** for the host `docker` group (**`DOCKER_GID`**). Without it, push fails in a loop and the UI shows **no templates**. Fix: set **`DOCKER_GID`** from `getent group docker | cut -d: -f3` on the Docker host (see root `docker-compose.yml` and [CODER_OFFICIAL_DEPLOYMENT.md](CODER_OFFICIAL_DEPLOYMENT.md)), redeploy, re-run post-deploy.
3. **`mkdir: ... /home/coder/workspace: Permission denied` inside the workspace** — The home volume mounts as **root** by default; the startup script must **`chown`** before **`mkdir`**. The template always runs **`sudo chown -R coder:coder $HOME`**. Push the latest template and **update** the workspace (or rebuild). If it persists, confirm the sandbox image still has **`sudo`** with **`NOPASSWD`** ([`image/Dockerfile`](../image/Dockerfile)).
3. **`CODER_TOKEN`** — Must be a valid API token for a user who can manage templates. Export **`CODER_SESSION_TOKEN`** for the CLI (`post-deploy.sh` does this). If OIDC never worked, you never created one; see **Deadlock** in §4.
4. **Base directory** — Must be repo root (`.`) so `/templates` contains your Terraform template. If you see the FATAL line above, fix base directory and redeploy.
5. **Manual push (bypass post-deploy)** — From any machine with `coder` CLI:  
   `CODER_URL=https://<your-coder-host> CODER_SESSION_TOKEN=<token> coder templates push opencode-sandbox -d ./template --variable sandbox_image=ghcr.io/zanzythebar/coder-opencode-sandbox:latest -y`  
   (Use your real URL, token, and image.)

6. **Stale `/templates` in the Coder container** — If `grep chown /templates/main.tf` inside the container does not show the latest commit, Coolify’s deployment checkout may be behind `main`. **Redeploy** the app (pull latest Git), or push using a **fresh tree from GitHub** (same idea as the fetch fallback in §3): extract `main.tar.gz`, set `TEMPLATE_DIR` to `…/template`, then `sh /deploy/post-deploy.sh`.

### OIDC / Authentik not working at all

- **Only GitHub and Email/Password on the first-time setup screen** — This is expected. Coder’s “create your first admin” page does not show OIDC. Create the first user with **Email and Password**, then use the **login** page (after logging out or in another session); OIDC appears there. See [authentik/OIDC_SETUP.md](authentik/OIDC_SETUP.md).
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
- **Template not updated after deploy** — Ensure `CODER_TOKEN` is set in Coolify and is still valid (expired tokens fail `coder templates push`). Confirm post-deploy runs on the **`coder`** service (see **§3 Post-deployment command**). Check Coolify deployment logs for `post-deploy:` lines and `Template opencode-sandbox pushed successfully.`
- **Post-deploy fails: “connection refused”** — Coder server may not be ready yet. The script waits for `/healthz` or `/api/v2/buildinfo`, then retries the push for up to ~2 minutes (override with `POST_DEPLOY_HEALTH_MAX_WAIT` / `POST_DEPLOY_PUSH_MAX_ATTEMPTS` if needed).
- **`coderd.inbox_notifications_watcher` / `failed to heartbeat ping` / `use of closed network connection`** — Usually a **disconnected browser WebSocket** (tab closed, network blip) or proxy idle timeout. If it is **occasional**, it is safe to ignore. If it is **constant**, check Traefik/Pangolin WebSocket support and timeouts, and that **`CODER_DERP_FORCE_WEBSOCKETS`** matches your edge (already `true` in root compose). Not specific to post-deploy.
