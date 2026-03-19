# Next steps

Follow these in order to go from zero to a working OpenCode sandbox on Coder.

## 1. Image: use pre-built (GHCR) or build locally

**Option A — Use the pre-built public image (recommended)**  
On every push to `main`, [GitHub Actions](.github/workflows/build-push-image.yml) builds and pushes to GHCR. Use:

```text
ghcr.io/<owner>/coder-opencode-sandbox:latest
```

(e.g. `ghcr.io/zanzythebar/coder-opencode-sandbox:latest`). Set this as the template variable `sandbox_image`. After the first run, make the package **Public** in the repo’s Packages settings.

**Option B — Build locally**

```bash
cd image && docker build -t opencode-sandbox:latest .
```

If Coder runs on another host, push to your own registry and set `sandbox_image` to that image.

## 2. Deploy Coder and configure Authentik

- Use [coder-deployment/](coder-deployment/) (Compose + `.env.example`) or [Coder’s install docs](https://coder.com/docs/install).
- Set **CODER_ACCESS_URL** to your public URL.
- Configure OIDC with Authentik: [docs/authentik/OIDC_SETUP.md](docs/authentik/OIDC_SETUP.md).
- Ensure Coder’s provisioner can reach Docker (socket or DOCKER_HOST).

## 3. Create the template

```bash
coder login   # to your Coder URL
coder templates create opencode-sandbox --directory template
```

When prompted (or in the dashboard), set **sandbox_image** to your image (e.g. `ghcr.io/<owner>/coder-opencode-sandbox:latest`, or `opencode-sandbox:latest` if you built locally).

## 4. Smoke-test

1. Log in via OIDC at your Coder URL.
2. Create a workspace from the **OpenCode sandbox** template and start it.
3. Open the **OpenCode** app and the **Terminal**; confirm the UI loads and you have a shell.
4. In the terminal, create a file under `/home/coder`; stop the workspace, then start it again and confirm the file is still there (persistence).

---

See [docs/OPERATOR.md](docs/OPERATOR.md) for full operator guidance and [docs/USER.md](docs/USER.md) for end-user instructions.
