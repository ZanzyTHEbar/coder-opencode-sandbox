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

# Variables live with the root module so editors and terraform-ls resolve them cleanly.
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

data "coder_parameter" "opencode_config_url" {
  name         = "opencode_config_url"
  display_name = "OpenCode config URL"
  description  = "Optional Git or GitHub URL to provision as ~/workspace/.opencode. Supports repo URLs and GitHub tree URLs."
  type         = "string"
  default      = ""
  mutable      = true
}

data "coder_parameter" "opencode_config_ref" {
  name         = "opencode_config_ref"
  display_name = "OpenCode config ref"
  description  = "Optional branch, tag, or commit override for the OpenCode config URL."
  type         = "string"
  default      = ""
  mutable      = true
}

data "coder_parameter" "opencode_config_subdir" {
  name         = "opencode_config_subdir"
  display_name = "OpenCode config subdirectory"
  description  = "Optional path inside the fetched repo. Leave empty to auto-detect .opencode or use the repo root."
  type         = "string"
  default      = ""
  mutable      = true
}

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

locals {
  # Docker names must match [a-zA-Z0-9][a-zA-Z0-9_.-]* and stay under 63 chars.
  _sanitized     = replace(replace(replace("${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}", " ", "-"), "/", "-"), "\\", "-")
  container_name = "coder-${substr(local._sanitized, 0, min(57, length(local._sanitized)))}"

  # Run before the agent init script so the home volume is writable before the agent touches it.
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
    "CODER_AGENT_TOKEN=${coder_agent.main.token}"
  ]
  must_run = true
}

# Coder agent: runs inside the container and starts OpenCode in the background.

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  startup_script = <<-EOT
    set -e
    export HOME=/home/coder
    # /tmp stays writable even if $HOME is still broken; use it for early diagnostics.
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

    # Keep workspace creation idempotent even if `.init_done` already exists.
    if ! mkdir -p "$HOME/workspace" 2>>"$TMPLOG"; then
      echo "FATAL: mkdir -p $HOME/workspace failed — read $TMPLOG and docs/DEBUG_WORKSPACE_VOLUME.md" | tee -a "$TMPLOG" >&2
      exit 1
    fi

    # Seed the home volume from `/etc/skel` only on first start.
    if [ ! -f "$HOME/.init_done" ]; then
      cp -rT /etc/skel "$HOME" 2>/dev/null || true
      touch "$HOME/.init_done"
    fi

    WORKSPACE_DIR="$HOME/workspace"
    OPENCODE_DIR="$HOME/.opencode"
    OPENCODE_LOG="$OPENCODE_DIR/server.log"
    PROFILE_ROOT="$HOME/.opencode-profile"
    PROFILE_RELEASES="$PROFILE_ROOT/releases"
    PROFILE_CURRENT="$PROFILE_ROOT/current"
    WORKSPACE_CONFIG_LINK="$WORKSPACE_DIR/.opencode"
    mkdir -p "$OPENCODE_DIR" "$PROFILE_RELEASES"
    : > "$OPENCODE_LOG"

    log_note() {
      echo "$1" | tee -a "$TMPLOG" "$OPENCODE_LOG" >/dev/null
    }

    is_managed_workspace_config() {
      [ -L "$WORKSPACE_CONFIG_LINK" ] || return 1
      _target=$(readlink -f "$WORKSPACE_CONFIG_LINK" 2>/dev/null || true)
      case "$_target" in
        "$PROFILE_ROOT"/*) return 0 ;;
        *) return 1 ;;
      esac
    }

    normalize_opencode_source() {
      OPENCODE_SOURCE_REPO=$${OPENCODE_CONFIG_URL%/}
      OPENCODE_SOURCE_REF=$OPENCODE_CONFIG_REF
      OPENCODE_SOURCE_SUBDIR=$OPENCODE_CONFIG_SUBDIR

      case "$OPENCODE_SOURCE_REPO" in
        https://github.com/*/tree/*)
          _rest=$${OPENCODE_SOURCE_REPO#https://github.com/}
          _owner=$${_rest%%/*}
          _rest=$${_rest#*/}
          _repo=$${_rest%%/*}
          _rest=$${_rest#*/}
          _rest=$${_rest#tree/}
          _parsed_ref=$${_rest%%/*}
          if [ "$_rest" = "$_parsed_ref" ]; then
            _parsed_subdir=""
          else
            _parsed_subdir=$${_rest#*/}
          fi
          OPENCODE_SOURCE_REPO="https://github.com/$${_owner}/$${_repo}.git"
          [ -n "$OPENCODE_SOURCE_REF" ] || OPENCODE_SOURCE_REF=$_parsed_ref
          if [ -z "$OPENCODE_SOURCE_SUBDIR" ] && [ -n "$_parsed_subdir" ]; then
            OPENCODE_SOURCE_SUBDIR=$_parsed_subdir
          fi
          ;;
        https://github.com/*)
          case "$OPENCODE_SOURCE_REPO" in
            *.git) ;;
            *) OPENCODE_SOURCE_REPO="$${OPENCODE_SOURCE_REPO}.git" ;;
          esac
          ;;
      esac
    }

    clone_opencode_repo() {
      if [ -n "$OPENCODE_SOURCE_REF" ]; then
        if GIT_TERMINAL_PROMPT=0 git -c protocol.file.allow=never clone --depth 1 --branch "$OPENCODE_SOURCE_REF" --single-branch "$OPENCODE_SOURCE_REPO" "$STAGED_DIR/repo" >>"$OPENCODE_LOG" 2>&1; then
          return 0
        fi
        rm -rf "$STAGED_DIR/repo"
        GIT_TERMINAL_PROMPT=0 git -c protocol.file.allow=never clone --depth 1 "$OPENCODE_SOURCE_REPO" "$STAGED_DIR/repo" >>"$OPENCODE_LOG" 2>&1 || return 1
        GIT_TERMINAL_PROMPT=0 git -c protocol.file.allow=never -C "$STAGED_DIR/repo" fetch --depth 1 origin "$OPENCODE_SOURCE_REF" >>"$OPENCODE_LOG" 2>&1 || return 1
        git -C "$STAGED_DIR/repo" checkout --detach FETCH_HEAD >>"$OPENCODE_LOG" 2>&1 || return 1
        return 0
      fi

      GIT_TERMINAL_PROMPT=0 git -c protocol.file.allow=never clone --depth 1 "$OPENCODE_SOURCE_REPO" "$STAGED_DIR/repo" >>"$OPENCODE_LOG" 2>&1
    }

    ensure_opencode_profile() {
      normalize_opencode_source

      PROFILE_HASH=$(printf '%s\n%s\n%s\n' "$OPENCODE_SOURCE_REPO" "$OPENCODE_SOURCE_REF" "$OPENCODE_SOURCE_SUBDIR" | sha256sum | cut -d' ' -f1)
      PROFILE_DIR="$PROFILE_RELEASES/$PROFILE_HASH"

      if [ ! -d "$PROFILE_DIR" ]; then
        STAGED_DIR=$(mktemp -d "$PROFILE_RELEASES/.staging.XXXXXX")
        log_note "Provisioning OpenCode config from $OPENCODE_SOURCE_REPO"

        if ! clone_opencode_repo; then
          rm -rf "$STAGED_DIR"
          log_note "FATAL: could not fetch OpenCode config from $OPENCODE_SOURCE_REPO"
          exit 1
        fi

        if [ -n "$OPENCODE_SOURCE_SUBDIR" ]; then
          SELECTED_PATH="$STAGED_DIR/repo/$OPENCODE_SOURCE_SUBDIR"
        elif [ -d "$STAGED_DIR/repo/.opencode" ]; then
          SELECTED_PATH="$STAGED_DIR/repo/.opencode"
        else
          SELECTED_PATH="$STAGED_DIR/repo"
        fi

        if [ ! -d "$SELECTED_PATH" ]; then
          rm -rf "$STAGED_DIR"
          log_note "FATAL: OpenCode config path does not exist inside the fetched repo"
          exit 1
        fi

        SELECTED_REAL=$(readlink -f "$SELECTED_PATH" 2>/dev/null || true)
        case "$SELECTED_REAL" in
          "$STAGED_DIR"/*) ;;
          *)
            rm -rf "$STAGED_DIR"
            log_note "FATAL: resolved OpenCode config path escaped the fetched repo"
            exit 1
            ;;
        esac

        SELECTED_REL=$${SELECTED_PATH#"$STAGED_DIR"/}
        ln -s "$SELECTED_REL" "$STAGED_DIR/selected"

        cat > "$STAGED_DIR/manifest" <<EOF
source_url=$OPENCODE_CONFIG_URL
source_repo=$OPENCODE_SOURCE_REPO
source_ref=$OPENCODE_SOURCE_REF
source_subdir=$OPENCODE_SOURCE_SUBDIR
resolved_commit=$(git -C "$STAGED_DIR/repo" rev-parse HEAD 2>/dev/null || echo unknown)
EOF

        mv "$STAGED_DIR" "$PROFILE_DIR"
      fi

      ln -sfn "$PROFILE_DIR/selected" "$PROFILE_CURRENT"

      if [ -e "$WORKSPACE_CONFIG_LINK" ] && [ ! -L "$WORKSPACE_CONFIG_LINK" ]; then
        log_note "WARNING: $WORKSPACE_CONFIG_LINK already exists and is not a symlink; leaving it unchanged"
        return 0
      fi

      ln -sfn "$PROFILE_CURRENT" "$WORKSPACE_CONFIG_LINK"
    }

    if [ -n "$OPENCODE_CONFIG_URL" ]; then
      ensure_opencode_profile
    elif is_managed_workspace_config; then
      log_note "Removing managed workspace .opencode link because no config URL is set"
      rm -f "$WORKSPACE_CONFIG_LINK"
    fi

    # Start OpenCode from the user's workspace, not filesystem root.
    cd "$WORKSPACE_DIR"
    opencode web --hostname 127.0.0.1 --port 4096 >>"$OPENCODE_LOG" 2>&1 </dev/null &
    echo $! > "$OPENCODE_DIR/server.pid"

    # Wait for OpenCode before reporting the agent ready.
    OPENCODE_READY=0
    for i in $(seq 1 60); do
      if curl -sf -o /dev/null http://127.0.0.1:4096/doc 2>/dev/null; then
        OPENCODE_READY=1
        break
      fi
      sleep 1
    done

    if [ "$OPENCODE_READY" != "1" ]; then
      echo "FATAL: OpenCode did not become ready on http://127.0.0.1:4096/doc" | tee -a "$TMPLOG" "$OPENCODE_LOG" >&2
      exit 1
    fi

  EOT

  env = {
    GIT_AUTHOR_NAME        = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL       = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL    = data.coder_workspace_owner.me.email
    HOME                   = "/home/coder"
    OPENCODE_CONFIG_REF    = data.coder_parameter.opencode_config_ref.value
    OPENCODE_CONFIG_SUBDIR = data.coder_parameter.opencode_config_subdir.value
    OPENCODE_CONFIG_URL    = data.coder_parameter.opencode_config_url.value
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

# OpenCode workspace app.

resource "coder_app" "opencode" {
  agent_id     = coder_agent.main.id
  slug         = "opencode"
  display_name = "OpenCode"
  url          = "http://localhost:4096/"
  icon         = "/icon/code.svg"
  # OpenCode expects to run at the host root, so expose it as a subdomain app.
  subdomain = true

  healthcheck {
    url       = "http://localhost:4096/doc"
    interval  = 10
    threshold = 15
  }
}
