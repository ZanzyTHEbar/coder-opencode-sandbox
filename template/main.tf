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

# Variables (co-located with root module so editors/terraform-ls resolve them when this file is the focus).
# Reserved for future use: per-template Docker host override.
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

  # Must run *before* the rest of coder_agent.main.init_script: that script starts the agent, which can
  # touch $HOME before startup_script runs. startup_script alone is too late for chown/mkdir.
  # Use /usr/bin/sudo so PATH cannot hide sudo (image: Dockerfile sudo + NOPASSWD).
  workspace_volume_bootstrap = <<-EOT
set -e
export HOME=/home/coder
/usr/bin/sudo chown -R coder:coder /home/coder
/usr/bin/sudo mkdir -p /home/coder/workspace
/usr/bin/sudo chown coder:coder /home/coder/workspace

EOT
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

  # Same pattern as Coder's docker template: agent init script may reference 127.0.0.1/localhost; map to host gateway.
  # https://github.com/coder/coder/blob/main/examples/templates/docker/main.tf
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

  # Our image sets CMD (no ENTRYPOINT); use command so we don't stack image CMD + entrypoint.
  # Do NOT rewrite 127.0.0.1 in the init script: OpenCode must bind and answer on loopback inside
  # the workspace (Coder app healthcheck uses localhost). Replacing with host.docker.internal breaks that.
  # Prepend volume bootstrap so chown/mkdir happen before agent bootstrap (see locals.workspace_volume_bootstrap).
  command = ["sh", "-c", join("", [local.workspace_volume_bootstrap, coder_agent.main.init_script])]
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

    # Ownership and workspace/ were fixed in init_script (see docker_container command prepend).

    # Prepare home with defaults on first start (volume was empty).
    if [ ! -f "$HOME/.init_done" ]; then
      cp -rT /etc/skel "$HOME" 2>/dev/null || true
      mkdir -p "$HOME/workspace"
      touch "$HOME/.init_done"
    fi

    # Bind loopback only (Coder app proxies to localhost). You may still see a password warning until OpenCode is configured with OPENCODE_SERVER_PASSWORD (would require matching coder_app healthcheck auth).
    (opencode web --hostname 127.0.0.1 --port 4096 &)

    # Wait for OpenCode to be ready so the Coder app healthcheck does not flake.
    for i in $(seq 1 60); do
      if curl -sf -o /dev/null http://127.0.0.1:4096/doc 2>/dev/null; then
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
    timeout      = 5
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 5
  }

  metadata {
    display_name = "Home Disk"
    key          = "2_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 10
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
  # Path-based apps break OpenCode’s SPA: the browser requests /assets/* from the Coder origin root (404 + wrong MIME).
  # Subdomain mode serves the app at the root of a dedicated host — requires CODER_WILDCARD_ACCESS_URL + DNS *.domain.
  # https://coder.com/docs/admin/networking/wildcard-access-url
  subdomain = true

  healthcheck {
    # OpenCode web serves OpenAPI spec at /doc; 2xx indicates server is up.
    url       = "http://localhost:4096/doc"
    interval  = 10
    threshold = 15
  }
}
