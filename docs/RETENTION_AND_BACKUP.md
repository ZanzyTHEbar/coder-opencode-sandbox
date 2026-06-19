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
- Git SSH public/private key material, stored through Vault-backed paths.

## Backup Baseline

1. Snapshot or export PVC data before destructive purge.
2. Encrypt backups before they leave the runtime host.
3. Record workspace ID, template version, image digest, and backup location.
4. Run a restore smoke test on a non-production workspace.

## Restore Smoke Test

1. Create a replacement workspace record or test workspace.
2. Restore home/workspace PVC data.
3. Start OpenCode.
4. Verify config, one marker file, and one known session are present.
5. Verify the restored workspace still cannot access internal networks.
