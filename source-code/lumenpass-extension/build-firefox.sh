#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# LumenPass – Firefox Extension Build & Package Script
#
# Automates:  dependency check → icon generation → type-check → Vite build
#             → manifest validation → asset optimization → .xpi packaging
#
# Usage:
#   ./build-firefox.sh                  # unsigned .xpi (for addons.mozilla.org upload)
#   ./build-firefox.sh --sign           # sign via web-ext (reads credentials from .env)
#
# Credentials (required only with --sign):
#   Create a .env file in this directory with:
#     WEB_EXT_API_KEY=<AMO JWT issuer>
#     WEB_EXT_API_SECRET=<AMO JWT secret>
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DIST_DIR="dist-firefox"
BUILD_LOG="build-firefox.log"
BUILDS_DIR="builds"
SIGN_FLAG=false
VERSION=""
XPI_NAME=""

# ── Colours ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Helpers ────────────────────────────────────────────────────────────────────
log()   { printf "${CYAN}[%s]${NC} %s\n" "$(date +%H:%M:%S)" "$*" | tee -a "$BUILD_LOG"; }
ok()    { printf "${GREEN}  ✓${NC} %s\n" "$*" | tee -a "$BUILD_LOG"; }
warn()  { printf "${YELLOW}  ⚠${NC} %s\n" "$*" | tee -a "$BUILD_LOG"; }
err()   { printf "${RED}  ✗ ERROR:${NC} %s\n" "$*" | tee -a "$BUILD_LOG" >&2; }
fatal() { err "$@"; exit 1; }

cleanup() {
  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    err "Build failed (exit code $exit_code). See $BUILD_LOG for details."
  fi
}
trap cleanup EXIT

# ── Parse arguments ────────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --sign) SIGN_FLAG=true ;;
    *)      fatal "Unknown argument: $arg" ;;
  esac
done

# ── Load .env ──────────────────────────────────────────────────────────────────
if [ -f ".env" ]; then
  set -a
  source ".env"
  set +a
fi

# ── Initialise log ─────────────────────────────────────────────────────────────
: > "$BUILD_LOG"
log "LumenPass Firefox Extension – Build started"
log "Working directory: $SCRIPT_DIR"

# ═══════════════════════════════════════════════════════════════════════════════
# 1. Prerequisite checks
# ═══════════════════════════════════════════════════════════════════════════════
log "Step 1/8 – Checking prerequisites…"

command -v node  >/dev/null 2>&1 || fatal "node is not installed"
command -v npm   >/dev/null 2>&1 || fatal "npm is not installed"

NODE_MAJOR=$(node -e "process.stdout.write(String(process.versions.node.split('.')[0]))")
if [ "$NODE_MAJOR" -lt 18 ]; then
  fatal "Node.js >= 18 required (found v$(node -v))"
fi

ok "Node $(node -v), npm $(npm -v)"

if [ ! -f package.json ]; then
  fatal "package.json not found – run this script from the extension root"
fi

if [ ! -d node_modules ]; then
  log "   node_modules missing – running npm install…"
  npm ci --ignore-scripts >> "$BUILD_LOG" 2>&1 || fatal "npm ci failed"
  ok "Dependencies installed"
else
  ok "node_modules present"
fi

if $SIGN_FLAG; then
  if ! npx --no-install web-ext --version >/dev/null 2>&1; then
    log "   Installing web-ext for signing…"
    npm install --no-save web-ext >> "$BUILD_LOG" 2>&1 || fatal "Failed to install web-ext"
  fi
  ok "web-ext available"

  if [ -z "${WEB_EXT_API_KEY:-}" ] || [ -z "${WEB_EXT_API_SECRET:-}" ]; then
    fatal "Signing requires WEB_EXT_API_KEY and WEB_EXT_API_SECRET (set in .env or environment)"
  fi
  ok "AMO signing credentials loaded"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 2. Validate Firefox manifest
# ═══════════════════════════════════════════════════════════════════════════════
log "Step 2/8 – Validating manifest.firefox.json…"

MANIFEST_PATH="src/manifest.firefox.json"
if [ ! -f "$MANIFEST_PATH" ]; then
  fatal "$MANIFEST_PATH not found"
fi

node -e "
  const fs = require('fs');
  const m = JSON.parse(fs.readFileSync('$MANIFEST_PATH', 'utf8'));
  const errors = [];

  if (m.manifest_version !== 3 && m.manifest_version !== 2)
    errors.push('manifest_version must be 2 or 3');
  if (!m.name || m.name.length > 45)
    errors.push('name is required and must be <= 45 chars');
  if (!m.version || !/^\d+\.\d+\.\d+$/.test(m.version))
    errors.push('version must be semver (e.g. 1.0.0)');
  if (!m.description || m.description.length > 132)
    errors.push('description is required and must be <= 132 chars');
  if (!m.browser_specific_settings?.gecko?.id)
    errors.push('browser_specific_settings.gecko.id is required for Firefox');
  if (!m.icons || !m.icons['48'] || !m.icons['128'])
    errors.push('icons must include 48 and 128 sizes (AMO requirement)');
  if (!m.action?.default_popup)
    errors.push('action.default_popup is required');
  if (!m.background?.scripts && !m.background?.service_worker)
    errors.push('background scripts/service_worker is required');
  if (!m.permissions || !Array.isArray(m.permissions))
    errors.push('permissions must be an array');

  if (errors.length) {
    errors.forEach(e => console.error('  ✗ ' + e));
    process.exit(1);
  }
  console.log('  version: ' + m.version);
  console.log('  gecko.id: ' + m.browser_specific_settings.gecko.id);
" >> "$BUILD_LOG" 2>&1 || fatal "Manifest validation failed – check $BUILD_LOG"

VERSION=$(node -e "
  const m = JSON.parse(require('fs').readFileSync('$MANIFEST_PATH','utf8'));
  process.stdout.write(m.version);
")
XPI_NAME="lumenpass-firefox-extension-v${VERSION}.xpi"

ok "manifest.firefox.json valid (v$VERSION)"

# ═══════════════════════════════════════════════════════════════════════════════
# 3. Generate icons
# ═══════════════════════════════════════════════════════════════════════════════
log "Step 3/8 – Generating icons…"
npm run generate:icons >> "$BUILD_LOG" 2>&1 || fatal "Icon generation failed"
ok "Icons generated"

# ═══════════════════════════════════════════════════════════════════════════════
# 4. TypeScript type-check
# ═══════════════════════════════════════════════════════════════════════════════
log "Step 4/8 – Running type-check…"
npx tsc --noEmit >> "$BUILD_LOG" 2>&1 || fatal "TypeScript type-check failed – fix errors before building"
ok "Type-check passed"

# ═══════════════════════════════════════════════════════════════════════════════
# 5. Vite build (Firefox target)
# ═══════════════════════════════════════════════════════════════════════════════
log "Step 5/8 – Building with Vite (BROWSER=firefox)…"
rm -rf "$DIST_DIR"
BROWSER=firefox npx vite build >> "$BUILD_LOG" 2>&1 || fatal "Vite build failed"

if [ ! -d "$DIST_DIR" ]; then
  fatal "Expected output directory $DIST_DIR not found after build"
fi

ok "Vite build complete → $DIST_DIR/"

# ═══════════════════════════════════════════════════════════════════════════════
# 6. Post-build validation
# ═══════════════════════════════════════════════════════════════════════════════
log "Step 6/8 – Post-build validation…"

REQUIRED_FILES=(
  "manifest.json"
)

MISSING=()
for f in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "$DIST_DIR/$f" ]; then
    MISSING+=("$f")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  fatal "Missing required files in build output: ${MISSING[*]}"
fi
ok "Build output structure validated"

BUILT_MANIFEST="$DIST_DIR/manifest.json"
node -e "
  const fs = require('fs');
  const m = JSON.parse(fs.readFileSync('$BUILT_MANIFEST', 'utf8'));
  if (!m.browser_specific_settings?.gecko?.id) {
    console.error('Built manifest missing gecko.id');
    process.exit(1);
  }
  if (m.manifest_version !== 3 && m.manifest_version !== 2) {
    console.error('Built manifest has invalid manifest_version');
    process.exit(1);
  }
" >> "$BUILD_LOG" 2>&1 || fatal "Built manifest validation failed"
ok "Built manifest.json contains gecko metadata"

# ═══════════════════════════════════════════════════════════════════════════════
# 7. Asset optimisation & size report
# ═══════════════════════════════════════════════════════════════════════════════
log "Step 7/8 – Asset report…"

TOTAL_SIZE=$(du -sh "$DIST_DIR" | awk '{print $1}')
JS_COUNT=$(find "$DIST_DIR" -name '*.js' | wc -l | tr -d ' ')
CSS_COUNT=$(find "$DIST_DIR" -name '*.css' | wc -l | tr -d ' ')
IMG_COUNT=$(find "$DIST_DIR" -name '*.png' -o -name '*.svg' | wc -l | tr -d ' ')

MAX_SIZE_BYTES=$((200 * 1024 * 1024))
ACTUAL_BYTES=$(du -sb "$DIST_DIR" 2>/dev/null | awk '{print $1}' || find "$DIST_DIR" -type f -exec stat -f%z {} + 2>/dev/null | awk '{s+=$1}END{print s}')

if [ -n "$ACTUAL_BYTES" ] && [ "$ACTUAL_BYTES" -gt "$MAX_SIZE_BYTES" ] 2>/dev/null; then
  warn "Extension size (${TOTAL_SIZE}) exceeds AMO 200 MB limit"
else
  ok "Size: $TOTAL_SIZE (within AMO limit)"
fi
ok "Assets: ${JS_COUNT} JS, ${CSS_COUNT} CSS, ${IMG_COUNT} images"

# ═══════════════════════════════════════════════════════════════════════════════
# 8. Package .xpi
# ═══════════════════════════════════════════════════════════════════════════════
log "Step 8/8 – Packaging .xpi…"

rm -f "$BUILDS_DIR/$XPI_NAME"

(cd "$DIST_DIR" && zip -r -FS -9 "../$BUILDS_DIR/$XPI_NAME" . -x '*.DS_Store' '*.map') >> "$BUILD_LOG" 2>&1 \
 || fatal "Failed to create .xpi archive"

XPI_SIZE=$(du -sh "$BUILDS_DIR/$XPI_NAME" | awk '{print $1}')
ok "$XPI_NAME created ($XPI_SIZE)"

# ── Optional: sign with web-ext ────────────────────────────────────────────────
if $SIGN_FLAG; then
  log "Signing with web-ext…"
  npx web-ext sign \
    --source-dir "$DIST_DIR" \
    --artifacts-dir "." \
    --api-key "$WEB_EXT_API_KEY" \
    --api-secret "$WEB_EXT_API_SECRET" \
    --channel listed \
    >> "$BUILD_LOG" 2>&1 || fatal "web-ext sign failed – check $BUILD_LOG"

  SIGNED_XPI=$(ls -t lumenpass-*.xpi 2>/dev/null | head -1)
  if [ -n "$SIGNED_XPI" ]; then
	mv "$SIGNED_XPI" "$BUILDS_DIR/"
	SIGNED_XPI="$BUILDS_DIR/$(basename "$SIGNED_XPI")"
	if [ -n "$SIGNED_XPI" ]; then
		ok "Signed: $SIGNED_XPI"
	fi
fi  else
    warn "Signing completed but no signed .xpi found in current directory"
  fi
fi

# ── web-ext lint (advisory) ────────────────────────────────────────────────────
if npx --no-install web-ext --version >/dev/null 2>&1; then
  log "Running web-ext lint (advisory)…"
  npx web-ext lint --source-dir "$DIST_DIR" --warnings-as-errors=false >> "$BUILD_LOG" 2>&1 \
    && ok "web-ext lint passed" \
    || warn "web-ext lint reported warnings – check $BUILD_LOG"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Done
# ═══════════════════════════════════════════════════════════════════════════════
printf " ${GREEN}${BOLD}✅ Firefox extension build complete!${NC}\n" >&2
printf " ${BOLD}Package:${NC} %s/%s (%s)\n" "$BUILDS_DIR" "$XPI_NAME" "$XPI_SIZE" >&2
printf " ${BOLD}Build:${NC} %s/\n" "$DIST_DIR" >&2
printf " ${BOLD}Log:${NC} %s\n\n" "$BUILD_LOG" >&2

if ! $SIGN_FLAG; then
  printf "   ${CYAN}To sign for distribution:${NC}\n"
  printf "     ./build-firefox.sh --sign\n\n"
  printf "   ${CYAN}To submit unsigned:${NC}\n"
  printf "     Upload %s to https://addons.mozilla.org/developers/\n\n" "$XPI_NAME"
fi
