#!/usr/bin/env bash
set -euo pipefail

# LumenPass – Chrome Extension Build Script
#
# Usage:
#   ./build.sh             # build only
#   ./build.sh zip         # build + lumenpass-chrome-<version>.zip
#   ./build.sh crx         # build + lumenpass-chrome-<version>.crx (signed with dist.pem)
#   ./build.sh zip crx     # build + both artifacts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DIST_DIR="dist"
KEY_FILE="dist.pem"
BUILDS_DIR="builds"
CREATE_ZIP=false
CREATE_CRX=false

for arg in "$@"; do
  case "$arg" in
    zip) CREATE_ZIP=true ;;
    crx) CREATE_CRX=true ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [zip] [crx]" >&2
      exit 1
      ;;
  esac
done

npm run build

if [ "$CREATE_ZIP" = true ] || [ "$CREATE_CRX" = true ]; then
  [ -d "$DIST_DIR" ] || { echo "dist/ not found after build" >&2; exit 1; }
  [ -f "$DIST_DIR/manifest.json" ] || { echo "dist/manifest.json not found – build output is incomplete" >&2; exit 1; }

  VERSION=$(node -e "
    const manifest = JSON.parse(require('fs').readFileSync('$DIST_DIR/manifest.json', 'utf8'));
    process.stdout.write(manifest.version || '');
  ")

  [ -n "$VERSION" ] || { echo "Could not read version from dist/manifest.json" >&2; exit 1; }
fi

if [ "$CREATE_ZIP" = true ]; then
	ZIP_NAME="lumenpass-chrome-${VERSION}.zip"
	rm -f "$BUILDS_DIR/$ZIP_NAME"
	
	(mkdir -p "$BUILDS_DIR" && cd "$DIST_DIR" && zip -r -FS -9 "../$BUILDS_DIR/$ZIP_NAME" . -x '*.DS_Store' '*.map')
	
	ZIP_SIZE=$(du -sh "$BUILDS_DIR/$ZIP_NAME" | awk '{print $1}')
	echo "✓ $ZIP_NAME created ($ZIP_SIZE)"
fi

if [ "$CREATE_CRX" = true ]; then
  [ -f "$KEY_FILE" ] || { echo "$KEY_FILE not found – cannot sign CRX" >&2; exit 1; }

  CRX_NAME="lumenpass-chrome-${VERSION}.crx"
  GENERATED_CRX="${SCRIPT_DIR}/${DIST_DIR}.crx"
  rm -f "$BUILDS_DIR/$CRX_NAME" "$GENERATED_CRX"
  mkdir -p "$BUILDS_DIR"

  CHROME=""
  for candidate in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium" \
    "$(command -v google-chrome 2>/dev/null || true)" \
    "$(command -v chromium 2>/dev/null || true)" \
    "$(command -v chromium-browser 2>/dev/null || true)"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      CHROME="$candidate"
      break
    fi
  done

  [ -n "$CHROME" ] || { echo "Could not locate Google Chrome / Chromium to pack CRX" >&2; exit 1; }

  ABS_DIST="$SCRIPT_DIR/$DIST_DIR"
  ABS_KEY="$SCRIPT_DIR/$KEY_FILE"

  "$CHROME" --pack-extension="$ABS_DIST" --pack-extension-key="$ABS_KEY" >/dev/null

  if [ -f "$GENERATED_CRX" ]; then
    mv "$GENERATED_CRX" "$BUILDS_DIR/$CRX_NAME"
  else
    echo "Chrome did not produce $GENERATED_CRX (check that $KEY_FILE is a valid private key)" >&2
    exit 1
  fi

  CRX_SIZE=$(du -sh "$BUILDS_DIR/$CRX_NAME" | awk '{print $1}')
  echo "✓ $CRX_NAME created ($CRX_SIZE)"
fi
