path "kv/data/platform/opencode/*" {
  capabilities = ["create", "read", "update", "list"]
}

path "kv/data/platform/images/*" {
  capabilities = ["create", "read", "update", "list"]
}

path "kv/data/platform/backups/*" {
  capabilities = ["create", "read", "update", "list"]
}

path "kv/metadata/platform/opencode/*" {
  capabilities = ["list"]
}

path "kv/metadata/platform/images/*" {
  capabilities = ["list"]
}

path "kv/metadata/platform/backups/*" {
  capabilities = ["list"]
}

path "sys/audit" {
  capabilities = ["read", "list"]
}
