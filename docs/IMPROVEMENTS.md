# Improvements: what we're missing and how to do better

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

**Gap:** No clear template version; operators may lose track of the current revision or preferred upgrade mechanisms.

**How to do better:**

- **Repo versioning:** Use git tags (e.g., `v1.0.0`) and/or a `VERSION` file; document the version in the template README or as a template variable.
- **Pin at create:** When running `coder templates create`, use a specific git commit or tag (clone/check out at `vX.Y.Z`), or use a tagged archive.
- **Upgrade path:** Document pulling the latest (or pinned) revision, re-running `coder templates push` (or creating a new template version), and workflows for updating workspaces to the new version. See [OPERATOR.md](OPERATOR.md#9-template-versioning-and-upgrades).

**Status:** OPERATOR.md covers template versioning/upgrades; consider adding a `VERSION` file and tagging releases.

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

- Use a build matrix (e.g., `platforms: linux/amd64,linux/arm64` with buildx) in CI to build/push manifest, ensuring `ghcr.io/.../coder-opencode-sandbox:latest` works on both.

**Status:** In backlog; implement when arm64 demand arises.

---

## 9. OpenCode defaults and first-run experience

**Gap:** The image ships without pre-configured OpenCode settings/providers; users must run `/connect` after first launch.

**How to do better:**

- Document in USER.md: "On first use, open OpenCode app and run `/connect` to link provider credentials."
- Optionally, provide minimal config in `/etc/skel` (e.g., README or snippet in `~/.config/opencode`), but do not store secrets in the image.

**Status:** USER.md can be extended; `/etc/skel` config is backlog.

---

## 10. Smoke-test automation

**Gap:** No end-to-end check ensures that a workspace can be started, have persistent files, stop/start, etc.

**How to do better:**

- Write a CI job/script using Coder API/CLI: create workspace from template, start, wait for OpenCode to be healthy, perform file persistence check (create file, stop/start workspace, verify persistence). Needs running Coder backend/OIDC (or test token); best suited for post-merge/nightly.

**Status:** Backlog; high value but complex to automate.

---

## 11. Encrypt-at-rest for persisted data

**Gap:** Workspace data in Docker volumes is not encrypted at rest, potentially exposing sensitive user or code data if the host filesystem is compromised.

**How to do better:**

- **Manual:** Use encrypted filesystem overlays or Docker volume drivers that provide encryption (e.g., [docker-volume-crypt](https://github.com/gdiepen/docker-volume-crypt), LUKS-backed host directories).
- **Automated:** Document and, if possible, script the setup of encrypted volumes for all user data directories. Encourage operators to enable host-level encryption.
- **Future:** Explore options for default encryption at the Docker or orchestrator level, and integrate encryption practices into template documentation.

**Status:** Not implemented; requires operator action and documentation.

---

## 12. Support for user-created environment templates

**Gap:** Only administrators can create or modify environment templates; users have no self-service mechanism to define and instantiate personalized workspace images.

**How to do better:**

- Design a user-facing UI or CLI workflow for non-admins to define environment templates (via form, YAML, or Dockerfile-like descriptors) and instantiate workspaces on demand.
- Document the procedures and add template examples to USER.md or a dedicated `USER_TEMPLATES.md`.
- Consider permissions and controls so that user templates do not compromise host security or exceed resource allocations.

**Status:** Not yet supported; design/discussion needed, and UI/permission model must be scoped.

---

## 13. Hooks for user environment modification and rebuilds

**Gap:** Users may want to customize their environments (install packages, change config) and recreate/rebuild workspaces with these modifications, but there is no support for environment modification hooks or user-driven rebuild pipelines.

**How to do better:**

- Provide hook mechanisms (pre-build/post-build or pre-start/post-start) allowing user-provided scripts to modify the Docker image or environment before workspace creation, or to trigger rebuilds after changes.
- Offer a "Customize Environment" UI or CLI command that invokes these hooks, optionally capturing user scripts or changes and integrating them into future environment builds.
- Document customization procedures in USER.md and OPERATOR.md, including rollback/reset guidance and safe rollback workflows.

**Status:** Not implemented; requires design and security review.

---

## Priority summary

| Priority | Item                                     | Effort | Status / next step                    |
|----------|------------------------------------------|--------|----------------------------------------|
| P0       | Backup process documented                | Low    | Done: BACKUP.md                        |
| P0       | Wildcard URLs documented                 | Low    | Done: WILDCARD_APP_URLS.md             |
| P0       | Template versioning doc                  | Low    | Done: OPERATOR §9 + optional VERSION   |
| P1       | Wait for OpenCode at startup             | Low    | Done: template startup_script          |
| P1       | CI Terraform validate                    | Low    | Done: workflow job                     |
| P2       | Resource limits (vars)                   | Medium | Backlog                                |
| P2       | Observability subsection                 | Low    | Optional OPERATOR addition             |
| P2       | Encrypt-at-rest for persisted data       | Medium | Backlog; operator and doc required     |
| P3       | Multi-arch image                        | Medium | Backlog                                |
| P3       | OpenCode first-run / skel                | Low    | USER.md + optional skel                |
| P3       | Smoke-test automation                    | High   | Backlog                                |
| P3       | User-created environment templates       | Medium | Backlog; design/permission required    |
| P3       | User environment hooks and rebuilds      | High   | Backlog; design/specification needed   |
