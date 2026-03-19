# OpenCode sandbox template

Terraform template for Coder: one workspace = one container + one persistent volume at `/home/coder`. The container runs the Coder agent (via init_script) and the agent's startup_script starts the OpenCode server on port 4096; the OpenCode app in the dashboard proxies to it.

## Variables

| Name | Default | Description |
|------|---------|-------------|
| `docker_socket` | `""` | Reserved. Use DOCKER_HOST on the Coder deployment for remote Docker. |
| `sandbox_image` | `opencode-sandbox:latest` | Docker image for the sandbox (build from `../image`). |

## Create template

From this directory (or repo root with `--directory template`):

```bash
coder templates create opencode-sandbox --directory template
```

Set `sandbox_image` to your built image (e.g. `opencode-sandbox:latest` or `your-registry/opencode-sandbox:latest`).

## Persistence

- Volume name: `coder-${data.coder_workspace.me.id}-home` (immutable id only).
- Mount: `/home/coder` (read-write). All OpenCode and user state under home persists across stop/start.
- Lifecycle: `ignore_changes = all` on the volume so Terraform does not recreate it.

## Container name

- Container name is derived from owner and workspace name, sanitized for Docker (`[a-zA-Z0-9_.-]`, max 63 chars): spaces/slashes/backslashes become dashes, then truncated.
