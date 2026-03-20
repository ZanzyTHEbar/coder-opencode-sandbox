# Variables stay in the root module so editors and terraform-ls resolve them cleanly.
variable "docker_socket" {
  default     = ""
  description = "Reserved. Docker is configured via Coder deployment (DOCKER_HOST). Leave empty."
  type        = string
}

variable "sandbox_image" {
  default     = "ghcr.io/zanzythebar/coder-opencode-sandbox:latest"
  description = "Docker image for the OpenCode sandbox (Linux + Coder agent + OpenCode server). Default: repo's GHCR image."
  type        = string
}

variable "workspace_docker_network" {
  default     = ""
  description = "Optional Docker network to attach workspace containers to (e.g. coolify). Default empty = Docker default bridge, which avoids routing/DNS issues on some hosts. Set only if you know you need the same network as Coder/Traefik."
  type        = string
}
