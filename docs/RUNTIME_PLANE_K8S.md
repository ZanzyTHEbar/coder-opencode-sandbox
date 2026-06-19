# Runtime Plane: k3s on a Dedicated VM

The runtime plane hosts untrusted OpenCode workspaces. It should be treated as a
separate blast radius from Coolify, Pangolin, Authentik, and the personal
OpenCode runtime.

## Baseline

- Dedicated Proxmox VM.
- k3s single-node first; multi-node workers later.
- Coder Kubernetes provider, not Docker provider, for external workspaces.
- No Docker socket inside Coder or workspace pods.
- StorageClass with per-workspace PVCs and quota strategy.
- RuntimeClass prepared for gVisor/Kata evaluation.
- PodSecurity restricted with explicit exceptions only when measured.

## Workspace Resources

Each workspace should get:

- namespace or strict label boundary,
- PVC `home` mounted at `/home/coder`,
- PVC `workspace` mounted at `/home/coder/workspace`,
- deployment/pod running the OpenCode image,
- private service reachable only by Coder agent/app proxy,
- NetworkPolicies for default deny ingress and restricted egress,
- resource requests/limits and quota.

## Egress Policy

Allowed by default:

- DNS,
- public HTTPS on TCP `443`,
- public Git SSH on TCP `22`.

Denied by default:

- RFC1918/private LAN ranges,
- CGNAT, loopback, link-local, multicast, and reserved ranges,
- Proxmox/Coolify/Pangolin/Auth/Postgres networks,
- Kubernetes API unless explicitly needed,
- cloud metadata IPs,
- runtime-node host services.

Internal egress exceptions require an explicit admin policy plus a negative E2E
test proving other internal destinations remain denied.

## Rollout Order

1. Replace the current Packer null-builder scaffold with a real Proxmox/QEMU VM
   image build.
2. Build VM image with Packer.
3. Provision VM and firewall with Terraform.
4. Install/configure k3s.
5. Install storage, NetworkPolicy, RuntimeClass, and monitoring primitives.
6. Deploy Coder against the runtime plane.
7. Register the Kubernetes OpenCode template.
8. Run public-route E2E isolation tests.
