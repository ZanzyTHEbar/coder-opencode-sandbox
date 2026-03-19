# Registering the Coder template (no GitHub Actions)

Template registration uses **`coder templates push`** — either from **Coolify post-deploy** ([`coder-deployment/post-deploy.sh`](../coder-deployment/post-deploy.sh)) or **manually** ([`scripts/bootstrap-template.sh`](../scripts/bootstrap-template.sh)).

If you **do not** use a CI pipeline to push templates (or cannot), use **`POST_DEPLOY_TEMPLATE_SOURCE`** so the **template never comes from a stale Coolify checkout** when “preserve repo during deployment” leaves old files on disk.

## Recommended: `auto` (default)

`POST_DEPLOY_TEMPLATE_SOURCE=auto` (set in [`docker-compose.yml`](../docker-compose.yml) or Coolify env):

1. **Use** the bind-mounted `./template` → `/templates` **if** it passes sanity checks (`workspace_volume_bootstrap` + `user = "0:0"` in `main.tf`).
2. **Otherwise** download the same tree from **GitHub** (`POST_DEPLOY_GITHUB_*`) and push from `/tmp`.

So every deploy **either** uses a **good** local checkout **or** self-heals from **`main`** — **no** separate CI required.

## Stricter: always fetch from GitHub

`POST_DEPLOY_TEMPLATE_SOURCE=github` — **ignore** the bind mount; **always** fetch `refs/heads/<ref>` tarball from GitHub before `coder templates push`. Use when you **never** trust the Coolify app directory. Requires outbound HTTPS to `github.com` (and **`POST_DEPLOY_GITHUB_TOKEN`** for private repos).

## Mount-only

`POST_DEPLOY_TEMPLATE_SOURCE=mount` — **only** `/templates`. Fails if the checkout is stale. Use only if you guarantee **fresh** git checkouts on every deploy (e.g. disable “preserve repo” or force pull before compose).

## Environment variables

| Variable | Role |
|----------|------|
| `POST_DEPLOY_TEMPLATE_SOURCE` | `auto` (default) \| `mount` \| `github` |
| `POST_DEPLOY_GITHUB_REPO` | e.g. `owner/repo` (default in compose) |
| `POST_DEPLOY_GITHUB_REF` | Branch or tag name (default `main`) |
| `POST_DEPLOY_GITHUB_REF_TYPE` | `heads` or `tags` |
| `POST_DEPLOY_GITHUB_TOKEN` | Optional Bearer PAT for private repos |

See [COOLIFY_E2E.md](COOLIFY_E2E.md) for Coolify + `CODER_TOKEN` + post-deploy command.

## Image builds vs template push

[`.github/workflows/build-push-image.yml`](../.github/workflows/build-push-image.yml) may still **build and push the sandbox image** to GHCR — that is **unrelated** to registering the Terraform template in Coder. Template registration is **only** `coder templates push` (post-deploy or manual).
