# Provider-specific Proxmox/k3s resources are added after remote state and
# provider credentials are configured outside git. This file intentionally keeps
# only stable, non-secret local contracts in the initial commit.

locals {
  runtime_node_names = [
    for index in range(var.runtime_node_count) :
    format("%s-%02d", var.runtime_plane_name, index + 1)
  ]
}

output "runtime_node_names" {
  description = "Planned opaque runtime node names."
  value       = local.runtime_node_names
}

output "blocked_egress_cidrs" {
  description = "Internal CIDRs runtime workloads must not reach by default."
  value       = var.internal_cidr_blocks
}
