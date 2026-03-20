# User guide: OpenCode sandbox on Coder

## Log in

1. Open your organization’s Coder URL (e.g. `https://dev.example.com`).
2. Log in with **OIDC** (e.g. “Sign in with Authentik”). Use your normal IdP credentials.

## Create and use your workspace

1. **Create a workspace** from the **OpenCode sandbox** template (e.g. name it `opencode` or `main`). One workspace per user is enough; you can reuse it.
2. Optional: set **OpenCode config URL** to a Git or GitHub repo that contains your OpenCode config. You can also set **OpenCode config ref** and **OpenCode config subdirectory** if needed.
3. **Start** the workspace. The first time may take a minute while the container, volume, and any requested OpenCode profile are created.
4. In the workspace dashboard you’ll see:
   - **OpenCode** — opens the OpenCode web UI (AI-assisted coding, sessions, projects).
   - **Terminal** — shell in the same environment (clone repos, run commands, install tools).

## Your data

- Everything in your home directory (`/home/coder`), including:
  - OpenCode sessions and state (`~/.local/share/opencode/`),
  - OpenCode config (`~/.config/opencode/`),
  - Provisioned OpenCode profile cache (`~/.opencode-profile/`),
  - Your code (e.g. `~/workspace`),
  - Shell history and dotfiles,
  is stored on a **persistent volume** and survives **Stop** and **Start**.
- If you set **OpenCode config URL**, the workspace creates a managed profile under `~/.opencode-profile/` and links `~/workspace/.opencode` to it.
- When you **stop** the workspace, the container is shut down but your data stays. **Start** again to get back the same environment.
- **Deleting** the workspace removes the volume and all data. Only delete when you no longer need that sandbox.

## Tips

- Use **Stop** when you’re done for the day to free resources; **Start** when you return.
- Put your code under `~/workspace` (or any folder under `/home/coder`) so it’s persisted.
- If you use a custom OpenCode config repo, treat `~/workspace/.opencode` as managed by the template unless you intentionally replace it.
- Configure LLM providers (e.g. API keys) in OpenCode’s settings; they’re stored in your home and persist across restarts.
