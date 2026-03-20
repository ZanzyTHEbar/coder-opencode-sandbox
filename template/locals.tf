locals {
  # Docker names must match [a-zA-Z0-9][a-zA-Z0-9_.-]* and stay under 63 chars.
  _sanitized     = replace(replace(replace("${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}", " ", "-"), "/", "-"), "\\", "-")
  container_name = "coder-${substr(local._sanitized, 0, min(57, length(local._sanitized)))}"

  # Run before the agent init script so the home volume is writable before the agent touches it.
  workspace_volume_bootstrap = templatefile("${path.module}/scripts/volume_bootstrap.sh.tpl", {})
  agent_startup_script       = templatefile("${path.module}/scripts/agent_startup.sh.tpl", {})
}
