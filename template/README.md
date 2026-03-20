# OpenCode sandbox template

Terraform template for Coder: one workspace = one container + one persistent volume at `/home/coder`. The container command prepends a root-owned bootstrap before the Coder agent `init_script`, and the agent `startup_script` starts the OpenCode server on port 4096; the OpenCode app in the dashboard proxies to it. The root module is split by concern, and the runtime shell now lives under `template/scripts/` and is rendered with `templatefile()`.

## Layout

- `main.tf`: entrypoint note for human readers
- `versions.tf`: Terraform and provider requirements
- `variables.tf`: template input variables
- `data.tf`: `coder_*` and `coder_parameter` data sources
- `locals.tf`: derived names plus rendered bootstrap/startup scripts
- `docker.tf`: Docker volume, image, and workspace container resources
- `coder.tf`: Coder agent and OpenCode app resources
- `scripts/volume_bootstrap.sh.tpl`: root-owned home-volume bootstrap prepended before the agent init script
- `scripts/agent_startup.sh.tpl`: user-space OpenCode startup and managed profile provisioning logic

## Variables

| Name | Default | Description |
|------|---------|-------------|
| `docker_socket` | `""` | Reserved. Use DOCKER_HOST on the Coder deployment for remote Docker. |
| `sandbox_image` | `ghcr.io/.../coder-opencode-sandbox:latest` (see `variables.tf`) | Docker image for the sandbox (build from `../image` or use GHCR). |
| `workspace_docker_network` | `""` | Optional Docker network to attach workspace containers to. Leave empty to use Docker's default bridge. |

## Workspace Parameters

These are Coder workspace parameters exposed through `data.coder_parameter` in `data.tf`, not root-module Terraform variables:

| Name | Default | Description |
|------|---------|-------------|
| `opencode_config_url` | `""` | Optional Git or GitHub URL provisioned into `~/workspace/.opencode` during workspace startup. |
| `opencode_config_ref` | `""` | Optional branch, tag, or commit override for `opencode_config_url`. |
| `opencode_config_subdir` | `""` | Optional path inside the fetched repo. Empty means auto-detect `.opencode` or use the repo root. |

## Create template

From this directory (or repo root with `--directory template`):

```bash
coder templates create opencode-sandbox --directory template
```

Set `sandbox_image` to your built image (e.g. `opencode-sandbox:latest` or `your-registry/opencode-sandbox:latest`).

When users provide `opencode_config_url`, the rendered startup script fetches that repo on workspace boot, stores it under `~/.opencode-profile/releases/`, and links `~/workspace/.opencode` to the selected profile. This keeps the managed profile out of the main workspace tree while still making it visible to OpenCode as project config.

## Persistence

- Volume name: `coder-${data.coder_workspace.me.id}-home` (immutable id only).
- Mount: `/home/coder` (read-write). All OpenCode and user state under home persists across stop/start.
- Managed OpenCode profile cache: `~/.opencode-profile/` persists across stop/start; `~/workspace/.opencode` can point to that managed cache.
- **First start:** Named volumes mount as **root:root** at `/home/coder`. The template sets **`user = "0:0"`** and **prepends** a bootstrap to the container **`command`** (before the agent `init_script`) so **`chown`/`mkdir`** run as **real root**; the agent then runs as **`coder`**. See **`docs/DEBUG_WORKSPACE_VOLUME.md`** if anything still fails — use **`bootstrap.log`** / **`/tmp/coder-opencode-startup.log`**, not blind `sudo` retries.
- Lifecycle: `ignore_changes = all` on the volume so Terraform does not recreate it.

## Container name

- Container name is derived from owner and workspace name, sanitized for Docker (`[a-zA-Z0-9_.-]`, max 63 chars): spaces/slashes/backslashes become dashes, then truncated.
