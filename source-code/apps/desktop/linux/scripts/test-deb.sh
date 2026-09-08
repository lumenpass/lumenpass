#!/usr/bin/env bash
# test-deb.sh
#
# End-to-end install / smoke / uninstall test for the LumenPass .deb.
#
# Two modes are supported:
#
#   1. native  — install on the current machine. This requires sudo and
#                actually mutates /opt and /usr. Use only on disposable
#                build hosts or CI runners.
#
#   2. docker  — spin up a clean container per target distribution and run
#                the same install/uninstall flow there. This is the
#                recommended mode for verifying multiple Debian-based
#                distributions (Ubuntu LTS, Debian Stable, etc.).
#
# Usage:
#   ./linux/scripts/test-deb.sh                       # docker, all targets
#   ./linux/scripts/test-deb.sh --mode native         # install on host
#   ./linux/scripts/test-deb.sh --targets ubuntu:22.04,debian:12
#
# Targets default to: ubuntu:22.04, ubuntu:24.04, debian:12.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DIST_DIR="${DESKTOP_DIR}/linux/packaging/dist"

MODE="docker"
TARGETS_DEFAULT="ubuntu:22.04,ubuntu:24.04,debian:12"
TARGETS="${TARGETS_DEFAULT}"
DEB_FILE=""

log()  { printf "\033[1;34m[test-deb]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[test-deb]\033[0m %s\n" "$*" >&2; }
fail() { printf "\033[1;31m[test-deb]\033[0m %s\n" "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)    MODE="$2"; shift 2 ;;
    --targets) TARGETS="$2"; shift 2 ;;
    --deb)     DEB_FILE="$2"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | head -n 30
      exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

if [[ -z "${DEB_FILE}" ]]; then
  DEB_FILE="$(ls -1t "${DIST_DIR}"/lumenpass_*.deb 2>/dev/null | head -n1 || true)"
fi
[[ -n "${DEB_FILE}" && -f "${DEB_FILE}" ]] \
  || fail "No .deb to test. Build one first with linux/scripts/build-deb.sh."

run_native() {
  log "Native install test using ${DEB_FILE}"
  command -v sudo >/dev/null 2>&1 || fail "sudo is required for native mode"

  log "Installing"
  sudo apt-get update -y
  sudo apt-get install -y "${DEB_FILE}"

  log "Verifying installed files"
  test -x /opt/lumenpass/lumenpass || fail "/opt/lumenpass/lumenpass missing"
  test -x /usr/bin/lumenpass       || fail "/usr/bin/lumenpass missing"
  test -f /usr/share/applications/lumenpass.desktop \
    || fail "lumenpass.desktop missing"
  test -f /usr/share/metainfo/lumenpass.metainfo.xml \
    || fail "lumenpass.metainfo.xml missing"

  log "Smoke test: launching with --version (5s timeout)"
  if command -v timeout >/dev/null 2>&1; then
    timeout 5 /usr/bin/lumenpass --version || true
  fi

  log "Uninstalling"
  sudo apt-get purge -y lumenpass

  log "Verifying clean removal"
  if [[ -e /opt/lumenpass/lumenpass ]]; then
    fail "/opt/lumenpass/lumenpass still present after purge"
  fi
  log "Native test PASS"
}

run_docker_target() {
  local image="$1"
  log "Running docker test against ${image}"
  command -v docker >/dev/null 2>&1 || fail "docker is required for docker mode"

  local deb_basename
  deb_basename="$(basename "${DEB_FILE}")"
  docker run --rm \
    -v "${DEB_FILE}:/tmp/${deb_basename}:ro" \
    -e DEBIAN_FRONTEND=noninteractive \
    "${image}" \
    bash -ec "
      set -euo pipefail
      apt-get update -y
      apt-get install -y --no-install-recommends ca-certificates desktop-file-utils lintian
      apt-get install -y /tmp/${deb_basename}

      test -x /opt/lumenpass/lumenpass
      test -x /usr/bin/lumenpass
      test -f /usr/share/applications/lumenpass.desktop
      test -f /usr/share/metainfo/lumenpass.metainfo.xml

      desktop-file-validate /usr/share/applications/lumenpass.desktop

      apt-get purge -y lumenpass
      ! test -e /opt/lumenpass/lumenpass
      echo '[OK] ${image}'
    "
}

case "${MODE}" in
  native) run_native ;;
  docker)
    IFS=',' read -r -a targets <<<"${TARGETS}"
    for t in "${targets[@]}"; do
      [[ -n "${t}" ]] && run_docker_target "${t}"
    done
    log "All docker targets passed."
    ;;
  *) fail "Unknown mode: ${MODE} (expected: native|docker)" ;;
esac
