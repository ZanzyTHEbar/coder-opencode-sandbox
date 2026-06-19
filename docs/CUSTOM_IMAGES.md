# Custom Runtime Images

Users may add layers, but every runnable custom image must inherit from the
approved base OpenCode image.

## Policy

- Default runtime uses the platform base image by immutable digest.
- Base image builds require an approved OpenCode release SHA-256.
- Pin the Ubuntu base by digest once the approved runtime digest is selected;
  `ubuntu:24.04` is only acceptable for local scaffold validation.
- Custom image builds run in isolated builder jobs, not inside the workspace pod.
- Builders have no Docker socket.
- The first effective `FROM` must be the approved base image or digest.
- Build secrets are mounted as build secrets only; never baked into layers.
- Output is pushed to an internal registry by digest.
- Scan/SBOM must pass before the digest is selectable.
- Restart/recreate uses the new digest while PVCs persist.

## User Flow

1. User edits `/home/coder/.opencode-image/Containerfile`.
2. User starts a build action.
3. Builder validates base inheritance.
4. Builder builds, scans, and pushes by digest.
5. Workspace metadata records the digest.
6. User restarts workspace.
7. New pod starts with the custom digest and existing PVCs.

## Rejection Cases

- Foreign base image.
- Privileged runtime requirements.
- Docker socket dependency.
- Secret material copied into final layers.
- Critical scanner result without explicit operator override.
