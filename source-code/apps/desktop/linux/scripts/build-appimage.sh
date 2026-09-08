#!/usr/bin/env bash
# build-appimage.sh
#
# Build a portable AppImage for LumenPass desktop.
#
# Pipeline:
#   1. Run `flutter build linux --release` (skipped when SKIP_FLUTTER_BUILD=1).
#   2. Stage the produced bundle into linux/packaging/staging/appimage/AppDir,
#      mirroring the /opt/lumenpass layout used by the .deb so the Flutter
#      binary's $ORIGIN-relative RPATH continues to resolve.
#   3. Drop a custom AppRun that exec()s into /opt/lumenpass/lumenpass.
#   4. Copy the existing .desktop entry, AppStream metadata, and hicolor icons.
#   5. Optionally bundle GTK + libsecret + libayatana-appindicator with
#      linuxdeploy + linuxdeploy-plugin-gtk (BUNDLE_GTK=1, default 0).
#   6. Pack the AppDir into LumenPass-<VERSION>-<arch>.AppImage with
#      appimagetool and move it into linux/packaging/dist/.
#
# Portability note:
#   AppImage portability across distros is achieved by building on the
#   *oldest* supported host (Ubuntu 22.04 LTS is the recommended baseline).
#   By default this script does NOT bundle GTK; users are expected to have
#   a system GTK 3 stack. Set BUNDLE_GTK=1 to embed GTK via linuxdeploy.
#
# Usage:
#   ./linux/scripts/build-appimage.sh                # release build for host arch
#   FLUTTER_BUILD_MODE=profile ./build-appimage.sh   # profile build
#   SKIP_FLUTTER_BUILD=1 ./build-appimage.sh         # reuse existing build/linux
#   BUNDLE_GTK=1 ./build-appimage.sh                 # embed GTK via linuxdeploy
#
# Required tooling on the build host:
#   flutter, file, wget or curl, fuse (libfuse2 on Debian/Ubuntu).
#   AppImage tools (linuxdeploy, linuxdeploy-plugin-gtk, appimagetool) are
#   downloaded automatically into linux/packaging/tools/ when missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PACKAGING_DIR="${DESKTOP_DIR}/linux/packaging"
ASSETS_DIR="${PACKAGING_DIR}/assets"
ICONS_DIR="${ASSETS_DIR}/icons"
STAGING_DIR="${PACKAGING_DIR}/staging/appimage"
DIST_DIR="${PACKAGING_DIR}/dist"
TOOLS_DIR="${PACKAGING_DIR}/tools"
APPDIR="${STAGING_DIR}/AppDir"

FLUTTER_BUILD_MODE="${FLUTTER_BUILD_MODE:-release}"
SKIP_FLUTTER_BUILD="${SKIP_FLUTTER_BUILD:-0}"
SKIP_TOOL_DOWNLOAD="${SKIP_TOOL_DOWNLOAD:-0}"
BUNDLE_GTK="${BUNDLE_GTK:-0}"

LINUXDEPLOY_BASE="${LINUXDEPLOY_BASE:-https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous}"
LINUXDEPLOY_GTK_URL="${LINUXDEPLOY_GTK_URL:-https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh}"
APPIMAGETOOL_BASE="${APPIMAGETOOL_BASE:-https://github.com/AppImage/appimagetool/releases/download/continuous}"

log()  { printf "\033[1;34m[build-appimage]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[build-appimage]\033[0m %s\n" "$*" >&2; }
fail() { printf "\033[1;31m[build-appimage]\033[0m %s\n" "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

# ---------------------------------------------------------------------------
# 1. Pre-flight checks + arch detection
# ---------------------------------------------------------------------------
require_cmd file
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  fail "Either curl or wget is required to download AppImage tooling."
fi

if [[ "${SKIP_FLUTTER_BUILD}" != "1" ]]; then
  require_cmd flutter
fi

if command -v dpkg >/dev/null 2>&1; then
  ARCH_DPKG="$(dpkg --print-architecture)"
else
  ARCH_DPKG=""
fi

case "${ARCH_DPKG}" in
  amd64) FLUTTER_ARCH_DIR="x64"; APPIMAGE_ARCH="x86_64" ;;
  arm64) FLUTTER_ARCH_DIR="arm64"; APPIMAGE_ARCH="aarch64" ;;
  *)
    UNAME_M="$(uname -m)"
    case "${UNAME_M}" in
      x86_64)        FLUTTER_ARCH_DIR="x64";   APPIMAGE_ARCH="x86_64" ;;
      aarch64|arm64) FLUTTER_ARCH_DIR="arm64"; APPIMAGE_ARCH="aarch64" ;;
      *) fail "Unsupported architecture: ${UNAME_M}" ;;
    esac
    ;;
esac

VERSION="$(awk '/^version:/{print $2; exit}' "${DESKTOP_DIR}/pubspec.yaml" | cut -d'+' -f1)"
[[ -n "${VERSION}" ]] || fail "Failed to read version from pubspec.yaml"
log "Building LumenPass-${VERSION}-${APPIMAGE_ARCH}.AppImage"

# ---------------------------------------------------------------------------
# 2. Flutter build
# ---------------------------------------------------------------------------
cd "${DESKTOP_DIR}"

if [[ "${SKIP_FLUTTER_BUILD}" != "1" ]]; then
  log "Running flutter pub get"
  flutter pub get

  log "Running flutter build linux --${FLUTTER_BUILD_MODE}"
  flutter build linux --"${FLUTTER_BUILD_MODE}"
fi

BUNDLE_SOURCE="${DESKTOP_DIR}/build/linux/${FLUTTER_ARCH_DIR}/${FLUTTER_BUILD_MODE}/bundle"
[[ -d "${BUNDLE_SOURCE}" ]] || fail "Flutter bundle not found at ${BUNDLE_SOURCE}. \
Run flutter build linux first or unset SKIP_FLUTTER_BUILD."

# ---------------------------------------------------------------------------
# 3. Stage AppDir
# ---------------------------------------------------------------------------
log "Staging AppDir at ${APPDIR}"
rm -rf "${STAGING_DIR}"
mkdir -p "${APPDIR}/opt/lumenpass"
mkdir -p "${APPDIR}/usr/bin"
mkdir -p "${APPDIR}/usr/share/applications"
mkdir -p "${APPDIR}/usr/share/metainfo"

cp -a "${BUNDLE_SOURCE}/." "${APPDIR}/opt/lumenpass/"
chmod 0755 "${APPDIR}/opt/lumenpass/lumenpass"

# /usr/bin wrapper (matches the .deb wrapper at packaging/assets/lumenpass)
cp "${ASSETS_DIR}/lumenpass" "${APPDIR}/usr/bin/lumenpass"
chmod 0755 "${APPDIR}/usr/bin/lumenpass"

# Desktop entry + AppStream metadata
cp "${ASSETS_DIR}/lumenpass.desktop" \
   "${APPDIR}/usr/share/applications/lumenpass.desktop"
cp "${ASSETS_DIR}/lumenpass.metainfo.xml" \
   "${APPDIR}/usr/share/metainfo/lumenpass.metainfo.xml"

# Hicolor icons
for size in 16 32 48 64 128 256 512; do
  src="${ICONS_DIR}/${size}x${size}/lumenpass.png"
  [[ -f "${src}" ]] || fail "Missing icon: ${src}"
  dst_dir="${APPDIR}/usr/share/icons/hicolor/${size}x${size}/apps"
  mkdir -p "${dst_dir}"
  cp "${src}" "${dst_dir}/lumenpass.png"
done

# Top-level .desktop + icon (mandatory per AppImage spec)
cp "${ASSETS_DIR}/lumenpass.desktop" "${APPDIR}/lumenpass.desktop"
cp "${ICONS_DIR}/256x256/lumenpass.png" "${APPDIR}/lumenpass.png"

# AppRun entry point. Resolves $HERE relative to the mounted AppImage so the
# /opt/lumenpass layout still works inside the squashfs.
cat > "${APPDIR}/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
export PATH="${HERE}/usr/bin:${PATH}"
# Ensure bundled GTK / glib (when BUNDLE_GTK=1 was used) wins over host libs.
export LD_LIBRARY_PATH="${HERE}/usr/lib:${HERE}/usr/lib/x86_64-linux-gnu:${HERE}/opt/lumenpass/lib:${LD_LIBRARY_PATH:-}"
export XDG_DATA_DIRS="${HERE}/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
exec "${HERE}/opt/lumenpass/lumenpass" "$@"
EOF
chmod 0755 "${APPDIR}/AppRun"

# ---------------------------------------------------------------------------
# 4. Fetch AppImage tooling
# ---------------------------------------------------------------------------
mkdir -p "${TOOLS_DIR}"
APPIMAGETOOL="${TOOLS_DIR}/appimagetool-${APPIMAGE_ARCH}.AppImage"
LINUXDEPLOY="${TOOLS_DIR}/linuxdeploy-${APPIMAGE_ARCH}.AppImage"
LINUXDEPLOY_GTK="${TOOLS_DIR}/linuxdeploy-plugin-gtk.sh"

fetch() {
  local url="$1" out="$2"
  if [[ -f "${out}" ]]; then return 0; fi
  log "Downloading $(basename "${out}")"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 -o "${out}" "${url}"
  else
    wget -O "${out}" "${url}"
  fi
}

if [[ "${SKIP_TOOL_DOWNLOAD}" != "1" ]]; then
  fetch "${APPIMAGETOOL_BASE}/appimagetool-${APPIMAGE_ARCH}.AppImage" "${APPIMAGETOOL}"
  if [[ "${BUNDLE_GTK}" == "1" ]]; then
    fetch "${LINUXDEPLOY_BASE}/linuxdeploy-${APPIMAGE_ARCH}.AppImage" "${LINUXDEPLOY}"
    fetch "${LINUXDEPLOY_GTK_URL}" "${LINUXDEPLOY_GTK}"
  fi
fi

[[ -f "${APPIMAGETOOL}" ]] || fail "appimagetool missing at ${APPIMAGETOOL}"
chmod +x "${APPIMAGETOOL}"

# ---------------------------------------------------------------------------
# 5. Optional GTK bundling (linuxdeploy + linuxdeploy-plugin-gtk)
# ---------------------------------------------------------------------------
if [[ "${BUNDLE_GTK}" == "1" ]]; then
  [[ -f "${LINUXDEPLOY}" ]] || fail "linuxdeploy missing at ${LINUXDEPLOY}"
  [[ -f "${LINUXDEPLOY_GTK}" ]] || fail "linuxdeploy-plugin-gtk missing at ${LINUXDEPLOY_GTK}"
  chmod +x "${LINUXDEPLOY}" "${LINUXDEPLOY_GTK}"
  export PATH="${TOOLS_DIR}:${PATH}"

  log "Bundling GTK with linuxdeploy-plugin-gtk"
  # APPIMAGE_EXTRACT_AND_RUN=1 sidesteps the libfuse2 requirement, which is
  # missing on Ubuntu 24.04+ by default. The AppImage tools self-extract to
  # a temp directory and run from there.
  APPIMAGE_EXTRACT_AND_RUN=1 \
  NO_STRIP="${NO_STRIP:-1}" \
  "${LINUXDEPLOY}" \
    --appdir "${APPDIR}" \
    --plugin gtk \
    --executable "${APPDIR}/opt/lumenpass/lumenpass" \
    --desktop-file "${APPDIR}/lumenpass.desktop" \
    --icon-file "${APPDIR}/lumenpass.png"
fi

# ---------------------------------------------------------------------------
# 6. Pack AppImage
# ---------------------------------------------------------------------------
mkdir -p "${DIST_DIR}"
ARTIFACT="LumenPass-${VERSION}-${APPIMAGE_ARCH}.AppImage"
OUTPUT="${DIST_DIR}/${ARTIFACT}"

log "Packing AppImage with appimagetool"
APPIMAGE_EXTRACT_AND_RUN=1 \
ARCH="${APPIMAGE_ARCH}" \
"${APPIMAGETOOL}" \
  --no-appstream \
  "${APPDIR}" \
  "${OUTPUT}"

[[ -f "${OUTPUT}" ]] || fail "appimagetool did not produce ${OUTPUT}"
chmod +x "${OUTPUT}"

log "Built AppImage: ${OUTPUT}"
log "Done."
