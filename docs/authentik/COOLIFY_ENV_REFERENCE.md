# Coder app — Coolify env reference

Use these in the **Coder** app in Coolify (UUID `w80cko84gsgkck8w48csoc0c`) so Coder can use Authentik OIDC and the post-deploy template push.

## Required (OIDC + runtime)

| Key | Value |
|-----|--------|
| `CODER_ACCESS_URL` | `https://coder.zacariahheim.com` |
| `CODER_OIDC_ISSUER_URL` | `https://auth.zacariahheim.com/application/o/coder/` |
| `CODER_OIDC_CLIENT_ID` | From Authentik provider (run `scripts/create_authentik_oidc_coder.py` and copy the printed value) |
| `CODER_OIDC_CLIENT_SECRET` | From Authentik provider (same script output) |
| `CODER_OIDC_EMAIL_FIELD` | `email` |
| `CODER_OIDC_USERNAME_FIELD` | `preferred_username` |
| `CODER_DISABLE_PASSWORD_AUTH` | `true` |
| `CODER_PROVISIONER_DAEMON` | `true` |
| `DOCKER_HOST` | `unix:///var/run/docker.sock` |

## Post-deploy template push

| Key | Value |
|-----|--------|
| `CODER_URL` | `http://127.0.0.1:4099` |
| `CODER_TOKEN` | Coder API/session token (create in Coder UI after first deploy; add to Coolify as secret) |
| `SANDBOX_IMAGE` | Optional. Override OpenCode sandbox image for template push (default in compose: `ghcr.io/zanzythebar/coder-opencode-sandbox:latest`). Must be listed in root `docker-compose.yml` `environment` so Coolify injects it. |

After adding or changing env vars in Coolify, redeploy the Coder app so the container gets the new values.
