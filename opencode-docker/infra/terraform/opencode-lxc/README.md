# Terraform: OpenCode LXC Contract

The OpenCode runtime LXC is created with the latest stable Debian option from the Proxmox community scripts Docker LXC installer.

Terraform does not create the LXC. It records and validates the contract for the script-created Debian Docker LXC, then emits the Ansible inventory hint and Coolify registration note.

Community script entrypoint:

```text
https://community-scripts.github.io/ProxmoxVE/scripts?id=docker
```

Run the installer on Proxmox, choose the latest stable Debian base, select the OpenCode sizing, then copy the resulting CTID/IP into `terraform.tfvars`.

## Usage

```sh
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars
terraform init
terraform plan
terraform apply
```

Use the `ansible_inventory_hint` output as the starting point for `../ansible/inventory/hosts.ini`.

## Docker LXC Notes

The Proxmox community script is responsible for the Debian LXC and Docker-compatible features. If Docker does not start, fix the script-created LXC profile explicitly during the DragonServer change-execution phase rather than hiding host-specific changes in Terraform.

Do not put host-specific values or secrets in git. `terraform.tfvars` should remain local/private.
