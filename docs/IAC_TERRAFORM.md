# Terraform IaC

Terraform owns reproducible infrastructure state for the multi-tenant runtime.

## Scope

- Dedicated Proxmox runtime VM(s).
- Firewall/routing primitives where provider support exists.
- k3s bootstrap inputs.
- Coder deployment inputs.
- Kubernetes namespaces, policies, storage primitives, and template support.
- Vault wiring and policy attachment.

## Local Layout

```text
infra/terraform/runtime-plane/
```

The initial module is intentionally small. It defines the contract and variables
without hiding provider-specific work behind fake defaults.

## Rules

- No secrets in `.tf`, `.tfvars`, state committed to git, or logs.
- Use variable names and opaque IDs, not emails or personal names.
- Run `terraform fmt` before review.
- Run `terraform validate` only after provider configuration is present.
- Run `terraform plan` before any live Proxmox or Kubernetes mutation.
