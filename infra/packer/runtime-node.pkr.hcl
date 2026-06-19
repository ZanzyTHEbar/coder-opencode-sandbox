packer {
  required_version = ">= 1.10.0"
}

variable "image_name" {
  type    = string
  default = "opencode-runtime-node"
}

variable "base_image" {
  type    = string
  default = "ubuntu-24.04"
}

source "null" "runtime_node_contract" {
  communicator = "none"
}

# This is a validation scaffold only. Replace the null source with a real
# Proxmox/QEMU source once target IDs, credentials, and image storage are wired
# outside git.
build {
  name    = var.image_name
  sources = ["source.null.runtime_node_contract"]
}
