#!/usr/bin/env bash
# validate-deb.sh
#
# Validate the most recently built LumenPass .deb against Debian packaging
# standards. Runs `lintian` (where available) and dpkg's own structural
# checks. Exits non-zero on lintian errors so it can be wired into CI.
#
# Usage:
#   ./linux/scripts/validate-deb.sh [path/to/file.deb]
#
# If no .deb path is provided, the script picks the newest file in
# linux/packaging/dist/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DIST_DIR="${DESKTOP_DIR}/linux/packaging/dist"

log() { printf "\033[1;34m[validate-deb]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[validate-deb]\033[0m %s\n" "$*" >&2; }
fail() { printf "\033[1;31m[validate-deb]\033[0m %s\n" "$*" >&2; exit 1; }

DEB_FILE="${1:-}"
if [[ -z "${DEB_FILE}" ]]; then
  DEB_FILE="$(ls -1t "${DIST_DIR}"/lumenpass_*.deb 2>/dev/null | head -n1 || true)"
fi

[[ -n "${DEB_FILE}" && -f "${DEB_FILE}" ]] \
  || fail "No .deb to validate. Build one with linux/scripts/build-deb.sh first."

log "Validating ${DEB_FILE}"

# ---------------------------------------------------------------------------
# 1. Structural sanity (dpkg-deb)
# ---------------------------------------------------------------------------
log "dpkg-deb --info"
dpkg-deb --info "${DEB_FILE}"

# Capture the full contents listing once. Piping `dpkg-deb --contents`
# directly into `head` triggers SIGPIPE, which combined with `set -o
# pipefail` aborts the entire validator before reaching the downstream
# invariants. Buffering in a variable avoids that.
contents_full="$(dpkg-deb --contents "${DEB_FILE}")"
log "dpkg-deb --contents (truncated to first 40 entries)"
awk 'NR<=40' <<<"${contents_full}"

# Required files inside the archive
REQUIRED_PATHS=(
  "./opt/lumenpass/lumenpass"
  "./opt/lumenpass/data/icudtl.dat"
  "./usr/bin/lumenpass"
  "./usr/share/applications/lumenpass.desktop"
  "./usr/share/metainfo/lumenpass.metainfo.xml"
  "./usr/share/icons/hicolor/256x256/apps/lumenpass.png"
)
contents="$(awk '{print $NF}' <<<"${contents_full}")"
for entry in "${REQUIRED_PATHS[@]}"; do
  if ! grep -Fxq "${entry}" <<<"${contents}"; then
    fail "Required path missing inside .deb: ${entry}"
  fi
done
log "All required paths present."

# ---------------------------------------------------------------------------
# 2. Desktop file validation
# ---------------------------------------------------------------------------
if command -v desktop-file-validate >/dev/null 2>&1; then
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "${TMP_DIR}"' EXIT
  dpkg-deb --extract "${DEB_FILE}" "${TMP_DIR}"
  log "Running desktop-file-validate"
  desktop-file-validate "${TMP_DIR}/usr/share/applications/lumenpass.desktop"

  # Guard against the icon-in-launcher regression: the desktop entry's
  # StartupWMClass must match the GTK application-id (which is the
  # Wayland app_id and, with g_set_prgname() in main.cc, the X11
  # WM_CLASS res_name). When these diverge, GNOME / KDE / Xfce cannot
  # map running windows back to lumenpass.desktop and fall back to the
  # generic application icon in the dock and taskbar.
  EXPECTED_WMCLASS="tranit.lumenpass.linux"
  ACTUAL_WMCLASS="$(awk -F= '/^StartupWMClass=/{print $2; exit}' \
    "${TMP_DIR}/usr/share/applications/lumenpass.desktop")"
  if [[ "${ACTUAL_WMCLASS}" != "${EXPECTED_WMCLASS}" ]]; then
    fail "StartupWMClass mismatch: expected '${EXPECTED_WMCLASS}', \
got '${ACTUAL_WMCLASS}'. The launcher icon will fall back to the system \
default until this matches the GTK application-id."
  fi
  log "StartupWMClass matches application-id (${EXPECTED_WMCLASS})."

  # Confirm the freedesktop hicolor icons are actually present at the
  # mandatory sizes. Missing files here cause silent fallbacks.
  for size in 16 32 48 64 128 256 512; do
    icon="${TMP_DIR}/usr/share/icons/hicolor/${size}x${size}/apps/lumenpass.png"
    [[ -f "${icon}" ]] || fail "Missing hicolor icon: ${icon#${TMP_DIR}}"
  done
  log "All hicolor icon sizes present."
else
  warn "desktop-file-validate not installed; skipping .desktop validation."
fi

# ---------------------------------------------------------------------------
# 3. AppStream validation
# ---------------------------------------------------------------------------
if command -v appstreamcli >/dev/null 2>&1; then
  log "Running appstreamcli validate"
  appstreamcli validate --pedantic \
    "${TMP_DIR:-/}/usr/share/metainfo/lumenpass.metainfo.xml" || true
else
  warn "appstreamcli not installed; skipping AppStream metadata validation."
fi

# ---------------------------------------------------------------------------
# 4. Lintian
# ---------------------------------------------------------------------------
if command -v lintian >/dev/null 2>&1; then
  log "Running lintian --info --display-info --pedantic"
  # We intentionally do not pass --fail-on=error here so the report is fully
  # printed; rely on the explicit exit code mapping below.
  set +e
  lintian --info --display-info --pedantic "${DEB_FILE}"
  LINTIAN_RC=$?
  set -e
  if [[ ${LINTIAN_RC} -ne 0 && ${LINTIAN_RC} -ne 1 ]]; then
    fail "lintian exited with status ${LINTIAN_RC}"
  fi
else
  warn "lintian not installed; cannot enforce Debian policy checks."
fi

log "Validation complete."
