# Multi-Tenant E2E Matrix

Run these through public Coder URLs whenever possible. Internal-only checks miss
the auth, wildcard routing, and app-proxy boundary.

## Required Tests

| Test | Expected result |
| --- | --- |
| User A login | Authentik login reaches Coder. |
| User A workspace create | Workspace pod starts; PVCs are created. |
| OpenCode app URL | Wildcard app URL opens at host root. |
| Session persistence | Session/file survives stop/start. |
| User B workspace | Separate pod/PVCs; no User A files. |
| Cross-user app open | User B cannot open User A app URL. |
| Suspend access | Running workspace stops; login/start denied. |
| Retention | PVCs remain during 30-day retention. |
| Network negative | Pod cannot reach LAN/internal services. |
| Egress allowlist | Pod can reach public HTTPS and Git SSH only. |
| Docker negative | Pod has no Docker socket/control. |
| Resource limits | Memory/disk/cpu limits enforce. |
| Log scan | No tokens, private keys, generated passwords, or email-heavy PII. |
| Custom image reject | Foreign `FROM` is rejected. |
| Custom image accept | Approved-base custom image builds and runs by digest. |
| Backup restore | Restored workspace boots with expected marker file/session. |
| Git SSH onboarding | PASS on VM100: private GitHub repo clone E2E passed after deploy-key registration. |
| Config/bootstrap parity | Pending until Kubernetes template matches the Docker template bootstrap features. |

## Minimum Evidence Per Run

- Coder workspace ID and template version.
- Runtime image digest.
- PVC names.
- App URL status.
- Negative-test command output.
- Redacted logs for failed tests only.

Do not onboard external beta users until pending bootstrap and production
hardening cases have concrete automation or an explicit accepted waiver.

## 2026-06-19 Live Smoke

This failed smoke is kept as root-cause history. It is superseded by the
follow-up smoke below.

- Coder buildinfo: public `https://coder.zacariahheim.com/api/v2/buildinfo` returned v2.34.3.
- Kubernetes runtime: namespace `coder` had one ready Coder pod and one ready Postgres pod.
- Existing Coder users: only `admin` was active; no previous OIDC-created users were present.
- Existing workspaces: one active `admin/ws`; three older `admin/ws` records were deleted.
- OIDC multi-user result: blocked before credential entry. The public `OpenID Connect` login redirected to Authentik and Authentik returned `Client ID Error`.
- Temporary Authentik users `coder-e2e-a` and `coder-e2e-b` were created for the smoke and removed after the blocker was confirmed.
- Workspace isolation result: not run, because multi-user OIDC login did not create User A/User B Coder sessions.

## 2026-06-19 Live Smoke Follow-Up

- Root cause: public traffic still traversed `coder-proxy` to the old k3s LXC
  `210`, so the browser received a stale OIDC authorize URL even though the
  current Coder deployment and Authentik provider matched.
- Fix applied: `coder-proxy` on `cool-res` was recreated with the same image,
  host network, restart policy, and listen port, changing only the upstream to
  the current k3s node backing LXC `211`.
- OIDC result: `coder-e2e-a` and `coder-e2e-b` both completed public
  Authentik -> Coder login through `https://coder.zacariahheim.com/login`.
- Workspace create result: `coder-e2e-a/e2e-1` and `coder-e2e-b/e2e-2` were
  created from template `opencode-k8s` through the Coder API.
- Workspace isolation result: each user saw only their own workspace via
  `GET /api/v2/workspaces?q=owner:me&limit=50`; direct `GET` of the other
  user's workspace ID returned `404`.
- Cleanup: both temporary workspaces were deleted through delete builds; the
  temporary Authentik users and local credential file were removed. Coder keeps
  OIDC user/workspace audit rows, with the smoke workspaces marked deleted.

## 2026-06-19 Git SSH Onboarding Status

- Kubernetes template now creates a per-workspace Ed25519 key at `/home/coder/.ssh/id_ed25519` during agent startup.
- The public key is exposed through Coder metadata `Git SSH Key`.
- Kubernetes template now accepts `workspace_repo_urls` and retries missing
  clones on startup. Private clones need the generated public key registered
  with the Git provider first.
- Startup seeds `known_hosts` for `github.com`, `gitlab.com`, and `bitbucket.org` when `ssh-keyscan` is available.
- Seeded Git host keys are a bootstrap convenience, not pinned host-key verification.
- Private Git SSH clone E2E is still blocked pending provider UX or a safe test
  private repo/deploy-key path; Vault persistence remains a separate production
  hardening decision.

## 2026-06-20 Live Restricted Runtime Smoke

- Restricted PodSecurity admission passed for a disposable workspace-shaped
  namespace and non-root pod.
- Static hostPath PV roots must be pre-owned by UID/GID `1800`; `fsGroup` alone
  did not make a root-owned `/home/coder` PV writable.
- Vault Agent injector server-side dry-run passed restricted PodSecurity and
  generated Kubernetes auth config with `audience = "vault"`.
- NetworkPolicy negative probes failed: LAN and Kubernetes API egress remained
  reachable on the current LXC k3s runtime, even though kube-router policy chains
  are present.
- External-user onboarding remains blocked until the runtime has enforcing
  NetworkPolicy and the updated Kubernetes template is pushed with a Coder API
  token and validated through a fresh Coder workspace.

## 2026-06-20 Isolation Gate Script

- Added `scripts/check-k8s-isolation.sh` to create a disposable restricted
  namespace, apply the workspace egress policies, and run DNS, public HTTPS,
  public Git SSH, internal LAN/NodePort, Kubernetes API, and metadata probes.
- Added `scripts/scan-log-secrets.sh` to scan logs without printing matched
  secret text; it reports only `file:line:label`. It covers high-signal secret
  patterns and does not replace manual PII review.
- Live LXC 211 result: DNS, public HTTPS, and public Git SSH were allowed as
  expected; internal Coder NodePort/LAN and Kubernetes API TCP access were also
  allowed, so the gate failed. Metadata was denied.
- External-user onboarding remains blocked until the isolation script passes on
  the target runtime and a fresh Coder workspace/app-access flow is validated.

## 2026-06-20 Batch J VM100 Workspace Smoke

- Coder was wired to VM `100` by mounting the VM kubeconfig into the Coder
  deployment and setting `KUBECONFIG`/`KUBE_CONFIG_PATH`.
- Template versions pushed during the smoke:
  - `batch-j-vm100-pvc-wait`: set `wait_until_bound = false` on `local-path`
    PVCs so Terraform does not wait forever before creating the first consumer
    pod.
  - `batch-j-vm100-user-env`: set `HOME`, `USER`, and `LOGNAME` for Coder agent
    and container processes.
  - `batch-j-vm100-image-user`: changed restricted runtime UID/GID/fsGroup from
    synthetic `1800` to the image's existing `coder` user UID/GID `1001` because
    `ssh-keygen` fails when the UID has no `/etc/passwd` entry.
- Fresh workspaces created from active template `opencode-k8s`:
  - `coder-batchj-a/batchj-imageuser-1`, workspace ID
    `ce764cb1-c592-47a2-b6f8-a384149ae3d6`, namespace
    `opencode-ce764cb1-c592-47a2-b6f8-a384149ae3d6`.
  - `coder-batchj-b/batchj-imageuser-2`, workspace ID
    `e3c61e2d-44bf-4667-bf71-b4cbeca406c6`, namespace
    `opencode-e3c61e2d-44bf-4667-bf71-b4cbeca406c6`.
- Both workspace builds succeeded, pods ran on node `opencode-runtime-vm100`,
  Coder agents connected, and OpenCode app health became `healthy`.
- Owner app URL check: User A opened
  `https://opencode--batchj-imageuser-1--coder-batchj-a.zacariahheim.com/doc`
  and received HTTP `200`.
- Cross-user checks: User B received HTTP `404` for User A's app URL and HTTP
  `404` for direct `GET /api/v2/workspaces/ce764cb1-c592-47a2-b6f8-a384149ae3d6`.
- File isolation smoke: a marker written to User A's `/home/coder/workspace` was
  absent from User B's `/home/coder/workspace`; the marker was removed after the
  check.
- Real workspace NetworkPolicy probes in User A's namespace passed:
  - DNS allowed,
  - public HTTPS allowed,
  - public Git SSH allowed,
  - internal LAN/NodePort denied,
  - Kubernetes API denied,
  - metadata endpoint denied.
- Cleanup: `batchj-imageuser-*` workspaces were deleted, their VM namespaces were
  removed, disposable Authentik users were deleted, the temporary Coder token was
  expired, local temp credential/token files were removed, and temporary Coder
  owner role on `coder-batch-j2` was cleared.
- At the time, secret isolation and Vault secret-read E2E were still pending;
  superseded by Batch P.

## 2026-06-20 Batch K VM100 Stop/Start and Runtime Controls

- Fresh workspace: `coder-batchk-a/batchk-1`, workspace ID
  `957b00af-6844-4502-b62e-077fd662896a`, namespace
  `opencode-957b00af-6844-4502-b62e-077fd662896a`.
- Active template: `opencode-k8s`, version `batch-j-vm100-image-user`.
- Runtime placement: pod ran on node `opencode-runtime-vm100`.
- Docker-negative proof inside the workspace pod:
  - Docker binary absent,
  - `/var/run/docker.sock` absent,
  - `docker ps` denied or unavailable.
- Resource control proof:
  - Kubernetes pod resources: CPU request `500m`, memory request `1Gi`, CPU limit
    `2`, memory limit `4Gi`, ephemeral-storage limit `4Gi`, runAs UID `1001`, no
    privilege escalation, read-only root filesystem.
  - In-pod cgroup limits: `memory.max=4294967296`, `cpu.max=200000 100000`, and
    root filesystem write to `/root` denied.
- Session/file persistence proof:
  - marker `persistence-batchk` was written to `/home/coder/workspace`,
  - workspace was stopped and restarted,
  - marker survived restart and app `/doc` returned HTTP `200` after restart.
- Suspend/stop access proof:
  - stop build reached Coder state `stopped`,
  - VM workspace pod count was `0` while stopped,
  - owner app URL returned HTTP `400` while stopped,
  - restart build returned to Coder state `running` with health `true`.
- Log secret scan proof:
  - Coder deployment logs from the last 2 hours and the Batch K workspace pod log
    were collected under `/tmp/opencode/batchk-log-scan`,
  - `scripts/scan-log-secrets.sh /tmp/opencode/batchk-log-scan` returned
    `log secret scan ok`.

## 2026-06-21 Batch L Private Git SSH Clone E2E

- Temporary private GitHub repo:
  `git@github.com:ZanzyTHEbar/opencode-sandbox-git-e2e-temp.git`.
- First live run found a real bug: Kubernetes `fsGroup`/volume behavior left
  `/home/coder/.ssh/id_ed25519` at mode `0660`, so SSH refused it with
  `UNPROTECTED PRIVATE KEY FILE`.
- Template fix: `template-kubernetes/scripts/agent_startup.sh.tpl` now forces
  `chmod go-rwx "$HOME/.ssh/id_ed25519"` immediately before cloning workspace
  repos.
- Fixed template version pushed to Coder and clone-tested: `batch-l-git-key-mode`,
  version ID `5ae70665-c575-42e6-9e69-2bece35c0497`.
- Follow-up security hardening version pushed after review: `batch-l-url-redaction`.
  It keeps the key-mode fix and also rejects credential-bearing repo URLs before
  clone attempts, and redacts clone failure logging to avoid persisting tokens in
  logs.
- Fresh fixed workspace: `coder-batchk-a/batchl-git-fixed`, workspace ID
  `413176c4-2499-4b84-aac7-93f7f60413e8`.
- Provider registration flow:
  - first start generated a per-workspace public key,
  - public key was added to the disposable private repo as read-only deploy key,
  - workspace was restarted with `workspace_repo_urls` still set.
- Clone proof after restart:
  - key mode was `600`,
  - repo existed at `/home/coder/workspace/opencode-sandbox-git-e2e-temp/.git`,
  - remote was `git@github.com:ZanzyTHEbar/opencode-sandbox-git-e2e-temp.git`,
  - HEAD short SHA was `5caebae`,
  - local app health check passed and Coder app health was `healthy`.
- Cleanup:
  - disposable Coder workspaces were deleted and VM namespaces were removed,
  - read-only deploy keys were removed from the temporary GitHub repo,
  - temporary Coder API/session keys were expired and temporary owner role was
    cleared,
  - disposable Authentik user was deleted and local temp credential files were
    removed,
  - follow-up `gh repo view` returned `404`, confirming the temporary GitHub repo
    is no longer present.

## 2026-06-21 Batch L Vault Target-Runtime Finding

- Before Batch P, Vault server and Vault Agent injector ran only in LXC `211`
  namespace `vault`.
- VM100, the external-user target runtime, had no `vault` namespace and no Vault
  mutating webhook configuration.
- The Kubernetes template had the needed conditional annotations, token automount,
  and Vault egress policy, but full per-workspace Vault secret-read E2E could not
  be proven on VM100 until Vault or an injector path existed on that target
  runtime.
- Do not count an LXC `211` Vault read as external-user isolation proof because
  LXC `211` failed the NetworkPolicy isolation gate.
- Superseded by Batch P, which proved the target-runtime VM100 Vault read path.

## 2026-06-21 Batch N Runtime Image Supply Chain

- Resolved current GHCR `latest` to immutable index digest
  `sha256:cc1b96eb61212139f4767020b7d094eb179515706083103ef75b1a3da76a25e4`.
- Pinned the Kubernetes template `opencode_image`, Docker template
  `sandbox_image`, Coolify compose default, post-deploy default, and bootstrap
  helper default to
  `ghcr.io/zanzythebar/coder-opencode-sandbox@sha256:cc1b96eb61212139f4767020b7d094eb179515706083103ef75b1a3da76a25e4`.
- Trivy scan of the pinned digest with `--severity CRITICAL --ignore-unfixed`
  returned `Total: 0 (CRITICAL: 0)`.
- Syft generated SPDX JSON SBOM evidence at
  `/tmp/opencode/runtime-image-cc1b96eb.spdx.json`.
- `.github/workflows/build-push-image.yml` now scans the pushed image digest and
  uploads an SPDX SBOM artifact for future base-image promotions.
- Live template version `batch-n-pinned-image` was pushed to Coder as active
  version `b1d56349-b6aa-4266-aeb9-f06dcc17c6a6` with `opencode_image` set to
  the pinned digest.
- Fresh smoke workspace `coder-batchn-push/batchn-pinned-1` pulled the pinned
  digest, reported the same container image ID, passed local `/doc` health, and
  returned HTTP `200` on the public app URL; workspace ID
  `606cbd9b-b532-4625-862d-ee03de44643a` was deleted after validation.

## 2026-06-21 Batch O Broader Log Secret and PII Review

- Collected temporary local review set under `/tmp/opencode/batcho-log-review`:
  - Coder deployment logs from the last 24h,
  - Coder namespace events,
  - VM100 Kubernetes events,
  - Authentik server logs from the last 24h.
- `scripts/scan-log-secrets.sh /tmp/opencode/batcho-log-review` returned
  `log secret scan ok`.
- No-value PII heuristic found expected identity/audit email fields:
  - Authentik: structured `user.email` fields,
  - Coder: userauth, notification, and audit log lines.
- Email hits were mostly disposable Batch users; external-domain hits were limited
  to expected operational domains (`gmail.com` and `opencode.local`).
- Sanitized manual sampling found no secret payloads, private keys, generated
  passwords, session cookies, or token values.
- Identity systems still log user email addresses by design; keep support log
  collection minimal and time-bounded.

## 2026-06-21 Batch P VM100 Vault Secret-Read E2E

- Temporary Vault dev server and Vault Agent injector were deployed on VM100 in
  namespace `vault`, with webhook `vault-agent-injector-cfg`.
- Disposable workspace: `coder-batchp-vault/batchp-vault`, workspace ID
  `0c11e71d-5693-4ed8-8abc-5a854aad0ff6`, namespace
  `opencode-0c11e71d-5693-4ed8-8abc-5a854aad0ff6`.
- Temporary Vault policy/role scoped only to
  `kv/data/workspaces/0c11e71d-5693-4ed8-8abc-5a854aad0ff6/git/deploy-key` and
  role `opencode-workspace-0c11e71d-5693-4ed8-8abc-5a854aad0ff6`.
- First live template version `batch-p-vault-e2e` failed because Vault rejected
  the default service-account token audience: `invalid audience (aud) claim`.
- Template fix: `template-kubernetes/kubernetes.tf` now projects a dedicated
  `vault-token` service-account token with audience `vault` and tells the Vault
  injector to use that volume.
- Corrected live version: `batch-p-vault-token-audience`. The first rebuild hit
  a Kubernetes Terraform provider refresh bug on the previously injector-mutated
  Deployment; deleting only the disposable workspace Deployment let Coder
  recreate it from the corrected template.
- Secret delivery proof:
  - build 5 reached `running`, job `succeeded`, health `true`,
  - pod volumes included `vault-token` and `vault-secrets`,
  - `/vault/secrets/git` existed and was non-empty,
  - recent `vault-agent-init` logs had no auth errors,
  - the workspace service-account token could read its own Vault path,
  - the same token was denied on a sibling workspace path.
- App and egress proof:
  - public app URL
    `https://opencode--batchp-vault--coder-batchp-vault.zacariahheim.com/doc`
    returned HTTP `200`,
  - workspace pod allowed public HTTPS, Coder public HTTPS, and Vault service
    egress,
  - workspace pod denied internal LAN/NodePort, Kubernetes API, and metadata
    endpoint egress.
- Cleanup:
  - active template restored to safe Vault-disabled version `batch-p-clean-pinned`,
    version ID `204d99e9-274e-47ab-97c9-783c759b50cf`,
  - disposable workspace was deleted and VM namespace removed,
  - Coder temp user was suspended, roles cleared, and 15 API keys expired,
  - disposable Authentik user was deleted,
  - VM100 `vault` namespace and `vault-agent-injector-cfg` webhook were removed,
  - local and Coder-pod temporary credential/template files were removed.
