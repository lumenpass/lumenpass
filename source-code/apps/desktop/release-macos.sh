#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

SIGN_ID="${SIGN_ID:-Developer ID Application: Tran Tuan (R3YX83R9RQ)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"
APP_NAME="LumenPass.app"
APP="build/macos/Build/Products/Release/${APP_NAME}"
ENTITLEMENTS="macos/Runner/Release.entitlements"
DART_DEFINES="dart_defines.prod.json"
EXTENSION_DIR="../../lumenpass-extension"
SAFARI_RESOURCES="macos/SafariExtension/Resources"

VERSION_RAW="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
VERSION="$(echo "$VERSION_RAW" | cut -d'+' -f1)"
PUBSPEC_BUILD="$(echo "$VERSION_RAW" | cut -d'+' -f2)"
DMG_DIR="releases"
DMG_BASENAME="LumenPass-${VERSION}.dmg"
DMG="$DMG_DIR/$DMG_BASENAME"

log() { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
fail() { printf '\n\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

log "Preflight checks"
require_cmd flutter
require_cmd codesign
require_cmd xcrun
require_cmd lipo
require_cmd shasum
require_cmd create-dmg
require_cmd npm

[[ -f "$DART_DEFINES" ]] || fail "Missing $DART_DEFINES"
[[ -f "$ENTITLEMENTS" ]] || fail "Missing $ENTITLEMENTS"
[[ -d "$EXTENSION_DIR" ]] || fail "Missing extension source dir: $EXTENSION_DIR"

if ! security find-identity -v -p codesigning | grep -q "$SIGN_ID"; then
  fail "Signing identity not found in keychain: $SIGN_ID"
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  fail "notarytool keychain profile '$NOTARY_PROFILE' not configured. Run: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <id> --team-id R3YX83R9RQ --password <app-specific>"
fi

log "Building Safari Web Extension and syncing into desktop target"
(
  cd "$EXTENSION_DIR"
  if [[ ! -d node_modules ]]; then
    log "Installing extension dependencies (npm ci)"
    npm ci
  fi
  npm run build:desktop-safari
)

if [[ ! -f "$SAFARI_RESOURCES/manifest.json" ]]; then
  fail "Safari extension Resources are empty after sync. Expected $SAFARI_RESOURCES/manifest.json. The .appex must contain a valid manifest or launchd will refuse to spawn the host app on clean machines."
fi
echo "Safari Resources OK: $(ls "$SAFARI_RESOURCES" | tr '\n' ' ')"

log "Building release .app (v${VERSION})"
flutter clean
flutter pub get
flutter build macos --release --dart-define-from-file="$DART_DEFINES"

[[ -d "$APP" ]] || fail "Build did not produce $APP"

APPEX="$APP/Contents/PlugIns/SafariExtension.appex"
if [[ -d "$APPEX" ]]; then
  if [[ ! -f "$APPEX/Contents/Resources/manifest.json" ]]; then
    fail "SafariExtension.appex was embedded without a manifest.json. Launchd will refuse to spawn the host app on clean machines."
  fi
  echo "SafariExtension.appex OK with manifest.json"

  log "Verifying SafariExtension.appex version matches pubspec.yaml"
  APPEX_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APPEX/Contents/Info.plist" 2>/dev/null || true)"
  APPEX_BUILD="$(plutil -extract CFBundleVersion raw -o - "$APPEX/Contents/Info.plist" 2>/dev/null || true)"
  EXPECTED_BUILD="${PUBSPEC_BUILD:-1}"
  echo "  pubspec.yaml:   ${VERSION_RAW}"
  echo "  .appex version: ${APPEX_VERSION:-<missing>} (build ${APPEX_BUILD:-<missing>})"
  if [[ "$APPEX_VERSION" != "$VERSION" ]]; then
    fail "SafariExtension.appex CFBundleShortVersionString ($APPEX_VERSION) does not match pubspec.yaml ($VERSION). Check that MARKETING_VERSION is driven by \$(FLUTTER_BUILD_NAME) in Runner.xcodeproj for the SafariExtension target."
  fi
  if [[ "$APPEX_BUILD" != "$EXPECTED_BUILD" ]]; then
    fail "SafariExtension.appex CFBundleVersion ($APPEX_BUILD) does not match pubspec.yaml build ($EXPECTED_BUILD). Check that CURRENT_PROJECT_VERSION is driven by \$(FLUTTER_BUILD_NUMBER) in Runner.xcodeproj for the SafariExtension target."
  fi
fi

log "Verifying universal binary"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/LumenPass")"
echo "Architectures: $ARCHS"
[[ "$ARCHS" == *"x86_64"* && "$ARCHS" == *"arm64"* ]] || fail "Binary is not universal (got: $ARCHS)"

log "Code-signing .app with hardened runtime"
codesign --deep --force --options runtime --timestamp \
  --sign "$SIGN_ID" \
  --entitlements "$ENTITLEMENTS" \
  "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

log "Building DMG: $DMG"
mkdir -p "$DMG_DIR"
rm -f "$DMG" "$DMG_BASENAME" "${DMG}.sha256" "${DMG_BASENAME}.sha256"
create-dmg \
  --volname "LumenPass ${VERSION}" \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "${APP_NAME}" 150 200 \
  --app-drop-link 450 200 \
  --hide-extension "${APP_NAME}" \
  "$DMG" \
  "$APP"

log "Signing DMG"
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"

log "Submitting to Apple notary service (this can take a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

log "Stapling notarization ticket"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

log "Verifying with Gatekeeper"
spctl --assess --type open --context context:primary-signature --verbose "$DMG" || true

log "Generating SHA-256 checksum"
(shasum -a 256 "$DMG" | tee "${DMG}.sha256")

log "Done"
echo "Artifact: $(pwd)/$DMG"
echo "Checksum: $(pwd)/${DMG}.sha256"
