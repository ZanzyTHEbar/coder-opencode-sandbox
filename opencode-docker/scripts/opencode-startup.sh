#!/bin/sh
set -e

export HOME=${HOME:-/home/coder}
export WORKSPACE_DIR=${WORKSPACE_DIR:-$HOME/workspace}
OPENCODE_SERVER_CWD=${OPENCODE_SERVER_CWD:-$HOME/opencode-hub}
OPENCODE_HOST=${OPENCODE_HOST:-0.0.0.0}
OPENCODE_PORT=${OPENCODE_PORT:-4096}
OPENCODE_APP_SHARE=${OPENCODE_APP_SHARE:-private}
OPENCODE_REQUIRE_PASSWORD=${OPENCODE_REQUIRE_PASSWORD:-true}
MEMORY_BANK_ROOT=${MEMORY_BANK_ROOT:-$HOME/.local/share/opencode/memory-bank}
WORKSPACE_BOOTSTRAP_FAILURE_POLICY=${WORKSPACE_BOOTSTRAP_FAILURE_POLICY:-warn}
WORKSPACE_BOOTSTRAP_TIMEOUT_SECONDS=${WORKSPACE_BOOTSTRAP_TIMEOUT_SECONDS:-600}
export MEMORY_BANK_ROOT

LOG_DIR=${OPENCODE_LOG_DIR:-/var/log/opencode}
TMPLOG=${STARTUP_LOG:-$LOG_DIR/startup.log}
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
BOOTSTRAP_ROOT="$HOME/.workspace-bootstrap"
BOOTSTRAP_RELEASES="$BOOTSTRAP_ROOT/releases"
BOOTSTRAP_CURRENT="$BOOTSTRAP_ROOT/current"

mkdir -p "$WORKSPACE_DIR" "$OPENCODE_SERVER_CWD" "$MEMORY_BANK_ROOT" "$LOG_DIR" "$OPENCODE_DIR" "$OPENCODE_CONFIG_PARENT" "$PROFILE_RELEASES" "$DOTFILES_RELEASES" "$BOOTSTRAP_RELEASES"
: > "$TMPLOG"
: > "$OPENCODE_LOG"

log_note() {
  echo "$1" | tee -a "$TMPLOG" "$OPENCODE_LOG"
}

log_note_err() {
  echo "$1" | tee -a "$TMPLOG" "$OPENCODE_LOG" >&2
}

trim_whitespace() {
  printf '%s\n' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

ensure_opencode_server_password() {
  case "$OPENCODE_REQUIRE_PASSWORD" in
    false|0|no|NO|No) _require_password=false ;;
    true|1|yes|YES|Yes|"") _require_password=true ;;
    *)
      _require_password=true
      log_note "WARNING: invalid OPENCODE_REQUIRE_PASSWORD value '$OPENCODE_REQUIRE_PASSWORD'; defaulting to true"
      ;;
  esac

  if [ -n "${OPENCODE_SERVER_PASSWORD:-}" ]; then
    _old_umask=$(umask)
    umask 077
    printf '%s' "$OPENCODE_SERVER_PASSWORD" > "$OPENCODE_SERVER_PASSWORD_FILE"
    umask "$_old_umask"
    chmod 600 "$OPENCODE_SERVER_PASSWORD_FILE"
    export OPENCODE_SERVER_PASSWORD
    log_note "OpenCode server password enabled from environment."
    return 0
  fi

  if [ "$_require_password" = "true" ]; then
    if [ ! -s "$OPENCODE_SERVER_PASSWORD_FILE" ]; then
      _old_umask=$(umask)
      umask 077
      od -An -N32 -tx1 /dev/urandom | tr -d ' \n' > "$OPENCODE_SERVER_PASSWORD_FILE"
      umask "$_old_umask"
    fi

    chmod 600 "$OPENCODE_SERVER_PASSWORD_FILE"
    OPENCODE_SERVER_PASSWORD=$(cat "$OPENCODE_SERVER_PASSWORD_FILE")
    export OPENCODE_SERVER_PASSWORD
    log_note "OpenCode server password generated because OPENCODE_REQUIRE_PASSWORD=true."
    return 0
  fi

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
  log_note "OpenCode public app password enabled; read $OPENCODE_SERVER_PASSWORD_FILE inside the container for HTTPS attach."
}

ensure_opencode_hub() {
  if [ ! -f "$OPENCODE_SERVER_CWD/README.md" ]; then
    cat > "$OPENCODE_SERVER_CWD/README.md" <<'EOF'
# OpenCode Runtime Hub

This directory is the neutral browser landing project for the persistent OpenCode server.

Use project-scoped attach commands for real work:

```sh
oca dragonserver
oca actual-mcp --continue
oca mealie-mcp --session <session_id>
```

Do not start project sessions from `/home/coder/workspace`; that directory only contains project folders.
EOF
  fi

  if [ ! -d "$OPENCODE_SERVER_CWD/.git" ]; then
    git -C "$OPENCODE_SERVER_CWD" init >/dev/null 2>&1 || return 0
  fi

  if git -C "$OPENCODE_SERVER_CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$OPENCODE_SERVER_CWD" config user.name "OpenCode Runtime" >/dev/null 2>&1 || true
    git -C "$OPENCODE_SERVER_CWD" config user.email "opencode-runtime@localhost" >/dev/null 2>&1 || true
    if ! git -C "$OPENCODE_SERVER_CWD" rev-parse --verify HEAD >/dev/null 2>&1; then
      git -C "$OPENCODE_SERVER_CWD" add README.md >/dev/null 2>&1 || true
      git -C "$OPENCODE_SERVER_CWD" commit -m "Initialize OpenCode runtime hub" >/dev/null 2>&1 || true
    fi
  fi
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
        */*) _candidate=${_candidate%/*} ;;
        *) break ;;
      esac
    done

    if [ -z "$SOURCE_PARSED_REF" ]; then
      _candidate=${_tail%%/*}
      if looks_like_git_commit_oid "$_candidate"; then
        SOURCE_PARSED_REF="$_candidate"
      else
        return 1
      fi
    fi
  fi

  case "$_tail" in
    "$SOURCE_PARSED_REF") SOURCE_PARSED_SUBDIR="" ;;
    "$SOURCE_PARSED_REF"/*) SOURCE_PARSED_SUBDIR=${_tail#"$SOURCE_PARSED_REF"/} ;;
    */*) SOURCE_PARSED_SUBDIR=${_tail#*/} ;;
    *) SOURCE_PARSED_SUBDIR="" ;;
  esac

  if [ "$_mode" = "blob" ] && [ -n "$SOURCE_PARSED_SUBDIR" ]; then
    case "$SOURCE_PARSED_SUBDIR" in
      */*) SOURCE_PARSED_SUBDIR=${SOURCE_PARSED_SUBDIR%/*} ;;
      *) SOURCE_PARSED_SUBDIR="" ;;
    esac
  fi
}

normalize_source_input() {
  SOURCE_REPO=$(strip_url_query_and_fragment "$SOURCE_INPUT_URL")
  SOURCE_REPO=${SOURCE_REPO%/}
  SOURCE_REF="$SOURCE_INPUT_REF"
  SOURCE_SUBDIR="$SOURCE_INPUT_SUBDIR"
  SOURCE_BROWSER_MODE=""
  SOURCE_BROWSER_TAIL=""

  _github_path=$(extract_github_path "$SOURCE_REPO" 2>/dev/null || true)
  if [ -n "$_github_path" ]; then
    _owner=${_github_path%%/*}
    _repo_path=${_github_path#*/}
    _repo=${_repo_path%%/*}

    if [ -n "$_owner" ] && [ -n "$_repo" ] && [ "$_repo_path" != "$_github_path" ]; then
      SOURCE_REPO="https://github.com/${_owner}/${_repo%.git}.git"

      if [ "$_repo_path" != "$_repo" ]; then
        _suffix=${_repo_path#*/}
        case "$_suffix" in
          tree/*)
            SOURCE_BROWSER_MODE="tree"
            SOURCE_BROWSER_TAIL=${_suffix#tree/}
            ;;
          blob/*)
            SOURCE_BROWSER_MODE="blob"
            SOURCE_BROWSER_TAIL=${_suffix#blob/}
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
          *) SOURCE_REPO="${SOURCE_REPO}.git" ;;
        esac
        ;;
    esac
  fi

  if [ -n "$SOURCE_BROWSER_TAIL" ]; then
    if ! resolve_github_browser_ref_and_subdir "$SOURCE_BROWSER_MODE" "$SOURCE_BROWSER_TAIL" "$SOURCE_REF"; then
      log_note_err "FATAL: could not resolve a ref from the GitHub browser URL"
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
  _name=${_name##*/}
  _name=${_name%.git}
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
  SELECTED_REL=${SELECTED_PATH#"$_stage_dir"/}
}

ensure_opencode_profile() {
  SOURCE_INPUT_URL="$OPENCODE_CONFIG_URL"
  SOURCE_INPUT_REF="${OPENCODE_CONFIG_REF:-}"
  SOURCE_INPUT_SUBDIR="${OPENCODE_CONFIG_SUBDIR:-}"
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
  [ -n "${WORKSPACE_REPO_URLS:-}" ] || return 0
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
    [ -n "$_target_name" ] || { log_note_err "FATAL: could not derive a workspace directory name from $_repo_entry"; exit 1; }
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

workspace_bootstrap_timeout_seconds() {
  _timeout="$WORKSPACE_BOOTSTRAP_TIMEOUT_SECONDS"
  case "$_timeout" in
    ''|*[!0-9]*|0) _timeout=600 ;;
  esac
  printf '%s\n' "$_timeout"
}

handle_workspace_bootstrap_failure() {
  _message="$1"
  if [ "$WORKSPACE_BOOTSTRAP_FAILURE_POLICY" = "fail" ]; then
    log_note_err "FATAL: $_message"
    exit 1
  fi
  log_note "WARNING: $_message; continuing because workspace bootstrap failure policy is warn"
  return 0
}

run_bounded_startup_command() {
  _label="$1"
  _working_dir="$2"
  _command="$3"
  _timeout=$(workspace_bootstrap_timeout_seconds)
  if [ -z "$_working_dir" ] || [ ! -d "$_working_dir" ]; then
    handle_workspace_bootstrap_failure "$_label working directory is not available"
    return 0
  fi
  log_note "Running $_label from $_working_dir (timeout ${_timeout}s)"
  set +e
  (
    cd "$_working_dir" || exit 1
    timeout "$_timeout" sh -lc "$_command"
  ) >>"$TMPLOG" 2>&1
  _status=$?
  set -e
  if [ "$_status" -ne 0 ]; then
    if [ "$_status" = "124" ]; then
      handle_workspace_bootstrap_failure "$_label timed out after ${_timeout}s"
    else
      handle_workspace_bootstrap_failure "$_label failed with exit status $_status"
    fi
    return 0
  fi
  log_note "$_label completed successfully"
}

ensure_workspace_bootstrap() {
  if [ -z "${WORKSPACE_BOOTSTRAP_COMMAND:-}" ]; then
    if [ -n "${WORKSPACE_BOOTSTRAP_URL:-}" ]; then
      log_note "NOTE: workspace bootstrap URL is set but no command was provided; skipping bootstrap"
    fi
    return 0
  fi

  if [ -z "${WORKSPACE_BOOTSTRAP_URL:-}" ]; then
    export BOOTSTRAP_DIR="$WORKSPACE_DIR"
    export BOOTSTRAP_REPO_DIR="$WORKSPACE_DIR"
    export WORKSPACE_DIR
    run_bounded_startup_command "workspace bootstrap command" "$WORKSPACE_DIR" "$WORKSPACE_BOOTSTRAP_COMMAND"
    return 0
  fi

  SOURCE_INPUT_URL="$WORKSPACE_BOOTSTRAP_URL"
  SOURCE_INPUT_REF=""
  SOURCE_INPUT_SUBDIR=""
  if ! normalize_source_input; then
    handle_workspace_bootstrap_failure "could not parse workspace bootstrap URL $WORKSPACE_BOOTSTRAP_URL"
    return 0
  fi
  BOOTSTRAP_HASH=$(printf '%s\n%s\n%s\n' "$SOURCE_REPO" "$SOURCE_REF" "$SOURCE_SUBDIR" | sha256sum | cut -d' ' -f1)
  _profile_dir="$BOOTSTRAP_RELEASES/$BOOTSTRAP_HASH"
  if [ ! -d "$_profile_dir" ]; then
    STAGED_DIR=$(mktemp -d "$BOOTSTRAP_RELEASES/.staging.XXXXXX")
    log_note "Provisioning workspace bootstrap from $SOURCE_REPO"
    if ! clone_source_repo_into "$STAGED_DIR/repo"; then
      rm -rf "$STAGED_DIR"
      handle_workspace_bootstrap_failure "could not fetch workspace bootstrap from $SOURCE_REPO"
      return 0
    fi
    if ! resolve_selected_source_dir "$STAGED_DIR" "$SOURCE_SUBDIR" ""; then
      rm -rf "$STAGED_DIR"
      handle_workspace_bootstrap_failure "workspace bootstrap path does not exist inside the fetched repo"
      return 0
    fi
    if ! ln -s "$SELECTED_REL" "$STAGED_DIR/selected"; then
      rm -rf "$STAGED_DIR"
      handle_workspace_bootstrap_failure "could not prepare workspace bootstrap cache"
      return 0
    fi
    cat > "$STAGED_DIR/manifest" <<EOF
source_url=$WORKSPACE_BOOTSTRAP_URL
source_repo=$SOURCE_REPO
source_ref=$SOURCE_REF
source_subdir=$SOURCE_SUBDIR
resolved_commit=$(git -C "$STAGED_DIR/repo" rev-parse HEAD 2>/dev/null || echo unknown)
EOF
    if ! mv "$STAGED_DIR" "$_profile_dir"; then
      rm -rf "$STAGED_DIR"
      handle_workspace_bootstrap_failure "could not store workspace bootstrap cache"
      return 0
    fi
  fi
  if ! ln -sfn "$_profile_dir/selected" "$BOOTSTRAP_CURRENT"; then
    handle_workspace_bootstrap_failure "could not activate workspace bootstrap cache"
    return 0
  fi
  _selected_dir=$(readlink -f "$BOOTSTRAP_CURRENT" 2>/dev/null || true)
  _repo_dir=$(readlink -f "$_profile_dir/repo" 2>/dev/null || true)
  [ -n "$_repo_dir" ] || _repo_dir="$_selected_dir"
  if [ -z "$_selected_dir" ] || [ ! -d "$_selected_dir" ]; then
    handle_workspace_bootstrap_failure "workspace bootstrap path is not available"
    return 0
  fi
  export BOOTSTRAP_DIR="$_selected_dir"
  export BOOTSTRAP_REPO_DIR="$_repo_dir"
  export WORKSPACE_DIR
  run_bounded_startup_command "workspace bootstrap command" "$_selected_dir" "$WORKSPACE_BOOTSTRAP_COMMAND"
}

ensure_linux_dotfiles() {
  SOURCE_INPUT_URL="$LINUX_DOTFILES_URL"
  SOURCE_INPUT_REF="${LINUX_DOTFILES_REF:-}"
  SOURCE_INPUT_SUBDIR="${LINUX_DOTFILES_SUBDIR:-}"
  if ! normalize_source_input; then
    handle_workspace_bootstrap_failure "could not parse Linux dotfiles URL $LINUX_DOTFILES_URL"
    return 0
  fi
  DOTFILES_HASH=$(printf '%s\n%s\n%s\n' "$SOURCE_REPO" "$SOURCE_REF" "$SOURCE_SUBDIR" | sha256sum | cut -d' ' -f1)
  _profile_dir="$DOTFILES_RELEASES/$DOTFILES_HASH"
  if [ ! -d "$_profile_dir" ]; then
    STAGED_DIR=$(mktemp -d "$DOTFILES_RELEASES/.staging.XXXXXX")
    log_note "Provisioning Linux dotfiles from $SOURCE_REPO"
    if ! clone_source_repo_into "$STAGED_DIR/repo"; then
      rm -rf "$STAGED_DIR"
      handle_workspace_bootstrap_failure "could not fetch Linux dotfiles from $SOURCE_REPO"
      return 0
    fi
    if ! resolve_selected_source_dir "$STAGED_DIR" "$SOURCE_SUBDIR" ""; then
      rm -rf "$STAGED_DIR"
      handle_workspace_bootstrap_failure "Linux dotfiles path does not exist inside the fetched repo"
      return 0
    fi
    if ! ln -s "$SELECTED_REL" "$STAGED_DIR/selected"; then
      rm -rf "$STAGED_DIR"
      handle_workspace_bootstrap_failure "could not prepare Linux dotfiles cache"
      return 0
    fi
    cat > "$STAGED_DIR/manifest" <<EOF
source_url=$LINUX_DOTFILES_URL
source_repo=$SOURCE_REPO
source_ref=$SOURCE_REF
source_subdir=$SOURCE_SUBDIR
resolved_commit=$(git -C "$STAGED_DIR/repo" rev-parse HEAD 2>/dev/null || echo unknown)
EOF
    if ! mv "$STAGED_DIR" "$_profile_dir"; then
      rm -rf "$STAGED_DIR"
      handle_workspace_bootstrap_failure "could not store Linux dotfiles cache"
      return 0
    fi
  fi
  if ! ln -sfn "$_profile_dir/selected" "$DOTFILES_CURRENT"; then
    handle_workspace_bootstrap_failure "could not activate Linux dotfiles cache"
    return 0
  fi
  if [ -z "${LINUX_DOTFILES_INSTALL_COMMAND:-}" ]; then
    log_note "NOTE: Linux dotfiles URL is set but no install command was provided; skipping apply step"
    return 0
  fi
  _selected_dir=$(readlink -f "$DOTFILES_CURRENT" 2>/dev/null || true)
  _repo_dir=$(readlink -f "$_profile_dir/repo" 2>/dev/null || true)
  [ -n "$_repo_dir" ] || _repo_dir="$_selected_dir"
  if [ -z "$_selected_dir" ] || [ ! -d "$_selected_dir" ]; then
    handle_workspace_bootstrap_failure "Linux dotfiles path is not available for apply"
    return 0
  fi
  export DOTFILES_DIR="$_selected_dir"
  export DOTFILES_REPO_DIR="$_repo_dir"
  export WORKSPACE_DIR
  run_bounded_startup_command "Linux dotfiles install command" "$_selected_dir" "$LINUX_DOTFILES_INSTALL_COMMAND"
}

log_note "=== OpenCode Docker startup begin $(date -Iseconds 2>/dev/null || date) ==="
log_note "uid=$(id -u) gid=$(id -g) user=$(id -un 2>/dev/null || echo '?') workspace=$WORKSPACE_DIR"

ensure_workspace_repos

if [ -n "${OPENCODE_CONFIG_URL:-}" ]; then
  ensure_opencode_profile
elif is_managed_opencode_config; then
  log_note "Removing managed OpenCode config link because no config URL is set"
  rm -f "$OPENCODE_CONFIG_LINK"
fi

ensure_workspace_bootstrap

if [ -n "${LINUX_DOTFILES_URL:-}" ]; then
  ensure_linux_dotfiles
elif [ -n "${LINUX_DOTFILES_INSTALL_COMMAND:-}" ]; then
  log_note "WARNING: Linux dotfiles install command is set but Linux dotfiles URL is empty; skipping apply step"
fi

ensure_opencode_server_password
ensure_opencode_hub

case "$OPENCODE_SERVER_CWD" in
  /|"$HOME"|"$WORKSPACE_DIR")
    log_note_err "FATAL: OPENCODE_SERVER_CWD must not be /, $HOME, or $WORKSPACE_DIR"
    exit 1
    ;;
esac

log_note "OpenCode server cwd: $OPENCODE_SERVER_CWD"
cd "$OPENCODE_SERVER_CWD"
opencode web --hostname "$OPENCODE_HOST" --port "$OPENCODE_PORT" >>"$OPENCODE_LOG" 2>&1 </dev/null &
OPENCODE_PID=$!
echo "$OPENCODE_PID" > "$OPENCODE_DIR/server.pid"

trap 'kill "$OPENCODE_PID" 2>/dev/null || true; wait "$OPENCODE_PID" 2>/dev/null || true' INT TERM

OPENCODE_READY=0
for _i in $(seq 1 60); do
  if [ -n "${OPENCODE_SERVER_PASSWORD:-}" ]; then
    if curl -sf -u "opencode:$OPENCODE_SERVER_PASSWORD" -o /dev/null "http://127.0.0.1:$OPENCODE_PORT/doc" 2>/dev/null; then
      OPENCODE_READY=1
      break
    fi
  else
    if curl -sf -o /dev/null "http://127.0.0.1:$OPENCODE_PORT/doc" 2>/dev/null; then
      OPENCODE_READY=1
      break
    fi
  fi
  if ! kill -0 "$OPENCODE_PID" 2>/dev/null; then
    log_note_err "FATAL: OpenCode process exited before readiness"
    wait "$OPENCODE_PID"
    exit $?
  fi
  sleep 1
done

if [ "$OPENCODE_READY" != "1" ]; then
  log_note_err "FATAL: OpenCode did not become ready on http://127.0.0.1:$OPENCODE_PORT/doc"
  exit 1
fi

log_note "OpenCode ready on http://$OPENCODE_HOST:$OPENCODE_PORT"
wait "$OPENCODE_PID"
