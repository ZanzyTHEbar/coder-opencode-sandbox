#!/bin/sh
# Register or update the opencode-sandbox template in Coder.
# Runs inside the Coder container from the Coolify post-deployment command.
#
# Template source (POST_DEPLOY_TEMPLATE_SOURCE):
#   deployed_commit (default) — Fetch the exact deployed commit, sync it back into `./template`, then push it.
#   auto                      — Use the bind mount only when it already matches `SOURCE_COMMIT`; otherwise fetch and sync.
#   mount                     — Only the bind mount; fail if stale (strict).
#   github_ref                — Fetch POST_DEPLOY_GITHUB_REF / POST_DEPLOY_GITHUB_REF_TYPE; ignores mount.
#
# Requires: CODER_URL (default http://127.0.0.1:4099), CODER_TOKEN (set in Coolify env).
# Optional: SANDBOX_IMAGE, POST_DEPLOY_GITHUB_REPO, POST_DEPLOY_GITHUB_REF, POST_DEPLOY_GITHUB_REF_TYPE, POST_DEPLOY_GITHUB_TOKEN.
set -e

CODER_URL="${CODER_URL:-http://127.0.0.1:4099}"
export CODER_URL
SANDBOX_IMAGE="${SANDBOX_IMAGE:-ghcr.io/zanzythebar/coder-opencode-sandbox:latest}"
MOUNT_TEMPLATE_DIR="${TEMPLATE_DIR:-/templates}"
POST_DEPLOY_TEMPLATE_SOURCE="${POST_DEPLOY_TEMPLATE_SOURCE:-deployed_commit}"
POST_DEPLOY_GITHUB_REPO="${POST_DEPLOY_GITHUB_REPO:-ZanzyTHEbar/coder-opencode-sandbox}"
POST_DEPLOY_GITHUB_REF="${POST_DEPLOY_GITHUB_REF:-}"
POST_DEPLOY_GITHUB_REF_TYPE="${POST_DEPLOY_GITHUB_REF_TYPE:-heads}"
POST_DEPLOY_SYNC_TEMPLATE_MOUNT="${POST_DEPLOY_SYNC_TEMPLATE_MOUNT:-1}"
TEMPLATE_SOURCE_STAMP_FILE=".coolify-source-commit"

# Set after resolve; may point at a fetched tree under `/tmp`.
TEMPLATE_DIR=""
# Remove this after a successful push when a fetch was required.
FETCH_TMPDIR=""

echo "post-deploy: start host=$(hostname 2>/dev/null || echo unknown) date=$(date -Iseconds 2>/dev/null || date) source=${POST_DEPLOY_TEMPLATE_SOURCE}" >&2

# Require the volume bootstrap and root user override so workspaces do not come up with a root-owned home volume.
template_verify_ok() {
  _dir="$1"
  _tf="$_dir/main.tf"
  [ -r "$_tf" ] && grep -q 'workspace_volume_bootstrap' "$_tf" 2>/dev/null \
    && grep -q 'user = "0:0"' "$_tf" 2>/dev/null \
    && [ ! -e "$_dir/variables.tf" ]
}

template_mount_matches_source_commit() {
  _dir="$1"
  [ -n "${SOURCE_COMMIT:-}" ] \
    && [ -r "$_dir/$TEMPLATE_SOURCE_STAMP_FILE" ] \
    && [ "$(tr -d '\r\n' < "$_dir/$TEMPLATE_SOURCE_STAMP_FILE" 2>/dev/null)" = "$SOURCE_COMMIT" ]
}

sync_template_to_mount() {
  _src="$1"
  _dst="$MOUNT_TEMPLATE_DIR"

  if [ "${POST_DEPLOY_SYNC_TEMPLATE_MOUNT}" != "1" ]; then
    echo "post-deploy: mount sync disabled; leaving bind-mounted template untouched" >&2
    return 0
  fi

  if [ "$_src" = "$_dst" ]; then
    if [ -n "${SOURCE_COMMIT:-}" ]; then
      printf '%s\n' "$SOURCE_COMMIT" > "$_dst/$TEMPLATE_SOURCE_STAMP_FILE"
    fi
    return 0
  fi

  mkdir -p "$_dst"
  if [ ! -w "$_dst" ]; then
    echo "post-deploy: FATAL: $_dst is not writable; cannot sync exact deployed template back to disk." >&2
    ls -ld "$_dst" >&2 || true
    exit 1
  fi

  echo "post-deploy: syncing exact template tree from $_src to $_dst (deleting stale files first)" >&2
  find "$_dst" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  cp -a "$_src"/. "$_dst"/

  if [ -n "${SOURCE_COMMIT:-}" ]; then
    printf '%s\n' "$SOURCE_COMMIT" > "$_dst/$TEMPLATE_SOURCE_STAMP_FILE"
  else
    rm -f "$_dst/$TEMPLATE_SOURCE_STAMP_FILE"
  fi

  TEMPLATE_DIR="$_dst"
}

fetch_template_archive() {
  _url="$1"
  _tmpd="/tmp/coder-opencode-template-fetch.$$"
  rm -rf "$_tmpd"
  mkdir -p "$_tmpd"

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

fetch_template_from_github_ref() {
  _repo="$POST_DEPLOY_GITHUB_REPO"
  _ref="$POST_DEPLOY_GITHUB_REF"
  _rtype="$POST_DEPLOY_GITHUB_REF_TYPE"
  if [ -z "$_ref" ]; then
    _ref="main"
  fi
  fetch_template_archive "https://github.com/${_repo}/archive/refs/${_rtype}/${_ref}.tar.gz"
}

fetch_template_from_source_commit() {
  if [ -z "${SOURCE_COMMIT:-}" ]; then
    echo "post-deploy: FATAL: SOURCE_COMMIT is empty; cannot guarantee template matches deployed stack revision." >&2
    echo "Use POST_DEPLOY_TEMPLATE_SOURCE=auto or github_ref only if exact deployed commit is unavailable." >&2
    exit 1
  fi
  echo "post-deploy: using SOURCE_COMMIT=${SOURCE_COMMIT} as template source of truth" >&2
  fetch_template_archive "https://github.com/${POST_DEPLOY_GITHUB_REPO}/archive/${SOURCE_COMMIT}.tar.gz"
}

resolve_template_dir() {
  case "$POST_DEPLOY_TEMPLATE_SOURCE" in
    deployed_commit)
      fetch_template_from_source_commit
      ;;
    mount)
      TEMPLATE_DIR="$MOUNT_TEMPLATE_DIR"
      if [ ! -r "$TEMPLATE_DIR/main.tf" ]; then
        echo "post-deploy: FATAL: no readable $TEMPLATE_DIR/main.tf — bind mount empty or wrong Coolify base directory." >&2
        ls -la "$TEMPLATE_DIR" >&2 || true
        exit 1
      fi
      if [ "${POST_DEPLOY_SKIP_TEMPLATE_VERIFY:-}" != "1" ] && ! template_verify_ok "$TEMPLATE_DIR"; then
        echo "post-deploy: FATAL: $TEMPLATE_DIR/main.tf missing bootstrap markers." >&2
        echo "Fix: ensure Coolify deploy refreshes the git checkout, or use POST_DEPLOY_TEMPLATE_SOURCE=deployed_commit/auto." >&2
        echo "See docs/TEMPLATE_REGISTRATION.md" >&2
        exit 1
      fi
      echo "post-deploy: using bind-mounted template at $TEMPLATE_DIR" >&2
      ;;
    github_ref|github)
      fetch_template_from_github_ref
      ;;
    auto|*)
      TEMPLATE_DIR="$MOUNT_TEMPLATE_DIR"
      if template_verify_ok "$TEMPLATE_DIR"; then
        if template_mount_matches_source_commit "$TEMPLATE_DIR"; then
          echo "post-deploy: bind-mounted template verified OK and matches SOURCE_COMMIT at $TEMPLATE_DIR" >&2
        else
          echo "post-deploy: bind mount passed sanity checks but is not stamped for SOURCE_COMMIT=${SOURCE_COMMIT}; fetching exact deployed commit..." >&2
          fetch_template_from_source_commit
        fi
      else
        if [ -n "${SOURCE_COMMIT:-}" ]; then
          echo "post-deploy: bind mount missing or stale; fetching exact deployed commit SOURCE_COMMIT=${SOURCE_COMMIT}..." >&2
          fetch_template_from_source_commit
        else
          echo "post-deploy: bind mount missing or stale; SOURCE_COMMIT unavailable, fetching configured GitHub ref..." >&2
          fetch_template_from_github_ref
        fi
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

if [ "$TEMPLATE_DIR" != "$MOUNT_TEMPLATE_DIR" ]; then
  sync_template_to_mount "$TEMPLATE_DIR"
fi

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
