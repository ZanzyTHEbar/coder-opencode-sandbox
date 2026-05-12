# Pangolin/Auth Public Routing

Run this only after the internal Coolify deployment is healthy on the dedicated OpenCode resource server.

## Target State

```text
browser
  -> Pangolin public resource
  -> Authentik gate
  -> Coolify/Traefik route
  -> opencode container port 4096
```

Recommended hostname for the public phase:

```text
opencode.zacariahheim.com
```

## Preconditions

- Dedicated LXC is registered in Coolify.
- OpenCode app is deployed internally and healthy.
- `OPENCODE_REQUIRE_PASSWORD=true` remains enabled.
- No host port `4096` is publicly exposed.
- Rollback path is ready: remove/disable Pangolin resource and leave internal Coolify app running.

## Coolify Domain Assignment

Assign the public hostname to the `opencode` service and route it to backend container port `4096`.

In Coolify UI terms, the domain field may be entered with a backend port suffix:

```text
https://opencode.zacariahheim.com:4096
```

This means public HTTPS on 443 routed by Traefik to container port `4096`. It does not mean publishing host port `4096` to the internet.

Expected public client URL:

```text
https://opencode.zacariahheim.com
```

Do not create a direct host-port mapping for `4096`.

## Firewall Gate

The Ansible baseline permits SSH only. Public routing requires one explicit firewall change after internal validation.

Preferred options, in order:

1. If Pangolin/Newt reaches the backend through an internal tunnel or Docker network, allow only that source to the required backend listener.
2. If Coolify/Traefik on this LXC must terminate HTTPS directly, allow TCP `80`/`443` only from the expected Pangolin/Newt/proxy source addresses where possible.
3. Avoid opening TCP `4096` externally.

Before changing UFW, capture:

```sh
ufw status verbose
ss -ltnp
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

After changing UFW, repeat the same checks and verify unauthenticated public requests still hit Authentik/Pangolin before OpenCode.

## Pangolin Resource

Create a Pangolin public resource for `opencode.zacariahheim.com` that targets the Coolify/Traefik HTTPS backend for the same hostname.

Follow the existing DragonServer Pangolin/Newt pattern rather than inventing a parallel tunnel. Historical DragonServer routing has used the Newt site to reach the Coolify resource backend while preserving Host/SNI.

Record in private ops notes:

- Pangolin resource ID
- site ID
- target backend address
- health check path
- auth policy/application attached

## Authentik Gate

OpenCode is not treated as an OIDC-native app. Use Pangolin/Auth proxy gating as the primary access control.

Requirements:

- unauthenticated requests redirect to or are blocked by Authentik
- authenticated requests reach OpenCode
- direct backend bypass is not publicly reachable
- OpenCode server password remains enabled as defense-in-depth

## Health Check

Use `/doc` as the application health path.

If the health checker cannot supply the OpenCode password, use a proxy/backend-level TCP or HTTPS reachability check instead and keep `/doc` validation as an operator check after authentication.

## Verification

Use a clean browser/private window:

1. Visit `https://opencode.zacariahheim.com` unauthenticated.
2. Confirm Authentik blocks or redirects before OpenCode is visible.
3. Authenticate with an authorized user.
4. Confirm OpenCode loads.
5. Confirm `/doc` responds after auth.
6. Confirm access fails again after logging out or from a separate unauthenticated session.

Backend checks:

```sh
curl -I https://opencode.zacariahheim.com
docker port <opencode-container>
ss -ltnp | grep -E '(:4096|:443|:80)' || true
ufw status verbose
```

Expected unauthenticated result is an Authentik/Pangolin redirect or denial, not raw OpenCode content.

Direct-bypass checks must also fail from outside the protected path:

```sh
curl -I http://<resource-server-ip>:4096/doc
curl -kI https://<resource-server-ip>/doc
curl -I http://<resource-server-ip>/doc
```

Acceptable outcomes are connection refused, timeout, or proxy/auth denial. Raw OpenCode content is a rollback trigger.

## Rollback

If any auth bypass or routing issue appears:

1. Disable the Pangolin resource or remove the public Coolify domain.
2. Confirm `https://opencode.zacariahheim.com` no longer reaches OpenCode.
3. Keep the internal Coolify deployment running for investigation.
4. Do not delete persistent data under `/srv/opencode`.
