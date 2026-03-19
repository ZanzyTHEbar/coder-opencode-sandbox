# Coder deployment assets

- **Docker Compose:** [`../docker-compose.yml`](../docker-compose.yml) at the **repository root** (so `./template` and this directory can be bind-mounted). Aligned with [Coder’s official `compose.yaml`](https://github.com/coder/coder/blob/main/compose.yaml); see [docs/CODER_OFFICIAL_DEPLOYMENT.md](../docs/CODER_OFFICIAL_DEPLOYMENT.md).
- **Env template:** [`.env.example`](.env.example)
- **Post-deploy:** [`post-deploy.sh`](post-deploy.sh) — run as `sh /deploy/post-deploy.sh` when using root compose + Coolify base directory `.`. On Coolify Compose, run this **on the `coder` service**, not `database`. Default **`POST_DEPLOY_TEMPLATE_SOURCE=auto`**: see [docs/TEMPLATE_REGISTRATION.md](../docs/TEMPLATE_REGISTRATION.md).
