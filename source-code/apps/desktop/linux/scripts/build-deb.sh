#!/usr/bin/env bash
# build-deb.sh
#
# Build a Debian (.deb) package for LumenPass desktop.
#
# Pipeline:
#   1. Run `flutter build linux --release` from the desktop app root.
#   2. Stage the produced bundle into linux/packaging/staging/bundle/.
#   3. Generate icon sizes from linux/packaging/assets/icons/source/lumenpass.png
#      using ImageMagick (`convert`) when present.
#   4. Invoke `dpkg-buildpackage -us -uc -b` against linux/packaging/.
#   5. Move the resulting .deb into linux/packaging/dist/.
#
# Usage:
#   ./linux/scripts/build-deb.sh                # release build for host arch
#   FLUTTER_BUILD_MODE=profile ./build-deb.sh   # profile build
#   SKIP_FLUTTER_BUILD=1 ./build-deb.sh         # reuse existing build/linux
#
# Required tooling on the build host:
#   flutter, cmake, ninja, clang, pkg-config, libgtk-3-dev, dpkg-dev,
#   debhelper (>= 13), fakeroot, lintian. Optional: imagemagick (convert).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${DESKTOP_DIR}/../.." && pwd)"
PACKAGING_DIR="${DESKTOP_DIR}/linux/packaging"
STAGING_DIR="${PACKAGING_DIR}/staging"
DIST_DIR="${PACKAGING_DIR}/dist"
ASSETS_DIR="${PACKAGING_DIR}/assets"
ICONS_DIR="${ASSETS_DIR}/icons"

FLUTTER_BUILD_MODE="${FLUTTER_BUILD_MODE:-release}"
SKIP_FLUTTER_BUILD="${SKIP_FLUTTER_BUILD:-0}"

log() { printf "\033[1;34m[build-deb]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[build-deb]\033[0m %s\n" "$*" >&2; }
fail() { printf "\033[1;31m[build-deb]\033[0m %s\n" "$*" >&2; exit 1; }

PUBSPEC_VERSION="$(awk '/^version:/{print $2; exit}' "${DESKTOP_DIR}/pubspec.yaml")"
VERSION="${PUBSPEC_VERSION%%+*}"
BUILD_NUMBER="${PUBSPEC_VERSION#*+}"
if [[ "${BUILD_NUMBER}" == "${PUBSPEC_VERSION}" ]]; then
  BUILD_NUMBER="1"
fi
DEB_VERSION="${VERSION}-${BUILD_NUMBER}"
[[ -n "${VERSION}" ]] || fail "Failed to read version from pubspec.yaml"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

# ---------------------------------------------------------------------------
# 1. Pre-flight checks
# ---------------------------------------------------------------------------
[[ -f "${REPO_ROOT}/LICENSE" ]] || fail "Repository license missing: ${REPO_ROOT}/LICENSE"
require_cmd dpkg-buildpackage
require_cmd dpkg-deb
require_cmd fakeroot

if [[ "${SKIP_FLUTTER_BUILD}" != "1" ]]; then
  require_cmd flutter
fi

# ---------------------------------------------------------------------------
# 2. Flutter build
# ---------------------------------------------------------------------------
cd "${DESKTOP_DIR}"

# Linux Google Drive support is now provided directly by `backup_service.dart`
# via the platform-aware `googleAuthFor()` factory in
# `lib/core/services/google_auth/`, which selects `LinuxGoogleAuth` (a pure-
# Dart loopback PKCE flow) on Linux. There is no longer a Linux-specific
# replacement file to swap in; the canonical service is used as-is.

if [[ "${SKIP_FLUTTER_BUILD}" != "1" ]]; then
  log "Running flutter pub get"
  flutter pub get

  log "Running flutter build linux --${FLUTTER_BUILD_MODE}"
  flutter build linux --"${FLUTTER_BUILD_MODE}"
fi

ARCH="$(dpkg --print-architecture)"
case "${ARCH}" in
  amd64) FLUTTER_ARCH_DIR="x64" ;;
  arm64) FLUTTER_ARCH_DIR="arm64" ;;
  *) fail "Unsupported architecture: ${ARCH}" ;;
esac

BUNDLE_SOURCE="${DESKTOP_DIR}/build/linux/${FLUTTER_ARCH_DIR}/${FLUTTER_BUILD_MODE}/bundle"
[[ -d "${BUNDLE_SOURCE}" ]] || fail "Flutter bundle not found at ${BUNDLE_SOURCE}. \
Run flutter build linux first or unset SKIP_FLUTTER_BUILD."

# ---------------------------------------------------------------------------
# 3. Stage bundle
# ---------------------------------------------------------------------------
log "Staging bundle from ${BUNDLE_SOURCE}"
rm -rf "${STAGING_DIR}/bundle"
mkdir -p "${STAGING_DIR}/bundle"
cp -a "${BUNDLE_SOURCE}/." "${STAGING_DIR}/bundle/"

# ---------------------------------------------------------------------------
# 4. Generate icon sizes (if a source icon exists and ImageMagick is present)
# ---------------------------------------------------------------------------
SOURCE_ICON="${ICONS_DIR}/source/lumenpass.png"
if [[ -f "${SOURCE_ICON}" ]]; then
  if command -v convert >/dev/null 2>&1; then
    log "Generating icon set from ${SOURCE_ICON}"
    for size in 16 32 48 64 128 256 512; do
      target_dir="${ICONS_DIR}/${size}x${size}"
      mkdir -p "${target_dir}"
      convert "${SOURCE_ICON}" -resize "${size}x${size}" "${target_dir}/lumenpass.png"
    done
  else
    warn "ImageMagick 'convert' not found; reusing pre-generated icons if any."
  fi
else
  warn "No source icon found at ${SOURCE_ICON}; ensure pre-generated PNGs exist."
fi

# Verify all required icon sizes are present
for size in 16 32 48 64 128 256 512; do
  target="${ICONS_DIR}/${size}x${size}/lumenpass.png"
  [[ -f "${target}" ]] || fail "Missing icon: ${target}"
done

# ---------------------------------------------------------------------------
# 5. Invoke dpkg-buildpackage
# ---------------------------------------------------------------------------
log "Building Debian package via dpkg-buildpackage"
cd "${PACKAGING_DIR}"

# dpkg-buildpackage drops artifacts in the parent directory. Use a tmp build
# root so we don't pollute linux/.
BUILD_ROOT="${PACKAGING_DIR}/build"
rm -rf "${BUILD_ROOT}"
mkdir -p "${BUILD_ROOT}/lumenpass"
cp -a "${PACKAGING_DIR}/debian"   "${BUILD_ROOT}/lumenpass/"
cp -a "${PACKAGING_DIR}/assets"   "${BUILD_ROOT}/lumenpass/"
cp -a "${STAGING_DIR}"            "${BUILD_ROOT}/lumenpass/"
cp "${REPO_ROOT}/LICENSE"         "${BUILD_ROOT}/lumenpass/LICENSE"

cd "${BUILD_ROOT}/lumenpass"
DCH_DIST="$(dpkg-parsechangelog --show-field Distribution)"
DCH_URGENCY="$(dpkg-parsechangelog --show-field Urgency)"
DCH_DATE="$(date -R)"
{
  printf 'lumenpass (%s) %s; urgency=%s\n\n' "${DEB_VERSION}" "${DCH_DIST:-stable}" "${DCH_URGENCY:-medium}"
  printf '  * Release %s.\n\n' "${VERSION}"
  printf ' -- TranTech Studio <admin@lumenpass.app>  %s\n\n' "${DCH_DATE}"
  cat debian/changelog
} > debian/changelog.new
mv debian/changelog.new debian/changelog
dpkg-buildpackage -us -uc -b -d --host-arch="${ARCH}"

# ---------------------------------------------------------------------------
# 6. Collect artifacts
# ---------------------------------------------------------------------------
mkdir -p "${DIST_DIR}"
shopt -s nullglob
mv "${BUILD_ROOT}"/lumenpass_*.deb         "${DIST_DIR}/" 2>/dev/null || true
mv "${BUILD_ROOT}"/lumenpass_*.buildinfo   "${DIST_DIR}/" 2>/dev/null || true
mv "${BUILD_ROOT}"/lumenpass_*.changes     "${DIST_DIR}/" 2>/dev/null || true
shopt -u nullglob

cd "${DIST_DIR}"
DEB_FILE="$(ls -1t lumenpass_*.deb 2>/dev/null | head -n1 || true)"

if [[ -z "${DEB_FILE}" ]]; then
  fail "No .deb file produced — check the dpkg-buildpackage logs above."
fi

log "Built package: ${DIST_DIR}/${DEB_FILE}"
log "Done."
