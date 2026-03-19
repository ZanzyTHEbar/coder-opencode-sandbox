#!/bin/sh
# Post-deployment script: register/update the opencode-sandbox template in Coder.
# Runs inside the Coder container when Coolify runs the post-deploy command.
# With repo-root docker-compose.yml: ./template → /templates, ./coder-deployment → /deploy (TEMPLATE_DIR defaults to /templates).
# Requires: CODER_URL (default http://127.0.0.1:4099), CODER_TOKEN (set in Coolify env).
# Optional: SANDBOX_IMAGE — must be in compose environment: for Coolify to pass it through.
# Optional: TEMPLATE_DIR — default /templates; override when using fetch-and-run (see docs/COOLIFY_E2E.md).
#
# Coolify (Docker Compose): the post-deployment command MUST be configured to run in the
# **coder** service, not **database**. See docs/COOLIFY_E2E.md § Post-deploy not running.
set -e

CODER_URL="${CODER_URL:-http://127.0.0.1:4099}"
export CODER_URL
SANDBOX_IMAGE="${SANDBOX_IMAGE:-ghcr.io/zanzythebar/coder-opencode-sandbox:latest}"
TEMPLATE_DIR="${TEMPLATE_DIR:-/templates}"

echo "post-deploy: start host=$(hostname 2>/dev/null || echo unknown) date=$(date -Iseconds 2>/dev/null || date)" >&2

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

if ! command -v coder >/dev/null 2>&1; then
  echo "post-deploy: FATAL: coder CLI not found in PATH — post-deploy must run in the **coder** service container, not database." >&2
  exit 1
fi

export CODER_SESSION_TOKEN="${CODER_TOKEN}"

# Wait until Coder HTTP is accepting traffic (fresh container after redeploy).
wait_for_coder_http() {
  max_wait="${POST_DEPLOY_HEALTH_MAX_WAIT:-90}"
  j=0
  while [ "$j" -lt "$max_wait" ]; do
    # /healthz is preferred for readiness; fallback to buildinfo (unauthenticated).
    if curl -sf --max-time 3 "${CODER_URL}/healthz" >/dev/null 2>&1 \
      || curl -sf --max-time 3 "${CODER_URL}/api/v2/buildinfo" >/dev/null 2>&1; then
      echo "post-deploy: Coder HTTP ready (${CODER_URL}) after ${j}s" >&2
      return 0
    fi
    j=$((j + 1))
    sleep 1
  done
  echo "post-deploy: WARN: Coder HTTP not ready after ${max_wait}s — will still try templates push" >&2
  return 0
}

wait_for_coder_http

# Coder server may not be ready for Terraform/provisioner immediately; retry (print errors).
max="${POST_DEPLOY_PUSH_MAX_ATTEMPTS:-24}"
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
