#!/bin/sh
set -eu

usage() {
  echo "usage: $0 <log-file-or-dir> [...]" >&2
  echo "prints file:line:label only; matched secret text is never printed" >&2
  echo "intended for runtime logs; source trees may contain expected pattern definitions/placeholders" >&2
}

[ "${1:-}" != "" ] || { usage; exit 2; }

scan_file() {
  file=$1
  [ -f "$file" ] || return 0
  awk '
    BEGIN { found = 0 }
    /-----BEGIN (OPENSSH|RSA|EC|DSA) PRIVATE KEY-----/ { print FILENAME ":" FNR ":private-key"; found = 1 }
    /CODER_(OIDC_CLIENT_SECRET|SESSION_TOKEN|TOKEN)=/ { print FILENAME ":" FNR ":coder-secret-env"; found = 1 }
    /VAULT_TOKEN=/ || /hvs\.[A-Za-z0-9_-]{20,}/ { print FILENAME ":" FNR ":vault-token"; found = 1 }
    /gh[pousr]_[A-Za-z0-9_]{20,}/ { print FILENAME ":" FNR ":github-token"; found = 1 }
    /github_pat_[A-Za-z0-9_]{20,}/ { print FILENAME ":" FNR ":github-token"; found = 1 }
    /https?:\/\/[^[:space:]\/]+:[^[:space:]@]+@/ { print FILENAME ":" FNR ":url-credential"; found = 1 }
    /postgres(ql)?:\/\/[^[:space:]]+:[^[:space:]@]+@/ { print FILENAME ":" FNR ":postgres-url-password"; found = 1 }
    /SESSION_COOKIE=/ || /AUTH_SESSION=/ { print FILENAME ":" FNR ":session-cookie"; found = 1 }
    END { exit found ? 1 : 0 }
  ' "$file"
}

failed=0
for path in "$@"; do
  if [ -d "$path" ]; then
    find "$path" -type f | while IFS= read -r file; do
      scan_file "$file" || exit 1
    done || failed=1
  else
    scan_file "$path" || failed=1
  fi
done

if [ "$failed" != "0" ]; then
  echo "secret-like log content found" >&2
  exit 1
fi

echo "log secret scan ok"
