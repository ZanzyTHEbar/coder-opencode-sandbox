# OpenCode sandbox image

Docker image used by the Coder template: Ubuntu + OpenCode server + git/curl. The Coder agent is started at runtime via the template's `init_script` (not baked into the image).

## Build

```bash
docker build -t opencode-sandbox:latest .
# Or with version override:
docker build --build-arg OPENCODE_VERSION=1.2.27 -t opencode-sandbox:latest .
```

## Push (for template use)

If Coder runs on a host that doesn't build the image, push to a registry and set the template variable `sandbox_image`:

```bash
docker tag opencode-sandbox:latest your-registry/opencode-sandbox:latest
docker push your-registry/opencode-sandbox:latest
# In Coder: template variable sandbox_image = "your-registry/opencode-sandbox:latest"
```

## Local template testing

Build and use the image by name so the template's default `sandbox_image` works:

```bash
docker build -t opencode-sandbox:latest .
# Then create/update the Coder template; ensure Docker socket is available to Coder.
```
