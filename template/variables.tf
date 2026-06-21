# Variables stay in the root module so editors and terraform-ls resolve them cleanly.
variable "docker_socket" {
  default     = ""
  description = "Reserved. Docker is configured via Coder deployment (DOCKER_HOST). Leave empty."
  type        = string
}

variable "sandbox_image" {
  default     = "ghcr.io/zanzythebar/coder-opencode-sandbox@sha256:cc1b96eb61212139f4767020b7d094eb179515706083103ef75b1a3da76a25e4"
  description = "Docker image for the OpenCode sandbox (Linux + Coder agent + OpenCode server). Default: repo's pinned GHCR image."
  type        = string
}

variable "workspace_docker_network" {
  default     = ""
  description = "Optional Docker network to attach workspace containers to (e.g. coolify). Default empty = Docker default bridge, which avoids routing/DNS issues on some hosts. Set only if you know you need the same network as Coder/Traefik."
  type        = string
}
