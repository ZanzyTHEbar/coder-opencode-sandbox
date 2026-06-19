# VM Images With Packer

Packer will build immutable runtime VM images for the dedicated k3s plane. The
current `infra/packer/runtime-node.pkr.hcl` is a validation scaffold only: it
uses a null builder and does not create a VM image yet.

## Image Responsibilities

- Pinned base OS.
- k3s prerequisites.
- Runtime kernel/modules required by storage and NetworkPolicy.
- Node hardening baseline.
- Monitoring/logging agents if used.
- No tenant data.
- No platform secrets baked into the image.

## Promotion Flow

1. Replace the null builder with a real Proxmox/QEMU source.
2. Keep Proxmox credentials, target IDs, and storage IDs outside git.
3. Build image from `infra/packer/runtime-node.pkr.hcl`.
4. Smoke boot a test VM.
5. Run k3s/node readiness checks.
6. Promote the image ID through Terraform variables.
7. Drain/replace runtime nodes through the VM orchestrator path.
