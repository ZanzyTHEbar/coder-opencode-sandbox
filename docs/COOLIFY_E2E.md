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
  - **CODER_TOKEN** — A Coder **API token** (not a browser session cookie). Create after first login; store in Coolify as a secret. See **§ API tokens and 7-day expiry** below if the UI only allows short-lived tokens.
- **SANDBOX_IMAGE** (optional) — Override the workspace sandbox image (default in compose: `ghcr.io/zanzythebar/coder-opencode-sandbox:latest`).
- **Token lifetime (optional but recommended for automation)** — Root [`docker-compose.yml`](../docker-compose.yml) sets **`CODER_DEFAULT_TOKEN_LIFETIME`** and **`CODER_MAX_ADMIN_TOKEN_LIFETIME`** (default `8760h` ≈ one year) so tokens you create are allowed to last longer than Coder’s stock **7-day** default. Override in Coolify if your policy needs different values.
- **`CODER_DATA_VOLUME_NAME` (optional)** — Docker volume name for Coder’s database (`/home/coder/.coder`). Default in compose: `coder_opencode_sandbox_server_data`. Set a **unique** value per Coder app if several instances share one Docker host. See **§ Persistent data (Coolify)** below — **required reading** so redeploys do not wipe users.

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

#### Persistent data (Coolify) — why admin + tokens disappeared on redeploy

**Correction:** On Coolify, a **plain** Compose volume like `coder-data: {}` often gets a Docker volume name derived from the **Compose project name**. Coolify may use a **different project path or name on each deploy**, so Docker creates a **new empty volume** every time. The container then starts with a **fresh Coder DB** → setup wizard again, **all users and API tokens gone**. This matches [Coolify issues where volumes are recreated on redeploy](https://github.com/coollabsio/coolify/issues/2376).

**Fix (in this repo’s root `docker-compose.yml`):** the `coder-data` volume uses an **explicit stable `name`**, defaulting to `coder_opencode_sandbox_server_data`, overridable with **`CODER_DATA_VOLUME_NAME`** in Coolify. After you deploy with this compose:

1. **One more time:** complete the first-user setup and create your admin + API token.
2. **Redeploy** — Docker should **reuse** the same named volume; users and tokens persist.
3. If you already had data in an **old** auto-named volume, it may still exist on the host under another name (orphaned). You can inspect with `docker volume ls` on the resource server and migrate if needed.

#### Browser session vs Coolify secret vs Coder DB

| What | Typical redeploy behavior |
|------|---------------------------|
| **Browser session** | You may need to sign in again — normal. |
| **`CODER_TOKEN` in Coolify** | Kept by Coolify; injected into the new container. |
| **Users + tokens inside Coder** | Stored under `/home/coder/.coder` in the **`coder-data` volume** — **persists only if that volume name is stable** (see above). |

**After fixing the volume name:** create the API token once, set `CODER_TOKEN` in Coolify, redeploy — the **same** in-Coder token remains valid until revoked or expired. Post-deploy only needs the env var, not an open browser session.

## What runs where

| Step                     | Where it runs         | How |
|--------------------------|------------------------|-----|
| Build sandbox image      | GitHub (or your CI)   | Use GHCR image or your registry. |
| Deploy Coder             | Coolify               | Root `docker-compose.yml`, base **`.`**. |
| Register/update template | Coolify              | Post-deploy: `sh /deploy/post-deploy.sh` (or fetch fallback). |
| Authentik OIDC           | One-time              | Run `scripts/create_authentik_oidc_coder.py` once. |

## Troubleshooting

### Setup wizard / admin / tokens reset on every redeploy

1. **Cause:** Docker volume for Coder data was not **stable-named**; Coolify changed the Compose project identity between deploys → **new empty volume** each time. See **§ Persistent data (Coolify)** above.
2. **Verify:** On the Docker host, `docker volume ls | grep coder` and `docker inspect <coder-container> --format '{{json .Mounts}}'` — the Coder data mount should point at a **fixed** volume name (e.g. `coder_opencode_sandbox_server_data`), not one that changes per deploy.
3. **Coolify merged compose:** Ensure the **generated** `docker-compose.yaml` on the server still contains your explicit `coder-data` volume `name:` (Coolify sometimes rewrites compose).

### No templates at all

1. **Coolify post-deploy logs** — Look for `CODER_TOKEN not set` (expected until you add a token), `FATAL: no readable /templates/main.tf` (wrong base directory / mount), or `coder templates push` errors (permissions, API down).
2. **`CODER_TOKEN`** — Must be a valid API token for a user who can manage templates. If OIDC never worked, you never created one; see **Deadlock** in §4.
3. **Base directory** — Must be repo root (`.`) so `/templates` contains your Terraform template. If you see the FATAL line above, fix base directory and redeploy.
4. **Manual push (bypass post-deploy)** — From any machine with `coder` CLI:  
   `CODER_URL=https://<your-coder-host> CODER_SESSION_TOKEN=<token> coder templates push opencode-sandbox -d ./template --variable sandbox_image=ghcr.io/zanzythebar/coder-opencode-sandbox:latest -y`  
   (Use your real URL, token, and image.)

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
- **Template not updated after deploy** — Ensure `CODER_TOKEN` is set in Coolify. Check Coolify logs for the post-deploy step; the script logs “Template opencode-sandbox pushed successfully.” on success.
- **Post-deploy fails: “connection refused”** — Coder server may not be ready yet. The script retries for up to ~1 minute.
