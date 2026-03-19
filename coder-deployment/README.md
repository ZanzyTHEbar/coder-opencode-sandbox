# Coder deployment assets

- **Docker Compose:** [`../docker-compose.yml`](../docker-compose.yml) at the **repository root** (so `./template` and this directory can be bind-mounted).
- **Env template:** [`.env.example`](.env.example)
- **Post-deploy:** [`post-deploy.sh`](post-deploy.sh) — mounted at `/deploy/post-deploy.sh` when using root compose + Coolify base directory `.`.
