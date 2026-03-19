# Alignment with Coder’s official Docker deployment

This repo’s root [`docker-compose.yml`](../docker-compose.yml) is **based on** Coder’s published Compose file and docs. Use this page when upgrading Coder, debugging DB/socket issues, or comparing behavior to upstream.

## Canonical upstream references

| Resource | URL |
|----------|-----|
| Official Compose (Postgres + Coder + docker.sock) | [coder/coder `compose.yaml`](https://github.com/coder/coder/blob/main/compose.yaml) |
| Install with Docker | [Coder docs — Docker](https://coder.com/docs/install/docker) |
| External PostgreSQL | [Using an External Database](https://coder.com/docs/tutorials/external-database) |
| Configuration (env vars) | [Coder admin setup](https://coder.com/docs/admin/setup) |

Minimum **PostgreSQL major version** for Coder: **13+** (upstream example uses **17**).

## What we match (on purpose)

- **Dedicated `database` service** with a named volume on `/var/lib/postgresql/data`.
- **`depends_on: database` with `condition: service_healthy`** so Coder starts after Postgres is ready.
- **`CODER_PG_CONNECTION_URL`** using the same URI shape as upstream:  
  `postgresql://USER:PASSWORD@database/DATABASE?sslmode=disable`  
  (host `database` is the Compose service name; default Postgres port **5432** is implied — no `:5432` required.)
- **`CODER_HTTP_ADDRESS`** bound to `0.0.0.0` and a published container port (see deltas below).
- **`CODER_ACCESS_URL`** set to the **public URL** users and workspaces use (must not be `localhost` / `127.0.0.1` for real templates — see [Docker install troubleshooting](https://coder.com/docs/install/docker#troubleshooting)).
- **Docker socket** mounted at `/var/run/docker.sock` with **`CODER_PROVISIONER_DAEMON=true`** and **`DOCKER_HOST=unix:///var/run/docker.sock`** for Docker-backed workspaces.
- **Image tag** — `ghcr.io/coder/coder:${CODER_VERSION:-latest}` so you can pin **`CODER_VERSION`** (e.g. `v2.x.x`) in production.

## Intentional differences (this repo / Coolify)

| Topic | Official `compose.yaml` | This repo |
|-------|-------------------------|-----------|
| HTTP port | **7080** | **4099** (Coolify often exposes this; override with **`CODER_HOST_PORT`** on the host side) |
| Network | Default Compose network | **`coolify` external network** so Coolify’s proxy can attach. Create once: `docker network create coolify` (or rely on Coolify creating it). |
| `coder_home` volume | Mounts `coder_home:/home/coder` (optional; mainly dev / tunnel URL) | **Omitted** — not required when using external Postgres and a real **`CODER_ACCESS_URL`** ([upstream comment](https://github.com/coder/coder/blob/main/compose.yaml)). |
| OIDC / tokens | Not in upstream file | **Authentik OIDC** env vars + **`CODER_TOKEN`** / **`CODER_URL`** for post-deploy template push. |
| Bind mounts | None | **`./template` → `/templates`**, **`./coder-deployment` → `/deploy`** for Coolify post-deploy. |
| `group_add` | Commented example for Docker GID | **Commented** — same fix path as upstream (see below). |

## Docker socket: `permission denied`

Coder runs **non-root**. If workspace builds fail with Docker errors, set the host **`docker` group GID** and uncomment **`group_add`** in [`docker-compose.yml`](../docker-compose.yml):

```bash
getent group docker | cut -d: -f3
```

Put that value in **`DOCKER_GID`** in your environment (Coolify / `.env`), then uncomment:

```yaml
group_add:
  - "${DOCKER_GID}"
```

See [Coder — Install Docker — Troubleshooting](https://coder.com/docs/install/docker#troubleshooting).

## Production checklist (short)

1. **Strong DB password** — set **`POSTGRES_PASSWORD`** (and optional **`POSTGRES_USER`** / **`POSTGRES_DB`**) via secrets; avoid shipping defaults.
2. **`CODER_ACCESS_URL`** — exact browser URL (scheme + host, no path); matches your reverse proxy and OIDC redirect URIs.
3. **Pin versions** — set **`CODER_VERSION`** and Postgres image tag if you want reproducible deploys.
4. **TLS** — terminate TLS at your reverse proxy (e.g. Traefik / Coolify); Coder behind HTTPS is the usual production pattern.
5. **First admin / OIDC** — follow [COOLIFY_E2E.md](COOLIFY_E2E.md) §4 (bootstrap vs **`CODER_DISABLE_PASSWORD_AUTH`** deadlock).

## Optional: local Compose without Coolify

If you do **not** use the `coolify` network, replace the `networks` section with a default project network or use a **`docker-compose.override.yml`** that removes the external network requirement. The official file is a good minimal baseline for that experiment.
