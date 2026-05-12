locals {
  lxc_contract = {
    container_id      = var.container_id
    hostname          = var.hostname
    proxmox_node      = var.proxmox_node
    ipv4_address      = var.ipv4_address
    cpu_cores         = var.cpu_cores
    memory_mb         = var.memory_mb
    disk_size_gb      = var.disk_size_gb
    os_family         = "debian"
    install_source    = "proxmox-community-scripts-docker-lxc"
    community_script  = var.community_script_url
    opencode_base_dir = var.opencode_base_dir
  }
}

check "debian_lxc_contract" {
  assert {
    condition     = var.container_id > 0
    error_message = "container_id must be the CTID of the Debian Docker LXC created by the Proxmox community script."
  }

  assert {
    condition     = var.ipv4_address != ""
    error_message = "ipv4_address must be set after the community script creates the LXC."
  }

  assert {
    condition     = var.cpu_cores >= 4 && var.memory_mb >= 8192 && var.disk_size_gb >= 100
    error_message = "OpenCode runtime sizing should be at least 4 vCPU, 8192 MB RAM, and 100 GB disk."
  }
}
