#!/bin/sh
set -eu

export HOME=/home/coder
export WORKSPACE_DIR=$${WORKSPACE_DIR:-$HOME/workspace}
mkdir -p "$HOME/.opencode" "$WORKSPACE_DIR" "$HOME/.ssh"
chmod 700 "$HOME/.opencode" "$HOME/.ssh"

if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
  ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "opencode-workspace" >/dev/null 2>&1
  chmod 600 "$HOME/.ssh/id_ed25519"
  chmod 644 "$HOME/.ssh/id_ed25519.pub"
fi

touch "$HOME/.ssh/known_hosts"
chmod 600 "$HOME/.ssh/known_hosts"
# ponytail: TOFU convenience only; pin provider host keys before production Git onboarding.
if command -v ssh-keyscan >/dev/null 2>&1; then
  for host in github.com gitlab.com bitbucket.org; do
    ssh-keyscan "$host" >>"$HOME/.ssh/known_hosts" 2>/dev/null || true
  done
  sort -u "$HOME/.ssh/known_hosts" -o "$HOME/.ssh/known_hosts"
fi

repo_name() {
  _name=$${1%/}
  _name=$${_name##*/}
  _name=$${_name%.git}
  printf '%s\n' "$_name"
}

clone_workspace_repos() {
  [ -n "$${WORKSPACE_REPO_URLS:-}" ] || return 0
  command -v git >/dev/null 2>&1 || { echo "git is required for WORKSPACE_REPO_URLS" >&2; exit 1; }
  [ ! -f "$HOME/.ssh/id_ed25519" ] || chmod go-rwx "$HOME/.ssh/id_ed25519"

  set -f
  _old_ifs=$IFS
  IFS=','
  set -- $WORKSPACE_REPO_URLS
  IFS=$_old_ifs
  set +f

  for repo in "$@"; do
    repo=$(printf '%s' "$repo" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -n "$repo" ] || continue
    case "$repo" in
      *://*@*) echo "workspace repo URLs must not include credentials" >&2; exit 1 ;;
      *://*|git@*:*) ;;
      *) echo "unsupported workspace repo URL" >&2; exit 1 ;;
    esac

    name=$(repo_name "$repo")
    [ -n "$name" ] || { echo "could not derive repo directory name from $repo" >&2; exit 1; }
    dest="$WORKSPACE_DIR/$name"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      echo "workspace repo exists, leaving unchanged: $dest"
      continue
    fi
    if ! GIT_TERMINAL_PROMPT=0 git -c protocol.file.allow=never clone --depth 1 "$repo" "$dest"; then
      echo "WARNING: could not clone workspace repo; register the Git SSH public key and restart to retry" >&2
    fi
  done
}

clone_workspace_repos

nohup opencode web --hostname 127.0.0.1 --port 4096 >"$HOME/.opencode/server.log" 2>&1 &
