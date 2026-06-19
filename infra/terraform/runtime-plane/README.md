# Runtime Plane Terraform

This directory owns the future dedicated runtime-plane infrastructure contract.
Do not apply it until provider credentials, remote state, and target variables are
set outside git.

Recommended first live apply target:

1. Proxmox VM from an approved Packer image after the current Packer scaffold is
   replaced with a real builder.
2. Firewall rules denying runtime access to internal networks by default.
3. k3s bootstrap outputs for Coder/Kubernetes provider use.
