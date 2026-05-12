# Ansible: OpenCode Resource Server

This prepares the latest stable Debian Docker LXC created by the Proxmox community scripts Docker installer for Coolify resource-server registration.

## Install Collections

```sh
ansible-galaxy collection install -r requirements.yml
```

## Inventory

Copy the example inventory and replace the IP after the community script creates the Debian LXC:

```sh
cp inventory/hosts.example.ini inventory/hosts.ini
$EDITOR inventory/hosts.ini
```

## Run

```sh
ansible-playbook -i inventory/hosts.ini playbooks/opencode-resource-server.yml
```

The playbook:

- verifies Docker Engine and Compose plugin installed by the community script
- enables Docker
- creates `/srv/opencode/{home,projects,logs,backups}`
- creates the `coolify` Docker network for validation/standalone testing
- enables a minimal UFW policy with SSH allowed

Public routing needs a later, explicit firewall change once Pangolin/Coolify routing is known. Do not open `4096` publicly; prefer allowing only the Pangolin/Newt/proxy source to `80`/`443` or the required internal listener.

Root SSH is used for bootstrap because the community-script-created LXC starts as an infrastructure host. If a long-lived operator account is desired, add it after Docker/Coolify registration and update inventory accordingly.

Coolify may create or manage its own Docker network after registration. If that happens, confirm the network name and update `opencode-docker/docker-compose.yaml` if it is not `coolify`.

## Ownership

The persistent directories are owned by UID/GID `1800` by default. The OpenCode image pins its in-container `coder` user to the same UID/GID, starts as root to fix top-level mount ownership, and then drops privileges.

If migrated files arrive with incompatible nested ownership, either fix them on the host before deployment or temporarily set `OPENCODE_CHOWN_RECURSIVE=true` for one container start.
