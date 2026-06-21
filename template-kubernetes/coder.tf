resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  startup_script = templatefile("${path.module}/scripts/agent_startup.sh.tpl", {})

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
    HOME                = "/home/coder"
    LOGNAME             = "coder"
    USER                = "coder"
    WORKSPACE_REPO_URLS = data.coder_parameter.workspace_repo_urls.value
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
    display_name = "Git SSH Key"
    key          = "2_git_ssh_key"
    script       = "cat /home/coder/.ssh/id_ed25519.pub 2>/dev/null || echo 'no key generated yet'"
    interval     = 60
    timeout      = 5
  }
}

resource "coder_app" "opencode" {
  agent_id     = coder_agent.main.id
  slug         = "opencode"
  display_name = "OpenCode"
  url          = "http://localhost:4096/"
  icon         = "/icon/code.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:4096/doc"
    interval  = 10
    threshold = 15
  }
}
