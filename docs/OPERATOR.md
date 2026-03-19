# Operator guide: Coder + OpenCode sandbox

## 1. Deploy Coder

- Use the reference [docker-compose.yml](../docker-compose.yml) at the **repository root** (run `docker compose up` from the repo root so `./template` and `./coder-deployment` mount correctly), or deploy Coder on Kubernetes per [Coder docs](https://coder.com/docs/install).
- Set **CODER_ACCESS_URL** to your public URL (e.g. `https://dev.example.com`). Coder must be reachable at this URL and able to reach your OIDC issuer (Authentik).

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

## 5. Create/update the template in Coder (e2e via Coolify)

- **Coolify:** Set **Post-deployment command** to `/deploy/post-deploy.sh` and set **CODER_TOKEN** in the app env. Every deploy will run the script inside the Coder container and push the template. See [COOLIFY_E2E.md](COOLIFY_E2E.md).
- **Manual:** Run `CODER_URL=https://coder.example.com CODER_TOKEN=<token> ./scripts/bootstrap-template.sh` from the repo root. Override image with `SANDBOX_IMAGE=... ./scripts/bootstrap-template.sh` if needed.

## 6. Persistence and lifecycle

- **Stop/start:** The persistent volume (named by workspace id) is kept when a workspace is stopped. On start, the same volume is mounted at `/home/coder`; OpenCode state, code, and config persist.
- **Delete:** Deleting a workspace runs `terraform destroy` and removes the volume. Data is not recoverable unless you implement a backup (e.g. pre-delete export to object storage). Prefer **stop** over **delete** for long-lived user data.

## 7. Wildcard / app URLs (optional)

- To give each workspace app a stable URL (e.g. for the OpenCode app), configure [Coder’s wildcard access URL](https://coder.com/docs/admin/networking/wildcard-access-url) and TLS so that `*.dev.example.com` resolves to Coder. Otherwise users open the OpenCode app via the dashboard (Coder proxies to the workspace).
- Full steps: [WILDCARD_APP_URLS.md](WILDCARD_APP_URLS.md).

## 8. Backup (before delete)

- Deleting a workspace removes its volume; data is lost unless you back up first. Prefer **stop** over **delete** when you want to keep data.
- To export a workspace's home before delete: see [BACKUP.md](BACKUP.md) for the volume export command and optional S3 upload.

## 9. Template versioning and upgrades

- **Version:** The repo tracks a template version in the root `VERSION` file (e.g. `1.0.0`). Releases can be tagged in git (e.g. `v1.0.0`).
- **Pin at create:** To use a specific revision when creating the template, clone the repo at a tag or commit before running `coder templates create opencode-sandbox --directory template`.
- **Upgrade:** Pull the latest (or desired tag), then run `coder templates push` from the `template/` directory to update the template in Coder. Existing workspaces may need to be updated to the new template version (Coder will prompt or allow "update workspace" when the template changes). Test with a single workspace before rolling out.

## 10. Troubleshooting

- **Agent never connects:** Ensure the container runs the agent init script (template sets `command = ["sh", "-c", coder_agent.main.init_script]`) and has `CODER_AGENT_TOKEN` in env. Check Coder logs and container logs.
- **OpenCode app 502 / unhealthy:** The agent’s startup_script starts `opencode web --hostname 0.0.0.0 --port 4096` in the background. Ensure OpenCode is installed in the image and the healthcheck URL `http://localhost:4096/doc` is reachable from inside the container.
- **Volume not persisting:** Volume name must use `data.coder_workspace.me.id` only (immutable). Do not use owner or workspace name in the volume name. Ensure `lifecycle { ignore_changes = all }` is set on the volume resource.
