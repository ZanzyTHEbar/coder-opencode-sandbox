variable "runtime_plane_name" {
  description = "Opaque name for the runtime plane."
  type        = string
  default     = "opencode-runtime"
}

variable "runtime_node_count" {
  description = "Number of runtime VM nodes to provision."
  type        = number
  default     = 1

  validation {
    condition     = var.runtime_node_count >= 1
    error_message = "At least one runtime node is required."
  }
}

variable "packer_image_id" {
  description = "Approved Packer image ID for runtime nodes."
  type        = string
}

variable "internal_cidr_blocks" {
  description = "CIDRs blocked from workspace pod egress."
  type        = list(string)
  default = [
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",
    "169.254.0.0/16",
  ]
}
