#!/bin/sh
# Post-deployment script: register/update the opencode-sandbox template in Coder.
# Runs inside the Coder container when Coolify runs the post-deploy command.
# Requires: CODER_URL (default http://127.0.0.1:4099), CODER_TOKEN (set in Coolify env).
# Template is at /templates (mounted from repo template/). Uses our GHCR sandbox image.
set -e

CODER_URL="${CODER_URL:-http://127.0.0.1:4099}"
export CODER_URL
SANDBOX_IMAGE="${SANDBOX_IMAGE:-ghcr.io/zanzythebar/coder-opencode-sandbox:latest}"

if [ -z "${CODER_TOKEN:-}" ]; then
  echo "CODER_TOKEN not set; skipping template push. Set it in Coolify env to automate." >&2
  exit 0
fi

export CODER_SESSION_TOKEN="${CODER_TOKEN}"

# Coder server may not be ready immediately; retry a few times.
max=12
i=0
while [ "$i" -lt "$max" ]; do
  if coder templates push opencode-sandbox -d /templates --variable "sandbox_image=${SANDBOX_IMAGE}" -y 2>/dev/null; then
    echo "Template opencode-sandbox pushed successfully."
    exit 0
  fi
  i=$((i + 1))
  [ "$i" -lt "$max" ] && sleep 5
done

echo "Failed to push template after ${max} attempts." >&2
exit 1
