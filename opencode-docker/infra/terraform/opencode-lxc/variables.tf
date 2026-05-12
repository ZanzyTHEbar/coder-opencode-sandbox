variable "container_id" {
  description = "CTID of the Debian Docker LXC created by the Proxmox community scripts Docker LXC installer."
  type        = number
}

variable "hostname" {
  description = "LXC hostname selected in the community script."
  type        = string
  default     = "opencode-runtime"
}

variable "proxmox_node" {
  description = "Proxmox node that hosts the script-created LXC."
  type        = string
  default     = "dragonserver"
}

variable "ipv4_address" {
  description = "IPv4 address assigned to the script-created LXC, without CIDR."
  type        = string
}

variable "cpu_cores" {
  description = "CPU cores selected in the community script."
  type        = number
  default     = 6
}

variable "memory_mb" {
  description = "Memory selected in the community script, in MB."
  type        = number
  default     = 12288
}

variable "disk_size_gb" {
  description = "Disk size selected in the community script, in GB."
  type        = number
  default     = 160
}

variable "community_script_url" {
  description = "Proxmox community scripts Docker LXC installer URL used to create the LXC."
  type        = string
  default     = "https://community-scripts.github.io/ProxmoxVE/scripts?id=docker"
}

variable "opencode_base_dir" {
  description = "Persistent OpenCode base directory created by Ansible inside the Debian LXC."
  type        = string
  default     = "/srv/opencode"
}
