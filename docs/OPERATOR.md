# Operator guide: Coder + OpenCode sandbox

## 1. Deploy Coder

- Use the reference [coder-deployment/docker-compose.yml](../coder-deployment/docker-compose.yml) or deploy Coder on Kubernetes per [Coder docs](https://coder.com/docs/install).
- Set **CODER_ACCESS_URL** to your public URL (e.g. `https://dev.example.com`). Coder must be reachable at this URL and able to reach your OIDC issuer (Authentik).

## 2. Configure OIDC (Authentik)

- In Authentik, create an OIDC provider and application for Coder. Redirect URI must be exactly:
  `https://<CODER_ACCESS_URL>/api/v2/users/oidc/callback`
- Set **Subject (sub)** to a stable value (e.g. “Based on the User's Hashed ID”) so the same user always gets the same identity.
- Configure Coder with:
  - **CODER_OIDC_ISSUER_URL** — Authentik OIDC issuer URL (e.g. `https://auth.example.com/application/o/<app-slug>/`).
  - **CODER_OIDC_CLIENT_ID**, **CODER_OIDC_CLIENT_SECRET** — from the Authentik OIDC application.
  - **CODER_OIDC_EMAIL_FIELD**, **CODER_OIDC_USERNAME_FIELD** — claim names (e.g. `email`, `preferred_username`).
  - **CODER_DISABLE_PASSWORD_AUTH=true** so only OIDC is used.

See [authentik/OIDC_SETUP.md](authentik/OIDC_SETUP.md) for step-by-step Authentik configuration.

## 3. Provisioner (Docker)

- Workspace templates use the Docker provider to create containers and volumes. Coder’s provisioner must have access to the Docker socket (or a remote Docker host).
- In Docker Compose, mount `/var/run/docker.sock` into the Coder container and set **CODER_PROVISIONER_DAEMON=true** and **DOCKER_HOST** as needed.
- Ensure the template variable **docker_socket** is set if Coder runs remotely (e.g. `unix:///var/run/docker.sock` on the host that runs workspaces).

## 4. Build and set the sandbox image

- From the repo root:
  ```bash
  cd image && docker build -t opencode-sandbox:latest .
  ```
- If Coder runs on another host or Kubernetes, push the image to a registry and reference it in the template:
  ```bash
  docker tag opencode-sandbox:latest your-registry/opencode-sandbox:latest
  docker push your-registry/opencode-sandbox:latest
  ```

## 5. Create the template in Coder

- Create the template from the `template/` directory:
  ```bash
  coder login  # to your Coder URL
  coder templates create opencode-sandbox --directory template
  ```
- When prompted (or in the dashboard), set the template variable **sandbox_image** to the image name (e.g. `opencode-sandbox:latest` or `your-registry/opencode-sandbox:latest`).
- Optionally set **docker_socket** if you use a non-default Docker host.

## 6. Persistence and lifecycle

- **Stop/start:** The persistent volume (named by workspace id) is kept when a workspace is stopped. On start, the same volume is mounted at `/home/coder`; OpenCode state, code, and config persist.
- **Delete:** Deleting a workspace runs `terraform destroy` and removes the volume. Data is not recoverable unless you implement a backup (e.g. pre-delete export to object storage). Prefer **stop** over **delete** for long-lived user data.

## 7. Wildcard / app URLs (optional)

- To give each workspace app a stable URL (e.g. for the OpenCode app), configure [Coder’s wildcard access URL](https://coder.com/docs/admin/networking/wildcard-access-url) and TLS so that `*.dev.example.com` resolves to Coder. Otherwise users open the OpenCode app via the dashboard (Coder proxies to the workspace).

## 8. Troubleshooting

- **Agent never connects:** Ensure the container runs the agent init script (template sets `command = ["sh", "-c", coder_agent.main.init_script]`) and has `CODER_AGENT_TOKEN` in env. Check Coder logs and container logs.
- **OpenCode app 502 / unhealthy:** The agent’s startup_script starts `opencode serve --hostname 0.0.0.0 --port 4096` in the background. Ensure OpenCode is installed in the image and the healthcheck URL `http://localhost:4096/doc` is reachable from inside the container.
- **Volume not persisting:** Volume name must use `data.coder_workspace.me.id` only (immutable). Do not use owner or workspace name in the volume name. Ensure `lifecycle { ignore_changes = all }` is set on the volume resource.
