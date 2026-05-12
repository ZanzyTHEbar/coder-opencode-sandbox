# Proxmox LXC Resource Server

Use a dedicated LXC for the Docker-only OpenCode runtime.

## Initial Shape

- OS: latest stable Debian from the Proxmox community scripts Docker LXC installer.
- CPU: 4-8 vCPU.
- RAM: 8-16 GB.
- Disk: 100-250 GB.
- Docker-compatible LXC features selected by the community script.
- Persistent storage under `/srv/opencode`.
- No unrelated production services.

## Why Dedicated

OpenCode is developer compute. It may hold repositories, shell history, package caches, credentials, OpenCode state, and arbitrary build output.

Keeping it on its own LXC reduces blast radius compared to the shared `cool-res` host while preserving Coolify deployment and rollback workflows.

## Provisioning Sequence

Future execution should use the `dragonserver-change-execution` workflow.

High-level order:

1. Run the Proxmox community scripts Docker LXC installer on Proxmox.
2. Choose the latest stable Debian base.
3. Select the OpenCode runtime sizing.
4. Create `/srv/opencode/{home,projects,logs,backups}`.
5. Register the LXC as a Coolify resource server.
6. Deploy `opencode-docker/docker-compose.yml` internally.
7. Validate persistence and health before any public route.

Terraform records the script-created LXC contract in `infra/terraform/opencode-lxc/`; Ansible prepares `/srv/opencode` and validates Docker in `infra/ansible/`.

## Backup Boundary

Back up `/srv/opencode` before migration and before public cutover.

Retain the old Coder workspace/volumes until the Docker-only service has soaked successfully.
