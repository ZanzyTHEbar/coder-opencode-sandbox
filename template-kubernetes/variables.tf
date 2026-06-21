variable "namespace_prefix" {
  description = "Prefix for per-workspace namespaces."
  type        = string
  default     = "opencode"
}

variable "opencode_image" {
  description = "Approved OpenCode runtime image reference pinned by immutable digest."
  type        = string
  default     = "ghcr.io/zanzythebar/coder-opencode-sandbox@sha256:cc1b96eb61212139f4767020b7d094eb179515706083103ef75b1a3da76a25e4"
}

variable "storage_class_name" {
  description = "StorageClass used for per-workspace PVCs."
  type        = string
}

variable "home_storage_size" {
  description = "PVC size for /home/coder."
  type        = string
  default     = "10Gi"
}

variable "workspace_storage_size" {
  description = "PVC size for /home/coder/workspace."
  type        = string
  default     = "20Gi"
}

variable "cpu_limit" {
  description = "CPU limit for the OpenCode pod."
  type        = string
  default     = "2"
}

variable "cpu_request" {
  description = "CPU request for the OpenCode pod."
  type        = string
  default     = "500m"
}

variable "memory_limit" {
  description = "Memory limit for the OpenCode pod."
  type        = string
  default     = "4Gi"
}

variable "memory_request" {
  description = "Memory request for the OpenCode pod."
  type        = string
  default     = "1Gi"
}

variable "ephemeral_storage_limit" {
  description = "Ephemeral storage limit for the OpenCode pod root/tmpfs layer."
  type        = string
  default     = "4Gi"
}

variable "ephemeral_storage_request" {
  description = "Ephemeral storage request for the OpenCode pod root/tmpfs layer."
  type        = string
  default     = "1Gi"
}

variable "runtime_class_name" {
  description = "Optional RuntimeClass for stronger sandboxing, such as gVisor. Empty string means default runtime."
  type        = string
  default     = ""
}

variable "vault_role" {
  description = "Vault Kubernetes auth role for this workspace. Used only when vault_git_secret_path is set."
  type        = string
  default     = "opencode-workspace"
}

variable "vault_git_secret_path" {
  description = "Optional Vault KV path injected into /vault/secrets/git. Leave empty to disable Vault Agent injection."
  type        = string
  default     = ""
}

variable "vault_namespace" {
  description = "Namespace containing Vault. Used only when vault_git_secret_path is set."
  type        = string
  default     = "vault"
}

variable "vault_port" {
  description = "Vault service port. Used only when vault_git_secret_path is set."
  type        = number
  default     = 8200
}

variable "internal_egress_block_cidrs" {
  description = "CIDRs blocked from workspace egress. Public internet remains allowed only on allowed_public_egress_ports."
  type        = list(string)
  default = [
    "0.0.0.0/8",
    "10.0.0.0/8",
    "100.64.0.0/10",
    "127.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",
    "169.254.0.0/16",
    "224.0.0.0/4",
    "240.0.0.0/4",
  ]
}

variable "allowed_public_egress_ports" {
  description = "TCP ports workspace pods may use to reach public IPs."
  type        = list(number)
  default     = [443, 22]
}
