#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: sync-opencode-to-dragon.sh <config|sessions|all> [--apply] [--stage-dir DIR]

Stages local OpenCode config/session data for the DragonServer OpenCode LXC.
By default it only writes a local staging directory.

Environment:
  LOCAL_HOME=$HOME
  LOCAL_STATE=$LOCAL_HOME/.local/share/opencode
  LOCAL_CONFIG=$LOCAL_HOME/.config/opencode
  LOCAL_PROJECT_PREFIX=/mnt/common/projects
  REMOTE_CONTAINER_HOME=/home/coder
  REMOTE_PROJECT_PREFIX=/home/coder/workspace
  REMOTE_HOST=opencode-runtime.example   # required with --apply
  REMOTE_HOME=/srv/opencode/home
  REMOTE_UID=1800
  REMOTE_GID=1800
  REPLACE_REMOTE_DB=1                    # required for --apply sessions/all
  REMOTE_OPENCODE_STOPPED=1              # required for --apply sessions/all

This intentionally does not copy account.json, auth.json, mcp-auth.json,
node_modules, caches, repos, logs, or tool-output.
USAGE
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

sql_quote() {
  printf "%s" "$1" | sed "s/'/''/g"
}

mode=${1:-}
[ -n "$mode" ] || { usage; exit 2; }
shift || true

apply=0
STAGE_DIR=${STAGE_DIR:-}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply)
      apply=1
      ;;
    --stage-dir)
      shift
      [ "$#" -gt 0 ] || die "--stage-dir requires a value"
      STAGE_DIR=$1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
  shift
done

case "$mode" in
  config|sessions|all) ;;
  *) die "mode must be config, sessions, or all" ;;
esac

LOCAL_HOME=${LOCAL_HOME:-$HOME}
LOCAL_STATE=${LOCAL_STATE:-$LOCAL_HOME/.local/share/opencode}
LOCAL_CONFIG=${LOCAL_CONFIG:-$LOCAL_HOME/.config/opencode}
LOCAL_AGENTS_SKILLS=${LOCAL_AGENTS_SKILLS:-$LOCAL_HOME/.agents/skills}
LOCAL_PONYTAIL=${LOCAL_PONYTAIL:-$LOCAL_STATE/ponytail}
LOCAL_PROJECT_PREFIX=${LOCAL_PROJECT_PREFIX:-/mnt/common/projects}
REMOTE_CONTAINER_HOME=${REMOTE_CONTAINER_HOME:-/home/coder}
REMOTE_PROJECT_PREFIX=${REMOTE_PROJECT_PREFIX:-/home/coder/workspace}
REMOTE_HOST=${REMOTE_HOST:-}
REMOTE_HOME=${REMOTE_HOME:-/srv/opencode/home}
REMOTE_UID=${REMOTE_UID:-1800}
REMOTE_GID=${REMOTE_GID:-1800}
REMOTE_BACKUP_DIR=${REMOTE_BACKUP_DIR:-/srv/opencode/backups}
REPLACE_REMOTE_DB=${REPLACE_REMOTE_DB:-0}
REMOTE_OPENCODE_STOPPED=${REMOTE_OPENCODE_STOPPED:-0}

if [ -z "$STAGE_DIR" ]; then
  STAGE_DIR=${TMPDIR:-/tmp}/opencode-dragon-sync-$(date -u +%Y%m%dT%H%M%SZ)
fi

stage_home=$STAGE_DIR/home
stage_state=$STAGE_DIR/state/.local/share/opencode

if [ "$apply" = "1" ] && { [ "$mode" = "sessions" ] || [ "$mode" = "all" ]; }; then
  [ "$REPLACE_REMOTE_DB" = "1" ] || die "session apply replaces the remote DB; set REPLACE_REMOTE_DB=1"
  [ "$REMOTE_OPENCODE_STOPPED" = "1" ] || die "stop remote OpenCode first, then set REMOTE_OPENCODE_STOPPED=1"
fi

copy_dir() {
  src=$1
  dest=$2
  [ -e "$src" ] || return 0
  mkdir -p "$dest"
  rsync -aL --delete \
    --exclude node_modules \
    --exclude '.cache' \
    --exclude 'account.json' \
    --exclude 'auth.json' \
    --exclude 'mcp-auth.json' \
    --exclude 'log' \
    --exclude 'logs' \
    --exclude 'tool-output' \
    --exclude 'repos' \
    "$src/" "$dest/"
}

rewrite_staged_home_paths() {
  [ -d "$stage_home" ] || return 0
  need perl
  export LOCAL_HOME REMOTE_CONTAINER_HOME
  find "$stage_home" -type f -size -10M -print0 |
    xargs -0 -r perl -0pi -e 's|\Q$ENV{LOCAL_HOME}\E|$ENV{REMOTE_CONTAINER_HOME}|g'
}

stage_config() {
  need rsync
  mkdir -p "$stage_home/.config" "$stage_home/.agents" "$stage_home/.local/share/opencode"
  copy_dir "$LOCAL_CONFIG" "$stage_home/.config/opencode"
  copy_dir "$LOCAL_AGENTS_SKILLS" "$stage_home/.agents/skills"
  copy_dir "$LOCAL_PONYTAIL" "$stage_home/.local/share/opencode/ponytail"
  rewrite_staged_home_paths
  printf 'Config staged at %s\n' "$stage_home"
}

stage_sessions() {
  need sqlite3

  src_db=$LOCAL_STATE/opencode.db
  [ -f "$src_db" ] || die "missing source DB: $src_db"

  mkdir -p "$stage_state/storage/session_diff" "$stage_state/storage/plugin/dcp"
  snapshot=$stage_state/opencode.db
  ids_file=$STAGE_DIR/selected-session-ids.txt
  manifest=$STAGE_DIR/session-sync-manifest.txt
  rm -f "$snapshot" "$ids_file" "$manifest"

  snapshot_sql=$(sql_quote "$snapshot")
  sqlite3 "$src_db" "VACUUM INTO '$snapshot_sql';"

  local_prefix_sql=$(sql_quote "$LOCAL_PROJECT_PREFIX")
  remote_prefix_sql=$(sql_quote "$REMOTE_PROJECT_PREFIX")
  local_rel_prefix_sql=$(sql_quote "${LOCAL_PROJECT_PREFIX#/}")
  remote_rel_prefix_sql=$(sql_quote "${REMOTE_PROJECT_PREFIX#/}")

  sqlite3 "$snapshot" "SELECT id FROM session WHERE directory LIKE '$local_prefix_sql/%' ORDER BY id;" > "$ids_file"
  selected_count=$(wc -l < "$ids_file" | tr -d ' ')
  [ "$selected_count" -gt 0 ] || die "no sessions matched $LOCAL_PROJECT_PREFIX/*"

  sqlite3 "$snapshot" <<SQL
PRAGMA foreign_keys=ON;
DELETE FROM session WHERE directory NOT LIKE '$local_prefix_sql/%';
UPDATE session SET parent_id = NULL WHERE parent_id IS NOT NULL AND parent_id NOT IN (SELECT id FROM session);
DELETE FROM project WHERE id NOT IN (SELECT DISTINCT project_id FROM session);
DELETE FROM workspace WHERE project_id NOT IN (SELECT id FROM project);
DELETE FROM project_directory WHERE project_id NOT IN (SELECT id FROM project);
DELETE FROM permission WHERE project_id NOT IN (SELECT id FROM project);
DELETE FROM event;
DELETE FROM event_sequence;
DELETE FROM account_state;
DELETE FROM account;
DELETE FROM control_account;
DELETE FROM session_share;
UPDATE session SET directory = replace(directory, '$local_prefix_sql', '$remote_prefix_sql') WHERE directory LIKE '$local_prefix_sql/%';
UPDATE session SET path = replace(path, '$local_prefix_sql', '$remote_prefix_sql') WHERE path LIKE '$local_prefix_sql%';
UPDATE session SET path = replace(path, '$local_rel_prefix_sql', '$remote_rel_prefix_sql') WHERE path LIKE '$local_rel_prefix_sql%';
UPDATE project SET worktree = replace(worktree, '$local_prefix_sql', '$remote_prefix_sql') WHERE worktree LIKE '$local_prefix_sql/%';
UPDATE project_directory SET directory = replace(directory, '$local_prefix_sql', '$remote_prefix_sql') WHERE directory LIKE '$local_prefix_sql/%';
UPDATE workspace SET directory = replace(directory, '$local_prefix_sql', '$remote_prefix_sql') WHERE directory LIKE '$local_prefix_sql/%';
VACUUM;
SQL

  fk_errors=$(sqlite3 "$snapshot" 'PRAGMA foreign_key_check;')
  [ -z "$fk_errors" ] || die "staged DB has foreign key errors: $fk_errors"

  while IFS= read -r session_id; do
    [ -n "$session_id" ] || continue
    for rel in storage/session_diff storage/plugin/dcp; do
      src=$LOCAL_STATE/$rel/$session_id.json
      dest=$stage_state/$rel/$session_id.json
      if [ -f "$src" ]; then
        mkdir -p "$(dirname "$dest")"
        cp -p "$src" "$dest"
      fi
    done
  done < "$ids_file"

  db_sessions=$(sqlite3 "$snapshot" 'SELECT count(*) FROM session;')
  old_paths=$(sqlite3 "$snapshot" "SELECT count(*) FROM session WHERE directory LIKE '$local_prefix_sql/%';")
  secret_rows=$(sqlite3 "$snapshot" "SELECT (SELECT count(*) FROM account) + (SELECT count(*) FROM control_account) + (SELECT count(*) FROM session_share);")

  cat > "$manifest" <<EOF
created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
source_db=$src_db
local_project_prefix=$LOCAL_PROJECT_PREFIX
remote_project_prefix=$REMOTE_PROJECT_PREFIX
session_count=$db_sessions
old_path_count=$old_paths
secret_row_count=$secret_rows
EOF

  [ "$db_sessions" = "$selected_count" ] || die "selected $selected_count sessions but staged DB has $db_sessions"
  [ "$old_paths" = "0" ] || die "staged DB still has $old_paths local project paths"
  [ "$secret_rows" = "0" ] || die "staged DB still has secret/share rows"

  printf 'Sessions staged at %s (%s sessions)\n' "$stage_state" "$db_sessions"
}

require_remote() {
  [ -n "$REMOTE_HOST" ] || die "REMOTE_HOST is required with --apply"
  need ssh
  need rsync
}

backup_remote_config() {
  backup=$REMOTE_BACKUP_DIR/opencode-config-$(date -u +%Y%m%dT%H%M%SZ)
  ssh "$REMOTE_HOST" "set -eu; mkdir -p '$backup'; cd '$REMOTE_HOME'; for p in .config/opencode .agents/skills .local/share/opencode/ponytail; do if [ -e \"\$p\" ]; then mkdir -p '$backup'/\"\$(dirname \"\$p\")\"; cp -a \"\$p\" '$backup'/\"\$p\"; fi; done"
  printf 'Remote config backup: %s:%s\n' "$REMOTE_HOST" "$backup"
}

backup_remote_db() {
  backup=$REMOTE_BACKUP_DIR/opencode-sync-$(date -u +%Y%m%dT%H%M%SZ)
  ssh "$REMOTE_HOST" "set -eu; mkdir -p '$backup'; if [ -e '$REMOTE_HOME/.local/share/opencode/opencode.db' ]; then cp -a '$REMOTE_HOME/.local/share/opencode/opencode.db'* '$backup/'; test -s '$backup/opencode.db'; else printf 'no existing remote DB at apply time\\n' > '$backup/NO_EXISTING_DB'; fi; if [ -d '$REMOTE_HOME/.local/share/opencode/storage' ]; then cp -a '$REMOTE_HOME/.local/share/opencode/storage' '$backup/storage'; fi"
  printf 'Remote DB backup: %s:%s\n' "$REMOTE_HOST" "$backup"
}

assert_remote_opencode_stopped() {
  ssh "$REMOTE_HOST" "set -eu; command -v docker >/dev/null; running=\$(docker ps --format '{{.ID}} {{.Names}} {{.Image}} {{.Command}}' | grep -E 'opencode|4096' || true); if [ -n \"\$running\" ]; then printf '%s\\n' \"\$running\" >&2; exit 1; fi; if pgrep -af '[o]pencode web' >/dev/null 2>&1; then pgrep -af '[o]pencode web' >&2; exit 1; fi"
}

preflight_session_apply() {
  [ "$apply" = "1" ] || return 0
  require_remote
  assert_remote_opencode_stopped
}

apply_config() {
  [ "$apply" = "1" ] || return 0
  require_remote
  backup_remote_config
  ssh "$REMOTE_HOST" "mkdir -p '$REMOTE_HOME/.config' '$REMOTE_HOME/.agents' '$REMOTE_HOME/.local/share/opencode'"
  rsync -a --delete \
    --exclude 'account.json' \
    --exclude 'auth.json' \
    --exclude 'mcp-auth.json' \
    "$stage_home/.config/opencode/" "$REMOTE_HOST:$REMOTE_HOME/.config/opencode/"
  if [ -d "$stage_home/.agents/skills" ]; then
    rsync -a --delete "$stage_home/.agents/skills/" "$REMOTE_HOST:$REMOTE_HOME/.agents/skills/"
  fi
  if [ -d "$stage_home/.local/share/opencode/ponytail" ]; then
    rsync -a --delete "$stage_home/.local/share/opencode/ponytail/" "$REMOTE_HOST:$REMOTE_HOME/.local/share/opencode/ponytail/"
  fi
  ssh "$REMOTE_HOST" "chown -R '$REMOTE_UID:$REMOTE_GID' '$REMOTE_HOME/.config/opencode' '$REMOTE_HOME/.agents' '$REMOTE_HOME/.local/share/opencode/ponytail' 2>/dev/null || true"
}

apply_sessions() {
  [ "$apply" = "1" ] || return 0
  require_remote
  assert_remote_opencode_stopped
  backup_remote_db

  ssh "$REMOTE_HOST" "mkdir -p '$REMOTE_HOME/.local/share/opencode/storage/session_diff' '$REMOTE_HOME/.local/share/opencode/storage/plugin/dcp'"
  rsync -a "$stage_state/opencode.db" "$REMOTE_HOST:$REMOTE_HOME/.local/share/opencode/opencode.db"
  rsync -a --delete "$stage_state/storage/session_diff/" "$REMOTE_HOST:$REMOTE_HOME/.local/share/opencode/storage/session_diff/"
  rsync -a --delete "$stage_state/storage/plugin/dcp/" "$REMOTE_HOST:$REMOTE_HOME/.local/share/opencode/storage/plugin/dcp/"
  ssh "$REMOTE_HOST" "rm -f '$REMOTE_HOME/.local/share/opencode/opencode.db-wal' '$REMOTE_HOME/.local/share/opencode/opencode.db-shm' && chown -R '$REMOTE_UID:$REMOTE_GID' '$REMOTE_HOME/.local/share/opencode'"
}

mkdir -p "$STAGE_DIR"

case "$mode" in
  config)
    stage_config
    apply_config
    ;;
  sessions)
    stage_sessions
    preflight_session_apply
    apply_sessions
    ;;
  all)
    stage_config
    stage_sessions
    preflight_session_apply
    apply_config
    apply_sessions
    ;;
esac

if [ "$apply" = "0" ]; then
  printf 'Dry run complete. Re-run with --apply and REMOTE_HOST set to copy staged data.\n'
fi
printf 'Stage directory: %s\n' "$STAGE_DIR"
