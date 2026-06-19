# Encryption Model

## Mode 1: Platform Encryption At Rest

Default MVP mode.

- Runtime VM disk encrypted with LUKS or ZFS native encryption.
- Storage layer may add per-PVC or per-dataset encryption.
- Backups encrypted before leaving the runtime host.
- Platform can mount/decrypt volumes while a workspace runs.

This protects powered-off disks, backups, and storage exposure. It does not hide
data from a compromised runtime host while the workspace is running.

## Mode 2: User-Held Workspace Unlock

Optional later mode.

- Workspace volume key is user-held or user-wrapped.
- User unlocks at start time.
- Stopped workspace data cannot be mounted without user unlock.
- Running workspace still sees plaintext because OpenCode and user commands need
  plaintext files.

Evaluate later with ZFS native encryption, LUKS image volumes, or a CSI driver
that fits k3s. Do not block the MVP on this mode.
