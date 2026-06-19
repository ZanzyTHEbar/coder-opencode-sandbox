#!/bin/sh
set -eu

HOME=/home/coder
export HOME

mkdir -p "$HOME/.opencode" "$HOME/workspace"
chmod 700 "$HOME/.opencode"

BINARY_DIR="${BINARY_DIR:-$(mktemp -d -t coder.XXXXXX)}"
BINARY_NAME=coder
CODER_URL="${CODER_AGENT_URL:-http://coder.coder.svc.cluster.local}"
BINARY_URL="${CODER_URL}/bin/coder-linux-amd64"
cd "$BINARY_DIR"

while :; do
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --compressed "$BINARY_URL" -o "$BINARY_NAME" && break
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$BINARY_URL" -O "$BINARY_NAME" && break
  else
    echo "no download tool found" >&2
    exit 127
  fi
  echo "retrying coder agent download in 10s..." >&2
  sleep 10
done

chmod +x "$BINARY_NAME"

export CODER_AGENT_AUTH="token:${CODER_AGENT_TOKEN}"

./"$BINARY_NAME" agent &

opencode web --hostname 127.0.0.1 --port 4096 --cwd "$HOME/workspace"
