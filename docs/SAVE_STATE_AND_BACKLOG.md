# Save state and backlog

**Last updated:** 2025-03-18 (from /save + audit).

## Current state

- **Repo:** `coder-opencode-sandbox` (Coder + OpenCode per-user sandboxes, OIDC via Authentik).
- **Implemented:**
  - Terraform template: persistent volume, Docker container, Coder agent, OpenCode app; startup runs OpenCode on port 4096.
  - Sandbox image (Dockerfile): Ubuntu 22.04, OpenCode from GitHub release, user `coder`, `/etc/skel` for first-run home.
  - GitHub Action: build image on push to `main`, push to GHCR with tags `latest`, `<short_sha>`, `v<opencode_version>`; lowercase image name for GHCR.
  - Docs: README, NEXT_STEPS, OPERATOR, USER, Authentik OIDC_SETUP, template README, image README.
  - Coder deployment: reference docker-compose and `.env.example`.
- **Resolved (audit 2025-03-18):** Template uses `opencode web`; `docker_socket` documented as reserved; container name sanitized; healthcheck `/doc` confirmed; CI parses last OPENCODE_VERSION; OPERATOR references GHCR.

## Required to get 100% working (operator checklist)

All of the following must be done in your environment; the repo does not do them for you:

1. **Image** — Use `ghcr.io/<owner>/coder-opencode-sandbox:latest` (set GHCR package to Public after first workflow run) or build from `image/` and push to a registry Coder can pull from.
2. **Deploy Coder** — Run Coder (e.g. `coder-deployment/docker-compose.yml`) with **CODER_ACCESS_URL** set to your public URL and **DOCKER_HOST** so the provisioner can create containers.
3. **Authentik OIDC** — Create OIDC provider + application in Authentik; set redirect URI to `https://<CODER_ACCESS_URL>/api/v2/users/oidc/callback`; set subject mode to a stable value (e.g. hashed user id); copy issuer URL, client id, client secret into Coder env.
4. **Coder env** — Set all `CODER_OIDC_*` and `CODER_DISABLE_PASSWORD_AUTH=true` in the Coder server (e.g. in Compose or K8s).
5. **Create template** — Run `coder templates create opencode-sandbox --directory template` and set **sandbox_image** to the image from step 1.
6. **Smoke-test** — Log in via OIDC, create a workspace, start it, open the OpenCode app and Terminal, create a file in `/home/coder`, stop/start workspace, confirm file persists.

## Backlog (future)

- **Persistence backup:** Documented manual process in [BACKUP.md](BACKUP.md). Optional automation (pre-delete hook or sidecar) remains future work.
- **Wildcard app URLs:** Documented in [WILDCARD_APP_URLS.md](WILDCARD_APP_URLS.md). No automation in repo.
- **Template versioning:** Documented in OPERATOR §9; `VERSION` file in repo root. Tagging releases and upgrade testing are operator responsibilities.
- **Smoke-test automation:** Script or CI to start workspace, hit OpenCode app, assert persistence after stop/start — not yet implemented (environment-dependent).
- **Other:** Resource limits (template vars), multi-arch image, observability subsection, OpenCode first-run/skel — see [IMPROVEMENTS.md](IMPROVEMENTS.md).
