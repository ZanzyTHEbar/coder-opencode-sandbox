# Registering the Coder template (no GitHub Actions)

Template registration uses **`coder templates push`** — either from **Coolify post-deploy** ([`coder-deployment/post-deploy.sh`](../coder-deployment/post-deploy.sh)) or **manually** ([`scripts/bootstrap-template.sh`](../scripts/bootstrap-template.sh)).

The critical requirement is:

- The template in Coder must match the **exact git revision** that Coolify just deployed.
- A preserved or stale bind-mounted checkout must **never** win over that deployed revision.

## Recommended: `deployed_commit` (default)

Coolify already injects **`SOURCE_COMMIT`** into the container environment.

`POST_DEPLOY_TEMPLATE_SOURCE=deployed_commit` makes post-deploy:

1. Read **`SOURCE_COMMIT`** from the running Coder container.
2. Download **that exact commit archive** from GitHub.
3. Sync that exact `template/` tree back into the bind-mounted `./template` directory, deleting stale files first.
4. Run **`coder templates push`** from the synced tree.

That gives you a hard guarantee:

- **Every redeploy** pushes the template.
- The template is **always in sync** with the **deployed stack revision**.
- Coolify’s **“preserve repo during deployment”** cannot leave deleted files behind in `./template`.

## `auto`

`POST_DEPLOY_TEMPLATE_SOURCE=auto` is a softer mode:

1. Use the bind-mounted `./template` → `/templates` only if it passes sanity checks **and** is already stamped with the current `SOURCE_COMMIT`.
2. Otherwise, fetch the **exact `SOURCE_COMMIT`** when available.
3. Sync that exact tree back into `./template`, deleting stale files first.
4. If `SOURCE_COMMIT` is unavailable, fall back to the configured GitHub ref.

Use this if you want to prefer the local checkout for speed, but still recover safely.

## `github_ref`

`POST_DEPLOY_TEMPLATE_SOURCE=github_ref` ignores the mount and fetches the configured ref:

- `POST_DEPLOY_GITHUB_REF`
- `POST_DEPLOY_GITHUB_REF_TYPE` (`heads` or `tags`)

Use this when you intentionally want a branch/tag-driven template source instead of the exact deployed commit.

## `mount`

`POST_DEPLOY_TEMPLATE_SOURCE=mount` uses only `/templates`.

This is strict and only safe if you can **prove** Coolify refreshes the checkout on every deploy.

## Environment variables

| Variable | Role |
|----------|------|
| `POST_DEPLOY_TEMPLATE_SOURCE` | `deployed_commit` (default) \| `auto` \| `github_ref` \| `mount` |
| `SOURCE_COMMIT` | Set by Coolify; exact deployed commit SHA. Used by `deployed_commit` and `auto`. |
| `POST_DEPLOY_GITHUB_REPO` | e.g. `owner/repo` (default in compose) |
| `POST_DEPLOY_GITHUB_REF` | Branch or tag name (used by `github_ref`, fallback for `auto`) |
| `POST_DEPLOY_GITHUB_REF_TYPE` | `heads` or `tags` |
| `POST_DEPLOY_GITHUB_TOKEN` | Optional Bearer PAT for private repos |
| `POST_DEPLOY_SYNC_TEMPLATE_MOUNT` | `1` (default) keeps `./template` synced to the pushed source tree, including deletions |

See [COOLIFY_E2E.md](COOLIFY_E2E.md) for Coolify + `CODER_TOKEN` + post-deploy command.

## Image builds vs template push

[`.github/workflows/build-push-image.yml`](../.github/workflows/build-push-image.yml) may still **build and push the sandbox image** to GHCR — that is **unrelated** to registering the Terraform template in Coder. Template registration is **only** `coder templates push` (post-deploy or manual).
