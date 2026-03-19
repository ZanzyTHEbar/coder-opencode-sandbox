# Debug: `/home/coder/workspace` permission denied (evidence-based)

This is the **real** workflow: prove **which phase** fails, **which user** runs `mkdir`, and **what the filesystem looks like** — not another blind `chown`/`sudo` guess.

## Execution order (must match what you see in logs)

1. **Container `command`** — `sh -c '<bootstrap><coder_agent.init_script>'`  
   - Runs as **`docker_container.user`** (this template: **`0:0`**).  
   - **Bootstrap** runs first: `chown`/`mkdir` on the named volume at `/home/coder`.  
   - Then Coder’s **agent installer** runs from `init_script`.

2. **Agent `startup_script`** — runs **after** the agent connects, as the **agent user** (normally **`coder`**, not root).  
   - This is where **`mkdir -p "$HOME/workspace"`** lives in this template.

So:

- If **`mkdir` fails in bootstrap logs** → problem is **volume mount / root / chown** (bootstrap path).  
- If **bootstrap log says OK** but **`startup.log` shows `HOME NOT writable` or `mkdir failed`** → problem is **agent identity / HOME / leftover permissions** after bootstrap.  
- If **no `.coder-debug` files** → you’re not running this template version, or the container **never reached** that code (init died earlier).

## 1) Read the on-volume logs (primary evidence)

After a failed start, from the **Docker host** that runs workspace containers:

```bash
# Replace with your workspace container name (Coder UI → workspace → Docker, or docker ps).
CID=<container_id_or_name>

docker exec "$CID" sh -c 'echo "=== /tmp fallback ==="; sed -n "1,200p" /tmp/coder-opencode-startup.log 2>&1; echo "=== .coder-debug ==="; ls -la /home/coder/.coder-debug 2>&1; echo ---; sed -n "1,200p" /home/coder/.coder-debug/bootstrap.log 2>&1; echo ---; sed -n "1,200p" /home/coder/.coder-debug/startup.log 2>&1'
```

If **`/home/coder` is not writable by `coder`**, bootstrap may never have run correctly and **`/tmp/coder-opencode-startup.log`** still captures the startup diagnostics (written before creating `.coder-debug`).

**Interpretation:**

| Observation | Likely meaning |
|-------------|----------------|
| `bootstrap.log` missing | Init never ran bootstrap (wrong image/command, or very old template). |
| `getent: MISSING` for `coder` | Image has no `coder` user → `chown` fails. |
| Bootstrap ends with `bootstrap ok` | Root path fixed `/home/coder`; look at `startup.log` next. |
| `HOME NOT writable` in startup | Effective user cannot write `/home/coder` (wrong UID, or perms reverted). |
| `mkdir failed` only in startup | Failure is in **agent** phase, not bootstrap. |

Redact secrets if you paste logs; paths and UIDs are usually safe.

## 2) Prove container user and mount (host)

```bash
docker inspect "$CID" --format 'User={{.Config.User}}'
docker exec "$CID" sh -c 'id; id coder 2>/dev/null; ls -lan /home; ls -lan /home/coder | head -30'
docker exec "$CID" sh -c 'grep -E " /home|/home/coder" /proc/mounts || true'
```

**Check:** `User=` should be **`0:0`** for this template’s bootstrap. If it’s empty or `coder`, an **old template revision** or **manual override** is in play.

## 3) Prove template and image in Coder

- **Template:** In Coder, confirm the workspace uses the template version that includes **`user = "0:0"`** and the bootstrap **prepended** to `init_script` (see `template/main.tf`). Re-push and **update** the workspace after changes.  
- **Image:** Confirm **`sandbox_image`** points at the image you built (digest/tag). A wrong image can omit user `coder`.

## 4) Decision rule (stop guessing)

Do **not** add another workaround until:

1. You have **`bootstrap.log` + `startup.log`** (or proof the container can’t create them), **and**  
2. **`docker inspect … Config.User`** matches what the template declares, **and**  
3. You know whether **`mkdir`** failed in **bootstrap** or **startup**.

Then fix the **specific** failure mode (missing user, wrong `User`, stale template, etc.).

## Related files in this repo

- `template/main.tf` — bootstrap + `user`, `command`, `startup_script`  
- `image/Dockerfile` — `coder` user + `/etc/skel/workspace`  
- `docs/OPERATOR.md` — operator troubleshooting index  
