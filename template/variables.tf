# Reserved for future use: per-template Docker host override.
# Today the provisioner uses the Coder deployment's DOCKER_HOST (e.g. set in docker-compose.yml at repo root).
# Set DOCKER_HOST on the Coder server if workspaces must use a remote Docker daemon.
variable "docker_socket" {
  default     = ""
  description = "Reserved. Docker is configured via Coder deployment (DOCKER_HOST). Leave empty."
  type        = string
}

# Sandbox image: our GHCR image (built by .github/workflows/build-push-image.yml). Override for custom registry.
variable "sandbox_image" {
  default     = "ghcr.io/zanzythebar/coder-opencode-sandbox:latest"
  description = "Docker image for the OpenCode sandbox (Linux + Coder agent + OpenCode server). Default: repo's GHCR image."
  type        = string
}

# Attach workspace containers to this Docker network so they can reach the Coder server and Traefik (same pattern as Coolify + Coder on one host).
# Set to "" to use Docker's default bridge only.
variable "workspace_docker_network" {
  default     = "coolify"
  description = "Docker network name for workspace containers (e.g. coolify). Matches root docker-compose external network so agents reach CODER_ACCESS_URL."
  type        = string
}
