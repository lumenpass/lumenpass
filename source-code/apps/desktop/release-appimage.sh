#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

GPG_KEY_ID="${GPG_KEY_ID:-6709A866C744182C}"
SKIP_DOCKER_TESTS="${SKIP_DOCKER_TESTS:-1}"
RELEASE_DIR="${RELEASE_DIR:-./release}"
CREATE_DETACHED_SIGNATURE="${CREATE_DETACHED_SIGNATURE:-1}"
DART_DEFINES="${DART_DEFINES:-dart_defines.prod.json}"
PACKAGING_DIR="linux/packaging"
DIST_DIR="${RELEASE_DIR}/appimage"
PACKAGING_DIST_DIR="${PACKAGING_DIR}/dist"
SCRIPTS_DIR="linux/scripts"
BUNDLE_GTK="${BUNDLE_GTK:-0}"

VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)"

log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33m!!\033[0m %s\n' "$*" >&2; }
fail() { printf '\n\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

log "Preflight checks"
require_cmd flutter
require_cmd file
require_cmd shasum

[[ -f "$DART_DEFINES" ]] || fail "Missing $DART_DEFINES (copy dart_defines.example.json and fill in production values)"
[[ -x "$SCRIPTS_DIR/build-appimage.sh" ]] || fail "Missing or non-executable $SCRIPTS_DIR/build-appimage.sh"
[[ -d "$PACKAGING_DIR/assets" ]] || fail "Missing $PACKAGING_DIR/assets"

if [[ -n "$GPG_KEY_ID" ]]; then
  require_cmd gpg
  if ! gpg --list-secret-keys "$GPG_KEY_ID" >/dev/null 2>&1; then
    fail "GPG secret key not found in keyring: $GPG_KEY_ID"
  fi
else
  warn "GPG_KEY_ID not set; the AppImage will not be signed. Set GPG_KEY_ID=<key> to enable signing."
fi

log "Building release Linux bundle (v${VERSION})"
flutter clean
flutter pub get
flutter build linux --release --dart-define-from-file="$DART_DEFINES"

log "Packaging AppImage"
rm -f "$DIST_DIR"/LumenPass-*.AppImage \
      "$DIST_DIR"/LumenPass-*.AppImage.asc \
      "$DIST_DIR"/LumenPass-*.AppImage.sha256 2>/dev/null || true

SKIP_FLUTTER_BUILD=1 FLUTTER_BUILD_MODE=release BUNDLE_GTK="$BUNDLE_GTK" "$SCRIPTS_DIR/build-appimage.sh"

mkdir -p "$DIST_DIR"
shopt -s nullglob
APPIMAGE_ARTIFACTS=("$PACKAGING_DIST_DIR"/LumenPass-${VERSION}-*.AppImage)
if [[ ${#APPIMAGE_ARTIFACTS[@]} -gt 0 ]]; then
  cp -f "${APPIMAGE_ARTIFACTS[@]}" "$DIST_DIR/"
fi
APPIMAGE_CANDIDATES=("$DIST_DIR"/LumenPass-${VERSION}-*.AppImage)
shopt -u nullglob
[[ ${#APPIMAGE_CANDIDATES[@]} -gt 0 ]] || fail "build-appimage.sh did not produce an AppImage in $DIST_DIR"
APPIMAGE_FILE="${APPIMAGE_CANDIDATES[0]}"
APPIMAGE_FILE="$(realpath "$APPIMAGE_FILE")"
[[ -x "$APPIMAGE_FILE" ]] || fail "AppImage is not executable: $APPIMAGE_FILE"
echo "Artifact: $APPIMAGE_FILE"

log "Validating AppImage runtime and contents"
"$APPIMAGE_FILE" --appimage-help >/dev/null
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
(
  cd "$TMP_DIR"
  "$APPIMAGE_FILE" --appimage-extract >/dev/null
  test -x squashfs-root/AppRun
  test -x squashfs-root/opt/lumenpass/lumenpass
  test -f squashfs-root/usr/share/applications/lumenpass.desktop
  test -f squashfs-root/usr/share/metainfo/lumenpass.metainfo.xml
  test -f squashfs-root/usr/share/icons/hicolor/256x256/apps/lumenpass.png
)

if [[ -n "$GPG_KEY_ID" && "$CREATE_DETACHED_SIGNATURE" == "1" ]]; then
  log "Signing AppImage with detached GPG signature (key: $GPG_KEY_ID)"
  rm -f "${APPIMAGE_FILE}.asc"
  gpg --batch --yes --armor --detach-sign \
      --local-user "$GPG_KEY_ID" \
      --output "${APPIMAGE_FILE}.asc" \
      "$APPIMAGE_FILE"
  gpg --verify "${APPIMAGE_FILE}.asc" "$APPIMAGE_FILE"
  echo "Signature: ${APPIMAGE_FILE}.asc"
fi

log "Generating SHA-256 checksum"
( cd "$(dirname "$APPIMAGE_FILE")" && shasum -a 256 "$(basename "$APPIMAGE_FILE")" | tee "$(basename "$APPIMAGE_FILE").sha256" )

log "Done"
echo "Artifact:  $APPIMAGE_FILE"
echo "Checksum:  ${APPIMAGE_FILE}.sha256"
if [[ -f "${APPIMAGE_FILE}.asc" ]]; then
  echo "Signature: ${APPIMAGE_FILE}.asc"
fi
