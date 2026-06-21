# Improvements and architecture roadmap

This document enumerates current gaps, desired improvements, and priority areas to make the project more robust, operator-friendly, and maintainable over time.

---

## 1. Persistence backup

**Gap:** Deleting a workspace removes the Docker volume; no built-in backup/export functionality is present.

**How to do better:**

- **Policy:** Prefer **stopping** over **deleting** workspaces containing important data.
- **Manual backup (pre-delete):** Export the Docker volume to a tarball, and optionally upload to S3/MinIO. See [BACKUP.md](BACKUP.md) for example commands and scripts.
- **Future:** Introduce a Coder lifecycle hook or external job to back up `/home/coder` before destruction (if Coder adds hooks or via sidecar containers).

**Status:** Manual backup process is documented in [BACKUP.md](BACKUP.md).

---

## 2. Wildcard app URLs

**Gap:** Without wildcard URLs, users must open the OpenCode app through the Coder dashboard proxy; there are no stable/shareable URLs per workspace app.

**How to do better:**

- Configure Coder’s **wildcard access URL** and TLS so every workspace app gets its own subdomain (e.g., `https://<workspace>-<app>.dev.example.com`).
- Requirements: DNS wildcard (`*.dev.example.com` → Coder), TLS support (wildcard certificate or proxy with ACME), and setting `CODER_WILDCARD_ACCESS_URL` (and possibly direct TLS/proxy termination).

**Status:** Steps are documented in [WILDCARD_APP_URLS.md](WILDCARD_APP_URLS.md).

---

## 3. Template versioning and upgrades

**Gap:** Template versioning exists, but release discipline is still mostly manual. Operators can read the current version, yet tags and upgrade expectations are not fully standardized.

**How to do better:**

- **Repo versioning:** Keep the root `VERSION` file current, use git tags (e.g., `v1.0.0`) for operator-facing releases, and document the version in the template README or release notes.
- **Pin at create:** When running `coder templates create`, use a specific git commit or tag (clone/check out at `vX.Y.Z`), or use a tagged archive.
- **Upgrade path:** Document pulling the latest (or pinned) revision, re-running `coder templates push` (or creating a new template version), and workflows for updating workspaces to the new version. See [OPERATOR.md](OPERATOR.md#9-template-versioning-and-upgrades).

**Status:** The repo already tracks template version in the root `VERSION` file, and OPERATOR.md covers upgrades. Release tags and bump discipline are still a follow-up.

---

## 4. Startup reliability (wait for OpenCode)

**Gap:** The agent’s startup script backgrounds `opencode web` and exits immediately; the healthcheck may run before OpenCode is ready, causing "unhealthy"/502s.

**How to do better:**

- In startup scripts, after starting OpenCode, **wait until** `http://localhost:4096/doc` returns a 2xx (e.g., use `curl` in a loop with a timeout) before exiting the script. This ensures the agent reports ready only when OpenCode responds.

**Status:** Implemented in the template’s `startup_script` (with a wait loop).

---

## 5. CI: validate Terraform

**Gap:** Terraform for the template is only validated locally, not as part of CI (no HCL or provider validation on PRs).

**How to do better:**

- Add a CI job to run `terraform init` and `terraform validate` in `template/`. No Coder backend required for static validation.

**Status:** GitHub Actions now include a validate job.

---

## 6. Resource limits (optional)

**Gap:** No CPU or memory limits are set by the template on workspace containers; heavy users may affect others.

**How to do better:**

- Add template variables (e.g. `memory_limit_mb`, `cpu_limit`) passed to Docker provider via `docker_container` resource (`memory`, `memory_swap`, `cpus`). Set generous defaults; allow org overrides.

**Status:** In backlog; requires Docker provider support and default values.

---

## 7. Observability and logging

**Gap:** OpenCode and startup scripts run inside containers; logs exist only in container stdout/stderr and are not centrally documented.

**How to do better:**

- Document log locations: `docker logs <container>` (or Coder's equivalent) to view workspace logs; Coder server logs for provisioner/agent troubleshooting; OpenCode logs via container stdout.
- Optionally add an "Observability" section in OPERATOR.md (where to find logs, how to correlate with Coder workspace/agent IDs).

**Status:** Basics are in OPERATOR.md troubleshooting; a “Logs and debugging” subsection would help.

---

## 8. Multi-arch image build (optional)

**Gap:** CI builds only for `ubuntu-latest` (amd64); arm64 (e.g., Mac M1/cloud) is not included.

**How to do better:**

- Use a build matrix (e.g., `platforms: linux/amd64,linux/arm64` with buildx) in CI to build/push a manifest, then deploy by immutable digest so both architectures resolve correctly.

**Status:** In backlog; implement when arm64 demand arises.

---

## 9. Workspace/project/server model

**Gap:** The current template starts OpenCode from `~/workspace`, which still encourages a mental model of "one workspace = one OpenCode project". That is too narrow for how OpenCode actually works.

**How to do better:**

- Treat a **Coder workspace** as a persistent Ubuntu machine for one user.
- Treat **OpenCode** as a server process running inside that machine.
- Treat **projects** as directories on disk inside that machine, not as the workspace itself.
- Make the default UX: **one workspace, many projects**.
- Standardize a filesystem layout such as:
  - `~/workspace/projects/*` for repo roots
  - `~/workspace/scratch` for temporary work
  - `~/workspace/shared` for non-repo material
- Document that users can work with multiple repos and parent directories in the same OpenCode server.

**Status:** Decision made. This should become the primary architecture documented in README, USER, OPERATOR, and future template changes.

---

## 10. Shared config vs project config

**Gap:** Shared config should live in OpenCode's global config path instead of being anchored to a single workspace root.

**How to do better:**

- Move shared org/user defaults toward:
  - `OPENCODE_CONFIG_DIR`
  - and/or `~/.config/opencode`
- Reserve repo-local `.opencode` directories and `opencode.json` files for **project-specific** configuration.
- Keep organization defaults, agents, commands, skills, and plugins outside the individual project root where practical.
- Preserve project-level override behavior so repo-local config remains possible and natural.

**Status:** Implemented for managed provisioning: remote OpenCode config now targets `~/.config/opencode`, while repo-local `.opencode` directories remain available for project-specific overrides.

---

## 11. Smoke-test automation

**Gap:** No end-to-end check ensures that a workspace can be started, have persistent files, stop/start, etc.

**How to do better:**

- Write a CI job/script using Coder API/CLI: create workspace from template, start, wait for OpenCode to be healthy, perform file persistence check (create file, stop/start workspace, verify persistence). Needs running Coder backend/OIDC (or test token); best suited for post-merge/nightly.

**Status:** Backlog; high value but complex to automate.

---

## 12. Encrypt-at-rest for persisted data

**Gap:** Workspace data in Docker volumes is not encrypted at rest, potentially exposing sensitive user or code data if the host filesystem is compromised.

**How to do better:**

- **Manual:** Use encrypted filesystem overlays or Docker volume drivers that provide encryption (e.g., [docker-volume-crypt](https://github.com/gdiepen/docker-volume-crypt), LUKS-backed host directories).
- **Automated:** Document and, if possible, script the setup of encrypted volumes for all user data directories. Encourage operators to enable host-level encryption.
- **Future:** Explore options for default encryption at the Docker or orchestrator level, and integrate encryption practices into template documentation.

**Status:** Not implemented; requires operator action and documentation.

---

## 13. Multi-project UX inside a single workspace

**Gap:** The repo does not yet clearly document or scaffold the intended multi-project workflow inside one workspace, even though this is the preferred user experience.

**How to do better:**

- Make "one workspace, many projects" the default documented workflow.
- Create or document canonical project locations such as `~/workspace/projects/<name>`.
- Update USER.md to explain that a single OpenCode workspace can host many repos and directories.
- Update smoke tests and onboarding docs to validate multiple project directories, not just one file in `/home/coder`.
- Ensure the template does not assume the first repo cloned into `~/workspace` is the only meaningful project root.

**Status:** Approved as the preferred UX direction. Docs and future template refinements should align to this model.

---

## 14. Hub-and-satellites mode (advanced)

**Gap:** OpenCode supports interacting with multiple servers, but the repo does not define how that should map to multiple Coder workspaces.

**How to do better:**

- Keep the default mode simple:
  - every workspace runs its own OpenCode web UI
  - every workspace is independently usable
- Introduce a separate advanced concept:
  - one designated workspace acts as a **hub**
  - additional workspaces act as **satellite servers**
- If implemented, satellites should use a headless server model (`opencode serve`) rather than being described as "TUI-only".
- Treat this as a power-user / multi-machine workflow, not the baseline product experience.
- Design explicit requirements before implementing:
  - server discovery
  - authentication
  - routing/network reachability
  - registration UX
  - failure handling when the hub is unavailable

**Status:** Approved conceptually as an advanced future mode. Not recommended as the default UX.

---

## Priority summary

| Priority | Item                                  | Effort | Status / next step                               |
|----------|---------------------------------------|--------|--------------------------------------------------|
| P0       | Backup process documented             | Low    | Done: BACKUP.md                                  |
| P0       | Wildcard URLs documented              | Low    | Done: WILDCARD_APP_URLS.md                       |
| P0       | Template versioning doc               | Low    | Done: OPERATOR §9 + VERSION                      |
| P1       | Wait for OpenCode at startup          | Low    | Done: template startup_script                    |
| P1       | CI Terraform validate                 | Low    | Done: workflow job                               |
| P1       | Workspace/project/server model        | Medium | Decision made; docs should be updated to match   |
| P1       | Multi-project UX in one workspace     | Medium | Approved direction; docs + template follow-up    |
| P2       | Shared config vs project config split | Medium | Move toward `OPENCODE_CONFIG_DIR` / `~/.config`  |
| P2       | Observability subsection              | Low    | Optional OPERATOR addition                       |
| P2       | Resource limits (vars)                | Medium | Backlog                                          |
| P2       | Encrypt-at-rest for persisted data    | Medium | Backlog; operator and doc required               |
| P3       | Hub-and-satellites multi-server mode  | High   | Advanced mode; requires design and network model |
| P3       | Multi-arch image                      | Medium | Backlog                                          |
| P3       | Smoke-test automation                 | High   | Backlog                                          |
