#!/usr/bin/env bash
set -euo pipefail

# LumenPass – Edge Extension Package Script
#
# Builds on top of the standard Chromium output in `dist/` and creates a
# submission-ready zip for Microsoft Edge Add-ons.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DIST_DIR="dist"
BUILD_LOG="build-edge.log"
BUILDS_DIR="builds"
ZIP_NAME=""

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log()   { printf "${CYAN}[%s]${NC} %s\n" "$(date +%H:%M:%S)" "$*" | tee -a "$BUILD_LOG"; }
ok()    { printf "${GREEN}  ✓${NC} %s\n" "$*" | tee -a "$BUILD_LOG"; }
err()   { printf "${RED}  ✗ ERROR:${NC} %s\n" "$*" | tee -a "$BUILD_LOG" >&2; }
fatal() { err "$@"; exit 1; }

cleanup() {
  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    err "Edge packaging failed (exit code $exit_code). See $BUILD_LOG for details."
  fi
}
trap cleanup EXIT

: > "$BUILD_LOG"
log "LumenPass Edge package – started"

[ -f package.json ] || fatal "package.json not found – run this script from the extension root"
[ -d "$DIST_DIR" ] || fatal "dist/ not found – run npm run build first"
[ -f "$DIST_DIR/manifest.json" ] || fatal "dist/manifest.json not found – build output is incomplete"

VERSION=$(node -e "
  const manifest = JSON.parse(require('fs').readFileSync('$DIST_DIR/manifest.json', 'utf8'));
  process.stdout.write(manifest.version || '');
")

[ -n "$VERSION" ] || fatal "Could not read version from dist/manifest.json"

log "Validating Chromium manifest for Edge…"
node -e "
  const fs = require('fs');
  const manifest = JSON.parse(fs.readFileSync('$DIST_DIR/manifest.json', 'utf8'));
  const errors = [];

  if (manifest.manifest_version !== 3) errors.push('manifest_version must be 3');
  if (!manifest.name) errors.push('name is required');
  if (!manifest.version || !/^\\d+\\.\\d+\\.\\d+$/.test(manifest.version)) {
    errors.push('version must be semver (e.g. 1.0.0)');
  }
  if (!manifest.description) errors.push('description is required');
  if (manifest.update_url) errors.push('update_url must not be present for Edge packaging');
  if (!manifest.background?.service_worker) errors.push('background.service_worker is required');
  if (!Array.isArray(manifest.permissions)) errors.push('permissions must be an array');
  if (!Array.isArray(manifest.host_permissions)) errors.push('host_permissions must be an array');

  if (errors.length) {
    errors.forEach((message) => console.error('  ✗ ' + message));
    process.exit(1);
  }
  console.log('  version: ' + manifest.version);
  console.log('  service_worker: ' + manifest.background.service_worker);
" >> "$BUILD_LOG" 2>&1 || fatal "Manifest validation failed"
ok "dist/manifest.json looks valid for Edge submission"

ZIP_NAME="lumenpass-edge-extension-v${VERSION}.zip"
rm -f "$BUILDS_DIR/$ZIP_NAME"

log "Creating Edge submission archive…"
(mkdir -p "$BUILDS_DIR" && cd "$DIST_DIR" && zip -r -FS -9 "../$BUILDS_DIR/$ZIP_NAME" . -x '*.DS_Store' '*.map') >> "$BUILD_LOG" 2>&1 \
 || fatal "Failed to create $ZIP_NAME"

ZIP_SIZE=$(du -sh "$BUILDS_DIR/$ZIP_NAME" | awk '{print $1}')
ok "$ZIP_NAME created ($ZIP_SIZE)"
log "Done"
