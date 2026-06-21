# Pangolin / Traefik: `*.zacariahheim.com` -> Coder

When `CODER_WILDCARD_ACCESS_URL` is set on Coder, workspace apps and VS Code use wildcard hostnames. Pangolin's edge Traefik must route those hosts to the same backend as the Coder portal.

## What is configured on DragonServer

On `ssh jumpbox`, under `~/stack/pangolin/config/traefik/`:

- `dynamic_config.yml` uses Pangolin's file provider to define wildcard routers that reuse the generated `15-Coder-Portal-service@http` backend.
- `coder-root-wildcard-router-redirect` handles HTTP -> HTTPS for one-label `*.zacariahheim.com` hosts.
- `coder-root-wildcard-router` handles HTTPS for one-label `*.zacariahheim.com` hosts.
- Both root wildcard routers use low priority so exact Pangolin resources continue
  to win for non-Coder subdomains.
- `tls.domains` uses `main: "zacariahheim.com"` plus `sans: ["*.zacariahheim.com"]`.

Back up `dynamic_config.yml` before edits, then reload Traefik:

```bash
cd ~/stack/pangolin
docker compose restart traefik
```

## Verification

From any client with DNS pointing at Pangolin:

```bash
curl -v --resolve 'test-wildcard.zacariahheim.com:443:<PANGOLIN_PUBLIC_IP>' \
  https://test-wildcard.zacariahheim.com/api/v2/buildinfo
```

- TLS certificate SAN includes `*.zacariahheim.com`.
- A random wildcard hostname reaches Coder and returns Coder headers. It may
  return `400 Invalid Application URL` if the hostname is not a real app URL.
- A real app URL such as `https://opencode--main--ws--admin.zacariahheim.com/doc` returns `200` when that workspace app is healthy.

On an operator machine with SSH aliases configured, run the drift check:

```bash
scripts/check-coder-routing.sh
```

It verifies `coder-proxy` is running, targets the current k3s node NodePort, the
root public buildinfo URL returns Coder headers, and a generated wildcard host
reaches Coder by checking the `x-coder-build-version` header without bypassing
TLS validation. A random wildcard host can return Coder's own
`400 Invalid Application URL`; that is still useful proof that Pangolin reached
Coder. If the script fails, do not rotate OIDC credentials first; check for a
stale proxy target.

## Traefik Warnings

- `No domain found in rule HostRegexp(...)` is informational; `tls.domains` still drives wildcard certificate selection.
- `service "15-Coder-service@http" does not exist` means the old service name is stale. Use `15-Coder-Portal-service@http` for the current Coder Portal resource.

## Pangolin UI vs File

Public resources in Pangolin are often exact hostnames. Catch-all `*.zacariahheim.com` routing is implemented in the Traefik file provider so it survives Pangolin API merges and stays aligned with `15-Coder-Portal-service`.

## Rollback

If `coder-proxy` is retargeted incorrectly, recreate it with the previous known
good upstream:

```bash
docker rm -f coder-proxy
docker run -d --name coder-proxy --restart unless-stopped --network host \
  alpine/socat TCP-LISTEN:30081,fork,reuseaddr TCP:<k3s-node-ip>:30080
```

Then rerun `scripts/check-coder-routing.sh`.
