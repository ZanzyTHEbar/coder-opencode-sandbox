#!/usr/bin/env bash
# Bootstrap the opencode-sandbox template in Coder (create or update).
# Uses our Terraform (template/) and GHCR image. Non-interactive when CODER_URL + CODER_TOKEN are set.
#
# Usage:
#   CODER_URL=https://coder.example.com [CODER_TOKEN=...] ./scripts/bootstrap-template.sh
#   # or from repo root: ./scripts/bootstrap-template.sh
#
# Requires: coder CLI (go install coder.com/coder/coder/v2@latest)
set -euo pipefail

SCRIPT_DIR="${BASH_SOURCE%/*}"
REPO_ROOT="${SCRIPT_DIR}/.."
TEMPLATE_NAME="opencode-sandbox"
TEMPLATE_DIR="${REPO_ROOT}/template"
# Must match template/main.tf variable sandbox_image default (GHCR image built by .github/workflows/build-push-image.yml)
SANDBOX_IMAGE="${SANDBOX_IMAGE:-ghcr.io/zanzythebar/coder-opencode-sandbox@sha256:cc1b96eb61212139f4767020b7d094eb179515706083103ef75b1a3da76a25e4}"

cd "$REPO_ROOT"

if ! command -v coder &>/dev/null; then
  echo "coder CLI not found. Install: go install coder.com/coder/coder/v2@latest" >&2
  exit 1
fi

if [[ -z "${CODER_URL:-}" ]]; then
  echo "CODER_URL is required (e.g. https://coder.example.com)" >&2
  exit 1
fi

export CODER_URL

# Non-interactive: use token if set
if [[ -n "${CODER_TOKEN:-}" ]]; then
  export CODER_SESSION_TOKEN="$CODER_TOKEN"
fi

echo "Pushing template '${TEMPLATE_NAME}' from ${TEMPLATE_DIR} (sandbox_image=${SANDBOX_IMAGE})..."
coder templates push "${TEMPLATE_NAME}" \
  --directory "${TEMPLATE_DIR}" \
  --variable "sandbox_image=${SANDBOX_IMAGE}" \
  -y

echo "Template '${TEMPLATE_NAME}' is ready. Users can create workspaces from it."
