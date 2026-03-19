terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

# ------------------------------------------------------------------------------
# Data sources
# ------------------------------------------------------------------------------

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# ------------------------------------------------------------------------------
# Persistent volume: one per workspace, survives stop/start.
# Name uses workspace id only (immutable) so renames do not recreate the volume.
# ------------------------------------------------------------------------------

resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace.me.id}-home"
  lifecycle {
    ignore_changes = all
  }
}

# ------------------------------------------------------------------------------
# Sandbox image (built from ../image; operator sets var.sandbox_image)
# ------------------------------------------------------------------------------

resource "docker_image" "sandbox" {
  name = var.sandbox_image
}

# ------------------------------------------------------------------------------
# Workspace container: only exists when workspace is started.
# Container name must match [a-zA-Z0-9][a-zA-Z0-9_.-]* (max 63 chars).
# ------------------------------------------------------------------------------

locals {
  # Docker container name: [a-zA-Z0-9][a-zA-Z0-9_.-]*, max 63 chars. Sanitize and truncate.
  _sanitized     = replace(replace(replace("${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}", " ", "-"), "/", "-"), "\\", "-")
  container_name = "coder-${substr(local._sanitized, 0, min(57, length(local._sanitized)))}"
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.sandbox.image_id
  name  = local.container_name

  hostname = data.coder_workspace.me.name

  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home.name
    read_only      = false
  }

  # Run Coder agent init script (downloads and starts the agent; agent runs startup_script).
  command = ["sh", "-c", coder_agent.main.init_script]
  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}"
  ]
  must_run = true
}

# ------------------------------------------------------------------------------
# Coder agent: runs inside the container, starts OpenCode in background.
# ------------------------------------------------------------------------------

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  startup_script = <<-EOT
    set -e
    export HOME=/home/coder

    # Prepare home with defaults on first start (volume was empty).
    if [ ! -f "$HOME/.init_done" ]; then
      cp -rT /etc/skel "$HOME" 2>/dev/null || true
      mkdir -p "$HOME/workspace"
      touch "$HOME/.init_done"
    fi

    # Start OpenCode web UI in background (port 4096; Coder app will proxy to it).
    (opencode web --hostname 0.0.0.0 --port 4096 &)

    # Wait for OpenCode to be ready so the Coder app healthcheck does not flake.
    for i in $(seq 1 30); do
      if curl -sf -o /dev/null http://localhost:4096/doc 2>/dev/null; then
        break
      fi
      sleep 1
    done

    # Agent is ready.
  EOT

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
    HOME                = "/home/coder"
  }

  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "2_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }
}

# ------------------------------------------------------------------------------
# OpenCode as workspace app: exposes the web UI on port 4096.
# ------------------------------------------------------------------------------

resource "coder_app" "opencode" {
  agent_id     = coder_agent.main.id
  slug         = "opencode"
  display_name = "OpenCode"
  url          = "http://localhost:4096/"
  icon         = "/icon/code.svg"

  healthcheck {
    # OpenCode web serves OpenAPI spec at /doc; 2xx indicates server is up.
    url       = "http://localhost:4096/doc"
    interval  = 10
    threshold = 15
  }
}
