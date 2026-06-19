path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# No workspace secret paths are granted here on purpose. Real workspace secret
# delivery must attach a rendered per-workspace policy scoped to one opaque
# workspace ID.
