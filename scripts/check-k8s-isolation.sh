#!/bin/sh
set -eu

usage() {
  echo "usage: KUBECTL=kubectl $0" >&2
  echo "optional: NAMESPACE=opencode-isolation-check INTERNAL_PROBE_URL=http://192.168.0.189:30080/api/v2/buildinfo" >&2
}

[ "${1:-}" = "" ] || { usage; exit 2; }

kubectl_cmd=${KUBECTL:-kubectl}
namespace=${NAMESPACE:-opencode-isolation-check-$$}
image=${PROBE_IMAGE:-busybox:1.36@sha256:73aaf090f3d85aa34ee199857f03fa3a95c8ede2ffd4cc2cdb5b94e566b11662}
public_probe_url=${PUBLIC_PROBE_URL:-https://example.com}
internal_probe_url=${INTERNAL_PROBE_URL:-http://192.168.0.189:30080/api/v2/buildinfo}
kube_probe_host=${KUBE_PROBE_HOST:-kubernetes.default.svc}
metadata_probe_url=${METADATA_PROBE_URL:-http://169.254.169.254/}
git_ssh_probe_host=${GIT_SSH_PROBE_HOST:-github.com}
created_namespace=0

case "$namespace" in
  *[!a-z0-9-]*|-*|*-|"") echo "namespace must be an RFC1123 label" >&2; exit 1 ;;
esac
[ ${#namespace} -le 63 ] || { echo "namespace must be <=63 chars" >&2; exit 1; }

cleanup() {
  if [ "$created_namespace" = "1" ] && [ "${KEEP_NAMESPACE:-}" != "1" ]; then
    $kubectl_cmd delete namespace "$namespace" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

$kubectl_cmd create namespace "$namespace" >/dev/null
created_namespace=1
$kubectl_cmd label namespace "$namespace" \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted >/dev/null

$kubectl_cmd apply -n "$namespace" -f - >/dev/null <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-public-egress
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 0.0.0.0/8
              - 10.0.0.0/8
              - 100.64.0.0/10
              - 127.0.0.0/8
              - 172.16.0.0/12
              - 192.168.0.0/16
              - 169.254.0.0/16
              - 224.0.0.0/4
              - 240.0.0.0/4
      ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 22
YAML

run_probe() {
  name=$1
  expected=$2
  command=$3

  $kubectl_cmd delete pod "$name" -n "$namespace" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  while $kubectl_cmd get pod "$name" -n "$namespace" >/dev/null 2>&1; do
    sleep 1
  done
  $kubectl_cmd apply -n "$namespace" -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $name
spec:
  restartPolicy: Never
  automountServiceAccountToken: false
  activeDeadlineSeconds: 20
  securityContext:
    runAsNonRoot: true
    runAsUser: 1800
    runAsGroup: 1800
    fsGroup: 1800
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: probe
      image: $image
      command: ["sh", "-lc", "$command"]
      securityContext:
        allowPrivilegeEscalation: false
        privileged: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
YAML

  i=0
  phase=Pending
  while [ "$i" -lt 30 ]; do
    phase=$($kubectl_cmd get pod "$name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo Pending)
    case "$phase" in Succeeded|Failed) break ;; esac
    i=$((i + 1))
    sleep 1
  done

  case "$expected:$phase" in
    allow:Succeeded) echo "$name ok allow" ;;
    deny:Failed) echo "$name ok deny" ;;
    deny:Succeeded) echo "$name failed: expected deny, got allow" >&2; return 1 ;;
    allow:*) echo "$name failed: expected allow, got $phase" >&2; return 1 ;;
    deny:*) echo "$name failed: expected deny, got $phase" >&2; return 1 ;;
  esac
}

failed=0
run_probe probe-dns allow "nslookup example.com >/dev/null" || failed=1
run_probe probe-public443 allow "wget -qO- --timeout=10 '$public_probe_url' >/dev/null" || failed=1
run_probe probe-public22 allow "nc -z -w 10 '$git_ssh_probe_host' 22" || failed=1
run_probe probe-internal deny "wget -qO- --timeout=5 '$internal_probe_url' >/dev/null" || failed=1
run_probe probe-kubeapi deny "nc -z -w 5 '$kube_probe_host' 443" || failed=1
run_probe probe-metadata deny "wget -qO- --timeout=5 '$metadata_probe_url' >/dev/null" || failed=1

if [ "$failed" != "0" ]; then
  echo "k8s isolation check failed" >&2
  exit 1
fi

echo "k8s isolation check ok"
