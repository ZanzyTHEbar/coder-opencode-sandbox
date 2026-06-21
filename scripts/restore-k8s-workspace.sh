#!/bin/sh
set -eu
umask 077

usage() {
  echo "usage: $0 <workspace-namespace> <backup-tar.gz>" >&2
  echo "set KUBECTL=kubectl as needed" >&2
}

[ "${1:-}" != "" ] || { usage; exit 2; }
[ "${2:-}" != "" ] || { usage; exit 2; }

namespace=$1
backup_file=$2
kubectl_cmd=${KUBECTL:-kubectl}
stamp=$(date -u +%Y%m%d%H%M%S)
pod=opencode-restore-$stamp

case "$namespace" in
  '' | *[!a-z0-9-]* | -* | *-)
    echo "invalid namespace: $namespace" >&2
    exit 2
    ;;
esac

if [ "${#namespace}" -gt 63 ]; then
  echo "invalid namespace: $namespace" >&2
  exit 2
fi

[ -r "$backup_file" ] || { echo "backup file not readable: $backup_file" >&2; exit 2; }
tar tzf "$backup_file" >/dev/null

has_restore_entry=0
while IFS= read -r entry; do
  case "$entry" in
    home | home/* | workspace | workspace/*) ;;
    *) echo "unsafe archive entry: $entry" >&2; exit 2 ;;
  esac
  case "$entry" in
    /* | ../* | */../* | */.. | ..) echo "unsafe archive entry: $entry" >&2; exit 2 ;;
  esac
  has_restore_entry=1
done <<EOF
$(tar tzf "$backup_file")
EOF

[ "$has_restore_entry" = 1 ] || { echo "backup must contain home/ or workspace/ entries" >&2; exit 2; }

tar tvzf "$backup_file" | while IFS= read -r line; do
  case "$line" in
    -* | d*) ;;
    *) echo "unsafe archive entry type" >&2; exit 2 ;;
  esac
done

cleanup() {
  $kubectl_cmd -n "$namespace" delete pod "$pod" --ignore-not-found=true >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

$kubectl_cmd -n "$namespace" apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $pod
  labels:
    app.kubernetes.io/name: opencode-workspace-restore
spec:
  restartPolicy: Never
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 1001
    runAsGroup: 1001
    fsGroup: 1001
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: restore
      image: busybox:1.36@sha256:73aaf090f3d85aa34ee199857f03fa3a95c8ede2ffd4cc2cdb5b94e566b11662
      command: ["sh", "-c", "sleep 3600"]
      securityContext:
        allowPrivilegeEscalation: false
        privileged: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
      volumeMounts:
        - name: home
          mountPath: /mnt/home
        - name: workspace
          mountPath: /mnt/workspace
  volumes:
    - name: home
      persistentVolumeClaim:
        claimName: home
    - name: workspace
      persistentVolumeClaim:
        claimName: workspace
EOF

$kubectl_cmd -n "$namespace" wait --for=condition=Ready "pod/$pod" --timeout=60s
$kubectl_cmd -n "$namespace" exec -i "$pod" -- tar xzf - -C /mnt <"$backup_file"

echo "restored $backup_file into namespace $namespace"
