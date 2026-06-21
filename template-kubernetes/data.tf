data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_parameter" "workspace_repo_urls" {
  name         = "workspace_repo_urls"
  display_name = "Workspace repo URLs"
  description  = "Optional comma-separated Git URLs to clone into ~/workspace. Each repo is cloned into ~/workspace/<repo-name>; existing paths are preserved. For private SSH repos, start once, register the displayed Git SSH public key, then restart to retry."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 40
}
