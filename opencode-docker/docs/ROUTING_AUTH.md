# Routing And Auth

The first deployment is internal-only. Do not add public DNS or Pangolin routing until OpenCode is healthy on the dedicated LXC resource server.

The detailed public routing runbook lives in `infra/pangolin/ROUTING_AUTH.md`.

## Public Phase Target

Recommended future hostname:

```text
opencode.zacariahheim.com
```

Expected path:

```text
browser -> Pangolin public resource -> Authentik gate -> Coolify/Traefik -> opencode:4096
```

## Auth Model

OpenCode should be treated as not having native OIDC support.

Primary auth must be enforced before traffic reaches OpenCode:

- Pangolin protected public resource.
- Authentik gate or forward-auth pattern already used on DragonServer.

`OPENCODE_SERVER_PASSWORD` is defense-in-depth and attach protection, not the primary access-control boundary.

Keep `OPENCODE_REQUIRE_PASSWORD=true` even for internal-only testing unless you are intentionally debugging proxy auth in an isolated network.

## Public Verification

Before declaring public routing complete:

- Unauthenticated public browser session is blocked or redirected to Authentik.
- Authenticated session reaches OpenCode.
- Direct backend bypass is not publicly reachable.
- `/doc` works after auth.
- OpenCode password works where expected.

If any auth bypass is found, remove the public route and keep the app internal-only.
