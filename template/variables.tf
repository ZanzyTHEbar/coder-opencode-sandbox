# Optional Docker socket (e.g. for remote Docker).
variable "docker_socket" {
  default     = ""
  description = "Docker socket URI. Leave empty to use default."
  type        = string
}

# Sandbox image: build from image/ and push to your registry, then set this.
variable "sandbox_image" {
  default     = "opencode-sandbox:latest"
  description = "Docker image for the OpenCode sandbox (Linux + Coder agent + OpenCode server)."
  type        = string
}
