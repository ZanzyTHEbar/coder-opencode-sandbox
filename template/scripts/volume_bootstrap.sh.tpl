set -e
export HOME=/home/coder
DBG=/home/coder/.coder-debug
mkdir -p "$DBG"
{
  echo "=== bootstrap begin $(date -Iseconds 2>/dev/null || date) ==="
  echo "uid=$(id -u) gid=$(id -g) user=$(id -un 2>/dev/null || echo '?')"
  echo "--- getent passwd coder ---"
  getent passwd coder || echo "MISSING: no passwd entry for coder"
  echo "--- ls -la /home/coder ---"
  ls -la /home/coder 2>&1 || true
  echo "--- mounts touching /home ---"
  grep -E ' /home|/home/coder' /proc/mounts 2>/dev/null || cat /proc/mounts | head -30
  echo "--- stat /home/coder ---"
  stat /home/coder 2>&1 || true
} >>"$DBG/bootstrap.log" 2>&1
chown -R coder:coder /home/coder
mkdir -p /home/coder/workspace
chown -R coder:coder /home/coder/workspace
{
  echo "=== bootstrap ok $(date -Iseconds 2>/dev/null || date) ==="
} >>"$DBG/bootstrap.log" 2>&1
