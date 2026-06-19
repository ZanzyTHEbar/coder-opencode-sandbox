# Vault Baseline

Vault stores platform, workspace, Git, builder, registry, and backup secrets.

Commit policies and auth role names here. Do not commit tokens, wrapped secrets,
unseal material, generated private keys, or real secret values.

`opencode-platform` is operator/platform-only. Workspace pods bind to
`opencode-workspace`, which intentionally grants no tenant secret access until a
per-workspace policy is rendered for one opaque workspace ID.
