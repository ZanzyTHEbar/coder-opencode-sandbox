# Runtime Plane Terraform

This directory owns the future dedicated runtime-plane infrastructure contract.
Do not apply it until provider credentials, remote state, and target variables are
set outside git.

Recommended first live apply target:

1. Proxmox VM from an approved Packer image after the current Packer scaffold is
   replaced with a real builder.
2. Firewall rules denying runtime access to internal networks by default.
3. k3s installed with an enforcing NetworkPolicy-capable CNI/policy engine.
   Calico is the default first candidate; Canal is acceptable if flannel data
   plane compatibility is required.
4. `scripts/check-k8s-isolation.sh` passing before Coder is pointed at the VM.
5. k3s bootstrap outputs for Coder/Kubernetes provider use.

Record the accepted runtime contract with the apply evidence: VM ID/name, image
ID, k3s version and install flags, CNI/policy engine name and version,
pod/service CIDRs, storage class, firewall rules, and isolation-gate output.

Do not retrofit CNI on LXC `211`. It is a proof-of-life runtime and currently
fails the internal NodePort/LAN and Kubernetes API deny probes despite visible
kube-router NetworkPolicy chains.

## 2026-06-20 Disposable VM Candidate

VM `100` (`opencode-runtime-vm100`, `192.168.0.50`) proved the minimum runtime
direction works: k3s `v1.35.5+k3s1` with flannel disabled and Calico `v3.30.2`
passed `scripts/check-k8s-isolation.sh`.

This is evidence, not yet Terraform state. Before using a runtime for external
users, codify or record the VM contract, firewall policy, image source, k3s
flags, CNI version, pod/service CIDRs, storage class, and isolation output.
