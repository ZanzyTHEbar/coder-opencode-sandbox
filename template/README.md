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
| `sandbox_image` | Pinned GHCR digest (see `variables.tf`) | Docker image for the sandbox (build from `../image` or use a promoted GHCR digest). |
| `workspace_docker_network` | `""` | Optional Docker network to attach workspace containers to. Leave empty to use Docker's default bridge. |

## Workspace Parameters

These are Coder workspace parameters exposed through `data.coder_parameter` in `data.tf`, not root-module Terraform variables:

| Name | Default | Description |
|------|---------|-------------|
| `opencode_config_url` | `""` | Optional Git URL or GitHub repo/tree/blob URL provisioned into `~/.config/opencode` during workspace startup. |
| `opencode_config_ref` | `""` | Optional branch, tag, or commit override for `opencode_config_url`. |
| `opencode_config_subdir` | `""` | Optional path inside the fetched repo. Empty means auto-detect `.opencode` or use the repo root. |
| `workspace_repo_urls` | `""` | Optional comma-separated Git URLs or GitHub repo/tree/blob URLs to clone into `~/workspace/<repo-name>`. Existing paths are left untouched. |
| `linux_dotfiles_url` | `""` | Optional Git URL or GitHub repo/tree/blob URL for Linux dotfiles to clone into a managed cache under `~/.dotfiles-profile/`. |
| `linux_dotfiles_install_command` | `""` | Optional shell command to run from the selected dotfiles directory on every startup. Prefer `workspace_bootstrap_command` for generic setup. |
| `workspace_bootstrap_url` | `""` | Optional Git URL or GitHub repo/tree/blob URL containing generic workspace bootstrap code. |
| `workspace_bootstrap_command` | `""` | Optional shell command to run as `coder` before OpenCode starts. Runs from the selected bootstrap URL directory, or `~/workspace` when no URL is set. |
| `workspace_bootstrap_timeout_seconds` | `600` | Maximum runtime for workspace bootstrap and Linux dotfiles commands. |
| `workspace_bootstrap_failure_policy` | `warn` | `warn` logs bootstrap failures and still starts OpenCode; `fail` stops workspace startup. |
| `opencode_app_share` | `owner` | Controls OpenCode app access: `owner`, `authenticated`, or password-protected `public` attach. |

## Create template

From this directory (or repo root with `--directory template`):

```bash
coder templates create opencode-sandbox --directory template
```

Set `sandbox_image` to your built local image for dev smoke tests, or to a promoted immutable registry digest for production.

When users provide `opencode_config_url`, the rendered startup script fetches that repo on workspace boot, stores it under `~/.opencode-profile/releases/`, and links `~/.config/opencode` to the selected profile. This keeps the managed profile in a cache while still exposing it through OpenCode's global config location. If `~/.config/opencode` already exists outside that managed cache, the script leaves it untouched and logs a warning instead of overwriting it.

When users provide `workspace_repo_urls`, each repo is cloned into `~/workspace/<repo-name>`. GitHub `tree` and `blob` URLs are accepted to pin the ref, but the full repo is still cloned into the workspace root. If the target path already exists, the script leaves it unchanged so local work is not overwritten.

When users provide `workspace_bootstrap_command`, that command runs as `coder` before OpenCode starts. If `workspace_bootstrap_url` is set, the selected repo or GitHub tree/blob path is cached under `~/.workspace-bootstrap/`, and the command runs from that selected directory with `BOOTSTRAP_DIR`, `BOOTSTRAP_REPO_DIR`, and `WORKSPACE_DIR` exported. If no bootstrap URL is set, the command runs from `~/workspace`. Bootstrap scripts must be idempotent because they rerun on every startup. By default, failures and timeouts are logged and OpenCode still starts; set `workspace_bootstrap_failure_policy` to `fail` for strict startup.

When users provide `linux_dotfiles_url`, the selected repo or GitHub tree/blob path is cached under `~/.dotfiles-profile/`. If `linux_dotfiles_install_command` is also set, that shell command runs from the selected dotfiles directory on every startup with `DOTFILES_DIR`, `DOTFILES_REPO_DIR`, and `WORKSPACE_DIR` exported so the command can install tools or apply home-directory changes before OpenCode starts. Dotfiles command timeout and failure behavior use the same workspace bootstrap timeout and failure-policy parameters.

## Persistence

- Volume name: `coder-${data.coder_workspace.me.id}-home` (immutable id only).
- Mount: `/home/coder` (read-write). All OpenCode and user state under home persists across stop/start.
- Managed OpenCode profile cache: `~/.opencode-profile/` persists across stop/start; when `opencode_config_url` is set, `~/.config/opencode` points to the selected managed profile. Repo-local `.opencode` directories remain available for project-specific overrides.
- Managed workspace bootstrap cache: `~/.workspace-bootstrap/` persists across stop/start when `workspace_bootstrap_url` is set.
- **First start:** Named volumes mount as **root:root** at `/home/coder`. The template sets **`user = "0:0"`** and **prepends** a bootstrap to the container **`command`** (before the agent `init_script`) so **`chown`/`mkdir`** run as **real root**; the agent then runs as **`coder`**. See **`../docs/DEBUG_WORKSPACE_VOLUME.md`** if anything still fails — use **`bootstrap.log`** / **`/tmp/coder-opencode-startup.log`**, not blind `sudo` retries.
- Lifecycle: `ignore_changes = all` on the volume so Terraform does not recreate it.

## Container name

- Container name is derived from owner and workspace name, sanitized for Docker (`[a-zA-Z0-9_.-]`, max 63 chars): spaces/slashes/backslashes become dashes, then truncated.
