# Retention And Backup

## Policy

- Removing Authentik access suspends the user immediately.
- Running workspaces stop as part of suspension.
- PVCs are retained for 30 days.
- Reactivation during retention restores access to the same PVCs.
- Purge after retention requires a backup decision and audit event.

## Data To Preserve

- `/home/coder/.local/share/opencode`
- `/home/coder/.config/opencode`
- `/home/coder/.opencode/server-password`
- `/home/coder/workspace`
- Git SSH public/private key material. The current Kubernetes scaffold stores it
  on the workspace PVC; the production target is Vault-backed persistence.

## Backup Baseline

1. Snapshot or export PVC data before destructive purge.
2. Encrypt backups before they leave the runtime host.
3. Record workspace ID, template version, image digest, and backup location.
4. Run a restore smoke test on a non-production workspace.

For Kubernetes workspaces, `scripts/backup-k8s-workspace.sh` is the minimal
operator-run export path. It mounts the `home` and `workspace` PVCs read-only in
a temporary restricted pod, streams a tarball to the operator machine, then
prunes local tarballs older than `RETENTION_DAYS`. The script uses a private
umask, writes to a temporary file, and only moves the tarball into place after a
successful stream.

```bash
RETENTION_DAYS=30 scripts/backup-k8s-workspace.sh opencode-<workspace-id> ./backups
```

Stop the workspace before backup when using `ReadWriteOnce` storage. Store the
result on encrypted storage or encrypt it before upload.

Restore an operator-trusted backup into a replacement namespace with existing
`home` and `workspace` PVCs:

```bash
scripts/restore-k8s-workspace.sh opencode-<replacement-workspace-id> \
  ./backups/opencode-<workspace-id>-<timestamp>.tar.gz
```

The restore helper rejects archive entries outside `home/` and `workspace/`,
absolute paths, parent traversal, and links. It mounts the destination PVCs
read-write in a temporary restricted pod and extracts the tarball under `/mnt`.
It does not wipe existing data, but archive entries overwrite matching
destination files. Prefer fresh replacement PVCs. Stop the destination workspace
first when using `ReadWriteOnce` storage.

## Restore Smoke Test

1. Create a replacement workspace record or test workspace with fresh PVCs.
2. Restore home/workspace PVC data with `scripts/restore-k8s-workspace.sh`.
3. Start OpenCode.
4. Verify config, one marker file, and one known session are present.
5. Verify the restored workspace still cannot access internal networks.

## 2026-06-20 Live Restore Smoke

- Created disposable restricted namespaces with `home` and `workspace` PVCs on
  LXC `211`.
- Wrote marker files into the source PVCs as UID/GID `1800`.
- Exported with `scripts/backup-k8s-workspace.sh`.
- Restored with `scripts/restore-k8s-workspace.sh` into replacement PVCs.
- Verified both restored marker files from a restricted non-root pod.
- Cleaned the disposable namespaces and returned their PVs to `Available`.

This smoke proves marker-file export/import mechanics. It does not replace the
remaining production requirements: encrypted off-host storage, checksum or
signature verification for backup provenance, scheduled backup automation, and a
restore drill against a real Coder workspace record.
