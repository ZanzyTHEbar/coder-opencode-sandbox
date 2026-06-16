# OpenCode Session Sync

Use offline, filtered migration for OpenCode sessions. Do not bidirectionally sync `opencode.db` while OpenCode is running.

## Why

OpenCode state is SQLite plus sidecar files. A live raw copy can miss WAL data, cannot merge two clients, and contains absolute paths. Local sessions use `/mnt/common/projects/*`; the DragonServer runtime uses `/home/coder/workspace/*` inside the container.

## What Syncs

Included:

- Global OpenCode config, agents, commands, rules, and skills.
- Ponytail skills/plugin files.
- Sessions whose `session.directory` is under `/mnt/common/projects/*`.
- Matching `storage/session_diff/<session_id>.json` and `storage/plugin/dcp/<session_id>.json` sidecars.

Excluded:

- `account.json`, `auth.json`, `mcp-auth.json`.
- `node_modules`, caches, repos, logs, and tool output.
- OpenCode event log rows and account/share token rows in the staged DB.

## Stage Locally

```sh
opencode-docker/scripts/sync-opencode-to-dragon.sh all
```

The script creates a local staging directory, snapshots the SQLite DB with `VACUUM INTO`, filters sessions, rewrites paths from `/mnt/common/projects` to `/home/coder/workspace`, and writes a manifest.

## Apply To DragonServer

Stop the remote OpenCode container first. Then run with a direct SSH target for the LXC:

```sh
REMOTE_HOST=<lxc-ssh-host> \
REPLACE_REMOTE_DB=1 \
REMOTE_OPENCODE_STOPPED=1 \
opencode-docker/scripts/sync-opencode-to-dragon.sh all --apply
```

Defaults assume the LXC host path is `/srv/opencode/home` and files should be owned by UID/GID `1800`.

`REPLACE_REMOTE_DB=1` is required because session apply replaces the active remote OpenCode DB with the filtered local export. The script backs up the existing remote DB under `/srv/opencode/backups` first and refuses to continue if an OpenCode container is still running.

## Verify

After starting OpenCode again:

```sh
sqlite3 /srv/opencode/home/.local/share/opencode/opencode.db \
  "SELECT count(*) FROM session WHERE directory LIKE '/home/coder/workspace/%';"
sqlite3 /srv/opencode/home/.local/share/opencode/opencode.db \
  "SELECT count(*) FROM session WHERE directory LIKE '/mnt/common/projects/%';"
```

Expected result: the first count matches the staged manifest; the second is `0`.

Then open a known project under `/home/coder/workspace/<project>` and confirm history appears.

Message text and sidecar JSON are copied as history and are not rewritten. Old path strings may remain inside conversation content; active session/project paths are rewritten in the database.

## Ongoing Rule

Use local-to-Dragon sync as the default. If two-way sync is ever needed, keep it append-only and offline. Never edit the same session from two clients and never run Syncthing/Unison/rsync directly over a live SQLite DB.
