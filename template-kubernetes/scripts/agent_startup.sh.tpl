#!/bin/sh
set -eu

export HOME=/home/coder
mkdir -p "$HOME/.opencode" "$HOME/workspace" "$HOME/.ssh"
chmod 700 "$HOME/.opencode" "$HOME/.ssh"

if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
  ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "opencode-workspace" >/dev/null 2>&1
  chmod 600 "$HOME/.ssh/id_ed25519"
  chmod 644 "$HOME/.ssh/id_ed25519.pub"
fi

nohup opencode web --hostname 127.0.0.1 --port 4096 >"$HOME/.opencode/server.log" 2>&1 &
