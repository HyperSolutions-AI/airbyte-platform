#!/usr/bin/env bash
# =============================================================================
# airgap-load-images.sh — run on the air-gapped machine
#
# Loads all saved images from the bundle, re-tags them under the internal
# registry, and pushes them.  After this script completes, configure Airbyte
# with JOB_KUBE_CONNECTOR_IMAGE_REGISTRY pointing to INTERNAL_REGISTRY.
#
# Usage:
#   ./airgap-load-images.sh <bundle-dir> <internal-registry>
#
# Examples:
#   ./airgap-load-images.sh /mnt/usb/airgap-bundle harbor.moi.internal
#   ./airgap-load-images.sh ./airgap-bundle 192.168.1.100:5000
# =============================================================================
set -euo pipefail

BUNDLE_DIR="${1:-}"
INTERNAL_REGISTRY="${2:-}"

[[ -z "${BUNDLE_DIR}" ]]       && { echo "Usage: $0 <bundle-dir> <internal-registry>"; exit 1; }
[[ -z "${INTERNAL_REGISTRY}" ]] && { echo "Usage: $0 <bundle-dir> <internal-registry>"; exit 1; }
[[ -f "${BUNDLE_DIR}/manifest.txt" ]] || { echo "ERROR: ${BUNDLE_DIR}/manifest.txt not found"; exit 1; }

INTERNAL_REGISTRY="${INTERNAL_REGISTRY%/}"  # strip trailing slash

log()  { echo "[$(date +%H:%M:%S)] $*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

# Derive the internal registry tag for an original image ref.
# Strips any existing registry host (anything with '.' or ':' before the first '/')
# and prepends the internal registry — identical logic to withImageRegistry() in
# PayloadKubeInputMapper.kt.
internal_tag() {
  local image="$1"
  local path="${image}"
  local i
  i=$(echo "${image}" | cut -d'/' -f1)
  if echo "${i}" | grep -qE '[\.\:]|^localhost$'; then
    # strip existing registry host
    path="${image#*/}"
  fi
  echo "${INTERNAL_REGISTRY}/${path}"
}

TOTAL=$(wc -l < "${BUNDLE_DIR}/manifest.txt" | tr -d ' ')
COUNT=0
ERRORS=0

log "=== Airbyte air-gap image loader ==="
log "Bundle  : ${BUNDLE_DIR}"
log "Registry: ${INTERNAL_REGISTRY}"
log "Images  : ${TOTAL}"
echo

while IFS='|' read -r original_image category archive_name; do
  COUNT=$((COUNT + 1))
  archive="${BUNDLE_DIR}/${category}/${archive_name}"

  log "[${COUNT}/${TOTAL}] ${original_image}"

  if [[ ! -f "${archive}" ]]; then
    log "  WARN: archive not found: ${archive}"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # Load image
  log "  load: ${archive}"
  if ! gunzip -c "${archive}" | docker load; then
    log "  ERROR: failed to load ${archive}"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # Re-tag with internal registry
  target=$(internal_tag "${original_image}")
  log "  tag : ${original_image} → ${target}"
  if ! docker tag "${original_image}" "${target}"; then
    log "  ERROR: failed to tag ${original_image}"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # Push to internal registry
  log "  push: ${target}"
  if ! docker push "${target}"; then
    log "  ERROR: failed to push ${target}"
    ERRORS=$((ERRORS + 1))
    continue
  fi

done < "${BUNDLE_DIR}/manifest.txt"

echo
log "=== Done ==="
log "Processed: ${COUNT} images"
log "Errors   : ${ERRORS}"
echo
log "Next steps:"
log "  Set in Helm values.yaml (or env vars):"
log "    global.image.registry: ${INTERNAL_REGISTRY}"
log "    global.connectorRegistry.seedProvider: local"
log "    JOB_KUBE_CONNECTOR_IMAGE_REGISTRY: ${INTERNAL_REGISTRY}"
log "    CONNECTOR_REGISTRY_BASE_URL: http://<your-registry-mirror>/files"
log "    DOCKER_HUB_BASE_URL: http://<your-registry-mirror-api>"
log "    GITHUB_DOCS_BASE_URL: http://<your-docs-mirror>"

[[ "${ERRORS}" -gt 0 ]] && exit 1 || exit 0
