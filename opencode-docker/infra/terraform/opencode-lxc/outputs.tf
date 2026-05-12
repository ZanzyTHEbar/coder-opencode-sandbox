output "lxc_contract" {
  description = "Recorded contract for the community-script-created Debian Docker LXC."
  value       = local.lxc_contract
}

output "ansible_inventory_hint" {
  description = "Inventory line for the Ansible preparation pass."
  value       = "${var.hostname} ansible_host=${var.ipv4_address} ansible_user=root"
}

output "coolify_registration_note" {
  description = "Next manual registration step."
  value       = "Register CT ${var.container_id} (${var.hostname}) as a Docker resource server in Coolify after Ansible succeeds."
}
