#!/usr/bin/env bash
# =============================================================================
# airgap-pull-images.sh — run on internet-connected machine
#
# Pulls every Airbyte platform image + all connector images, saves them as
# compressed tar archives, and produces a manifest.  Transfer the output
# directory to the air-gapped environment and run airgap-load-images.sh.
#
# Usage:
#   ./airgap-pull-images.sh [output-dir] [platform-version]
#
# Examples:
#   ./airgap-pull-images.sh ./airgap-bundle dev
#   ./airgap-pull-images.sh /mnt/usb/airbyte-bundle 1.1.0
# =============================================================================
set -euo pipefail

OUTPUT_DIR="${1:-./airgap-bundle}"
PLATFORM_VERSION="${2:-dev}"

PLATFORM_IMAGES=(
  "airbyte/bootloader:${PLATFORM_VERSION}"
  "airbyte/server:${PLATFORM_VERSION}"
  "airbyte/worker:${PLATFORM_VERSION}"
  "airbyte/webapp:${PLATFORM_VERSION}"
  "airbyte/workload-launcher:${PLATFORM_VERSION}"
  "airbyte/container-orchestrator:${PLATFORM_VERSION}"
  "airbyte/connector-sidecar:${PLATFORM_VERSION}"
  "airbyte/workload-init-container:${PLATFORM_VERSION}"
  "airbyte/keycloak:${PLATFORM_VERSION}"
  "airbyte/keycloak-setup:${PLATFORM_VERSION}"
  "airbyte/featureflag-server:${PLATFORM_VERSION}"
  # Declarative manifest image — pull the latest versions from local provider
  "airbyte/source-declarative-manifest:0.90.0"
  "airbyte/source-declarative-manifest:1.7.0"
  "airbyte/source-declarative-manifest:2.1.0"
  "airbyte/source-declarative-manifest:3.10.4"
  "airbyte/source-declarative-manifest:4.3.0"
)

INFRA_IMAGES=(
  "temporalio/auto-setup:1.27.2"
  "temporalio/ui:2.30.1"
  "minio/minio:RELEASE.2023-11-20T22-40-07Z"
  "postgres:13-alpine"
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[$(date +%H:%M:%S)] $*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

pull_and_save() {
  local image="$1"
  local category="$2"
  # Derive a filesystem-safe filename from the image ref
  local filename
  filename=$(echo "${image}" | tr '/:' '__')
  local archive="${OUTPUT_DIR}/${category}/${filename}.tar.gz"

  if [[ -f "${archive}" ]]; then
    log "  skip (exists): ${image}"
    return
  fi

  log "  pull: ${image}"
  if ! docker pull "${image}" 2>&1; then
    log "  WARN: failed to pull ${image}, skipping"
    echo "${image}" >> "${OUTPUT_DIR}/pull_failures.txt"
    return
  fi

  log "  save: ${image} → ${archive}"
  docker save "${image}" | gzip -9 > "${archive}"
  echo "${image}|${category}|${filename}.tar.gz" >> "${OUTPUT_DIR}/manifest.txt"
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
mkdir -p "${OUTPUT_DIR}/platform" "${OUTPUT_DIR}/infra" "${OUTPUT_DIR}/connectors"
: > "${OUTPUT_DIR}/manifest.txt"
: > "${OUTPUT_DIR}/pull_failures.txt"

log "=== Airbyte air-gap bundle builder ==="
log "Output : ${OUTPUT_DIR}"
log "Version: ${PLATFORM_VERSION}"
echo

# ---------------------------------------------------------------------------
# Platform images
# ---------------------------------------------------------------------------
log "--- Platform images (${#PLATFORM_IMAGES[@]}) ---"
for img in "${PLATFORM_IMAGES[@]}"; do
  pull_and_save "${img}" "platform"
done

# ---------------------------------------------------------------------------
# Infrastructure images
# ---------------------------------------------------------------------------
log "--- Infrastructure images (${#INFRA_IMAGES[@]}) ---"
for img in "${INFRA_IMAGES[@]}"; do
  pull_and_save "${img}" "infra"
done

# ---------------------------------------------------------------------------
# Connector images — read from local_oss_registry.json
# ---------------------------------------------------------------------------
REGISTRY_JSON="$(dirname "$0")/../airbyte-config/specs/src/main/resources/seed/local_oss_registry.json"
if [[ ! -f "${REGISTRY_JSON}" ]]; then
  fail "Cannot find local_oss_registry.json at ${REGISTRY_JSON}"
fi

CONNECTOR_IMAGES=$(python3 - <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
images = set()
for s in data.get('sources', []):
    images.add(f"{s['dockerRepository']}:{s['dockerImageTag']}")
for d in data.get('destinations', []):
    images.add(f"{d['dockerRepository']}:{d['dockerImageTag']}")
for img in sorted(images):
    print(img)
PYEOF
"${REGISTRY_JSON}")

TOTAL=$(echo "${CONNECTOR_IMAGES}" | wc -l | tr -d ' ')
log "--- Connector images (${TOTAL}) ---"
COUNT=0
while IFS= read -r img; do
  COUNT=$((COUNT + 1))
  log "  [${COUNT}/${TOTAL}]"
  pull_and_save "${img}" "connectors"
done <<< "${CONNECTOR_IMAGES}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
FAILURES=$(wc -l < "${OUTPUT_DIR}/pull_failures.txt" | tr -d ' ')
SAVED=$(wc -l < "${OUTPUT_DIR}/manifest.txt" | tr -d ' ')
BUNDLE_SIZE=$(du -sh "${OUTPUT_DIR}" | cut -f1)

echo
log "=== Done ==="
log "Saved   : ${SAVED} images"
log "Failed  : ${FAILURES} images (see ${OUTPUT_DIR}/pull_failures.txt)"
log "Size    : ${BUNDLE_SIZE}"
log "Manifest: ${OUTPUT_DIR}/manifest.txt"

if [[ "${FAILURES}" -gt 0 ]]; then
  echo
  log "Failed images:"
  cat "${OUTPUT_DIR}/pull_failures.txt"
fi
