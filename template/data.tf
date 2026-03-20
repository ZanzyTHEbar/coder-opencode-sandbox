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
