# Coolify Deployment

Deploy `opencode-docker/docker-compose.yaml` as a repo-backed Docker Compose app.

The step-by-step resource registration and internal-first deployment runbook lives in `infra/coolify/README.md`.

## Phase 1: Internal Only

Do not assign a public domain for the first deployment.

Configure the app on the dedicated OpenCode resource server and verify container health from the server or Coolify logs first.

## Required Host Paths

Create these paths on the target LXC before deploying:

```sh
/srv/opencode/home
/srv/opencode/projects
/srv/opencode/logs
/srv/opencode/backups
```

The Compose file mounts:

- `/srv/opencode/home` to `/home/coder`
- `/srv/opencode/projects` to `/home/coder/workspace`
- `/srv/opencode/logs` to `/var/log/opencode`

## Network

The compose app expects the external Docker network to be named `coolify`, matching DragonServer's other Coolify deployments.

If the dedicated resource server uses a different network name, update `docker-compose.yaml` before deployment.

## Domains

Phase 1 should not set a domain.

For the later public phase, assign a dedicated host to the `opencode` service on container port `4096`, for example:

```text
https://opencode.zacariahheim.com
```

If the Coolify UI expects a port suffix in the domain field, use `https://opencode.zacariahheim.com:4096` to mean “route public HTTPS to backend container port 4096.” The public client URL remains `https://opencode.zacariahheim.com` on port 443.

Do not publish host port `4096` directly to the internet.

Only the `opencode` service should receive a public route.

## Health

The health check probes `/doc` on port `4096`.

If `/home/coder/.opencode/server-password` exists, the health check uses basic auth with username `opencode`.

## Secrets

Set `OPENCODE_SERVER_PASSWORD` in Coolify secrets for defense-in-depth, or leave it blank and keep `OPENCODE_REQUIRE_PASSWORD=true` so startup generates a persistent password. Do not commit real passwords to `.env` or docs.

To retrieve a generated password after deployment, exec into the `opencode` container and read:

```sh
/home/coder/.opencode/server-password
```

Do not paste the value into tickets, shared logs, or terminal transcripts.

If migrated files are root-owned, fix ownership before deployment or set `OPENCODE_CHOWN_RECURSIVE=true` for one startup, then turn it back off to avoid expensive recursive ownership repair on every restart.

Avoid mounting `/var/run/docker.sock` unless a later explicit requirement needs Docker control from inside OpenCode.

## Updates

Keep `OPENCODE_DISABLE_AUTOUPDATE=true`. This runtime updates by rebuilding the container image, not by mutating the binary inside `/home/coder`.

The repo has a scheduled/manual workflow at `.github/workflows/update-opencode-docker.yml` that builds `opencode-docker/Dockerfile` against the latest upstream OpenCode release and publishes versioned GHCR tags.

For the Coolify source-build deployment, the minimal safe update path is:

```bash
# On the LXC, after stopping the OpenCode container and before redeploying:
mkdir -p /srv/opencode/backups
backup=/srv/opencode/backups/opencode-home-$(date -u +%Y%m%dT%H%M%SZ).tar.gz
cd /srv/opencode/home
shopt -s nullglob
db_files=(.local/share/opencode/opencode.db*)
tar czf "$backup" \
  .config/opencode .local/share/opencode/storage "${db_files[@]}"
tar tzf "$backup" >/dev/null
```

Then redeploy the Coolify app with `OPENCODE_VERSION` pinned to the target release, for example `1.17.7`. After health checks pass, leave the pin in place until the next planned update window.

Rollback is the previous Coolify image/deployment plus the matching tarball from `/srv/opencode/backups`.
