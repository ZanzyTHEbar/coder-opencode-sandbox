# Pangolin / Traefik: `*.dev.zacariahheim.com` → Coder

When **`CODER_WILDCARD_ACCESS_URL`** is set on Coder, workspace apps and VS Code use hostnames under **`*.dev.<your-domain>`**. Pangolin’s edge Traefik must route those hosts to the **same backend** as **`dev.<your-domain>`** (the Coder / Coolify service).

## What was configured (jumpbox)

On **`ssh jumpbox`**, under **`~/stack/pangolin/config/traefik/`**:

- **`dynamic_config.yml`** (file provider) defines two extra routers that reuse Pangolin’s existing **`15-Coder-service@http`** (same URL as **`Host(\`dev.zacariahheim.com\`)`** from the Pangolin API):

  - **`coder-dev-wildcard-router-redirect`** — HTTP → HTTPS for `HostRegexp` matching one label + **`.dev.zacariahheim.com`**
  - **`coder-dev-wildcard-router`** — HTTPS, **`tls.domains`** with **`main: "*.dev.zacariahheim.com"`** so ACME (DNS-01 via Cloudflare) can issue a wildcard certificate

- A timestamped backup is created beside the file on each edit: **`dynamic_config.yml.bak.<timestamp>`**.

- Reload: **`cd ~/stack/pangolin && docker compose restart traefik`** (or **`docker compose up -d`**).

## Verification

From the jumpbox (or any client with DNS pointing at Pangolin):

```bash
curl -v --resolve 'test-wildcard.dev.zacariahheim.com:443:<PANGOLIN_PUBLIC_IP>' \
  https://test-wildcard.dev.zacariahheim.com/
```

- TLS: **`subject: CN=*.dev.zacariahheim.com`**, SAN matches the hostname.
- HTTP **`404 page not found`** on **`/`** for a random hostname is normal (Coder has no route for that host at `/`); important part is **TLS + TCP to Coder**, not 200 on `/`.

## Traefik warnings

- **`No domain found in rule HostRegexp(...)`** — informational; **`tls.domains`** still drives ACME for the wildcard.
- Brief **`crowdsec@file` does not exist** on restart can appear until the file provider finishes loading; if it persists, restart the stack with **`docker compose up -d`** in **`~/stack/pangolin`**.

## Pangolin UI vs file

Public resources in Pangolin are often **exact** hostnames. Catch-all **`*.dev…`** routing is implemented here in the **Traefik file provider** so it survives Pangolin API merges and stays aligned with **`15-Coder-service`**.
