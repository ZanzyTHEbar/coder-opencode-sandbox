# OpenCode Docker Infrastructure

This directory supports the requested rollout sequence:

1. Create the latest-stable Debian Docker LXC with the Proxmox community script.
2. Record the script-created LXC contract with Terraform and prepare it with Ansible.
3. Register the LXC in Coolify as a Docker resource server.
4. Deploy OpenCode to that resource server.
5. Add Pangolin/Auth routing only after internal validation.

## Directories

- `terraform/opencode-lxc/`: contract for the Debian Docker LXC created by the Proxmox community script.
- `ansible/`: Docker validation and `/srv/opencode` preparation.
- `coolify/`: resource registration and internal deployment runbook.
- `pangolin/`: public routing/auth runbook for the later phase.

## Execution Boundary

These files are safe to commit. They do not contain live tokens or host-specific secrets.

Actual Proxmox/Coolify/Pangolin changes are live infrastructure mutations and should be run through the DragonServer change-execution workflow with a baseline, rollback note, and post-change verification.

The LXC itself is created by the Proxmox community scripts Docker LXC installer using the latest stable Debian base. Terraform does not create the container.
