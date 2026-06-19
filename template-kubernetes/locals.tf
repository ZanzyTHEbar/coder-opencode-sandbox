locals {
  workspace_slug = lower(replace(replace(data.coder_workspace.me.id, "_", "-"), " ", "-"))
  namespace      = "${var.namespace_prefix}-${local.workspace_slug}"
}
