#!/usr/bin/env bash
# build-rpm.sh
#
# Build an RPM package for LumenPass desktop.
#
# Why docker? `rpmbuild`'s automatic Requires/Provides extraction needs an
# RPM-native distro to resolve shared-library names to package names
# (e.g. libgtk-3.so.0 -> gtk3). Running rpmbuild on Ubuntu produces a .rpm
# but with weak/missing dependency metadata, which trips rpmlint and breaks
# `dnf install`. We therefore build inside a Fedora container by default.
#
# Pipeline:
#   1. Run `flutter build linux --release` on the host (skipped when
#      SKIP_FLUTTER_BUILD=1).
#   2. Stage the produced bundle + packaging assets into a tarball at
#      linux/packaging/rpm/SOURCES/lumenpass-<VERSION>.tar.gz.
#   3. Spin up a Fedora container (docker by default), install rpm-build,
#      rpmlint and run `rpmbuild -bb` against the spec file.
#   4. Copy the produced RPM out into linux/packaging/dist/.
#   5. Run rpmlint inside the container (best-effort; warnings do not fail
#      the build by default — set FAIL_ON_RPMLINT=1 to enforce).
#
# Set FORCE_HOST_BUILD=1 to skip docker and run rpmbuild directly on the
# host (only useful on Fedora/RHEL/openSUSE-style hosts).
#
# Usage:
#   ./linux/scripts/build-rpm.sh                       # default: docker, fedora:40
#   FEDORA_IMAGE=fedora:39 ./linux/scripts/build-rpm.sh
#   SKIP_FLUTTER_BUILD=1 ./linux/scripts/build-rpm.sh
#   FORCE_HOST_BUILD=1 ./linux/scripts/build-rpm.sh
#
# Required tooling on the host:
#   flutter (unless SKIP_FLUTTER_BUILD=1), tar, docker (unless
#   FORCE_HOST_BUILD=1).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${DESKTOP_DIR}/../.." && pwd)"
PACKAGING_DIR="${DESKTOP_DIR}/linux/packaging"
ASSETS_DIR="${PACKAGING_DIR}/assets"
ICONS_DIR="${ASSETS_DIR}/icons"
RPM_DIR="${PACKAGING_DIR}/rpm"
DIST_DIR="${PACKAGING_DIR}/dist"
SPEC_FILE="${RPM_DIR}/lumenpass.spec"

FLUTTER_BUILD_MODE="${FLUTTER_BUILD_MODE:-release}"
SKIP_FLUTTER_BUILD="${SKIP_FLUTTER_BUILD:-0}"
FORCE_HOST_BUILD="${FORCE_HOST_BUILD:-0}"
FEDORA_IMAGE="${FEDORA_IMAGE:-fedora:40}"
FAIL_ON_RPMLINT="${FAIL_ON_RPMLINT:-0}"

log()  { printf "\033[1;34m[build-rpm]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[build-rpm]\033[0m %s\n" "$*" >&2; }
fail() { printf "\033[1;31m[build-rpm]\033[0m %s\n" "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

# ---------------------------------------------------------------------------
# 1. Pre-flight
# ---------------------------------------------------------------------------
[[ -f "${SPEC_FILE}" ]] || fail "Spec file missing: ${SPEC_FILE}"
[[ -f "${REPO_ROOT}/LICENSE" ]] || fail "Repository license missing: ${REPO_ROOT}/LICENSE"
require_cmd tar

if [[ "${SKIP_FLUTTER_BUILD}" != "1" ]]; then
  require_cmd flutter
fi

if [[ "${FORCE_HOST_BUILD}" != "1" ]]; then
  require_cmd docker
fi

if command -v dpkg >/dev/null 2>&1; then
  ARCH_DPKG="$(dpkg --print-architecture)"
else
  ARCH_DPKG=""
fi

case "${ARCH_DPKG}" in
  amd64) FLUTTER_ARCH_DIR="x64";   RPM_ARCH="x86_64" ;;
  arm64) FLUTTER_ARCH_DIR="arm64"; RPM_ARCH="aarch64" ;;
  *)
    UNAME_M="$(uname -m)"
    case "${UNAME_M}" in
      x86_64)        FLUTTER_ARCH_DIR="x64";   RPM_ARCH="x86_64" ;;
      aarch64|arm64) FLUTTER_ARCH_DIR="arm64"; RPM_ARCH="aarch64" ;;
      *) fail "Unsupported architecture: ${UNAME_M}" ;;
    esac
    ;;
esac

PUBSPEC_VERSION="$(awk '/^version:/{print $2; exit}' "${DESKTOP_DIR}/pubspec.yaml")"
VERSION="${PUBSPEC_VERSION%%+*}"
BUILD_NUMBER="${PUBSPEC_VERSION#*+}"
if [[ "${BUILD_NUMBER}" == "${PUBSPEC_VERSION}" ]]; then
  BUILD_NUMBER="1"
fi
RPM_RELEASE="${RPM_RELEASE:-${BUILD_NUMBER}}"
[[ -n "${VERSION}" ]] || fail "Failed to read version from pubspec.yaml"
log "Building lumenpass-${VERSION}-${RPM_RELEASE}.${RPM_ARCH}.rpm"

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
# 3. Stage SOURCES tarball
# ---------------------------------------------------------------------------
log "Staging RPM source tree"
TOPDIR="${RPM_DIR}/topdir"
SOURCES="${TOPDIR}/SOURCES"
SPECS="${TOPDIR}/SPECS"
RPMS="${TOPDIR}/RPMS"
SRPMS="${TOPDIR}/SRPMS"
BUILD="${TOPDIR}/BUILD"
BUILDROOT="${TOPDIR}/BUILDROOT"

rm -rf "${TOPDIR}"
mkdir -p "${SOURCES}" "${SPECS}" "${RPMS}" "${SRPMS}" "${BUILD}" "${BUILDROOT}"

STAGE="${RPM_DIR}/staging/lumenpass-${VERSION}"
rm -rf "${RPM_DIR}/staging"
mkdir -p "${STAGE}/bundle" "${STAGE}/assets/icons"

cp -a "${BUNDLE_SOURCE}/." "${STAGE}/bundle/"
cp "${ASSETS_DIR}/lumenpass" "${STAGE}/assets/lumenpass"
cp "${ASSETS_DIR}/lumenpass.desktop" "${STAGE}/assets/lumenpass.desktop"
cp "${ASSETS_DIR}/lumenpass.metainfo.xml" "${STAGE}/assets/lumenpass.metainfo.xml"

for size in 16 32 48 64 128 256 512; do
  src="${ICONS_DIR}/${size}x${size}/lumenpass.png"
  [[ -f "${src}" ]] || fail "Missing icon: ${src}"
  mkdir -p "${STAGE}/assets/icons/${size}x${size}"
  cp "${src}" "${STAGE}/assets/icons/${size}x${size}/lumenpass.png"
done

# Ship the canonical repository license in the RPM source and binary package.
cp "${REPO_ROOT}/LICENSE" "${STAGE}/LICENSE"

TARBALL="${SOURCES}/lumenpass-${VERSION}.tar.gz"
log "Creating source tarball ${TARBALL}"
tar -C "${RPM_DIR}/staging" -czf "${TARBALL}" "lumenpass-${VERSION}"

cp "${SPEC_FILE}" "${SPECS}/lumenpass.spec"

# ---------------------------------------------------------------------------
# 4. Build inside docker (or directly on the host when forced)
# ---------------------------------------------------------------------------
build_in_container() {
  log "Building RPM inside ${FEDORA_IMAGE}"

  if ! docker info >/dev/null 2>&1; then
    fail "docker daemon is not reachable. Start docker or rerun with FORCE_HOST_BUILD=1."
  fi

  local mount="/work"
  local host_uid host_gid
  host_uid="$(id -u)"
  host_gid="$(id -g)"

  # rpmbuild needs to run as root inside the container so dnf can install
  # build dependencies, but the artifacts end up under TOPDIR which is a
  # bind mount from the host. We chown the tree back to the invoking
  # user as the last step so re-runs and cleanup don't need sudo on the
  # host. Errors during chown are tolerated; the build itself is the
  # operation that determines exit status.
  docker run --rm \
    -v "${TOPDIR}:${mount}" \
    -w "${mount}" \
    -e "RPM_VERSION=${VERSION}" \
    -e "RPM_RELEASE=${RPM_RELEASE}" \
    -e "FAIL_ON_RPMLINT=${FAIL_ON_RPMLINT}" \
    -e "HOST_UID=${host_uid}" \
    -e "HOST_GID=${host_gid}" \
    "${FEDORA_IMAGE}" \
    bash -lc "
      set -euo pipefail
      cleanup() {
        chown -R \"\${HOST_UID}:\${HOST_GID}\" \"${mount}\" 2>/dev/null || true
      }
      trap cleanup EXIT
      dnf install -y --setopt=install_weak_deps=False \
        rpm-build rpmlint rpmdevtools tar gzip findutils
      rpmbuild \
        --define '_topdir ${mount}' \
        --define '_lumenpass_version ${VERSION}' \
        --define '_lumenpass_release ${RPM_RELEASE}' \
        -bb SPECS/lumenpass.spec
      RPM_FILE=\$(find RPMS -name 'lumenpass-*.rpm' | head -n1)
      if [ -z \"\${RPM_FILE}\" ]; then
        echo 'rpmbuild produced no .rpm' >&2
        exit 1
      fi
      echo \"Built: \${RPM_FILE}\"
      if command -v rpmlint >/dev/null 2>&1; then
        echo '--- rpmlint ---'
        if ! rpmlint \"\${RPM_FILE}\"; then
          if [ \"\${FAIL_ON_RPMLINT:-0}\" = \"1\" ]; then
            exit 1
          fi
          echo 'rpmlint reported issues; continuing because FAIL_ON_RPMLINT != 1' >&2
        fi
      fi
    "
}

build_on_host() {
  log "Building RPM directly on host (FORCE_HOST_BUILD=1)"
  require_cmd rpmbuild
  rpmbuild \
    --define "_topdir ${TOPDIR}" \
    --define "_lumenpass_version ${VERSION}" \
    --define "_lumenpass_release ${RPM_RELEASE}" \
    -bb "${SPECS}/lumenpass.spec"
}

if [[ "${FORCE_HOST_BUILD}" == "1" ]]; then
  build_on_host
else
  build_in_container
fi

# ---------------------------------------------------------------------------
# 5. Collect artifacts
# ---------------------------------------------------------------------------
mkdir -p "${DIST_DIR}"
shopt -s nullglob
RPM_FILES=("${RPMS}"/*/lumenpass-*.rpm)
shopt -u nullglob
[[ ${#RPM_FILES[@]} -gt 0 ]] || fail "No .rpm produced under ${RPMS}"

for rpm in "${RPM_FILES[@]}"; do
  cp -v "${rpm}" "${DIST_DIR}/"
done

log "Done. Artifacts in ${DIST_DIR}"
ls -1 "${DIST_DIR}"/lumenpass-*.rpm
