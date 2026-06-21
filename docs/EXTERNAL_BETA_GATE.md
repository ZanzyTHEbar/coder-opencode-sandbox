# External Beta Gate

Do not onboard external users until every required gate is either `PASS` or has
an explicit written waiver. A waiver must name the owner, expiry date, affected
users, compensating controls, and rollback plan. Non-waivable blockers are listed
below.

## Current Decision

Status: **BLOCKED**.

Reason: VM `100` now passes Coder workspace create/start/app-access, real
workspace NetworkPolicy validation, stop/start persistence, stopped-workspace app
revocation, Docker-negative, resource-control checks, private Git SSH clone E2E,
target-runtime Vault secret-read and secret-path denial, pinned runtime-image
scan/SBOM evidence, and broader log secret/PII review. Remaining blockers are
production codification, backup/restore hardening, custom-image self-service, and
template parity items below.

## Required Gates

| Gate | Status | Evidence |
| --- | --- | --- |
| Public OIDC multi-user login | PASS | `docs/E2E_MULTI_TENANT.md` 2026-06-19 follow-up smoke. |
| Coder workspace ownership isolation | PASS | Batch J VM `100` smoke: User A/B each saw own workspace; direct cross-user workspace API returned `404`; cross-user app URL returned `404`; simple A-file marker was absent from B. Batch K proved same-workspace file persistence across stop/start. Batch P proved a workspace service-account token could read only its own Vault path and was denied on a sibling path. |
| Wildcard app routing | PASS | `scripts/check-coder-routing.sh` validates current routing; Batch J owner app URL `https://opencode--batchj-imageuser-1--coder-batchj-a.zacariahheim.com/doc` returned `200`, while User B got `404`. |
| Dedicated runtime plane | PARTIAL | VM `100` with k3s + Calico passed `scripts/check-k8s-isolation.sh` and fresh Coder workspace smoke; VM provisioning/firewall are not codified in Terraform/Packer. |
| Restricted PodSecurity admission | PASS | Batch J template version `batch-j-vm100-image-user` created two restricted workspace pods on VM `100`; both reached `Running`, Coder agent connected, app health `healthy`. |
| PVC ownership under restricted PodSecurity | PASS | Template now uses image user UID/GID `1001` with `fsGroup=1001`; fresh local-path PVC workspaces wrote home/workspace data without a root init container. |
| NetworkPolicy internal egress denial | PASS | Passed on VM `100` using both `scripts/check-k8s-isolation.sh` and real workspace namespace probes; failed on LXC 211, which remains disallowed. |
| Vault Agent injection | PASS | Batch P deployed temporary Vault + injector on VM100, pushed `batch-p-vault-token-audience`, and proved `/vault/secrets/git` injection, same-workspace Vault read, cross-workspace path denial, app `/doc` HTTP `200`, and workspace egress allow/deny policy. Temporary Vault resources were removed and active template was restored to `batch-p-clean-pinned`. |
| Git SSH private clone onboarding | PASS | Batch L fixed private key mode before clone and proved a private GitHub repo clone through a read-only deploy key on VM100 fixed template version `batch-l-git-key-mode`; follow-up version `batch-l-url-redaction` rejects credentialed repo URLs and redacts clone failure logs. Deploy keys, workspaces, and the temporary GitHub repo were cleaned up. |
| Backup and restore | PARTIAL | Marker-file backup/restore smoke passed; off-host encryption, provenance, scheduling, and real workspace restore drill remain. |
| Custom image acceptance/rejection | PARTIAL | Operator helper enforces approved digest base and promotion hooks; isolated self-service builder is not implemented. |
| Log secret scan and PII review | PASS | Batch O scanned Coder deployment logs, Coder events, VM100 events, and Authentik server logs from the last 24h with `scripts/scan-log-secrets.sh`; result `log secret scan ok`. No-value PII review found expected Authentik `user.email` and Coder auth/audit email fields, mostly disposable Batch users, with no secret payloads, private keys, passwords, or token values. |
| Runtime image supply chain | PASS | Batch N pins the OpenCode runtime to `ghcr.io/zanzythebar/coder-opencode-sandbox@sha256:cc1b96eb61212139f4767020b7d094eb179515706083103ef75b1a3da76a25e4`; Trivy critical scan returned 0 findings; Syft generated an SPDX SBOM at `/tmp/opencode/runtime-image-cc1b96eb.spdx.json`; live template version `batch-n-pinned-image` pulled the pinned digest and app `/doc` returned `200`; CI now scans and uploads an SBOM for future GHCR builds. |
| Template parity | PARTIAL | Live Kubernetes template push/create/start/app-access validated as `batch-j-vm100-image-user`; Docker-template parity for OpenCode config bootstrap, workspace bootstrap, and dotfiles remains incomplete. |
| Session persistence | PASS | Batch K marker in `/home/coder/workspace` survived Coder stop/start on VM `100`; app `/doc` returned `200` after restart. |
| Suspend access | PASS | Batch K stop build reached state `stopped`; workspace pod count was `0`; owner app URL returned HTTP `400` while stopped; restart returned state `running`. |
| Docker negative | PASS | Batch K workspace pod had no Docker binary, no `/var/run/docker.sock`, and `docker ps` was denied or unavailable. |
| Resource limits | PASS | Batch K pod had CPU/memory/ephemeral limits; in-pod cgroup proof showed `memory.max=4294967296`, `cpu.max=200000 100000`, and read-only root writes were denied. |

## Operator Runbook

1. Run `scripts/check-coder-routing.sh` from the repo root.
2. Push the current `template-kubernetes/` to Coder with a scoped API token.
3. Create two disposable OIDC users and one workspace each.
4. Verify each user only sees their own workspace and cannot fetch the other
   workspace ID or app URL.
5. Run `scripts/check-k8s-isolation.sh` on the dedicated VM target runtime. All
   negative probes must fail before Coder is wired to that plane. VM `100`
   passed once as a runtime gate and once through a real workspace namespace.
6. Run a Vault Agent secret-read E2E with a disposable per-workspace policy,
   role, and test secret; delete the secret and role after the test.
7. Run a private Git SSH clone E2E using a disposable private repo or deploy key.
8. Run backup plus restore into fresh replacement PVCs and verify marker files or
   a real workspace restore drill.
9. Run custom image reject/accept tests and select only pushed registry digests.
10. Run `scripts/scan-log-secrets.sh` against collected Coder, workspace,
    provisioner, and operator logs, then perform manual PII review.
11. Record evidence links, workspace IDs, template version, image digest, and
    rollback plan before inviting users.

## Waiver Template

```markdown
Gate:
Status: WAIVED
Owner:
Expiry:
Affected users:
Risk accepted:
Compensating controls:
Rollback plan:
Evidence reviewed:
```

## Non-Waivable Blockers

No waiver may cover:

- raw secret leakage,
- cross-user data, app, file, session, or secret access,
- unrestricted workspace access to DragonServer infrastructure,
- failed internal egress denial on the target runtime,
- wiring Coder to a runtime that has not passed `scripts/check-k8s-isolation.sh`,
- using LXC 211 as the external-user runtime target,
- missing fresh Coder-template create/start/app-access validation.
