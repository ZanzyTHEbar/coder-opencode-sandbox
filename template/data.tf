data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_parameter" "opencode_config_url" {
  name         = "opencode_config_url"
  display_name = "OpenCode config URL"
  description  = "Optional Git URL or GitHub repo/tree/blob URL to provision as ~/.config/opencode."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 10
}

data "coder_parameter" "opencode_config_ref" {
  name         = "opencode_config_ref"
  display_name = "OpenCode config ref"
  description  = "Optional branch, tag, or commit override for the OpenCode config URL."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 20
}

data "coder_parameter" "opencode_config_subdir" {
  name         = "opencode_config_subdir"
  display_name = "OpenCode config subdirectory"
  description  = "Optional path inside the fetched repo. Leave empty to auto-detect .opencode or use the repo root."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 30
}

data "coder_parameter" "workspace_repo_urls" {
  name         = "workspace_repo_urls"
  display_name = "Workspace repo URLs"
  description  = "Optional comma-separated Git URLs or GitHub repo/tree/blob URLs to clone into ~/workspace. Each repo is cloned into ~/workspace/<repo-name> and existing paths are preserved."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 40
}

data "coder_parameter" "linux_dotfiles_url" {
  name         = "linux_dotfiles_url"
  display_name = "Linux dotfiles URL"
  description  = "Optional Git URL or GitHub repo/tree/blob URL for dotfiles to clone and apply to the Linux environment."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 50
}

data "coder_parameter" "linux_dotfiles_install_command" {
  name         = "linux_dotfiles_install_command"
  display_name = "Linux dotfiles install command"
  description  = "Optional shell command to run from the selected dotfiles directory on every startup (for example: ./install.sh or stow bash git)."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 60
}

data "coder_parameter" "opencode_app_share" {
  name         = "opencode_app_share"
  display_name = "OpenCode app sharing"
  description  = "Controls who can reach the OpenCode web app. Keep Owner unless you need local `opencode attach` against the public HTTPS app URL. Public URL attach requires the generated OpenCode server password."
  type         = "string"
  default      = "owner"
  mutable      = true
  order        = 70

  option {
    name        = "Owner only"
    description = "Safe default. Use Coder auth, Coder terminal, SSH, or port forwarding."
    value       = "owner"
  }

  option {
    name        = "Authenticated users"
    description = "Allow any authenticated Coder user to open the app. Local CLI attach still usually needs port forwarding."
    value       = "authenticated"
  }

  option {
    name        = "Public URL attach"
    description = "Allow public HTTPS routing for local attach, protected by the generated OpenCode server password."
    value       = "public"
  }

  validation {
    regex = "^(owner|authenticated|public)$"
    error = "OpenCode app sharing must be owner, authenticated, or public."
  }
}
