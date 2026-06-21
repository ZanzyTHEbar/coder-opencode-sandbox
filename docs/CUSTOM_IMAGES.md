# Custom Runtime Images

Users may add layers, but every runnable custom image must inherit from the
approved base OpenCode image.

## Target Policy

- Default runtime uses the platform base image by immutable digest.
- Base image builds require an approved OpenCode release SHA-256.
- Pin the Ubuntu base by digest once the approved runtime digest is selected;
  `ubuntu:24.04` is only acceptable for local scaffold validation.
- Custom image builds run in isolated builder jobs, not inside the workspace pod.
- Builders have no Docker socket.
- Every `FROM` must be the approved base image pinned by digest.
- `COPY --from=` and BuildKit `RUN --mount=from=` may reference only local
  stages, not external images.
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

## Minimal Builder Path

The platform runtime image currently used for external workspaces is pinned to
`ghcr.io/zanzythebar/coder-opencode-sandbox@sha256:cc1b96eb61212139f4767020b7d094eb179515706083103ef75b1a3da76a25e4`.
Batch N scanned that digest with Trivy (`0` critical findings) and generated a
Syft SPDX SBOM. Future base-image workflow runs repeat the scan and upload an
SBOM artifact before promotion.

`scripts/build-custom-image.sh` is the current operator-side baseline. It rejects
Containerfiles with no `FROM`, any `FROM` that is not the approved base, and
approved bases that are not pinned by digest unless `ALLOW_UNPINNED_BASE=1` is
set for local-only testing. It then builds with Docker or Podman:

```bash
APPROVED_BASE_IMAGE=ghcr.io/example/opencode-base@sha256:<digest> \
  scripts/build-custom-image.sh /path/to/Containerfile registry.local/opencode/custom:user-test /path/to/context
```

Use `BUILDER=podman` to avoid Docker on the builder host. This script is an
operator-side promotion helper; it does not enforce the target isolated-builder
or no-Docker-socket policy by itself.

Promotion is explicit. `PUSH_IMAGE=1` requires `SCAN_CMD` and `SBOM_CMD` commands
that consume `$IMAGE_TAG`, then pushes and prints the matching registry digest.
Set `APPROVED_REGISTRY_PREFIX` with a trailing slash to constrain where promoted
images can be pushed:

```bash
APPROVED_BASE_IMAGE=ghcr.io/example/opencode-base@sha256:<digest> \
SCAN_CMD='trivy image --exit-code 1 "$IMAGE_TAG"' \
SBOM_CMD='syft "$IMAGE_TAG" -o spdx-json > custom-image.spdx.json' \
APPROVED_REGISTRY_PREFIX=registry.local/opencode/ \
PUSH_IMAGE=1 \
OUTPUT_DIGEST_FILE=custom-image.digest \
  scripts/build-custom-image.sh /path/to/Containerfile registry.local/opencode/custom:user-test /path/to/context
```

Do not select custom images by mutable tag in Coder. Use the printed digest only.

## Rejection Cases

- Foreign base image.
- Foreign external build source via `COPY --from=` or `RUN --mount=from=`.
- Unpinned approved base image, unless explicitly waived for local testing.
- Missing scan/SBOM command during promotion.
- Privileged runtime requirements.
- Docker socket dependency.
- Secret material copied into final layers.
- Critical scanner result, enforced by the configured `SCAN_CMD`.
