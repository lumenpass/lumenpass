#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

GPG_KEY_ID="${GPG_KEY_ID:-6709A866C744182C}"
SKIP_DOCKER_TESTS="${SKIP_DOCKER_TESTS:-1}"
RELEASE_DIR="${RELEASE_DIR:-./release}"
DEB_SIGN_MODE="${DEB_SIGN_MODE:-auto}"
CREATE_DETACHED_SIGNATURE="${CREATE_DETACHED_SIGNATURE:-1}"
DIST_DIR="${RELEASE_DIR}/deb"
SCRIPTS_DIR="linux/scripts"
DART_DEFINES="dart_defines.prod.json"
PACKAGING_DIR="linux/packaging"

PUBSPEC_VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
VERSION="${PUBSPEC_VERSION%%+*}"
BUILD_NUMBER="${PUBSPEC_VERSION#*+}"
if [[ "$BUILD_NUMBER" == "$PUBSPEC_VERSION" ]]; then
  BUILD_NUMBER="1"
fi
DEB_VERSION="${VERSION}-${BUILD_NUMBER}"
ARCH="$(dpkg --print-architecture)"

log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33m!!\033[0m %s\n' "$*" >&2; }
fail() { printf '\n\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

log "Preflight checks"
require_cmd flutter
require_cmd dpkg
require_cmd dpkg-buildpackage
require_cmd dpkg-deb
require_cmd fakeroot
require_cmd lintian
require_cmd desktop-file-validate
require_cmd appstreamcli
require_cmd convert
require_cmd shasum

[[ -f "$DART_DEFINES" ]] || fail "Missing $DART_DEFINES (copy dart_defines.example.json and fill in production values)"
[[ -d "$PACKAGING_DIR/debian" ]] || fail "Missing $PACKAGING_DIR/debian"
[[ -d "$PACKAGING_DIR/assets" ]] || fail "Missing $PACKAGING_DIR/assets"
[[ -x "$SCRIPTS_DIR/build-deb.sh" ]] || fail "Missing or non-executable $SCRIPTS_DIR/build-deb.sh"
[[ -x "$SCRIPTS_DIR/validate-deb.sh" ]] || fail "Missing or non-executable $SCRIPTS_DIR/validate-deb.sh"
[[ -x "$SCRIPTS_DIR/test-deb.sh" ]] || fail "Missing or non-executable $SCRIPTS_DIR/test-deb.sh"

case "$ARCH" in
  amd64|arm64) ;;
  *) fail "Unsupported host architecture: $ARCH (expected amd64 or arm64)" ;;
esac

PUBSPEC_DEB_VERSION="$(awk '/^lumenpass /{print $2; exit}' "$PACKAGING_DIR/debian/changelog" | tr -d '()')"
if [[ "$PUBSPEC_DEB_VERSION" != "$DEB_VERSION" ]]; then
  fail "Version mismatch: pubspec.yaml=${PUBSPEC_VERSION} expects debian/changelog top entry=${DEB_VERSION}, found ${PUBSPEC_DEB_VERSION}. Update debian/changelog before releasing."
fi

if [[ -n "$GPG_KEY_ID" ]]; then
  require_cmd gpg
  if ! gpg --list-secret-keys "$GPG_KEY_ID" >/dev/null 2>&1; then
    fail "GPG secret key not found in keyring: $GPG_KEY_ID"
  fi
  case "$DEB_SIGN_MODE" in
    auto)
      if command -v dpkg-sig >/dev/null 2>&1; then
        DEB_SIGN_MODE="dpkg-sig"
      else
        warn "dpkg-sig not installed; falling back to DEB_SIGN_MODE=detached-only"
        DEB_SIGN_MODE="detached-only"
      fi
      ;;
    dpkg-sig) require_cmd dpkg-sig ;;
    detached-only) ;;
    none) ;;
    *) fail "Unsupported DEB_SIGN_MODE: $DEB_SIGN_MODE (expected auto, dpkg-sig, detached-only, or none)" ;;
  esac
else
  warn "GPG_KEY_ID not set; the .deb will not be signed. Set GPG_KEY_ID=<key> to enable signing."
fi

if [[ "$SKIP_DOCKER_TESTS" != "1" ]]; then
  require_cmd docker
  if ! docker info >/dev/null 2>&1; then
    fail "docker daemon is not reachable. Start docker or rerun with SKIP_DOCKER_TESTS=1."
  fi
fi

log "Building release Linux bundle (v${DEB_VERSION}, ${ARCH})"
flutter clean
flutter pub get
FLUTTER_BUILD_COMMAND=(flutter build linux --release --dart-define-from-file="$DART_DEFINES")
printf 'Flutter build command:'
printf ' %q' "${FLUTTER_BUILD_COMMAND[@]}"
printf '\n'
"${FLUTTER_BUILD_COMMAND[@]}"

case "$ARCH" in
  amd64) FLUTTER_ARCH_DIR="x64" ;;
  arm64) FLUTTER_ARCH_DIR="arm64" ;;
esac
BUNDLE_DIR="build/linux/${FLUTTER_ARCH_DIR}/release/bundle"
[[ -d "$BUNDLE_DIR" ]] || fail "Flutter bundle not found at $BUNDLE_DIR"
[[ -x "$BUNDLE_DIR/lumenpass" ]] || fail "Built binary missing: $BUNDLE_DIR/lumenpass"

log "Packaging .deb (reusing the bundle just built)"
rm -f "$DIST_DIR"/lumenpass_*.deb \
      "$DIST_DIR"/lumenpass_*.buildinfo \
      "$DIST_DIR"/lumenpass_*.changes \
      "$DIST_DIR"/lumenpass_*.deb.asc \
      "$DIST_DIR"/lumenpass_*.deb.sha256 2>/dev/null || true

SKIP_FLUTTER_BUILD=1 FLUTTER_BUILD_MODE=release "$SCRIPTS_DIR/build-deb.sh"

mkdir -p "$DIST_DIR"
cp -f "$PACKAGING_DIR/dist/lumenpass_${DEB_VERSION}_${ARCH}.deb" "$DIST_DIR/" 2>/dev/null || true
cp -f "$PACKAGING_DIR/dist/lumenpass_${DEB_VERSION}_${ARCH}.buildinfo" "$DIST_DIR/" 2>/dev/null || true
cp -f "$PACKAGING_DIR/dist/lumenpass_${DEB_VERSION}_${ARCH}.changes" "$DIST_DIR/" 2>/dev/null || true

DEB_FILE="$DIST_DIR/lumenpass_${DEB_VERSION}_${ARCH}.deb"
[[ -n "$DEB_FILE" && -f "$DEB_FILE" ]] || fail "build-deb.sh did not produce a .deb in $DIST_DIR"
echo "Artifact: $DEB_FILE"

log "Validating .deb (lintian + structural + AppStream + desktop file)"
"$SCRIPTS_DIR/validate-deb.sh" "$DEB_FILE"

if [[ -n "$GPG_KEY_ID" ]]; then
  if [[ "$DEB_SIGN_MODE" == "none" ]]; then
    warn "DEB_SIGN_MODE=none — skipping all .deb signing (no dpkg-sig, no .asc)"
  else
    case "$DEB_SIGN_MODE" in
      dpkg-sig)
        log "Signing .deb in-place with dpkg-sig (key: $GPG_KEY_ID)"
        dpkg-sig --sign builder -k "$GPG_KEY_ID" "$DEB_FILE"
        dpkg-sig --verify "$DEB_FILE"
        ;;
      detached-only)
        warn "DEB_SIGN_MODE=detached-only — skipping dpkg-sig in-package signature"
        ;;
    esac

    if [[ "$CREATE_DETACHED_SIGNATURE" == "1" ]]; then
      log "Signing final .deb with detached GPG signature (key: $GPG_KEY_ID)"
      rm -f "${DEB_FILE}.asc"
      gpg --batch --yes --armor --detach-sign \
          --local-user "$GPG_KEY_ID" \
          --output "${DEB_FILE}.asc" \
          "$DEB_FILE"
      gpg --verify "${DEB_FILE}.asc" "$DEB_FILE"
      echo "Signature: ${DEB_FILE}.asc"
    fi
  fi
fi

if [[ "$SKIP_DOCKER_TESTS" != "1" ]]; then
  log "Running install/uninstall smoke tests in docker (${DOCKER_TEST_TARGETS})"
  "$SCRIPTS_DIR/test-deb.sh" --mode docker --targets "$DOCKER_TEST_TARGETS" --deb "$DEB_FILE"
else
  warn "SKIP_DOCKER_TESTS=1 — skipping docker install/uninstall matrix"
fi

log "Generating SHA-256 checksum"
( cd "$(dirname "$DEB_FILE")" && shasum -a 256 "$(basename "$DEB_FILE")" | tee "$(basename "$DEB_FILE").sha256" )

log "Done"
echo "Artifact: $(pwd)/$DEB_FILE"
echo "Checksum: $(pwd)/${DEB_FILE}.sha256"
if [[ -n "$GPG_KEY_ID" ]]; then
 echo "Signature: $(pwd)/${DEB_FILE}.asc"
fi
