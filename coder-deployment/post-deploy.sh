#!/bin/sh
# Post-deployment script: register/update the opencode-sandbox template in Coder.
# Runs inside the Coder container when Coolify runs the post-deployment command.
#
# Template source (POST_DEPLOY_TEMPLATE_SOURCE):
#   auto (default) — Use bind mount ./template → /templates if it passes sanity checks;
#                    otherwise fetch from GitHub so stale Coolify checkouts cannot register old Terraform.
#   mount          — Only the bind mount; fail if missing bootstrap markers (strict).
#   github         — Always fetch from GitHub (ignore mount).
#
# Requires: CODER_URL (default http://127.0.0.1:4099), CODER_TOKEN (set in Coolify env).
# Optional: SANDBOX_IMAGE, POST_DEPLOY_GITHUB_REPO, POST_DEPLOY_GITHUB_REF, POST_DEPLOY_GITHUB_REF_TYPE, POST_DEPLOY_GITHUB_TOKEN
#
# Coolify: post-deployment command MUST run in the **coder** service. See docs/COOLIFY_E2E.md.
set -e

CODER_URL="${CODER_URL:-http://127.0.0.1:4099}"
export CODER_URL
SANDBOX_IMAGE="${SANDBOX_IMAGE:-ghcr.io/zanzythebar/coder-opencode-sandbox:latest}"
MOUNT_TEMPLATE_DIR="${TEMPLATE_DIR:-/templates}"
POST_DEPLOY_TEMPLATE_SOURCE="${POST_DEPLOY_TEMPLATE_SOURCE:-auto}"
POST_DEPLOY_GITHUB_REPO="${POST_DEPLOY_GITHUB_REPO:-ZanzyTHEbar/coder-opencode-sandbox}"
POST_DEPLOY_GITHUB_REF="${POST_DEPLOY_GITHUB_REF:-main}"
POST_DEPLOY_GITHUB_REF_TYPE="${POST_DEPLOY_GITHUB_REF_TYPE:-heads}"

# Set after resolve; may point at fetched tree under /tmp
TEMPLATE_DIR=""
# Temp dir to rm after successful push (only when fetched)
FETCH_TMPDIR=""

echo "post-deploy: start host=$(hostname 2>/dev/null || echo unknown) date=$(date -Iseconds 2>/dev/null || date) source=${POST_DEPLOY_TEMPLATE_SOURCE}" >&2

# Must include volume bootstrap + root user or workspaces get root-owned /home/coder (permission denied on mkdir).
template_verify_ok() {
  _dir="$1"
  _tf="$_dir/main.tf"
  [ -r "$_tf" ] && grep -q 'workspace_volume_bootstrap' "$_tf" 2>/dev/null \
    && grep -q 'user = "0:0"' "$_tf" 2>/dev/null
}

fetch_template_from_github() {
  _repo="$POST_DEPLOY_GITHUB_REPO"
  _ref="$POST_DEPLOY_GITHUB_REF"
  _rtype="$POST_DEPLOY_GITHUB_REF_TYPE"
  _tmpd="/tmp/coder-opencode-template-fetch.$$"
  rm -rf "$_tmpd"
  mkdir -p "$_tmpd"
  _url="https://github.com/${_repo}/archive/refs/${_rtype}/${_ref}.tar.gz"

  echo "post-deploy: fetching template from ${_url}" >&2
  if command -v curl >/dev/null 2>&1; then
    if [ -n "${POST_DEPLOY_GITHUB_TOKEN:-}" ]; then
      curl -fsSL --max-time 180 -H "Authorization: Bearer ${POST_DEPLOY_GITHUB_TOKEN}" "$_url" -o "${_tmpd}/src.tar.gz"
    else
      curl -fsSL --max-time 180 "$_url" -o "${_tmpd}/src.tar.gz"
    fi
  elif command -v wget >/dev/null 2>&1; then
    if [ -n "${POST_DEPLOY_GITHUB_TOKEN:-}" ]; then
      wget -q --header="Authorization: Bearer ${POST_DEPLOY_GITHUB_TOKEN}" -O "${_tmpd}/src.tar.gz" "$_url"
    else
      wget -q -O "${_tmpd}/src.tar.gz" "$_url"
    fi
  else
    echo "post-deploy: FATAL: need curl or wget to fetch template from GitHub" >&2
    exit 1
  fi

  _root=$(tar -tzf "${_tmpd}/src.tar.gz" | head -1 | cut -d/ -f1 | tr -d '\r')
  (cd "$_tmpd" && tar -xzf src.tar.gz)
  TEMPLATE_DIR="${_tmpd}/${_root}/template"
  FETCH_TMPDIR="$_tmpd"

  if ! template_verify_ok "$TEMPLATE_DIR"; then
    echo "post-deploy: FATAL: fetched template failed sanity check (expected bootstrap + user=0:0 in main.tf)" >&2
    rm -rf "$_tmpd"
    exit 1
  fi
  echo "post-deploy: fetched template OK at $TEMPLATE_DIR" >&2
}

resolve_template_dir() {
  case "$POST_DEPLOY_TEMPLATE_SOURCE" in
    github)
      fetch_template_from_github
      ;;
    mount)
      TEMPLATE_DIR="$MOUNT_TEMPLATE_DIR"
      if [ ! -r "$TEMPLATE_DIR/main.tf" ]; then
        echo "post-deploy: FATAL: no readable $TEMPLATE_DIR/main.tf — bind mount empty or wrong Coolify base directory." >&2
        ls -la "$TEMPLATE_DIR" >&2 || true
        exit 1
      fi
      if [ "${POST_DEPLOY_SKIP_TEMPLATE_VERIFY:-}" != "1" ] && ! template_verify_ok "$TEMPLATE_DIR"; then
        echo "post-deploy: FATAL: $TEMPLATE_DIR/main.tf missing bootstrap markers — see docs/COOLIFY_E2E.md" >&2
        echo "Or set POST_DEPLOY_TEMPLATE_SOURCE=auto to fetch from GitHub when the mount is stale." >&2
        exit 1
      fi
      echo "post-deploy: using bind-mounted template at $TEMPLATE_DIR" >&2
      ;;
    auto|*)
      TEMPLATE_DIR="$MOUNT_TEMPLATE_DIR"
      if template_verify_ok "$TEMPLATE_DIR"; then
        echo "post-deploy: bind-mounted template verified OK at $TEMPLATE_DIR" >&2
      else
        echo "post-deploy: bind mount missing or stale; fetching from GitHub (${POST_DEPLOY_GITHUB_REPO} refs/${POST_DEPLOY_GITHUB_REF_TYPE}/${POST_DEPLOY_GITHUB_REF})..." >&2
        fetch_template_from_github
      fi
      ;;
  esac
}

if [ -z "${CODER_TOKEN:-}" ]; then
  echo "CODER_TOKEN not set; skipping template push. Set it in Coolify env after you can log in (see docs/COOLIFY_E2E.md if OIDC is broken)." >&2
  exit 0
fi

if ! command -v coder >/dev/null 2>&1; then
  echo "post-deploy: FATAL: coder CLI not found in PATH — post-deploy must run in the **coder** service container, not database." >&2
  exit 1
fi

resolve_template_dir

export CODER_SESSION_TOKEN="${CODER_TOKEN}"

# Wait until Coder HTTP is accepting traffic (fresh container after redeploy).
wait_for_coder_http() {
  max_wait="${POST_DEPLOY_HEALTH_MAX_WAIT:-90}"
  j=0
  while [ "$j" -lt "$max_wait" ]; do
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

max="${POST_DEPLOY_PUSH_MAX_ATTEMPTS:-24}"
i=0
while [ "$i" -lt "$max" ]; do
  echo "post-deploy: templates push attempt $((i + 1))/${max}..." >&2
  if coder templates push opencode-sandbox -d "$TEMPLATE_DIR" --variable "sandbox_image=${SANDBOX_IMAGE}" -y; then
    echo "Template opencode-sandbox pushed successfully."
    if [ -n "${FETCH_TMPDIR:-}" ]; then
      rm -rf "$FETCH_TMPDIR"
      echo "post-deploy: removed temporary fetch directory" >&2
    fi
    exit 0
  fi
  i=$((i + 1))
  [ "$i" -lt "$max" ] && sleep 5
done

echo "Failed to push template after ${max} attempts." >&2
exit 1
