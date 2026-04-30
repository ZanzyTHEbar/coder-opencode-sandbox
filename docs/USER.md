# User guide: OpenCode sandbox on Coder

## Log in

1. Open your organization’s Coder URL (e.g. `https://dev.example.com`).
2. Log in with **OIDC** (e.g. “Sign in with Authentik”). Use your normal IdP credentials.

## Create and use your workspace

1. **Create a workspace** from the **OpenCode sandbox** template (e.g. name it `opencode` or `main`). Use one long-lived workspace for many repos unless you intentionally need isolation.
2. Optional: set **OpenCode config URL** to a Git URL or GitHub repo/tree/blob URL that contains your OpenCode config. You can also set **OpenCode config ref** and **OpenCode config subdirectory** if needed.
3. Optional: set **Workspace repo URLs** to a comma-separated list of repos to clone into `~/workspace`, and/or set **Linux dotfiles URL** plus **Linux dotfiles install command** if you want to bootstrap the Linux environment itself.
4. Optional: set **OpenCode app sharing** to **Public URL attach** only if you need `opencode attach https://<app-url>` from a local machine without Coder browser cookies. This mode is protected by a generated OpenCode server password. Keep **Owner only** for normal browser, terminal, SSH, and port-forward workflows.
5. **Start** the workspace. The first time may take a minute while the container, volume, requested OpenCode profile, workspace repos, and any dotfiles bootstrap are created.
6. In the workspace dashboard you’ll see:
    - **OpenCode** — opens the OpenCode web UI (AI-assisted coding, sessions, projects).
    - **Terminal** — shell in the same environment (clone repos, run commands, install tools).

## Standard workflow

1. Keep repos under `~/workspace`. A single workspace can contain many repos and scratch directories.
2. Open **OpenCode** from the Coder workspace page for browser work.
3. Open **Terminal** from the workspace page when you need a shell in the same persistent environment.
4. From a local machine, run `coder ssh <workspace>` for direct terminal access after logging in with the Coder CLI.
5. Use **Stop** when finished for the day. Do not **Delete** unless you are ready to remove the persistent home volume.

## Attach the OpenCode TUI

OpenCode runs one backend in the workspace on `127.0.0.1:4096`. Browser UI and TUI attach clients connect to that same backend, so sessions and state are shared.

### Inside the workspace

Use the Coder terminal or SSH into the workspace, then run:

```bash
opencode attach http://127.0.0.1:4096
```

### From a local machine with port forwarding

Forward the OpenCode port through Coder SSH, then attach locally:

```bash
coder port-forward <workspace> --tcp 4096:4096
opencode attach http://127.0.0.1:4096
```

If port `4096` is busy locally, forward to another local port and attach to that port instead.

### From a public workspace app URL

This requires **OpenCode app sharing** set to **Public URL attach**. That setting opens public HTTPS routing, but OpenCode requires the generated server password before exposing sessions. Prefer `coder port-forward` unless public HTTPS attach is explicitly needed.

Read the generated password from inside the workspace, open the **OpenCode** app once from the Coder workspace page, and copy the app URL. Browser password prompts use username `opencode`. Then run:

```bash
coder ssh <workspace> -- cat /home/coder/.opencode/server-password
opencode attach --password '<server-password>' https://<opencode-app-url>
```

Treat the copied URL and server password as workspace access secrets.

## Your data

- Everything in your home directory (`/home/coder`), including:
  - OpenCode sessions and state (`~/.local/share/opencode/`),
  - OpenCode config (`~/.config/opencode/`),
  - Provisioned OpenCode profile cache (`~/.opencode-profile/`),
  - Your code (e.g. `~/workspace`),
  - Shell history and dotfiles,
  is stored on a **persistent volume** and survives **Stop** and **Start**.
- If you set **OpenCode config URL**, the workspace creates a managed profile under `~/.opencode-profile/` and links `~/.config/opencode` to it.
- Repo-local `.opencode` directories and `opencode.json` files remain available for project-specific overrides inside cloned repos or other workspace folders.
- If you set **Workspace repo URLs**, each missing repo is cloned into `~/workspace/<repo-name>`. Existing files, directories, and repos are left untouched.
- If you set **Linux dotfiles URL**, the selected dotfiles repo is cached under `~/.dotfiles-profile/`. When **Linux dotfiles install command** is set, that command reruns on every startup so it can reapply home-directory changes or install tools in the recreated container.
- When you **stop** the workspace, the container is shut down but your data stays. **Start** again to get back the same environment.
- **Deleting** the workspace removes the volume and all data. Only delete when you no longer need that sandbox.

## Tips

- Use **Stop** when you’re done for the day to free resources; **Start** when you return.
- Put your code under `~/workspace` (or any folder under `/home/coder`) so it’s persisted.
- If you use a custom OpenCode config repo, treat `~/.config/opencode` as managed by the template unless you intentionally replace it. If you already have your own unmanaged file, directory, or symlink there, the template leaves it alone and logs a warning.
- **Linux dotfiles install command** runs from the selected dotfiles directory with `DOTFILES_DIR`, `DOTFILES_REPO_DIR`, and `WORKSPACE_DIR` exported. Use it for commands like `./install.sh`, `make bootstrap`, or `stow bash git`.
- Configure LLM providers (e.g. API keys) in OpenCode’s settings; they’re stored in your home and persist across restarts.
