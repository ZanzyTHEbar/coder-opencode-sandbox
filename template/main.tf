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

  # Must run *before* the rest of coder_agent.main.init_script (agent touches $HOME early).
  # Run as root (see docker_container.user): named volumes are root:root — sudo can still fail in some
  # Docker/seccomp setups; real root avoids that. Coder's init then continues (agent runs as non-root).
  # Writes /home/coder/.coder-debug/bootstrap.log for evidence-based debugging (see docs/DEBUG_WORKSPACE_VOLUME.md).
  workspace_volume_bootstrap = <<-EOT
set -e
export HOME=/home/coder
DBG=/home/coder/.coder-debug
mkdir -p "$DBG"
{
  echo "=== bootstrap begin $(date -Iseconds 2>/dev/null || date) ==="
  echo "uid=$(id -u) gid=$(id -g) user=$(id -un 2>/dev/null || echo '?')"
  echo "--- getent passwd coder ---"
  getent passwd coder || echo "MISSING: no passwd entry for coder"
  echo "--- ls -la /home/coder ---"
  ls -la /home/coder 2>&1 || true
  echo "--- mounts touching /home ---"
  grep -E ' /home|/home/coder' /proc/mounts 2>/dev/null || cat /proc/mounts | head -30
  echo "--- stat /home/coder ---"
  stat /home/coder 2>&1 || true
} >>"$DBG/bootstrap.log" 2>&1
chown -R coder:coder /home/coder
mkdir -p /home/coder/workspace
chown -R coder:coder /home/coder/workspace
{
  echo "=== bootstrap ok $(date -Iseconds 2>/dev/null || date) ==="
} >>"$DBG/bootstrap.log" 2>&1

EOT
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.sandbox.image_id
  name  = local.container_name

  # Override image USER (coder): bootstrap must fix volume ownership as real root; sudo is unreliable here.
  user = "0:0"

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
    # /tmp always writable — if $HOME is root-owned, .coder-debug cannot be created; still get evidence here.
    TMPLOG=/tmp/coder-opencode-startup.log
    DBG=/home/coder/.coder-debug
    set +e
    {
      echo "=== startup begin $(date -Iseconds 2>/dev/null || date) ==="
      echo "uid=$(id -u) gid=$(id -g) user=$(id -un 2>/dev/null || echo '?')"
      echo "--- getent passwd (current) ---"
      getent passwd "$(id -un)" 2>/dev/null || true
      echo "--- ls -la /home /home/coder ---"
      ls -la /home 2>&1 | head -20
      ls -la /home/coder 2>&1 | head -60
      if test -w "$HOME"; then echo "HOME writable: yes"; else echo "HOME writable: NO"; fi
      echo "--- ls -ld home + workspace ---"
      ls -ld "$HOME" "$HOME/workspace" 2>&1 || true
    } | tee -a "$TMPLOG"
    set -e
    mkdir -p "$DBG" 2>>"$TMPLOG" || echo "NOTE: could not mkdir $DBG (home may be root-owned); see $TMPLOG" | tee -a "$TMPLOG"
    if [ -w "$DBG" ]; then
      cp -f "$TMPLOG" "$DBG/startup.log" 2>/dev/null || cat "$TMPLOG" >>"$DBG/startup.log" 2>/dev/null || true
    fi

    # Ensure workspace dir exists even if .init_done was set without it (idempotent).
    if ! mkdir -p "$HOME/workspace" 2>>"$TMPLOG"; then
      echo "FATAL: mkdir -p $HOME/workspace failed — read $TMPLOG and docs/DEBUG_WORKSPACE_VOLUME.md" | tee -a "$TMPLOG" >&2
      exit 1
    fi

    # Prepare home with defaults on first start (volume was empty).
    if [ ! -f "$HOME/.init_done" ]; then
      cp -rT /etc/skel "$HOME" 2>/dev/null || true
      touch "$HOME/.init_done"
    fi

    # Bind loopback only (Coder app proxies to localhost). Redirect output so the startup script can exit cleanly
    # without Coder thinking the background child still owns stdout/stderr.
    OPENCODE_DIR="$HOME/.opencode"
    OPENCODE_LOG="$OPENCODE_DIR/server.log"
    mkdir -p "$OPENCODE_DIR"
    : > "$OPENCODE_LOG"
    opencode web --hostname 127.0.0.1 --port 4096 >>"$OPENCODE_LOG" 2>&1 </dev/null &
    echo $! > "$OPENCODE_DIR/server.pid"

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
