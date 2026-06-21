#!/bin/sh
set -eu

PROXMOX_HOST=${PROXMOX_HOST:-lan-proxmox}
COOLIFY_HOST=${COOLIFY_HOST:-cool-res}
K3S_LXC_ID=${K3S_LXC_ID:-211}
CODER_PROXY_CONTAINER=${CODER_PROXY_CONTAINER:-coder-proxy}
CODER_NODEPORT=${CODER_NODEPORT:-30080}
CODER_PUBLIC_URL=${CODER_PUBLIC_URL:-https://coder.zacariahheim.com}
CODER_WILDCARD_BASE_DOMAIN=${CODER_WILDCARD_BASE_DOMAIN:-zacariahheim.com}
CODER_WILDCARD_TEST_URL=${CODER_WILDCARD_TEST_URL:-https://coder-route-check-$$.$CODER_WILDCARD_BASE_DOMAIN}
SSH_CONNECT_TIMEOUT=${SSH_CONNECT_TIMEOUT:-10}
SSH_COMMAND_TIMEOUT=${SSH_COMMAND_TIMEOUT:-30}
CURL_CONNECT_TIMEOUT=${CURL_CONNECT_TIMEOUT:-10}
CURL_MAX_TIME=${CURL_MAX_TIME:-20}

command -v timeout >/dev/null 2>&1 || { echo "timeout command required" >&2; exit 2; }

k3s_node_ip=$(timeout "$SSH_COMMAND_TIMEOUT" ssh -o BatchMode=yes -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" -o ServerAliveInterval=5 -o ServerAliveCountMax=1 "$PROXMOX_HOST" \
  "pct exec $K3S_LXC_ID -- env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin k3s kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type==\"InternalIP\")].address}'")

proxy_cmd=$(timeout "$SSH_COMMAND_TIMEOUT" ssh -o BatchMode=yes -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" -o ServerAliveInterval=5 -o ServerAliveCountMax=1 "$COOLIFY_HOST" \
  "docker inspect $CODER_PROXY_CONTAINER --format '{{json .Config.Cmd}} {{.State.Status}}'")

case "$proxy_cmd" in
  *"TCP:$k3s_node_ip:$CODER_NODEPORT"*" running") ;;
  *)
    echo "coder-proxy mismatch: expected TCP:$k3s_node_ip:$CODER_NODEPORT in running container" >&2
    echo "$proxy_cmd" >&2
    exit 1
    ;;
esac

root_headers=$(curl -fsS --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" -D - -o /dev/null "$CODER_PUBLIC_URL/api/v2/buildinfo")
case "$root_headers" in
  *"x-coder-build-version"*) ;;
  *)
    echo "root host did not return Coder headers" >&2
    echo "$root_headers" >&2
    exit 1
    ;;
esac

wildcard_headers=$(curl -fsS --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" -D - -o /dev/null "$CODER_WILDCARD_TEST_URL/api/v2/buildinfo")
case "$wildcard_headers" in
  *"x-coder-build-version"*) ;;
  *)
    echo "wildcard host did not reach Coder" >&2
    echo "$wildcard_headers" >&2
    exit 1
    ;;
esac

echo "coder routing ok: proxy -> $k3s_node_ip:$CODER_NODEPORT"
