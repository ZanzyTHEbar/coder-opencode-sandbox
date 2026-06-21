#!/bin/sh
set -eu

usage() {
  echo "usage: APPROVED_BASE_IMAGE=<image-or-digest> $0 <Containerfile> <tag> [context]" >&2
  echo "set BUILDER=docker or BUILDER=podman as needed" >&2
  echo "optional: SCAN_CMD='scanner command using \$IMAGE_TAG', SBOM_CMD='sbom command using \$IMAGE_TAG', PUSH_IMAGE=1" >&2
}

[ "${APPROVED_BASE_IMAGE:-}" != "" ] || { usage; exit 2; }
[ "${1:-}" != "" ] || { usage; exit 2; }
[ "${2:-}" != "" ] || { usage; exit 2; }

containerfile=$1
tag=$2
context=${3:-$(dirname "$containerfile")}
builder=${BUILDER:-docker}
normalized_containerfile=
cleanup() {
  [ "$normalized_containerfile" = "" ] || rm -f "$normalized_containerfile"
}
trap cleanup EXIT INT TERM

[ -r "$containerfile" ] || { echo "Containerfile not readable: $containerfile" >&2; exit 1; }

case "$builder" in
  docker|podman|/*) ;;
  *) echo "BUILDER must be docker, podman, or an absolute path" >&2; exit 1 ;;
esac

normalized_containerfile=$(mktemp)
awk '
  {
    line = $0
    if (line ~ /\\[[:space:]]*$/) {
      sub(/[[:space:]]*\\[[:space:]]*$/, " ", line)
      buffer = buffer line
      next
    }
    print buffer line
    buffer = ""
  }
  END {
    if (buffer != "") print buffer
  }
' "$containerfile" >"$normalized_containerfile"

case "$APPROVED_BASE_IMAGE" in
  *@sha256:*) ;;
  *)
    [ "${PUSH_IMAGE:-}" != "1" ] || { echo "cannot push with unpinned APPROVED_BASE_IMAGE" >&2; exit 1; }
    if [ "${ALLOW_UNPINNED_BASE:-}" != "1" ]; then
      echo "APPROVED_BASE_IMAGE must be pinned by digest; set ALLOW_UNPINNED_BASE=1 for local-only testing" >&2
      exit 1
    fi
    ;;
esac

from_count=$(awk 'tolower($1) == "from" { count++ } END { print count + 0 }' "$normalized_containerfile")
if [ "$from_count" = "0" ]; then
  echo "rejected: Containerfile has no FROM" >&2
  exit 1
fi

bad_from=$(awk '
  tolower($1) == "from" {
    image = $2
    if (image ~ /^--platform=/) image = $3
    if (image != approved) print image
  }
' approved="$APPROVED_BASE_IMAGE" "$normalized_containerfile" | head -n 1)

if [ "$bad_from" != "" ]; then
  echo "rejected: FROM '$bad_from' is not approved base '$APPROVED_BASE_IMAGE'" >&2
  exit 1
fi

stage_aliases=$(awk '
  tolower($1) == "from" {
    for (i = 3; i <= NF; i++) {
      if (tolower($i) == "as" && (i + 1) <= NF) print $(i + 1)
    }
  }
' "$normalized_containerfile")

bad_external_source=$(awk -v aliases="$stage_aliases" '
  function allowed(source, i, count, values) {
    if (source ~ /^[0-9]+$/) return 1
    count = split(aliases, values, "\n")
    for (i = 1; i <= count; i++) if (source == values[i]) return 1
    return 0
  }
  function reject(source) {
    if (source != "" && !allowed(source)) {
      print source
      exit
    }
  }
  tolower($1) == "copy" || tolower($1) == "add" {
    for (i = 2; i <= NF; i++) {
      if ($i ~ /^--from=/) {
        source = $i
        sub(/^--from=/, "", source)
        reject(source)
      }
    }
  }
  tolower($1) == "run" {
    for (i = 2; i <= NF; i++) {
      if ($i ~ /^--mount=/) {
        source = $i
        sub(/^--mount=/, "", source)
        n = split(source, parts, ",")
        for (j = 1; j <= n; j++) {
          if (parts[j] ~ /^from=/) {
            sub(/^from=/, "", parts[j])
            reject(parts[j])
          }
        }
      }
    }
  }
' "$normalized_containerfile")

if [ "$bad_external_source" != "" ]; then
  echo "rejected: external build source '$bad_external_source' is not a local stage" >&2
  exit 1
fi

$builder build --pull -f "$containerfile" -t "$tag" "$context"
IMAGE_TAG=$tag
export IMAGE_TAG

if [ "${SBOM_CMD:-}" != "" ]; then
  sh -c "$SBOM_CMD"
fi

if [ "${SCAN_CMD:-}" != "" ]; then
  sh -c "$SCAN_CMD"
fi

if [ "${PUSH_IMAGE:-}" = "1" ]; then
  [ "${SCAN_CMD:-}" != "" ] || { echo "SCAN_CMD is required when PUSH_IMAGE=1" >&2; exit 1; }
  [ "${SBOM_CMD:-}" != "" ] || { echo "SBOM_CMD is required when PUSH_IMAGE=1" >&2; exit 1; }
  if [ "${APPROVED_REGISTRY_PREFIX:-}" != "" ]; then
    case "$APPROVED_REGISTRY_PREFIX" in
      */) ;;
      *) echo "APPROVED_REGISTRY_PREFIX must end with /" >&2; exit 1 ;;
    esac
    case "$tag" in
      "$APPROVED_REGISTRY_PREFIX"*) ;;
      *) echo "tag must start with APPROVED_REGISTRY_PREFIX=$APPROVED_REGISTRY_PREFIX" >&2; exit 1 ;;
    esac
  fi
  $builder push "$tag"
  repo=${tag%:*}
  digest=$($builder image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$tag" | awk -v repo="$repo" 'index($0, repo "@") == 1 { print; exit }')
  if [ "$digest" = "" ] || [ "$digest" = "<no value>" ]; then
    echo "pushed image has no RepoDigest; cannot promote by digest" >&2
    exit 1
  fi
  printf '%s\n' "$digest"
  if [ "${OUTPUT_DIGEST_FILE:-}" != "" ]; then
    umask 077
    printf '%s\n' "$digest" >"$OUTPUT_DIGEST_FILE"
  fi
else
  $builder image inspect --format '{{.Id}}' "$tag"
  echo "local build only; set PUSH_IMAGE=1 plus SCAN_CMD/SBOM_CMD for promotion" >&2
fi
