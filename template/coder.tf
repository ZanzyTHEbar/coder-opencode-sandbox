# Coder agent: runs inside the container and starts OpenCode in the background.
resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  startup_script = local.agent_startup_script

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
