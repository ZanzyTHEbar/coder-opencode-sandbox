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
| Git SSH onboarding | Pending until per-workspace SSH keys are implemented. |
| Config/bootstrap parity | Pending until Kubernetes template matches the Docker template bootstrap features. |

## Minimum Evidence Per Run

- Coder workspace ID and template version.
- Runtime image digest.
- PVC names.
- App URL status.
- Negative-test command output.
- Redacted logs for failed tests only.

Do not onboard external beta users until pending Git/bootstrap/secret-delivery
cases have concrete automation or an explicit accepted waiver.
