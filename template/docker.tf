# Persistent volume: one per workspace, survives stop/start.
resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace.me.id}-home"

  lifecycle {
    ignore_changes = all
  }
}

# Sandbox image (built from `image/`; operator sets `var.sandbox_image`).
resource "docker_image" "sandbox" {
  name = var.sandbox_image
}

# Workspace container: created only while the workspace is running.
resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.sandbox.image_id
  name  = local.container_name

  # Override the image USER so bootstrap can fix ownership on the named volume.
  user = "0:0"

  hostname = data.coder_workspace.me.name

  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home.name
    read_only      = false
  }

  # Match Coder's docker template and expose the host gateway inside the workspace.
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  dynamic "networks_advanced" {
    for_each = var.workspace_docker_network != "" ? [var.workspace_docker_network] : []

    content {
      name = networks_advanced.value
    }
  }

  # Our image sets CMD, so use command here and prepend the volume bootstrap.
  command = ["sh", "-c", join("", [local.workspace_volume_bootstrap, coder_agent.main.init_script])]
  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
  ]
  must_run = true
}
