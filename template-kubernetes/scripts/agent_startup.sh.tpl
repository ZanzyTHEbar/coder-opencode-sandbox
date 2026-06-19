#!/bin/sh
set -eu

export HOME=/home/coder
mkdir -p "$HOME/.opencode" "$HOME/workspace"
chmod 700 "$HOME/.opencode"

nohup opencode web --hostname 127.0.0.1 --port 4096 --cwd "$HOME/workspace" >"$HOME/.opencode/server.log" 2>&1 &
