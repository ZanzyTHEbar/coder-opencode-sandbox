# Vault Baseline

Vault stores platform, workspace, Git, builder, registry, and backup secrets.

Commit policies and auth role names here. Do not commit tokens, wrapped secrets,
unseal material, generated private keys, or real secret values.

`opencode-platform` is operator/platform-only. Workspace pods bind to
`opencode-workspace`, which intentionally grants no tenant secret access until a
per-workspace policy is rendered for one opaque workspace ID.

For Git secret delivery, render the example policy and role files with the real
workspace slug, matching the namespace suffix from `template-kubernetes/locals.tf`.
Attach that role through the Kubernetes template, then set `vault_git_secret_path`
to the matching KV-v2 path, such as
`kv/data/workspaces/<workspace_slug>/git/deploy-key`. Leaving the path empty
emits no Vault injector annotations.
