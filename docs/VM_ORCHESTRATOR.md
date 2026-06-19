# VM Orchestrator

The VM orchestrator is an internal operator module for runtime node lifecycle. It
is not tenant-facing.

## Responsibilities

- Track runtime VM inventory and capacity.
- Promote approved Packer image versions.
- Request or prepare Terraform apply workflows.
- Drain runtime nodes before replacement.
- Record audit events for node lifecycle operations.
- Report capacity and failures to operators.

## Non-Responsibilities

- No browser workspace routing.
- No direct user API.
- No secret storage outside Vault.
- No bypass around Terraform state.

Keep this as a modular-monolith module unless it needs separate permissions,
runtime dependencies, or independent scaling.
