# Operator guide: Coder + OpenCode sandbox

## 1. Deploy Coder

- Use the reference [docker-compose.yml](../docker-compose.yml) at the **repository root** (run `docker compose up` from the repo root so `./template` and `./coder-deployment` mount correctly), or deploy Coder on Kubernetes per [Coder docs](https://coder.com/docs/install).
- **Upstream parity:** This compose follows [Coder’s official `compose.yaml`](https://github.com/coder/coder/blob/main/compose.yaml) for Postgres wiring, health checks, and Docker provisioner basics. See [CODER_OFFICIAL_DEPLOYMENT.md](CODER_OFFICIAL_DEPLOYMENT.md) for a diff table (ports, `coolify` network, OIDC, bind mounts) and **Docker socket `group_add`** if you hit permission errors.
- **Database:** The reference compose runs a **dedicated PostgreSQL** service and sets **`CODER_PG_CONNECTION_URL`** (not Coder’s built-in embedded Postgres). Persist the **`postgres-data`** volume; set **`POSTGRES_PASSWORD`** (and optional **`POSTGRES_USER`** / **`POSTGRES_DB`**) via env or secrets. See [COOLIFY_E2E.md](COOLIFY_E2E.md) § *Where Coder stores data*.
- **Coolify network:** The file uses **`networks: coolify` (external)**. Ensure that network exists on the Docker host (`docker network create coolify`) or that Coolify created it, or adjust networking per [CODER_OFFICIAL_DEPLOYMENT.md](CODER_OFFICIAL_DEPLOYMENT.md).
- Set **CODER_ACCESS_URL** to your public URL (e.g. `https://dev.example.com`). It must be reachable by users and workspaces — not `localhost` for non-local templates ([Coder Docker install](https://coder.com/docs/install/docker)).
- **Wildcard (strongly recommended / effectively required for OpenCode + VS Code):** Set **`CODER_WILDCARD_ACCESS_URL`** (e.g. `*.dev.example.com` when the UI is `https://dev.example.com`), create **DNS `A`/`CNAME` for `*.dev.example.com`**, terminate **TLS for the wildcard**, and route that traffic to Coder (same as the main host). The OpenCode template uses **`subdomain = true`** on `coder_app` so the SPA loads at the root of a hostname; without wildcard + DNS, assets request `/assets/...` from the wrong origin (white page, `text/plain` / `text/html` MIME errors). VS Code Desktop also relies on resolvable **wildcard-style SSH hostnames** — without `*.domain` in DNS you often get **“hostname could not be found”**. See [WILDCARD_APP_URLS.md](WILDCARD_APP_URLS.md).

## 2. Configure OIDC (Authentik)

- In Authentik, create an OIDC provider and application for Coder. Redirect URI must be exactly:
  `https://<CODER_ACCESS_URL>/api/v2/users/oidc/callback`
- Set **Subject (sub)** to a stable value (e.g. “Based on the User's Hashed ID”) so the same user always gets the same identity.
- Configure Coder with:
  - **CODER_OIDC_ISSUER_URL** — Authentik OIDC issuer URL (e.g. `https://auth.example.com/application/o/<app-slug>/`).
  - **CODER_OIDC_CLIENT_ID**, **CODER_OIDC_CLIENT_SECRET** — from the Authentik OIDC application.
  - **CODER_OIDC_EMAIL_FIELD**, **CODER_OIDC_USERNAME_FIELD** — claim names (e.g. `email`, `preferred_username`).
  - **CODER_DISABLE_PASSWORD_AUTH=true** so only OIDC is used.

See [authentik/OIDC_SETUP.md](authentik/OIDC_SETUP.md) for step-by-step Authentik configuration.

## 3. Provisioner (Docker)

- Workspace templates use the Docker provider to create containers and volumes. Coder’s provisioner must have access to the Docker socket (or a remote Docker host).
- In Docker Compose, mount `/var/run/docker.sock` into the Coder container and set **CODER_PROVISIONER_DAEMON=true** and **DOCKER_HOST** as needed.
- Configure Docker at the Coder deployment: set **DOCKER_HOST** in the Coder server environment (e.g. in Compose) so the provisioner can reach the Docker daemon that runs workspace containers. The template variable `docker_socket` is reserved for future use.

## 4. Build and set the sandbox image

**Option A — Use the pre-built image (recommended)**  
On every push to `main`, [GitHub Actions](../.github/workflows/build-push-image.yml) builds and pushes the image to GHCR. Use:

- **`ghcr.io/<owner>/coder-opencode-sandbox:latest`** (e.g. `ghcr.io/zanzythebar/coder-opencode-sandbox:latest`)

Set this as the template variable **sandbox_image**. After the first workflow run, set the package to **Public** in the repo’s Packages settings. See the [main README](../README.md#pre-built-image-ghcr) for details.

**Option B — Build locally**

- From the repo root:
  ```bash
  cd image && docker build -t opencode-sandbox:latest .
  ```
- If Coder runs on another host or Kubernetes, push the image to a registry and reference it in the template:
  ```bash
  docker tag opencode-sandbox:latest your-registry/opencode-sandbox:latest
  docker push your-registry/opencode-sandbox:latest
  ```

## 5. Create/update the template in Coder

- **Coolify (recommended):** Set **Post-deployment command** to `sh /deploy/post-deploy.sh` and **CODER_TOKEN**. Default **`POST_DEPLOY_TEMPLATE_SOURCE=deployed_commit`** fetches the exact **`SOURCE_COMMIT`** from GitHub on every redeploy — **no** GitHub Actions required. See [COOLIFY_E2E.md](COOLIFY_E2E.md) and [TEMPLATE_REGISTRATION.md](TEMPLATE_REGISTRATION.md).
- **Manual:** Run `CODER_URL=https://coder.example.com CODER_TOKEN=<token> ./scripts/bootstrap-template.sh` from the repo root. Override image with `SANDBOX_IMAGE=... ./scripts/bootstrap-template.sh` if needed.
- The template exposes workspace parameters for **OpenCode config URL**, **OpenCode config ref**, **OpenCode config subdirectory**, **Workspace repo URLs**, **Linux dotfiles URL**, and **Linux dotfiles install command**. Users can paste Git URLs or GitHub repo/tree/blob URLs at workspace creation time; the startup script fetches OpenCode config into `~/.opencode-profile/` and exposes it through `~/.config/opencode`, clones any missing workspace repos into `~/workspace`, and can rerun a dotfiles install command from `~/.dotfiles-profile/` before OpenCode starts.

## 6. Persistence and lifecycle

- **Stop/start:** The persistent volume (named by workspace id) is kept when a workspace is stopped. On start, the same volume is mounted at `/home/coder`; OpenCode state, code, and config persist.
- **Delete:** Deleting a workspace runs `terraform destroy` and removes the volume. Data is not recoverable unless you implement a backup (e.g. pre-delete export to object storage). Prefer **stop** over **delete** for long-lived user data.

## 7. Wildcard / app URLs (required for OpenCode + VS Code in practice)

- The template sets **`subdomain = true`** on the OpenCode `coder_app`. That needs **`CODER_WILDCARD_ACCESS_URL`**, **wildcard DNS**, and **TLS** for `*.your-deployment-host` — not optional if you want a working OpenCode UI or VS Code over SSH. Path-only access breaks SPAs that use absolute `/assets/...` URLs.
- The template exposes **OpenCode app sharing** as a workspace parameter. Default **Owner only** keeps Coder auth on the app. **Public URL attach** sets `share = "public"` so local `opencode attach https://<app-url>` works without Coder browser cookies, but startup also sets `OPENCODE_SERVER_PASSWORD` from `/home/coder/.opencode/server-password`; clients must use `opencode attach --password`, and browser password prompts use username `opencode`. Keep wildcard routing HTTPS-only, treat public app URLs and server passwords as workspace access secrets, and prefer `coder port-forward` when public attach is not needed.
- Full steps: [WILDCARD_APP_URLS.md](WILDCARD_APP_URLS.md) · [Coder wildcard access URL](https://coder.com/docs/admin/networking/wildcard-access-url).

## 8. Backup (before delete)

- Deleting a workspace removes its volume; data is lost unless you back up first. Prefer **stop** over **delete** when you want to keep data.
- To export a workspace's home before delete: see [BACKUP.md](BACKUP.md) for the volume export command and optional S3 upload.

## 9. Template versioning and upgrades

- **Version:** The repo tracks a template version in the root `VERSION` file (e.g. `1.0.0`). Releases can be tagged in git (e.g. `v1.0.0`).
- **Pin at create:** To use a specific revision when creating the template, clone the repo at a tag or commit before running `coder templates create opencode-sandbox --directory template`.
- **Upgrade:** Pull the latest (or desired tag), then run `coder templates push` from the `template/` directory to update the template in Coder. Existing workspaces may need to be updated to the new template version (Coder will prompt or allow "update workspace" when the template changes). Test with a single workspace before rolling out.

## 10. Troubleshooting

- **Agent never connects / “Workspace agents are not connected”:** Workspaces must reach **`CODER_ACCESS_URL`** and finish agent bootstrap. The template defines **`host.docker.internal` → host-gateway** (for anything that must reach the Docker host); **OpenCode stays on `127.0.0.1`** inside the workspace—do not rewrite loopback to `host.docker.internal` in the init script or the app will bind wrong and healthchecks fail. Optional **`workspace_docker_network`** (e.g. `coolify`) only if you need that attachment; default is empty (bridge). Server-side use **`CODER_DERP_FORCE_WEBSOCKETS`** and optionally **`CODER_BLOCK_DIRECT`** (compose defaults both on). Confirm `CODER_AGENT_TOKEN` is injected and check Coder + workspace container logs; see [Coder networking troubleshooting](https://coder.com/docs/admin/networking/troubleshooting) and `coder ping <workspace>`.
- **OpenCode app 502 / unhealthy:** The agent’s startup_script starts `opencode web --hostname 127.0.0.1 --port 4096` in the background (Coder proxies to localhost). Ensure OpenCode is installed in the image and the healthcheck URL `http://localhost:4096/doc` is reachable from inside the container.
- **Custom OpenCode config URL fails at startup:** Check `/tmp/coder-opencode-startup.log` and `/home/coder/.opencode/server.log` in the workspace. Bad URLs, private repos without credentials, or missing subdirectories now fail the startup script instead of silently booting without the profile. If `~/.config/opencode` already exists outside the managed cache, the template leaves it unchanged and logs a warning instead of replacing it.
- **Workspace repo bootstrap behaves unexpectedly:** `workspace_repo_urls` accepts comma-separated Git URLs or GitHub repo/tree/blob URLs. GitHub tree/blob URLs can pin a ref, but the template still clones the full repo into `~/workspace/<repo-name>`. Existing target paths are preserved rather than updated in place, so delete or rename the path first if you want the template to reclone it.
- **Linux dotfiles install command fails:** Check `/tmp/coder-opencode-startup.log`. The template caches dotfiles under `~/.dotfiles-profile/` and runs `linux_dotfiles_install_command` from the selected directory on every startup. The command receives `DOTFILES_DIR`, `DOTFILES_REPO_DIR`, and `WORKSPACE_DIR` in the environment and currently fails the startup script if the command exits non-zero.
- **OpenCode white page; console 404 on `/assets/...`; CSS/JS “MIME type text/plain” or “text/html”:** The UI was opened in **path** mode or wildcard is misconfigured. Assets are being fetched from **`https://<CODER_HOST>/assets/...`** (Coder/Traefik) instead of the workspace app. Fix: **`CODER_WILDCARD_ACCESS_URL`**, **`*.domain` DNS**, TLS, proxy route for wildcard to Coder; **push template** with **`subdomain = true`**; open the app again (subdomain URL). OpenCode does not support a subpath/base-URL workaround today.
- **VS Code: hostname could not be found / remote closes:** Usually **missing wildcard DNS** for the same domain pattern Coder uses for SSH (see **`coder config-ssh`**). Configure **`CODER_WILDCARD_ACCESS_URL`** and **`*.your-subdomain`** DNS per [WILDCARD_APP_URLS.md](WILDCARD_APP_URLS.md). If the network path is still wrong after that, try **`CODER_BLOCK_DIRECT=false`** temporarily to rule out relay-only issues (compose defaults it to `true`).
- **Logs: `inbox_notifications_watcher` / heartbeat ping / `use of closed network connection`:** Typically a **closed WebSocket** (browser disconnected, proxy drop). Sporadic lines are normal. Persistent storms point to reverse-proxy WebSocket or timeout settings — align with [Coder networking](https://coder.com/docs/admin/networking) and edge timeouts.
- **Template not updating on Coolify redeploy:** Post-deploy must run in the **`coder`** Compose service, not **`database`**. The script searches `PATH`, `/opt/coder`, `/opt/coder/coder`, `/usr/local/bin/coder`, and `/usr/bin/coder` for the Coder CLI. Use a **full deploy** and read Coolify deployment logs for `post-deploy:` — see [COOLIFY_E2E.md](COOLIFY_E2E.md) §3.
- **`mkdir: cannot create directory '/home/coder/workspace': Permission denied`:** Don’t guess — follow **[DEBUG_WORKSPACE_VOLUME.md](DEBUG_WORKSPACE_VOLUME.md)**. The template prepends bootstrap before the agent **`init_script`** via the container **`command`**, sets **`user = "0:0"`**, and writes **`/home/coder/.coder-debug/bootstrap.log`** + **`/tmp/coder-opencode-startup.log`** so you can see **bootstrap vs startup** and **which user** failed. **Push the template**, **update** the workspace, then **`docker exec`** the logs. Confirm **`SANDBOX_IMAGE`** and **`docker inspect … Config.User`** match the template.
- **Volume not persisting:** Volume name must use `data.coder_workspace.me.id` only (immutable). Do not use owner or workspace name in the volume name. Ensure `lifecycle { ignore_changes = all }` is set on the volume resource.
