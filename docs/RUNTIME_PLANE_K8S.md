# Runtime Plane: k3s

The runtime plane hosts untrusted OpenCode workspaces. It should be treated as a
separate blast radius from Coolify, Pangolin, Authentik, and the personal
OpenCode runtime.

## Current Live Baseline

Verified on 2026-06-19:

- Proxmox LXC `211`, hostname `opencode-k3s2`.
- Ubuntu 24.04, 4 cores, 8 GiB memory, 50 GiB rootfs, no swap.
- LXC features: `nesting=1`, `keyctl=1`, `fuse=1`.
- k3s `v1.35.5+k3s1`, single control-plane node.
- Runtime: `containerd://2.2.3-k3s1` on Proxmox kernel `6.8.12-17-pve`.
- Default StorageClass: `local-path`, provisioner
  `kubernetes.io/no-provisioner`, reclaim policy `Delete`.
- Coder namespace `coder` runs one ready Coder pod and one ready Postgres pod.
- Coder is exposed by NodePort `30080`; public traffic reaches it through
  Pangolin -> `coder-proxy` on `cool-res` -> LXC `211` k3s node NodePort.
- Coder image: `ghcr.io/coder/coder:v2.34.3`.

The live LXC is a proof-of-life runtime, not the final external-user isolation
target. It proves Coder can run on k3s and that routing can reach Coder headers,
but it does not close real workspace app access, cross-user app denial, VM,
PodSecurity, NetworkPolicy, backup, Vault delivery, or tenant-isolation gates.

## Measured Gaps

- The `coder` namespace has no `pod-security.kubernetes.io/*` labels.
- `template-kubernetes/` labels workspace namespaces as restricted; the VM `100`
  create/start/app-access path passed in the Batch J smoke.
- RuntimeClasses exist, but live workspace pods are not using one.
- The current k3s data plane is flannel with kube-router NetworkPolicy chains
  present. Live negative probes still showed LAN/NodePort and Kubernetes API TCP
  egress were reachable, so workspace NetworkPolicies are not an enforced
  security boundary on this LXC runtime.
- The Kubernetes template relies on `fsGroup` for PVC ownership instead of a root
  init container. The live Coder template uses the image's existing `coder`
  UID/GID `1001`; synthetic UID `1800` broke `ssh-keygen` because it had no
  `/etc/passwd` entry.
- The default `local-path` storage behavior deletes PVC data when claims are
  destroyed; retention/backup is not automated yet.

## 2026-06-20 Restricted Runtime Smoke

- A disposable namespace `opencode-batch-a` with restricted
  `enforce/audit/warn` labels admitted a non-root pod with RuntimeDefault
  seccomp, dropped capabilities, no privilege escalation, read-only rootfs, and
  `automountServiceAccountToken=false`.
- With root-owned static hostPath PV roots, `/home/coder` was not writable by UID
  `1800`; after pre-owning the disposable PV roots as `1800:1800`, both
  `/home/coder` and `/home/coder/workspace` were writable.
- DNS and public HTTPS probes succeeded.
- LAN and Kubernetes API egress probes also succeeded despite default-deny plus
  allowlist NetworkPolicies. Later audit confirmed kube-router NetworkPolicy
  iptables chains exist, so the failure is not simply a missing policy
  controller. Do not treat NetworkPolicy as effective on this LXC runtime.
- Vault Agent injector server-side dry-run passed restricted PodSecurity and
  injected non-root init/sidecar containers. The generated agent config included
  Kubernetes auth `audience = "vault"` after using
  `vault.hashicorp.com/auth-config-audience`.
- The updated local `template-kubernetes/` was not pushed to Coder because no
  Coder API token was available in the live pod. Fresh Coder-template validation
  still requires a token-backed template push.

## 2026-06-20 Isolation Gate Script

`scripts/check-k8s-isolation.sh` now codifies the repeatable runtime egress gate:

- create disposable restricted namespace,
- apply default-deny, DNS allow, and public egress allow policies,
- prove DNS and public HTTPS work,
- prove public Git SSH works,
- prove internal LAN/NodePort, Kubernetes API, and metadata endpoints are denied.

On the current LXC 211 runtime, the script failed because internal NodePort/LAN
access and Kubernetes API TCP access were still allowed. DNS, public HTTPS, and
public Git SSH were allowed; metadata was denied. A follow-up audit found
kube-router NetworkPolicy chains on the host, but the gate still fails. The
runtime remains blocked until all negative probes fail on the target runtime.

## 2026-06-20 Dedicated VM Isolation Smoke

Provisioned disposable Proxmox VM `100` named `opencode-runtime-vm100` at
`192.168.0.50` from `ubuntu-24.04-server-cloudimg-amd64.img`.

Runtime contract:

- image SHA256: `6e7016f2c9f4d3c00f48789eb6b9043ba2172ccc1b6b1eaf3ed1e29dd3e52bb3`,
- VM: 4 vCPU, 8 GiB RAM, 50 GiB disk on `tank`, bridge `vmbr0`, static IP
  `192.168.0.50`,
- k3s: `v1.35.5+k3s1`, install flags `--disable=traefik`,
  `--disable=servicelb`, `--flannel-backend=none`,
  `--disable-network-policy`, `--cluster-cidr=10.42.0.0/16`,
  `--service-cidr=10.43.0.0/16`, and PodSecurity/NodeRestriction admission,
- CNI/policy engine: Calico `v3.30.2`, IPPool `172.16.0.0/16`, IPIP enabled,
- storage: default `local-path` with `WaitForFirstConsumer`,
- Proxmox firewall: not yet codified; this smoke proves pod egress isolation via
  Calico NetworkPolicy, not host-level firewall policy.

`scripts/check-k8s-isolation.sh` passed on this VM:

- DNS allowed,
- public HTTPS allowed,
- public Git SSH allowed,
- internal LAN/NodePort denied,
- Kubernetes API TCP denied,
- metadata endpoint denied.

This resolves the runtime NetworkPolicy enforcement proof for the disposable VM
candidate.

## 2026-06-20 Batch J Coder Workspace Smoke on VM100

Coder was wired to VM `100` by mounting the VM kubeconfig into the Coder
deployment. Active template version `batch-j-vm100-image-user` created two fresh
workspaces on VM `100`:

- `coder-batchj-a/batchj-imageuser-1` in namespace
  `opencode-ce764cb1-c592-47a2-b6f8-a384149ae3d6`,
- `coder-batchj-b/batchj-imageuser-2` in namespace
  `opencode-e3c61e2d-44bf-4667-bf71-b4cbeca406c6`.

Results:

- both workspace builds succeeded,
- both pods ran on node `opencode-runtime-vm100`,
- both Coder agents connected and app health became `healthy`,
- owner app `/doc` returned HTTP `200`,
- cross-user app and direct workspace API access returned HTTP `404`,
- a User A workspace marker was absent from User B's PVC,
- real workspace namespace probes allowed DNS/public HTTPS/public Git SSH and
  denied LAN/NodePort, Kubernetes API, and metadata.

Template fixes required by the smoke:

- `wait_until_bound = false` for `local-path` PVCs, because `WaitForFirstConsumer`
  cannot bind before Terraform creates the first consumer pod,
- `HOME`, `USER`, and `LOGNAME` set for the Coder agent/container,
- run as UID/GID/fsGroup `1001`, matching the image's `coder` user.

External-user onboarding remains blocked by the open gates in
`docs/EXTERNAL_BETA_GATE.md`, not by the Coder-to-VM100 app path.

## 2026-06-20 Batch K Stop/Start and Resource Controls on VM100

Workspace `coder-batchk-a/batchk-1` (`957b00af-6844-4502-b62e-077fd662896a`)
validated runtime behavior beyond initial create/start:

- stop build reached Coder state `stopped`, and VM pod count was `0`,
- owner app URL returned HTTP `400` while stopped,
- restart returned Coder state `running` with health `true`,
- `/home/coder/workspace` marker `persistence-batchk` survived stop/start,
- Docker binary and `/var/run/docker.sock` were absent inside the pod,
- pod limits were present: CPU `2`, memory `4Gi`, ephemeral storage `4Gi`,
- cgroup enforcement matched the limits: `memory.max=4294967296` and
  `cpu.max=200000 100000`,
- root filesystem write to `/root` was denied.
- automated log secret scan of recent Coder/workspace logs returned
  `log secret scan ok`.

## 2026-06-21 Batch L Private Git SSH Clone on VM100

Template version `batch-l-git-key-mode` fixed private Git SSH clone by forcing
the generated key to owner-only mode immediately before Git operations. Follow-up
version `batch-l-url-redaction` kept that fix and added credential-bearing URL
rejection plus redacted clone failure logging.

Fresh workspace `coder-batchk-a/batchl-git-fixed`
(`413176c4-2499-4b84-aac7-93f7f60413e8`) validated the flow against a temporary
private GitHub repo:

- first start generated a per-workspace public key,
- key was registered as a read-only deploy key,
- restart retried `workspace_repo_urls`,
- `/home/coder/.ssh/id_ed25519` mode was `600`,
- `/home/coder/workspace/opencode-sandbox-git-e2e-temp/.git` existed,
- Coder app health was `healthy`.

## 2026-06-21 Batch L Vault Target-Runtime Gap

Before Batch P, Vault existed only on the LXC `211` proof-of-life cluster. VM100
had no `vault` namespace and no Vault Agent injector webhook, so target-runtime
Vault secret-read E2E was open. Do not use LXC `211` Vault reads as
external-user proof because LXC `211` failed the NetworkPolicy isolation gate.

Superseded by Batch P, which deployed temporary Vault + injector on VM100 and
proved the target-runtime read path.

## 2026-06-21 Batch N Runtime Image Digest Pinning

The OpenCode runtime image is pinned to immutable digest
`ghcr.io/zanzythebar/coder-opencode-sandbox@sha256:cc1b96eb61212139f4767020b7d094eb179515706083103ef75b1a3da76a25e4`.
Local supply-chain checks against that digest passed:

- Trivy critical vulnerability scan: `Total: 0 (CRITICAL: 0)`,
- Syft SPDX SBOM generated at `/tmp/opencode/runtime-image-cc1b96eb.spdx.json`.

Future GHCR base-image builds run the same critical scan and upload an SPDX SBOM
artifact in `.github/workflows/build-push-image.yml`.

Live Coder template version `batch-n-pinned-image`
(`b1d56349-b6aa-4266-aeb9-f06dcc17c6a6`) uses the pinned digest. Disposable
workspace `606cbd9b-b532-4625-862d-ee03de44643a` pulled that exact image,
passed local `/doc` health, returned public app HTTP `200`, and was deleted after
validation.

## 2026-06-21 Batch O Log Review

Broader log review covered last-24h Coder deployment logs, Coder events, VM100
events, and Authentik server logs. `scripts/scan-log-secrets.sh` returned
`log secret scan ok`. Manual no-value PII review found expected Authentik
`user.email` fields and Coder auth/audit email fields, mostly disposable Batch
users, but no secret payloads, private keys, generated passwords, session
cookies, or token values.

## 2026-06-21 Batch P Vault Secret Read on VM100

Batch P deployed temporary Vault + Vault Agent injector on VM100, then started
workspace `0c11e71d-5693-4ed8-8abc-5a854aad0ff6` from Coder template version
`batch-p-vault-token-audience`.

Results:

- dedicated projected `vault-token` volume with audience `vault` fixed the Vault
  Kubernetes auth audience mismatch,
- `/vault/secrets/git` was injected and non-empty,
- workspace service-account auth read only its own Vault path and was denied on a
  sibling workspace path,
- public app `/doc` returned HTTP `200`,
- pod egress allowed public HTTPS, Coder public HTTPS, and Vault service access,
  and denied internal LAN/NodePort, Kubernetes API, and metadata endpoints.

Cleanup restored active Coder template `batch-p-clean-pinned`, deleted the
workspace namespace, removed VM100 `vault` and webhook resources, suspended the
temporary Coder user with roles cleared and keys expired, deleted the Authentik
user, and removed temp credential files.

## 2026-06-20 Runtime Plane Decision

Do not retrofit CNI or policy enforcement in-place on LXC `211`. It is a working
proof-of-life stack for Coder, Postgres, routing, OIDC, and Vault injector
admission checks; replacing CNI/policy plumbing on the same single-node LXC risks
downtime without proving external-user isolation.

The production path is a fresh dedicated Proxmox VM runtime plane:

- install k3s with an enforcing NetworkPolicy-capable CNI/policy engine,
- prefer Calico first; Canal is acceptable if flannel data plane compatibility is
  required; defer Cilium until eBPF/kernel complexity is justified,
- run `scripts/check-k8s-isolation.sh` before migrating any Coder workspace,
- only wire Coder to the new plane after DNS/public HTTPS/public Git SSH allow and
  LAN/NodePort/Kubernetes API/metadata deny all pass.

Record the runtime contract before accepting the VM: VM ID/name, OS image digest
or image ID, k3s version, install flags, CNI/policy engine name and version,
pod/service CIDRs, storage class, firewall rules, and the isolation gate output.

LXC `211` remains useful for proof-of-life and regression checks, but it is not
the external-user runtime target.

## Routing Note

`coder-proxy` must target the current k3s node. A stale upstream can still serve
valid Coder buildinfo while returning old OIDC authorize URLs, which looks like
an Authentik client-ID mismatch. Verify the proxy target when OIDC fingerprints
match in Coder/Auth but the browser redirect does not.

## Target Baseline

- Dedicated Proxmox VM, not the current LXC proof-of-life runtime.
- k3s single-node first; multi-node workers later.
- Enforcing NetworkPolicy-capable CNI/policy engine, with Calico as the first
  default candidate.
- Coder Kubernetes provider, not Docker provider, for external workspaces.
- No Docker socket inside Coder or workspace pods.
- StorageClass with per-workspace PVCs and quota strategy.
- RuntimeClass prepared for gVisor/Kata or another measured sandbox runtime.
- PodSecurity `restricted` with explicit exceptions only when measured and
  documented.

## Workspace Resources

Each workspace should get:

- namespace or strict label boundary,
- PVC `home` mounted at `/home/coder`,
- PVC `workspace` mounted at `/home/coder/workspace`,
- deployment/pod running the OpenCode image,
- private service reachable only by Coder agent/app proxy,
- NetworkPolicies for default deny ingress and restricted egress,
- an enforcing NetworkPolicy-capable CNI/runtime,
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
4. Install k3s with an enforcing NetworkPolicy-capable CNI/policy engine.
5. Install storage, RuntimeClass, and monitoring primitives.
6. Run `scripts/check-k8s-isolation.sh`; all negative probes must fail.
7. Deploy Coder against the runtime plane.
8. Register the Kubernetes OpenCode template.
9. Run public-route E2E isolation tests.
