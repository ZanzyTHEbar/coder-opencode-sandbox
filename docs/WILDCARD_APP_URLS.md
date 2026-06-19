# Wildcard app URLs (stable URLs per workspace app)

## Symptoms if this is missing or misconfigured

- **OpenCode (or any SPA) white screen** in the app tab; browser console shows **404** on `/assets/index-….js`, **stylesheet MIME type `text/plain`**, scripts **refused** because MIME is **`text/html`** (you’re getting Traefik/Coder error HTML or plain-text fallbacks, not the workspace app). Root cause: path-based routing made the document load from the app proxy, but **`/assets/*` resolves to the main site origin** (e.g. `https://dev.example.com/assets/...`), not the workspace.
- **VS Code Desktop** fails with **hostname could not be resolved** and drops the remote — Coder’s SSH/config hostnames expect a **wildcard DNS zone** matching **`CODER_WILDCARD_ACCESS_URL`**.

The fix for both is the same: **`CODER_WILDCARD_ACCESS_URL`**, **DNS `*.domain` → Coder**, **TLS for the wildcard**, and your reverse proxy (Coolify/Traefik) routing **`Host: *.<domain>`** to the Coder service. The OpenCode template uses **`subdomain = true`** on `coder_app` so the app is served at the **root of a dedicated hostname** (compatible with SPAs).

For the external multi-tenant runtime, wildcard app routing still terminates at
Coder. Do not create public routes directly to workspace pods.

---

Without a wildcard access URL, users open the OpenCode app only through the Coder dashboard (Coder proxies to the workspace). With a **wildcard access URL** and TLS, each workspace app can have a stable, shareable URL like:

```text
https://<workspace>-<app>.<wildcard-domain>
```

Example: `https://myworkspace-opencode.dev.example.com` for the OpenCode app in workspace `myworkspace`.

---

## 1. Coder configuration

Set the following on the Coder server (e.g. in your Compose or K8s env):

| Variable | Example | Purpose |
|----------|---------|---------|
| `CODER_WILDCARD_ACCESS_URL` | `*.dev.example.com` | Wildcard host pattern for app subdomains. |

Coder will use this to route requests for `https://<something>.dev.example.com` to the right workspace app. The main Coder UI stays at `CODER_ACCESS_URL` (e.g. `https://dev.example.com`).

Reference: [Coder – Wildcard Access URL](https://coder.com/docs/admin/networking/wildcard-access-url).

---

## 2. DNS

Point the wildcard (and optionally the main host) at the host(s) where Coder or your reverse proxy runs:

```text
*.dev.example.com   A     <Coder-or-proxy-IP>
dev.example.com    A     <Coder-or-proxy-IP>
```

Or use CNAME:

```text
*.dev.example.com   CNAME   coder.example.com.
```

---

## 3. Edge reverse proxy (Pangolin / Traefik)

If **`dev.example.com`** is fronted by **Pangolin** (Traefik on a jumpbox), add routers so **`*.dev.example.com`** uses the **same backend** as **`dev.example.com`**. See **[PANGOLIN_TRAEFIK_WILDCARD.md](PANGOLIN_TRAEFIK_WILDCARD.md)** for the pattern used on DragonServer (`HostRegexp` + reuse **`15-Coder-service@http`**, wildcard cert on **`*.dev.<domain>`**).

---

## 4. TLS

Wildcard app URLs require TLS for the wildcard host. Two common approaches:

### Option A: Reverse proxy in front of Coder (recommended)

Run Caddy, NGINX, or Traefik in front of Coder and terminate TLS there. Use ACME (e.g. Let’s Encrypt) to get a wildcard certificate (`*.dev.example.com`). Wildcard issuance often requires DNS-01 challenge (e.g. Caddy with a DNS provider, or cert-bot with a plugin).

- Proxy forwards `https://*.dev.example.com` and `https://dev.example.com` to Coder (e.g. `http://localhost:8080`).
- Coder does **not** serve TLS; set `CODER_ACCESS_URL=https://dev.example.com` and `CODER_WILDCARD_ACCESS_URL=https://*.dev.example.com` (or the same host with a wildcard subdomain per Coder docs).

### Option B: Coder serves TLS directly

If Coder holds the wildcard cert:

```bash
export CODER_TLS_ENABLE=true
export CODER_TLS_CERT_FILE=/path/to/wildcard.dev.example.com.crt
export CODER_TLS_KEY_FILE=/path/to/wildcard.dev.example.com.key
```

Use a single cert that covers both the main host and `*.dev.example.com` (SANs or wildcard cert). Then set `CODER_ACCESS_URL` and `CODER_WILDCARD_ACCESS_URL` to the same host/wildcard pattern.

---

## 5. Checklist

1. **DNS:** `*.dev.example.com` (and main host) resolve to Coder or your proxy.
2. **TLS:** Wildcard (or multi-SAN) cert in place; either at reverse proxy (Option A) or Coder (Option B).
3. **Coder env:** `CODER_WILDCARD_ACCESS_URL` set (e.g. `https://*.dev.example.com`).
4. **Restart Coder** after changing env so the new wildcard config is loaded.

After that, workspace app URLs (e.g. OpenCode) can use the stable subdomain pattern; exact format is in [Coder’s wildcard access URL docs](https://coder.com/docs/admin/networking/wildcard-access-url).

---

## 6. Troubleshooting

- **App opens in dashboard but not at wildcard URL:** Confirm DNS and TLS for the wildcard host; confirm `CODER_WILDCARD_ACCESS_URL` and that Coder was restarted.
- **Certificate errors:** Ensure the cert’s CN or SANs include the wildcard (e.g. `*.dev.example.com`) and that clients are using the same hostname.
- **Cookie/session issues:** Avoid using a bare top-level domain for the wildcard; use a subdomain (e.g. `*.dev.example.com`), as some browsers restrict cookies on certain patterns.
