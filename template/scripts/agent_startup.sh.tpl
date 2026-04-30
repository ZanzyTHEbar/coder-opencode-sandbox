set -e
export HOME=/home/coder
# /tmp stays writable even if $HOME is still broken; use it for early diagnostics.
TMPLOG=/tmp/coder-opencode-startup.log
DBG=/home/coder/.coder-debug
set +e
{
  echo "=== startup begin $(date -Iseconds 2>/dev/null || date) ==="
  echo "uid=$(id -u) gid=$(id -g) user=$(id -un 2>/dev/null || echo '?')"
  echo "--- getent passwd (current) ---"
  getent passwd "$(id -un)" 2>/dev/null || true
  echo "--- ls -la /home /home/coder ---"
  ls -la /home 2>&1 | head -20
  ls -la /home/coder 2>&1 | head -60
  if test -w "$HOME"; then echo "HOME writable: yes"; else echo "HOME writable: NO"; fi
  echo "--- ls -ld home + workspace ---"
  ls -ld "$HOME" "$HOME/workspace" 2>&1 || true
} | tee -a "$TMPLOG"
set -e
mkdir -p "$DBG" 2>>"$TMPLOG" || echo "NOTE: could not mkdir $DBG (home may be root-owned); see $TMPLOG" | tee -a "$TMPLOG"
if [ -w "$DBG" ]; then
  cp -f "$TMPLOG" "$DBG/startup.log" 2>/dev/null || cat "$TMPLOG" >>"$DBG/startup.log" 2>/dev/null || true
fi

# Keep workspace creation idempotent even if `.init_done` already exists.
if ! mkdir -p "$HOME/workspace" 2>>"$TMPLOG"; then
  echo "FATAL: mkdir -p $HOME/workspace failed — read $TMPLOG and the DEBUG_WORKSPACE_VOLUME.md guide in this repo" | tee -a "$TMPLOG" >&2
  exit 1
fi

# Seed the home volume from `/etc/skel` only on first start.
if [ ! -f "$HOME/.init_done" ]; then
  cp -rT /etc/skel "$HOME" 2>/dev/null || true
  touch "$HOME/.init_done"
fi

WORKSPACE_DIR="$HOME/workspace"
OPENCODE_DIR="$HOME/.opencode"
OPENCODE_LOG="$OPENCODE_DIR/server.log"
OPENCODE_SERVER_PASSWORD_FILE="$OPENCODE_DIR/server-password"
OPENCODE_CONFIG_PARENT="$HOME/.config"
OPENCODE_CONFIG_LINK="$OPENCODE_CONFIG_PARENT/opencode"
PROFILE_ROOT="$HOME/.opencode-profile"
PROFILE_RELEASES="$PROFILE_ROOT/releases"
PROFILE_CURRENT="$PROFILE_ROOT/current"
DOTFILES_ROOT="$HOME/.dotfiles-profile"
DOTFILES_RELEASES="$DOTFILES_ROOT/releases"
DOTFILES_CURRENT="$DOTFILES_ROOT/current"
mkdir -p "$OPENCODE_DIR" "$OPENCODE_CONFIG_PARENT" "$PROFILE_RELEASES" "$DOTFILES_RELEASES"
: > "$OPENCODE_LOG"

log_note() {
  echo "$1" | tee -a "$TMPLOG" "$OPENCODE_LOG"
}

log_note_err() {
  echo "$1" | tee -a "$TMPLOG" "$OPENCODE_LOG" >&2
}

ensure_opencode_server_password() {
  if [ "$OPENCODE_APP_SHARE" != "public" ]; then
    unset OPENCODE_SERVER_PASSWORD
    if [ -s "$OPENCODE_SERVER_PASSWORD_FILE" ]; then
      log_note "OpenCode server password file exists but is inactive because app sharing is not public."
    fi
    return 0
  fi

  if [ ! -s "$OPENCODE_SERVER_PASSWORD_FILE" ]; then
    _old_umask=$(umask)
    umask 077
    od -An -N32 -tx1 /dev/urandom | tr -d ' \n' > "$OPENCODE_SERVER_PASSWORD_FILE"
    umask "$_old_umask"
  fi

  chmod 600 "$OPENCODE_SERVER_PASSWORD_FILE"
  OPENCODE_SERVER_PASSWORD=$(cat "$OPENCODE_SERVER_PASSWORD_FILE")
  export OPENCODE_SERVER_PASSWORD
  log_note "OpenCode public app password enabled; read $OPENCODE_SERVER_PASSWORD_FILE inside the workspace for HTTPS attach."
}

is_managed_opencode_config() {
  [ -L "$OPENCODE_CONFIG_LINK" ] || return 1
  _target=$(readlink "$OPENCODE_CONFIG_LINK" 2>/dev/null || true)
  case "$_target" in
    "$PROFILE_CURRENT"|"$PROFILE_ROOT"/*) return 0 ;;
  esac
  _target=$(readlink -f "$OPENCODE_CONFIG_LINK" 2>/dev/null || true)
  case "$_target" in
    "$PROFILE_ROOT"/*) return 0 ;;
    *) return 1 ;;
  esac
}

opencode_config_link_available() {
  if [ -L "$OPENCODE_CONFIG_LINK" ]; then
    if is_managed_opencode_config; then
      return 0
    fi
    if [ ! -e "$OPENCODE_CONFIG_LINK" ]; then
      log_note "WARNING: $OPENCODE_CONFIG_LINK is a broken symlink outside the managed profile cache; leaving it unchanged"
      return 1
    fi
    log_note "WARNING: $OPENCODE_CONFIG_LINK already points outside the managed profile cache; leaving it unchanged"
    return 1
  fi

  if [ -e "$OPENCODE_CONFIG_LINK" ]; then
    log_note "WARNING: $OPENCODE_CONFIG_LINK already exists and is not a symlink; leaving it unchanged"
    return 1
  fi

  return 0
}

trim_whitespace() {
  printf '%s\n' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

SOURCE_INPUT_URL=""
SOURCE_INPUT_REF=""
SOURCE_INPUT_SUBDIR=""
SOURCE_REPO=""
SOURCE_REF=""
SOURCE_SUBDIR=""
SOURCE_BROWSER_MODE=""
SOURCE_BROWSER_TAIL=""
SOURCE_PARSED_REF=""
SOURCE_PARSED_SUBDIR=""

strip_url_query_and_fragment() {
  printf '%s\n' "$1" | sed 's/[?#].*$//'
}

extract_github_path() {
  _trimmed=$(strip_url_query_and_fragment "$1")
  _path=$(printf '%s\n' "$_trimmed" | sed 's#^[Hh][Tt][Tt][Pp]\([Ss]\)\{0,1\}://\([Ww][Ww][Ww]\.\)\{0,1\}[Gg][Ii][Tt][Hh][Uu][Bb]\.[Cc][Oo][Mm]/##')
  [ "$_path" = "$_trimmed" ] && return 1
  printf '%s\n' "$_path"
}

github_ref_exists() {
  _ref="$1"
  GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code "$SOURCE_REPO" "refs/heads/$_ref" >/dev/null 2>&1 \
    || GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code "$SOURCE_REPO" "refs/tags/$_ref" >/dev/null 2>&1
}

looks_like_git_commit_oid() {
  printf '%s\n' "$1" | grep -Eq '^[0-9A-Fa-f]{7,40}$'
}

resolve_github_browser_ref_and_subdir() {
  _mode="$1"
  _tail="$2"
  _known_ref="$3"

  SOURCE_PARSED_REF=""
  SOURCE_PARSED_SUBDIR=""
  [ -n "$_tail" ] || return 0

  if [ -n "$_known_ref" ]; then
    SOURCE_PARSED_REF="$_known_ref"
  else
    _candidate="$_tail"
    while [ -n "$_candidate" ]; do
      if github_ref_exists "$_candidate"; then
        SOURCE_PARSED_REF="$_candidate"
        break
      fi

      case "$_candidate" in
        */*) _candidate=$${_candidate%/*} ;;
        *) break ;;
      esac
    done

    if [ -z "$SOURCE_PARSED_REF" ]; then
      _candidate=$${_tail%%/*}
      if looks_like_git_commit_oid "$_candidate"; then
        SOURCE_PARSED_REF="$_candidate"
      else
        return 1
      fi
    fi
  fi

  case "$_tail" in
    "$SOURCE_PARSED_REF")
    SOURCE_PARSED_SUBDIR=""
    ;;
    "$SOURCE_PARSED_REF"/*)
      SOURCE_PARSED_SUBDIR=$${_tail#"$SOURCE_PARSED_REF"/}
      ;;
    */*)
      SOURCE_PARSED_SUBDIR=$${_tail#*/}
      ;;
    *)
      SOURCE_PARSED_SUBDIR=""
      ;;
  esac

  if [ "$_mode" = "blob" ] && [ -n "$SOURCE_PARSED_SUBDIR" ]; then
    case "$SOURCE_PARSED_SUBDIR" in
      */*) SOURCE_PARSED_SUBDIR=$${SOURCE_PARSED_SUBDIR%/*} ;;
      *) SOURCE_PARSED_SUBDIR="" ;;
    esac
  fi
}

normalize_source_input() {
  SOURCE_REPO=$(strip_url_query_and_fragment "$SOURCE_INPUT_URL")
  SOURCE_REPO=$${SOURCE_REPO%/}
  SOURCE_REF="$SOURCE_INPUT_REF"
  SOURCE_SUBDIR="$SOURCE_INPUT_SUBDIR"
  SOURCE_BROWSER_MODE=""
  SOURCE_BROWSER_TAIL=""

  _github_path=$(extract_github_path "$SOURCE_REPO" 2>/dev/null || true)
  if [ -n "$_github_path" ]; then
    _owner=$${_github_path%%/*}
    _repo_path=$${_github_path#*/}
    _repo=$${_repo_path%%/*}

    if [ -n "$_owner" ] && [ -n "$_repo" ] && [ "$_repo_path" != "$_github_path" ]; then
      SOURCE_REPO="https://github.com/$${_owner}/$${_repo%.git}.git"

      if [ "$_repo_path" != "$_repo" ]; then
        _suffix=$${_repo_path#*/}
        case "$_suffix" in
          tree/*)
            SOURCE_BROWSER_MODE="tree"
            SOURCE_BROWSER_TAIL=$${_suffix#tree/}
            ;;
          blob/*)
            SOURCE_BROWSER_MODE="blob"
            SOURCE_BROWSER_TAIL=$${_suffix#blob/}
            ;;
          *)
            log_note "WARNING: unsupported GitHub browser URL path; using repo root for provisioning"
            ;;
        esac
      fi
    fi
  else
    case "$SOURCE_REPO" in
      https://github.com/*)
        case "$SOURCE_REPO" in
          *.git) ;;
          *) SOURCE_REPO="$${SOURCE_REPO}.git" ;;
        esac
        ;;
    esac
  fi

  if [ -n "$SOURCE_BROWSER_TAIL" ]; then
    if ! resolve_github_browser_ref_and_subdir "$SOURCE_BROWSER_MODE" "$SOURCE_BROWSER_TAIL" "$SOURCE_REF"; then
      log_note_err "FATAL: could not resolve a ref from the GitHub browser URL; use OpenCode config ref to disambiguate it"
      return 1
    fi
    [ -n "$SOURCE_REF" ] || SOURCE_REF=$SOURCE_PARSED_REF
    if [ -z "$SOURCE_SUBDIR" ] && [ -n "$SOURCE_PARSED_SUBDIR" ]; then
      SOURCE_SUBDIR=$SOURCE_PARSED_SUBDIR
    fi
  fi
}

source_repo_dir_name() {
  _name="$SOURCE_REPO"
  _name=$${_name##*/}
  _name=$${_name%.git}
  printf '%s\n' "$_name"
}

clone_source_repo_into() {
  _dest="$1"

  if [ -n "$SOURCE_REF" ]; then
    if GIT_TERMINAL_PROMPT=0 git -c protocol.file.allow=never clone --depth 1 --branch "$SOURCE_REF" --single-branch "$SOURCE_REPO" "$_dest" >>"$OPENCODE_LOG" 2>&1; then
      return 0
    fi
    rm -rf "$_dest"
    GIT_TERMINAL_PROMPT=0 git -c protocol.file.allow=never clone --depth 1 "$SOURCE_REPO" "$_dest" >>"$OPENCODE_LOG" 2>&1 || return 1
    GIT_TERMINAL_PROMPT=0 git -c protocol.file.allow=never -C "$_dest" fetch --depth 1 origin "$SOURCE_REF" >>"$OPENCODE_LOG" 2>&1 || return 1
    git -C "$_dest" checkout --detach FETCH_HEAD >>"$OPENCODE_LOG" 2>&1 || return 1
    return 0
  fi

  GIT_TERMINAL_PROMPT=0 git -c protocol.file.allow=never clone --depth 1 "$SOURCE_REPO" "$_dest" >>"$OPENCODE_LOG" 2>&1
}

resolve_selected_source_dir() {
  _stage_dir="$1"
  _selected_subdir="$2"
  _fallback_dir="$3"

  if [ -n "$_selected_subdir" ]; then
    SELECTED_PATH="$_stage_dir/repo/$_selected_subdir"
  elif [ -n "$_fallback_dir" ] && [ -d "$_stage_dir/repo/$_fallback_dir" ]; then
    SELECTED_PATH="$_stage_dir/repo/$_fallback_dir"
  else
    SELECTED_PATH="$_stage_dir/repo"
  fi

  [ -d "$SELECTED_PATH" ] || return 1

  SELECTED_REAL=$(readlink -f "$SELECTED_PATH" 2>/dev/null || true)
  case "$SELECTED_REAL" in
    "$_stage_dir"/*) ;;
    *) return 1 ;;
  esac

  SELECTED_REL=$${SELECTED_PATH#"$_stage_dir"/}
}

ensure_opencode_profile() {
  SOURCE_INPUT_URL="$OPENCODE_CONFIG_URL"
  SOURCE_INPUT_REF="$OPENCODE_CONFIG_REF"
  SOURCE_INPUT_SUBDIR="$OPENCODE_CONFIG_SUBDIR"
  normalize_source_input || exit 1

  PROFILE_HASH=$(printf '%s\n%s\n%s\n' "$SOURCE_REPO" "$SOURCE_REF" "$SOURCE_SUBDIR" | sha256sum | cut -d' ' -f1)
  PROFILE_DIR="$PROFILE_RELEASES/$PROFILE_HASH"

  if [ ! -d "$PROFILE_DIR" ]; then
    STAGED_DIR=$(mktemp -d "$PROFILE_RELEASES/.staging.XXXXXX")
    log_note "Provisioning OpenCode config from $SOURCE_REPO"

    if ! clone_source_repo_into "$STAGED_DIR/repo"; then
      rm -rf "$STAGED_DIR"
      log_note_err "FATAL: could not fetch OpenCode config from $SOURCE_REPO"
      exit 1
    fi

    if ! resolve_selected_source_dir "$STAGED_DIR" "$SOURCE_SUBDIR" ".opencode"; then
      rm -rf "$STAGED_DIR"
      log_note_err "FATAL: OpenCode config path does not exist inside the fetched repo"
      exit 1
    fi

    ln -s "$SELECTED_REL" "$STAGED_DIR/selected"

    cat > "$STAGED_DIR/manifest" <<EOF
source_url=$OPENCODE_CONFIG_URL
source_repo=$SOURCE_REPO
source_ref=$SOURCE_REF
source_subdir=$SOURCE_SUBDIR
resolved_commit=$(git -C "$STAGED_DIR/repo" rev-parse HEAD 2>/dev/null || echo unknown)
EOF

    mv "$STAGED_DIR" "$PROFILE_DIR"
  fi

  ln -sfn "$PROFILE_DIR/selected" "$PROFILE_CURRENT"

  if ! opencode_config_link_available; then
    return 0
  fi

  ln -sfn "$PROFILE_CURRENT" "$OPENCODE_CONFIG_LINK"
}

ensure_workspace_repos() {
  [ -n "$WORKSPACE_REPO_URLS" ] || return 0

  set -f
  _old_ifs=$IFS
  IFS=','
  set -- $WORKSPACE_REPO_URLS
  IFS=$_old_ifs
  set +f

  for _repo_entry in "$@"; do
    _repo_entry=$(trim_whitespace "$_repo_entry")
    [ -n "$_repo_entry" ] || continue

    SOURCE_INPUT_URL="$_repo_entry"
    SOURCE_INPUT_REF=""
    SOURCE_INPUT_SUBDIR=""
    if ! normalize_source_input; then
      log_note_err "FATAL: could not parse workspace repo URL $_repo_entry"
      exit 1
    fi

    _target_name=$(source_repo_dir_name)
    if [ -z "$_target_name" ]; then
      log_note_err "FATAL: could not derive a workspace directory name from $_repo_entry"
      exit 1
    fi

    _target_dir="$WORKSPACE_DIR/$_target_name"
    if [ -e "$_target_dir" ] || [ -L "$_target_dir" ]; then
      log_note "NOTE: workspace repo target $_target_dir already exists; leaving it unchanged"
      continue
    fi

    if [ -n "$SOURCE_SUBDIR" ]; then
      log_note "NOTE: ignoring GitHub subdirectory component for workspace repo $_repo_entry; cloning the full repo into $_target_dir"
    fi

    log_note "Cloning workspace repo $SOURCE_REPO into $_target_dir"
    if ! clone_source_repo_into "$_target_dir"; then
      log_note_err "FATAL: could not clone workspace repo from $SOURCE_REPO"
      exit 1
    fi
  done
}

ensure_linux_dotfiles() {
  SOURCE_INPUT_URL="$LINUX_DOTFILES_URL"
  SOURCE_INPUT_REF=""
  SOURCE_INPUT_SUBDIR=""
  normalize_source_input || exit 1

  DOTFILES_HASH=$(printf '%s\n%s\n%s\n' "$SOURCE_REPO" "$SOURCE_REF" "$SOURCE_SUBDIR" | sha256sum | cut -d' ' -f1)
  _profile_dir="$DOTFILES_RELEASES/$DOTFILES_HASH"

  if [ ! -d "$_profile_dir" ]; then
    STAGED_DIR=$(mktemp -d "$DOTFILES_RELEASES/.staging.XXXXXX")
    log_note "Provisioning Linux dotfiles from $SOURCE_REPO"

    if ! clone_source_repo_into "$STAGED_DIR/repo"; then
      rm -rf "$STAGED_DIR"
      log_note_err "FATAL: could not fetch Linux dotfiles from $SOURCE_REPO"
      exit 1
    fi

    if ! resolve_selected_source_dir "$STAGED_DIR" "$SOURCE_SUBDIR" ""; then
      rm -rf "$STAGED_DIR"
      log_note_err "FATAL: Linux dotfiles path does not exist inside the fetched repo"
      exit 1
    fi

    ln -s "$SELECTED_REL" "$STAGED_DIR/selected"

    cat > "$STAGED_DIR/manifest" <<EOF
source_url=$LINUX_DOTFILES_URL
source_repo=$SOURCE_REPO
source_ref=$SOURCE_REF
source_subdir=$SOURCE_SUBDIR
resolved_commit=$(git -C "$STAGED_DIR/repo" rev-parse HEAD 2>/dev/null || echo unknown)
EOF

    mv "$STAGED_DIR" "$_profile_dir"
  fi

  ln -sfn "$_profile_dir/selected" "$DOTFILES_CURRENT"

  if [ -z "$LINUX_DOTFILES_INSTALL_COMMAND" ]; then
    log_note "NOTE: Linux dotfiles URL is set but no install command was provided; skipping apply step"
    return 0
  fi

  _selected_dir=$(readlink -f "$DOTFILES_CURRENT" 2>/dev/null || true)
  _repo_dir=$(readlink -f "$_profile_dir/repo" 2>/dev/null || true)
  [ -n "$_repo_dir" ] || _repo_dir="$_selected_dir"

  if [ -z "$_selected_dir" ] || [ ! -d "$_selected_dir" ]; then
    log_note_err "FATAL: Linux dotfiles path is not available for apply"
    exit 1
  fi

  log_note "Applying Linux dotfiles from $_selected_dir"
  if ! (
    export DOTFILES_DIR="$_selected_dir"
    export DOTFILES_REPO_DIR="$_repo_dir"
    export WORKSPACE_DIR
    cd "$_selected_dir" || exit 1
    sh -lc "$LINUX_DOTFILES_INSTALL_COMMAND"
  ) >>"$TMPLOG" 2>&1; then
    log_note_err "FATAL: Linux dotfiles install command failed"
    exit 1
  fi

  log_note "Linux dotfiles install command completed successfully"
}

ensure_workspace_repos

if [ -n "$OPENCODE_CONFIG_URL" ]; then
  ensure_opencode_profile
elif is_managed_opencode_config; then
  log_note "Removing managed OpenCode config link because no config URL is set"
  rm -f "$OPENCODE_CONFIG_LINK"
fi

if [ -n "$LINUX_DOTFILES_URL" ]; then
  ensure_linux_dotfiles
elif [ -n "$LINUX_DOTFILES_INSTALL_COMMAND" ]; then
  log_note "WARNING: Linux dotfiles install command is set but Linux dotfiles URL is empty; skipping apply step"
fi

ensure_opencode_server_password

# Start OpenCode from the user's workspace, not filesystem root.
cd "$WORKSPACE_DIR"
opencode web --hostname 127.0.0.1 --port 4096 >>"$OPENCODE_LOG" 2>&1 </dev/null &
echo $! > "$OPENCODE_DIR/server.pid"

# Wait for OpenCode before reporting the agent ready.
OPENCODE_READY=0
for i in $(seq 1 60); do
  if [ -n "$OPENCODE_SERVER_PASSWORD" ]; then
    if curl -sf -u "opencode:$OPENCODE_SERVER_PASSWORD" -o /dev/null http://127.0.0.1:4096/doc 2>/dev/null; then
      OPENCODE_READY=1
      break
    fi
  else
    if curl -sf -o /dev/null http://127.0.0.1:4096/doc 2>/dev/null; then
      OPENCODE_READY=1
      break
    fi
  fi
  sleep 1
done

if [ "$OPENCODE_READY" != "1" ]; then
  echo "FATAL: OpenCode did not become ready on http://127.0.0.1:4096/doc" | tee -a "$TMPLOG" "$OPENCODE_LOG" >&2
  exit 1
fi
