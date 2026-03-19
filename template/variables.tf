# Reserved for future use: per-template Docker host override.
# Today the provisioner uses the Coder deployment's DOCKER_HOST (e.g. set in coder-deployment/docker-compose.yml).
# Set DOCKER_HOST on the Coder server if workspaces must use a remote Docker daemon.
variable "docker_socket" {
  default     = ""
  description = "Reserved. Docker is configured via Coder deployment (DOCKER_HOST). Leave empty."
  type        = string
}

# Sandbox image: build from image/ and push to your registry, then set this.
variable "sandbox_image" {
  default     = "opencode-sandbox:latest"
  description = "Docker image for the OpenCode sandbox (Linux + Coder agent + OpenCode server)."
  type        = string
}
