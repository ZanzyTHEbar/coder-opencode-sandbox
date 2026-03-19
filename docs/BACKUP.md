# Persistence backup (pre-delete export)

When you **delete** a workspace, Coder runs `terraform destroy` and the Docker volume for that workspace is removed. All data under `/home/coder` (OpenCode state, code, config, shell history) is lost unless you back it up first.

**Policy:** For long-lived user data, prefer **stopping** the workspace instead of deleting it. Use backup when you must delete but need to retain data.

---

## Manual backup (export volume to tarball)

You need the **volume name** for the workspace. The template names it:

```text
coder-<workspace-id>-home
```

You can get the workspace ID from the Coder UI (workspace settings or URL) or with:

```bash
coder list
# Or: coder show <workspace-name> (if you have the workspace name)
```

Then on the **host where Coder runs the workspace containers** (where Docker has the volume):

```bash
# Replace WORKSPACE_ID with the actual workspace id (e.g. from Coder UI).
VOLUME_NAME="coder-<WORKSPACE_ID>-home"
BACKUP_FILE="backup-${VOLUME_NAME}-$(date +%Y%m%d-%H%M%S).tar.gz"

docker run --rm \
  -v "${VOLUME_NAME}:/data:ro" \
  -v "$(pwd):/out" \
  alpine \
  tar czf "/out/${BACKUP_FILE}" -C /data .

echo "Created ${BACKUP_FILE}"
```

This creates a tarball of the whole `/home/coder` tree (read-only mount) in the current directory. Restore into a new volume or inspect with `tar tzf ...`.

---

## Optional: upload to S3-compatible storage

After creating the tarball, use `aws s3 cp` (or MinIO/rclone) to upload:

```bash
aws s3 cp "${BACKUP_FILE}" "s3://your-bucket/backups/coder/${BACKUP_FILE}"
```

Use lifecycle or retention policies on the bucket as needed.

---

## Restore (into a new workspace or volume)

Restoring “into a new workspace” means creating a new workspace and then replacing its empty home with the backup. Only do this if you understand Coder’s volume naming and lifecycle.

1. Create a new workspace (same template) and **start** it once so the volume exists.
2. On the host, stop the new workspace’s container (so the volume is unmounted), then:

   ```bash
   NEW_VOLUME_NAME="coder-<NEW_WORKSPACE_ID>-home"
   docker run --rm \
     -v "${NEW_VOLUME_NAME}:/data" \
     -v "$(pwd):/in:ro" \
     alpine \
     sh -c "cd /data && tar xzf /in/${BACKUP_FILE} --strip-components=0"
   ```

3. Start the new workspace again; the restored files will be under `/home/coder`.

Use with care: avoid overwriting a volume that’s in use and match UIDs/permissions if you mix systems.

---

## Summary

- **Before delete:** Export the volume with the `docker run ... alpine tar czf ...` one-liner; optionally upload the tarball to S3.
- **Prefer:** Use “stop” instead of “delete” when you don’t need to reclaim the volume.
- See [OPERATOR.md](OPERATOR.md) for persistence and lifecycle, and [IMPROVEMENTS.md](IMPROVEMENTS.md) for backup in the improvement plan.
