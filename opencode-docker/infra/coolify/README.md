# Coolify Resource Registration And Deployment

This is the post-LXC sequence:

1. Register the community-script-created and Ansible-prepared Debian Docker LXC as a Coolify Docker resource server.
2. Deploy `opencode-docker/docker-compose.yml` to that resource server with no public domain.
3. Validate OpenCode internally.
4. Add public routing only after Pangolin/Auth is ready.

## Registration

Use Coolify's resource-server registration workflow for a Docker server.

Record the resulting identifiers here in your private ops notes, not in git:

- Coolify server UUID
- Coolify destination UUID
- Docker network name on the resource server
- OpenCode app/service UUID

Do not reuse the shared `coolifyresources` target for the production OpenCode runtime unless the dedicated LXC path is explicitly abandoned.

## Internal-Only First Deploy

Create the Coolify app/service against the new resource server and point it at this repo path:

```text
Base directory: opencode-docker
Compose file: docker-compose.yml
```

Do not assign a public domain in the first deployment.

Set environment variables from `opencode-docker/.env.example`.

Minimum expected values:

```env
OPENCODE_HOME_PATH=/srv/opencode/home
OPENCODE_PROJECTS_PATH=/srv/opencode/projects
OPENCODE_LOGS_PATH=/srv/opencode/logs
OPENCODE_REQUIRE_PASSWORD=true
WORKSPACE_BOOTSTRAP_FAILURE_POLICY=warn
WORKSPACE_BOOTSTRAP_TIMEOUT_SECONDS=600
```

Use a Coolify secret for `OPENCODE_SERVER_PASSWORD`, or leave it blank and retrieve the generated password from `/home/coder/.opencode/server-password` inside the container.

## Compose Raw API Shape

If using Coolify's API instead of the UI, the existing DragonServer control plane uses `/services` with a request shape like this:

```json
{
  "type": "docker-compose",
  "name": "opencode-docker",
  "description": "Docker-only OpenCode runtime",
  "project_uuid": "<coolify-project-uuid>",
  "environment_name": "production",
  "server_uuid": "<dedicated-opencode-server-uuid>",
  "destination_uuid": "<dedicated-opencode-destination-uuid>",
  "instant_deploy": false,
  "docker_compose_raw": "<contents of opencode-docker/docker-compose.yml>",
  "urls": [],
  "force_domain_override": false
}
```

The exact Coolify API schema can drift by version. Verify against live Coolify before mutation.

## Validation

After deployment, validate on the resource server or via Coolify exec/logs:

```sh
docker ps --filter name=opencode
docker exec <opencode-container> sh -lc 'p=$(cat /home/coder/.opencode/server-password); curl -fsS -u "opencode:$p" http://127.0.0.1:4096/doc >/dev/null'
docker exec <opencode-container> test -w /home/coder/workspace
docker exec <opencode-container> test -s /var/log/opencode/startup.log
```

Then restart/redeploy and confirm:

- `/home/coder` state persists.
- `/home/coder/workspace` files persist.
- generated server password persists unless intentionally rotated.
- logs remain available under `/srv/opencode/logs`.

## Public Cutover Gate

Do not assign a public domain until all internal checks pass and `../pangolin/ROUTING_AUTH.md` is executed.

Before public cutover, verify the resource server is not exposing OpenCode directly:

```sh
docker port <opencode-container>
ss -ltnp | grep 4096 || true
ufw status verbose
```

There should be no internet-facing host-port binding for `4096`.
