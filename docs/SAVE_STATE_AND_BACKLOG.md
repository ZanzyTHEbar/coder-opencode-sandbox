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
- **Known issues (being addressed):**
  1. Template uses `opencode serve`; should use `opencode web` for web UI.
  2. Variable `docker_socket` is declared but not used in template (provisioner uses host Docker).
  3. Container name uses raw owner/workspace names (may need sanitization for Docker).
  4. OPERATOR.md does not yet reference GHCR pre-built image.

## Next logical steps (priority order)

1. **Correct OpenCode command** — In template `startup_script`, use `opencode web --hostname 0.0.0.0 --port 4096` so the Coder app gets the web UI, not only the API.
2. **docker_socket** — Either wire the template variable to the Docker provider (if Coder supports passing DOCKER_HOST per-template) or document that Docker is configured at Coder deployment (e.g. `DOCKER_HOST` in Compose) and remove/repurpose the variable.
3. **Healthcheck** — Confirm `/doc` is served by `opencode web` (keep as-is or switch to `/` or `/global/health` if needed).
4. **Container name** — Sanitize owner/workspace for Docker (e.g. replace spaces/slashes, length limit) or document that names must be safe.
5. **Workflow robustness** — Ensure OPENCODE_VERSION parsing in CI handles multiple ARG lines in Dockerfile.
6. **Docs** — OPERATOR.md: add “Pre-built image (GHCR)” and link to README; backlog: persistence backup, wildcard URL, template versioning.

## Backlog (future)

- **Persistence backup:** Pre-delete export of volume data to object storage (or doc a manual process).
- **Wildcard app URLs:** Document or automate Coder wildcard access URL + TLS for stable app URLs.
- **Template versioning:** Pin template version (e.g. in Coder) and document upgrade path.
- **Smoke-test automation:** Script or CI to start workspace, hit OpenCode app, assert persistence after stop/start.
