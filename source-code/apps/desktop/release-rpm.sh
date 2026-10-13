#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

GPG_KEY_ID="${GPG_KEY_ID:-6709A866C744182C}"
SKIP_DOCKER_TESTS="${SKIP_DOCKER_TESTS:-1}"
RELEASE_DIR="${RELEASE_DIR:-./release}"
DIST_DIR="${RELEASE_DIR}/rpm"
SCRIPTS_DIR="linux/scripts"
DART_DEFINES="dart_defines.prod.json"
PACKAGING_DIR="linux/packaging"
FEDORA_IMAGE="${FEDORA_IMAGE:-fedora:40}"
FAIL_ON_RPMLINT="${FAIL_ON_RPMLINT:-0}"
RPM_SIGN_MODE="${RPM_SIGN_MODE:-auto}"
CREATE_DETACHED_SIGNATURE="${CREATE_DETACHED_SIGNATURE:-1}"

PUBSPEC_VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
VERSION="${PUBSPEC_VERSION%%+*}"
BUILD_NUMBER="${PUBSPEC_VERSION#*+}"
if [[ "$BUILD_NUMBER" == "$PUBSPEC_VERSION" ]]; then
  BUILD_NUMBER="1"
fi
RPM_RELEASE="${BUILD_NUMBER}"
ARCH="$(uname -m)"

log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33m!!\033[0m %s\n' "$*" >&2; }
fail() { printf '\n\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

rpm_sign_available() {
  command -v rpmsign >/dev/null 2>&1 && command -v rpm >/dev/null 2>&1
}

sign_rpm() {
  local rpm_file="$1"
  local rpmmacros_backup=""
  local restore_rpmmacros=0

  require_cmd rpmsign
  require_cmd rpm

  if [[ -f "$HOME/.rpmmacros" ]]; then
    rpmmacros_backup="$(mktemp)"
    cp "$HOME/.rpmmacros" "$rpmmacros_backup"
    restore_rpmmacros=1
  fi

  trap 'if [[ "${restore_rpmmacros:-0}" == "1" ]]; then cp "$rpmmacros_backup" "$HOME/.rpmmacros"; rm -f "$rpmmacros_backup"; fi' RETURN

  if ! grep -Eq '^%_signature[[:space:]]+gpg' "$HOME/.rpmmacros" 2>/dev/null || \
     ! grep -Eq '^%_gpg_name[[:space:]]+' "$HOME/.rpmmacros" 2>/dev/null; then
    {
      printf '%%_signature gpg\n'
      printf '%%_gpg_name %s\n' "$GPG_KEY_ID"
    } >> "$HOME/.rpmmacros"
  fi

  rpmsign --addsign "$rpm_file"
  rpm -Kv "$rpm_file"
}

log "Preflight checks"
require_cmd flutter
require_cmd docker
require_cmd shasum

[[ -f "$DART_DEFINES" ]] || fail "Missing $DART_DEFINES (copy dart_defines.example.json and fill in production values)"
[[ -x "$SCRIPTS_DIR/build-rpm.sh" ]] || fail "Missing or non-executable $SCRIPTS_DIR/build-rpm.sh"
[[ -f "$PACKAGING_DIR/rpm/lumenpass.spec" ]] || fail "Missing $PACKAGING_DIR/rpm/lumenpass.spec"

if ! docker info >/dev/null 2>&1; then
  fail "docker daemon is not reachable. Start docker or rerun with FORCE_HOST_BUILD=1."
fi

if [[ -n "$GPG_KEY_ID" ]]; then
  require_cmd gpg
  if ! gpg --list-secret-keys "$GPG_KEY_ID" >/dev/null 2>&1; then
    fail "GPG secret key not found in keyring: $GPG_KEY_ID"
  fi
  case "$RPM_SIGN_MODE" in
    auto)
      if rpm_sign_available; then
        RPM_SIGN_MODE="rpmsign"
      else
        warn "rpmsign/rpm not installed on host; falling back to RPM_SIGN_MODE=detached-only"
        RPM_SIGN_MODE="detached-only"
      fi
      ;;
    rpmsign) require_cmd rpmsign; require_cmd rpm ;;
    detached-only) ;;
    none) ;;
    *) fail "Unsupported RPM_SIGN_MODE: $RPM_SIGN_MODE (expected auto, rpmsign, detached-only, or none)" ;;
  esac
else
  warn "GPG_KEY_ID not set; the RPM will not be signed. Set GPG_KEY_ID=<key> to enable signing."
fi

log "Building release Linux bundle (v${VERSION})"
flutter clean
flutter pub get
flutter build linux --release --dart-define-from-file="$DART_DEFINES"

log "Packaging RPM"
rm -f "$DIST_DIR"/lumenpass-*.rpm \
      "$DIST_DIR"/lumenpass-*.rpm.asc \
      "$DIST_DIR"/lumenpass-*.rpm.sha256 2>/dev/null || true

RPM_RELEASE="$RPM_RELEASE" \
SKIP_FLUTTER_BUILD=1 \
FLUTTER_BUILD_MODE=release \
FEDORA_IMAGE="$FEDORA_IMAGE" \
FAIL_ON_RPMLINT="$FAIL_ON_RPMLINT" \
"$SCRIPTS_DIR/build-rpm.sh"

mkdir -p "$DIST_DIR"
shopt -s nullglob
RPM_ARTIFACTS=("$PACKAGING_DIR"/dist/lumenpass-${VERSION}-${RPM_RELEASE}*.rpm)
if [[ ${#RPM_ARTIFACTS[@]} -gt 0 ]]; then
  cp -f "${RPM_ARTIFACTS[@]}" "$DIST_DIR/"
fi
RPM_CANDIDATES=("$DIST_DIR"/lumenpass-${VERSION}-${RPM_RELEASE}*.rpm)
shopt -u nullglob
[[ ${#RPM_CANDIDATES[@]} -gt 0 ]] || fail "build-rpm.sh did not produce an RPM in $DIST_DIR"
RPM_FILE="${RPM_CANDIDATES[0]}"
echo "Artifact: $RPM_FILE"

log "Validating RPM metadata"
docker run --rm -v "$(pwd):/work" -w /work "$FEDORA_IMAGE" \
  bash -lc "set -e; rpm -qpi '$RPM_FILE' >/dev/null; rpm -qpl '$RPM_FILE' >/dev/null; rpm -qpR '$RPM_FILE' | grep -Ev '^(rpmlib|/bin/sh)'"

if [[ -n "$GPG_KEY_ID" ]]; then
  if [[ "$RPM_SIGN_MODE" == "none" ]]; then
    warn "RPM_SIGN_MODE=none — skipping RPM signing and detached signature"
  else
    case "$RPM_SIGN_MODE" in
      rpmsign)
        log "Signing RPM in-place with rpmsign (key: $GPG_KEY_ID)"
        sign_rpm "$RPM_FILE"
        ;;
      detached-only)
        warn "RPM_SIGN_MODE=detached-only — skipping embedded RPM signature"
        ;;
    esac

    if [[ "$CREATE_DETACHED_SIGNATURE" == "1" ]]; then
      log "Signing RPM with detached GPG signature (key: $GPG_KEY_ID)"
      rm -f "${RPM_FILE}.asc"
      gpg --batch --yes --armor --detach-sign \
          --local-user "$GPG_KEY_ID" \
          --output "${RPM_FILE}.asc" \
          "$RPM_FILE"
      gpg --verify "${RPM_FILE}.asc" "$RPM_FILE"
      echo "Signature: ${RPM_FILE}.asc"
    fi
  fi
fi

if [[ "$SKIP_DOCKER_TESTS" != "1" ]]; then
  log "Running install/uninstall smoke test in docker (${FEDORA_IMAGE})"
  docker run --rm -v "$(pwd):/work" -w /work "$FEDORA_IMAGE" \
    bash -lc "set -e; dnf install -y '/work/${RPM_FILE}' >/tmp/install.log; rpm -q lumenpass; test -x /usr/bin/lumenpass; test -x /opt/lumenpass/lumenpass; test -f /usr/share/applications/lumenpass.desktop; test -f /usr/share/metainfo/lumenpass.metainfo.xml; dnf remove -y lumenpass >/tmp/remove.log; ! rpm -q lumenpass >/dev/null 2>&1"
else
  warn "SKIP_DOCKER_TESTS=1 — skipping RPM install/uninstall smoke test"
fi

log "Generating SHA-256 checksum"
( cd "$(dirname "$RPM_FILE")" && shasum -a 256 "$(basename "$RPM_FILE")" | tee "$(basename "$RPM_FILE").sha256" )

log "Done"
echo "Artifact: $(pwd)/$RPM_FILE"
echo "Checksum: $(pwd)/${RPM_FILE}.sha256"
