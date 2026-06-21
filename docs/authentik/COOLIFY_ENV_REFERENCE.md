# Coder app — Coolify env reference

Use these in the **Coder** app in Coolify (UUID `w80cko84gsgkck8w48csoc0c`) so Coder can use Authentik OIDC and the post-deploy template push.

## Required (OIDC + runtime)

| Key | Value |
|-----|--------|
| `CODER_ACCESS_URL` | `https://coder.zacariahheim.com` |
| `CODER_OIDC_ISSUER_URL` | `https://auth.zacariahheim.com/application/o/coder/` |
| `CODER_OIDC_CLIENT_ID` | From the Authentik provider. Must match the Coder provider's client ID exactly. |
| `CODER_OIDC_CLIENT_SECRET` | From the Authentik provider. Only print helper output with `PRINT_CODER_OIDC_CLIENT_SECRET=1` during initial setup. |
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
| `SANDBOX_IMAGE` | Optional. Override OpenCode sandbox image for template push. Default in compose is pinned to `ghcr.io/zanzythebar/coder-opencode-sandbox@sha256:cc1b96eb61212139f4767020b7d094eb179515706083103ef75b1a3da76a25e4`. Must be listed in root `docker-compose.yml` `environment` so Coolify injects it. |

After adding or changing env vars in Coolify, redeploy the Coder app so the container gets the new values.

When running `scripts/create_authentik_oidc_coder.py`, set both
`CODER_ACCESS_URL` and `AUTHENTIK_PUBLIC_URL`; the helper exits instead of using
example domains so it cannot rewrite a live provider to placeholders by mistake.

If login fails with Authentik `Client ID Error`, compare the client ID in the browser's `/application/o/authorize/?client_id=...` URL with the Authentik Coder provider before debugging user credentials. If Coder and Authentik match but the browser does not, check for a stale reverse-proxy/backend target serving an older Coder instance.
