# Modular Monolith First

Build platform glue as one deployable system until a real split is forced.

## Modules

- `identity`: Authentik/Coder subject mapping and access policy helpers.
- `workspaces`: lifecycle state, Coder API integration, retention state.
- `runtime`: Kubernetes capacity and template integration.
- `images`: custom image validation, build jobs, registry digests, scanning.
- `secrets`: Vault paths, wrapping, and key lifecycle.
- `repos`: Git SSH key provisioning and clone metadata.
- `audit`: append-only audit events and redaction.
- `admin`: operator UI/API glue.

## Split Only When

- The module needs a different trust boundary.
- The module needs independent scaling.
- The module has a distinct runtime dependency profile.
- The module has independent ownership/release cadence.
- Keeping it in-process creates measurable operational risk.

Likely first splits: image builder, VM orchestrator, backup/restore worker.
