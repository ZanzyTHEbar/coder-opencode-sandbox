#!/bin/sh
set -eu

export HOME=${HOME:-/home/coder}
export WORKSPACE_DIR=${WORKSPACE_DIR:-$HOME/workspace}
LOG_DIR=${OPENCODE_LOG_DIR:-/var/log/opencode}
OPENCODE_CHOWN_RECURSIVE=${OPENCODE_CHOWN_RECURSIVE:-false}

mkdir -p "$HOME" "$WORKSPACE_DIR" "$LOG_DIR"
chown coder:coder "$HOME" "$WORKSPACE_DIR" "$LOG_DIR"

if [ "$OPENCODE_CHOWN_RECURSIVE" = "true" ]; then
  chown -R coder:coder "$HOME" "$WORKSPACE_DIR" "$LOG_DIR"
fi

if [ ! -f "$HOME/.init_done" ]; then
  cp -rT /etc/skel "$HOME" 2>/dev/null || true
  touch "$HOME/.init_done"
  chown coder:coder "$HOME/.init_done" "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bash_logout" 2>/dev/null || true
fi

exec gosu coder /usr/local/bin/opencode-startup
