#!/usr/bin/env bash
# Mirror the images in a mirror list into Artifactory. Three modes:
#   scripts/mirror-images.sh direct    <list> <registry-prefix>   bastion that reaches both sides
#   scripts/mirror-images.sh to-disk   <list> <dir>               connected side of an air gap
#   scripts/mirror-images.sh from-disk <list> <dir> <registry-prefix>   disconnected side
# <registry-prefix> = REGISTRY_PREFIX from mg-settings, e.g. artifactory.example.com/docker-local
# Credentials come from REGISTRY_AUTH_FILE (a pull secret JSON holding registry.redhat.io
# and/or your Artifactory entries): `podman login --authfile ...` builds one.
set -euo pipefail
mode="$1"; list="$2"
auth=(); [ -n "${REGISTRY_AUTH_FILE:-}" ] && auth=(-a "$REGISTRY_AUTH_FILE")
grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$list" | while read -r src dest; do
  case "$mode" in
    direct)    oc image mirror "${auth[@]}" --keep-manifest-list "$src" "$3/$dest" ;;
    to-disk)   oc image mirror "${auth[@]}" --keep-manifest-list "$src" "file://mg/$dest" --dir="$3" ;;
    from-disk) oc image mirror "${auth[@]}" --keep-manifest-list --from-dir="$3" "file://mg/$dest" "$4/$dest" ;;
    *) echo "mode must be direct, to-disk or from-disk" >&2; exit 1 ;;
  esac
  echo "mirrored $src -> $dest"
done
