#!/bin/sh
set -eu
umask 077

usage() {
  echo "usage: $0 <workspace-namespace> <backup-dir>" >&2
  echo "set RETENTION_DAYS=30 and KUBECTL=kubectl as needed" >&2
}

[ "${1:-}" != "" ] || { usage; exit 2; }
[ "${2:-}" != "" ] || { usage; exit 2; }

namespace=$1
backup_dir=$2
retention_days=${RETENTION_DAYS:-30}
kubectl_cmd=${KUBECTL:-kubectl}
stamp=$(date -u +%Y%m%d%H%M%S)
pod=opencode-backup-$stamp
outfile=$backup_dir/$namespace-$stamp.tar.gz
tmpfile=$outfile.tmp.$$

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

case "$retention_days" in
  '' | *[!0-9]*)
    echo "RETENTION_DAYS must be a non-negative integer" >&2
    exit 2
    ;;
esac

mkdir -p "$backup_dir"

cleanup() {
  rm -f "$tmpfile"
  $kubectl_cmd -n "$namespace" delete pod "$pod" --ignore-not-found=true >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

$kubectl_cmd -n "$namespace" apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $pod
  labels:
    app.kubernetes.io/name: opencode-workspace-backup
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
    - name: backup
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
          readOnly: true
        - name: workspace
          mountPath: /mnt/workspace
          readOnly: true
  volumes:
    - name: home
      persistentVolumeClaim:
        claimName: home
        readOnly: true
    - name: workspace
      persistentVolumeClaim:
        claimName: workspace
        readOnly: true
EOF

$kubectl_cmd -n "$namespace" wait --for=condition=Ready "pod/$pod" --timeout=60s
$kubectl_cmd -n "$namespace" exec "$pod" -- tar czf - -C /mnt home workspace >"$tmpfile"
chmod 600 "$tmpfile"
mv "$tmpfile" "$outfile"
find "$backup_dir" -maxdepth 1 -type f -name "$namespace-*.tar.gz" -mtime +"$retention_days" -delete

echo "created $outfile"
