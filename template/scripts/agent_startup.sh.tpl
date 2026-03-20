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
PROFILE_ROOT="$HOME/.opencode-profile"
PROFILE_RELEASES="$PROFILE_ROOT/releases"
PROFILE_CURRENT="$PROFILE_ROOT/current"
WORKSPACE_CONFIG_LINK="$WORKSPACE_DIR/.opencode"
mkdir -p "$OPENCODE_DIR" "$PROFILE_RELEASES"
: > "$OPENCODE_LOG"

log_note() {
  echo "$1" | tee -a "$TMPLOG" "$OPENCODE_LOG"
}

log_note_err() {
  echo "$1" | tee -a "$TMPLOG" "$OPENCODE_LOG" >&2
}

is_managed_workspace_config() {
  [ -L "$WORKSPACE_CONFIG_LINK" ] || return 1
  _target=$(readlink "$WORKSPACE_CONFIG_LINK" 2>/dev/null || true)
  case "$_target" in
    "$PROFILE_CURRENT"|"$PROFILE_ROOT"/*) return 0 ;;
  esac
  _target=$(readlink -f "$WORKSPACE_CONFIG_LINK" 2>/dev/null || true)
  case "$_target" in
    "$PROFILE_ROOT"/*) return 0 ;;
    *) return 1 ;;
  esac
}

workspace_config_link_available() {
  if [ -L "$WORKSPACE_CONFIG_LINK" ]; then
    if is_managed_workspace_config; then
      return 0
    fi
    if [ ! -e "$WORKSPACE_CONFIG_LINK" ]; then
      log_note "WARNING: $WORKSPACE_CONFIG_LINK is a broken symlink outside the managed profile cache; leaving it unchanged"
      return 1
    fi
    log_note "WARNING: $WORKSPACE_CONFIG_LINK already points outside the managed profile cache; leaving it unchanged"
    return 1
  fi

  if [ -e "$WORKSPACE_CONFIG_LINK" ]; then
    log_note "WARNING: $WORKSPACE_CONFIG_LINK already exists and is not a symlink; leaving it unchanged"
    return 1
  fi

  return 0
}

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
  GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code "$OPENCODE_SOURCE_REPO" "refs/heads/$_ref" >/dev/null 2>&1 \
    || GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code "$OPENCODE_SOURCE_REPO" "refs/tags/$_ref" >/dev/null 2>&1
}

looks_like_git_commit_oid() {
  printf '%s\n' "$1" | grep -Eq '^[0-9A-Fa-f]{7,40}$'
}

resolve_github_browser_ref_and_subdir() {
  _mode="$1"
  _tail="$2"
  _known_ref="$3"

  OPENCODE_PARSED_REF=""
  OPENCODE_PARSED_SUBDIR=""
  [ -n "$_tail" ] || return 0

  if [ -n "$_known_ref" ]; then
    OPENCODE_PARSED_REF="$_known_ref"
  else
    _candidate="$_tail"
    while [ -n "$_candidate" ]; do
      if github_ref_exists "$_candidate"; then
        OPENCODE_PARSED_REF="$_candidate"
        break
      fi

      case "$_candidate" in
        */*) _candidate=$${_candidate%/*} ;;
        *) break ;;
      esac
    done

    if [ -z "$OPENCODE_PARSED_REF" ]; then
      _candidate=$${_tail%%/*}
      if looks_like_git_commit_oid "$_candidate"; then
        OPENCODE_PARSED_REF="$_candidate"
      else
        return 1
      fi
    fi
  fi

  case "$_tail" in
    "$OPENCODE_PARSED_REF")
    OPENCODE_PARSED_SUBDIR=""
    ;;
    "$OPENCODE_PARSED_REF"/*)
      OPENCODE_PARSED_SUBDIR=$${_tail#"$OPENCODE_PARSED_REF"/}
      ;;
    */*)
      OPENCODE_PARSED_SUBDIR=$${_tail#*/}
      ;;
    *)
      OPENCODE_PARSED_SUBDIR=""
      ;;
  esac

  if [ "$_mode" = "blob" ] && [ -n "$OPENCODE_PARSED_SUBDIR" ]; then
    case "$OPENCODE_PARSED_SUBDIR" in
      */*) OPENCODE_PARSED_SUBDIR=$${OPENCODE_PARSED_SUBDIR%/*} ;;
      *) OPENCODE_PARSED_SUBDIR="" ;;
    esac
  fi
}

normalize_opencode_source() {
  OPENCODE_SOURCE_REPO=$(strip_url_query_and_fragment "$OPENCODE_CONFIG_URL")
  OPENCODE_SOURCE_REPO=$${OPENCODE_SOURCE_REPO%/}
  OPENCODE_SOURCE_REF=$OPENCODE_CONFIG_REF
  OPENCODE_SOURCE_SUBDIR=$OPENCODE_CONFIG_SUBDIR
  OPENCODE_SOURCE_BROWSER_MODE=""
  OPENCODE_SOURCE_BROWSER_TAIL=""

  _github_path=$(extract_github_path "$OPENCODE_SOURCE_REPO" 2>/dev/null || true)
  if [ -n "$_github_path" ]; then
    _owner=$${_github_path%%/*}
    _repo_path=$${_github_path#*/}
    _repo=$${_repo_path%%/*}

    if [ -n "$_owner" ] && [ -n "$_repo" ] && [ "$_repo_path" != "$_github_path" ]; then
      OPENCODE_SOURCE_REPO="https://github.com/$${_owner}/$${_repo%.git}.git"

      if [ "$_repo_path" != "$_repo" ]; then
        _suffix=$${_repo_path#*/}
        case "$_suffix" in
          tree/*)
            OPENCODE_SOURCE_BROWSER_MODE="tree"
            OPENCODE_SOURCE_BROWSER_TAIL=$${_suffix#tree/}
            ;;
          blob/*)
            OPENCODE_SOURCE_BROWSER_MODE="blob"
            OPENCODE_SOURCE_BROWSER_TAIL=$${_suffix#blob/}
            ;;
          *)
            log_note "WARNING: unsupported GitHub browser URL path; using repo root for provisioning"
            ;;
        esac
      fi
    fi
  else
    case "$OPENCODE_SOURCE_REPO" in
      https://github.com/*)
        case "$OPENCODE_SOURCE_REPO" in
          *.git) ;;
          *) OPENCODE_SOURCE_REPO="$${OPENCODE_SOURCE_REPO}.git" ;;
        esac
        ;;
    esac
  fi

  if [ -n "$OPENCODE_SOURCE_BROWSER_TAIL" ]; then
    if ! resolve_github_browser_ref_and_subdir "$OPENCODE_SOURCE_BROWSER_MODE" "$OPENCODE_SOURCE_BROWSER_TAIL" "$OPENCODE_SOURCE_REF"; then
      log_note_err "FATAL: could not resolve a ref from the GitHub browser URL; use OpenCode config ref to disambiguate it"
      return 1
    fi
    [ -n "$OPENCODE_SOURCE_REF" ] || OPENCODE_SOURCE_REF=$OPENCODE_PARSED_REF
    if [ -z "$OPENCODE_SOURCE_SUBDIR" ] && [ -n "$OPENCODE_PARSED_SUBDIR" ]; then
      OPENCODE_SOURCE_SUBDIR=$OPENCODE_PARSED_SUBDIR
    fi
  fi
}

clone_opencode_repo() {
  if [ -n "$OPENCODE_SOURCE_REF" ]; then
    if GIT_TERMINAL_PROMPT=0 git -c protocol.file.allow=never clone --depth 1 --branch "$OPENCODE_SOURCE_REF" --single-branch "$OPENCODE_SOURCE_REPO" "$STAGED_DIR/repo" >>"$OPENCODE_LOG" 2>&1; then
      return 0
    fi
    rm -rf "$STAGED_DIR/repo"
    GIT_TERMINAL_PROMPT=0 git -c protocol.file.allow=never clone --depth 1 "$OPENCODE_SOURCE_REPO" "$STAGED_DIR/repo" >>"$OPENCODE_LOG" 2>&1 || return 1
    GIT_TERMINAL_PROMPT=0 git -c protocol.file.allow=never -C "$STAGED_DIR/repo" fetch --depth 1 origin "$OPENCODE_SOURCE_REF" >>"$OPENCODE_LOG" 2>&1 || return 1
    git -C "$STAGED_DIR/repo" checkout --detach FETCH_HEAD >>"$OPENCODE_LOG" 2>&1 || return 1
    return 0
  fi

  GIT_TERMINAL_PROMPT=0 git -c protocol.file.allow=never clone --depth 1 "$OPENCODE_SOURCE_REPO" "$STAGED_DIR/repo" >>"$OPENCODE_LOG" 2>&1
}

ensure_opencode_profile() {
  normalize_opencode_source || exit 1

  PROFILE_HASH=$(printf '%s\n%s\n%s\n' "$OPENCODE_SOURCE_REPO" "$OPENCODE_SOURCE_REF" "$OPENCODE_SOURCE_SUBDIR" | sha256sum | cut -d' ' -f1)
  PROFILE_DIR="$PROFILE_RELEASES/$PROFILE_HASH"

  if [ ! -d "$PROFILE_DIR" ]; then
    STAGED_DIR=$(mktemp -d "$PROFILE_RELEASES/.staging.XXXXXX")
    log_note "Provisioning OpenCode config from $OPENCODE_SOURCE_REPO"

    if ! clone_opencode_repo; then
      rm -rf "$STAGED_DIR"
      log_note_err "FATAL: could not fetch OpenCode config from $OPENCODE_SOURCE_REPO"
      exit 1
    fi

    if [ -n "$OPENCODE_SOURCE_SUBDIR" ]; then
      SELECTED_PATH="$STAGED_DIR/repo/$OPENCODE_SOURCE_SUBDIR"
    elif [ -d "$STAGED_DIR/repo/.opencode" ]; then
      SELECTED_PATH="$STAGED_DIR/repo/.opencode"
    else
      SELECTED_PATH="$STAGED_DIR/repo"
    fi

    if [ ! -d "$SELECTED_PATH" ]; then
      rm -rf "$STAGED_DIR"
      log_note_err "FATAL: OpenCode config path does not exist inside the fetched repo"
      exit 1
    fi

    SELECTED_REAL=$(readlink -f "$SELECTED_PATH" 2>/dev/null || true)
    case "$SELECTED_REAL" in
      "$STAGED_DIR"/*) ;;
      *)
        rm -rf "$STAGED_DIR"
        log_note_err "FATAL: resolved OpenCode config path escaped the fetched repo"
        exit 1
        ;;
    esac

    SELECTED_REL=$${SELECTED_PATH#"$STAGED_DIR"/}
    ln -s "$SELECTED_REL" "$STAGED_DIR/selected"

    cat > "$STAGED_DIR/manifest" <<EOF
source_url=$OPENCODE_CONFIG_URL
source_repo=$OPENCODE_SOURCE_REPO
source_ref=$OPENCODE_SOURCE_REF
source_subdir=$OPENCODE_SOURCE_SUBDIR
resolved_commit=$(git -C "$STAGED_DIR/repo" rev-parse HEAD 2>/dev/null || echo unknown)
EOF

    mv "$STAGED_DIR" "$PROFILE_DIR"
  fi

  ln -sfn "$PROFILE_DIR/selected" "$PROFILE_CURRENT"

  if ! workspace_config_link_available; then
    return 0
  fi

  ln -sfn "$PROFILE_CURRENT" "$WORKSPACE_CONFIG_LINK"
}

if [ -n "$OPENCODE_CONFIG_URL" ]; then
  ensure_opencode_profile
elif is_managed_workspace_config; then
  log_note "Removing managed workspace .opencode link because no config URL is set"
  rm -f "$WORKSPACE_CONFIG_LINK"
fi

# Start OpenCode from the user's workspace, not filesystem root.
cd "$WORKSPACE_DIR"
opencode web --hostname 127.0.0.1 --port 4096 >>"$OPENCODE_LOG" 2>&1 </dev/null &
echo $! > "$OPENCODE_DIR/server.pid"

# Wait for OpenCode before reporting the agent ready.
OPENCODE_READY=0
for i in $(seq 1 60); do
  if curl -sf -o /dev/null http://127.0.0.1:4096/doc 2>/dev/null; then
    OPENCODE_READY=1
    break
  fi
  sleep 1
done

if [ "$OPENCODE_READY" != "1" ]; then
  echo "FATAL: OpenCode did not become ready on http://127.0.0.1:4096/doc" | tee -a "$TMPLOG" "$OPENCODE_LOG" >&2
  exit 1
fi
