#!/bin/sh
# Post-deployment script: register/update the opencode-sandbox template in Coder.
# Runs inside the Coder container when Coolify runs the post-deploy command.
# With repo-root docker-compose.yml: ./template → /templates, ./coder-deployment → /deploy (TEMPLATE_DIR defaults to /templates).
# Requires: CODER_URL (default http://127.0.0.1:4099), CODER_TOKEN (set in Coolify env).
# Optional: SANDBOX_IMAGE — must be in compose environment: for Coolify to pass it through.
# Optional: TEMPLATE_DIR — default /templates; override when using fetch-and-run (see docs/COOLIFY_E2E.md).
set -e

CODER_URL="${CODER_URL:-http://127.0.0.1:4099}"
export CODER_URL
SANDBOX_IMAGE="${SANDBOX_IMAGE:-ghcr.io/zanzythebar/coder-opencode-sandbox:latest}"
TEMPLATE_DIR="${TEMPLATE_DIR:-/templates}"

# Fail loud if the template tree is missing (wrong Coolify base dir or broken bind mount).
if [ ! -r "$TEMPLATE_DIR/main.tf" ]; then
  echo "post-deploy: FATAL: no readable $TEMPLATE_DIR/main.tf — bind mount likely empty. Coolify Base directory must be repo root (.) so ./template mounts to /templates." >&2
  ls -la "$TEMPLATE_DIR" >&2 || true
  exit 1
fi

if [ -z "${CODER_TOKEN:-}" ]; then
  echo "CODER_TOKEN not set; skipping template push. Set it in Coolify env after you can log in (see docs/COOLIFY_E2E.md if OIDC is broken)." >&2
  exit 0
fi

export CODER_SESSION_TOKEN="${CODER_TOKEN}"

# Coder server may not be ready immediately; retry a few times (print errors; do not hide stderr).
max=12
i=0
while [ "$i" -lt "$max" ]; do
  echo "post-deploy: templates push attempt $((i + 1))/${max}..." >&2
  if coder templates push opencode-sandbox -d "$TEMPLATE_DIR" --variable "sandbox_image=${SANDBOX_IMAGE}" -y; then
    echo "Template opencode-sandbox pushed successfully."
    exit 0
  fi
  i=$((i + 1))
  [ "$i" -lt "$max" ] && sleep 5
done

echo "Failed to push template after ${max} attempts." >&2
exit 1
