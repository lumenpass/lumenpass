# Build & Release LumenPass Desktop (macOS DMG)

End-to-end guide for producing a signed, notarized, universal `.dmg` of LumenPass desktop and uploading it for public download.

All commands assume you run them from this directory:

```bash
cd "/Users/trantuan/Works/Tran/LumenPass Workspaces/lumenpass/apps/desktop"
```

---

## 0. Architecture: Intel vs Apple Silicon

`flutter build macos --release` produces a **universal binary** (`x86_64` + `arm64`) by default, so a single `.app` and a single `.dmg` work natively on both Intel and Apple Silicon Macs. You do **not** need to publish separate Intel/ARM downloads.

Verify after building:

```bash
lipo -archs build/macos/Build/Products/Release/lumenpass.app/Contents/MacOS/lumenpass
# Expected output: x86_64 arm64
```

---

## 1. Prerequisites (one-time setup)

### 1.1 Apple Developer account

- Active **Apple Developer Program** membership ($99/year).
- A **Developer ID Application** certificate installed in your login keychain. Verify with:

  ```bash
  security find-identity -v -p codesigning
  ```

  You should see:

  ```
  Developer ID Application: Tran Tuan (R3YX83R9RQ)
  ```

  Team ID `R3YX83R9RQ` matches the `DEVELOPMENT_TEAM` set in `macos/Runner/Configs/AppInfo.xcconfig`.

### 1.2 Tools

```bash
# Flutter (already installed)
flutter --version

# create-dmg for building styled DMGs
brew install create-dmg
```

### 1.3 Notarization credentials (one-time)

Create an **app-specific password** at https://appleid.apple.com → Sign-In and Security → App-Specific Passwords.

Store it in a `notarytool` keychain profile so you don't have to pass credentials every time:

```bash
xcrun notarytool store-credentials "AC_NOTARY" \
  --apple-id "YOUR_APPLE_ID@example.com" \
  --team-id "R3YX83R9RQ" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

After this, you can run `xcrun notarytool ... --keychain-profile "AC_NOTARY"`.

---

## 2. Build the release `.app`

> **Important:** The desktop app embeds the Safari Web Extension at
> `LumenPass.app/Contents/PlugIns/SafariExtension.appex`. Its `Resources/`
> folder must contain a valid `manifest.json` and built JS/CSS, otherwise
> launchd will refuse to spawn the host app on a clean machine
> (`RBSRequestErrorDomain Code=5 / Launchd job spawn failed`). The host app
> works on your dev machine only because PlugInKit cached a registration
> from a previous Xcode debug run.
>
> Always build and sync the extension before building the desktop app:
>
> ```bash
> cd ../../lumenpass-extension
> npm ci    # first time only
> npm run build:desktop-safari    # builds dist-safari/ and copies to apps/desktop/macos/SafariExtension/Resources/
> cd -
> ```
>
> The `release-macos.sh` one-shot script does this for you and fails fast if
> the manifest is missing.

```bash
flutter clean
flutter pub get

flutter build macos --release \
  --dart-define-from-file=dart_defines.prod.json
```

Output:

```
build/macos/Build/Products/Release/lumenpass.app
```

Quick sanity checks:

```bash
# Verify universal binary
lipo -archs build/macos/Build/Products/Release/lumenpass.app/Contents/MacOS/lumenpass

# Verify the Safari appex actually has its resources
ls build/macos/Build/Products/Release/lumenpass.app/Contents/PlugIns/SafariExtension.appex/Contents/Resources/manifest.json

# Run the app locally to confirm it launches
open build/macos/Build/Products/Release/lumenpass.app
```

---

## 3. Code-sign the `.app`

Sign with the hardened runtime and embed the release entitlements (required so `flutter_secure_storage`, `google_sign_in`, network, etc. continue to work after `--deep` re-signing):

```bash
codesign --deep --force --options runtime --timestamp \
  --sign "Developer ID Application: Tran Tuan (R3YX83R9RQ)" \
  --entitlements macos/Runner/Release.entitlements \
  build/macos/Build/Products/Release/lumenpass.app
```

Verify:

```bash
codesign --verify --deep --strict --verbose=2 \
  build/macos/Build/Products/Release/lumenpass.app
```

`spctl` will still say "rejected / Unnotarized" at this stage — that is expected and resolved by step 6.

---

## 4. Build the DMG

The version is read from `pubspec.yaml`. Currently `1.0.1`.

```bash
VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)
DMG="LumenPass-${VERSION}.dmg"

rm -f "$DMG"

create-dmg \
  --volname "LumenPass ${VERSION}" \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "lumenpass.app" 150 200 \
  --app-drop-link 450 200 \
  --hide-extension "lumenpass.app" \
  "$DMG" \
  "build/macos/Build/Products/Release/lumenpass.app"
```

Plain `hdiutil` fallback (no Homebrew dependency):

```bash
hdiutil create -volname "LumenPass" \
  -srcfolder build/macos/Build/Products/Release/lumenpass.app \
  -ov -format UDZO "$DMG"
```

---

## 5. Sign the DMG

```bash
codesign --force --timestamp \
  --sign "Developer ID Application: Tran Tuan (R3YX83R9RQ)" \
  "$DMG"
```

---

## 6. Notarize and staple

Submit to Apple's notary service and wait for the result:

```bash
xcrun notarytool submit "$DMG" \
  --keychain-profile "AC_NOTARY" \
  --wait
```

When status is `Accepted`, staple the ticket so Gatekeeper accepts it offline:

```bash
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
```

If notarization fails, fetch the log with the submission ID returned above:

```bash
xcrun notarytool log <submission-id> --keychain-profile "AC_NOTARY"
```

Common issues: missing hardened runtime, missing timestamp, unsigned helper binaries inside the bundle.

---

## 7. Upload to your server

Pick whichever matches your hosting:

```bash
# SCP
scp "$DMG" user@yourserver:/var/www/downloads/

# rsync (resumable)
rsync -avzP "$DMG" user@yourserver:/var/www/downloads/

# AWS S3
aws s3 cp "$DMG" s3://your-bucket/downloads/ --acl public-read

# Cloudflare R2 / Backblaze B2 / etc. — use the matching CLI
```

Public URL example:

```
https://yourdomain.com/downloads/LumenPass-1.0.1.dmg
```

Recommended additions:
- Publish a SHA-256 checksum next to the DMG so users can verify integrity:

  ```bash
  shasum -a 256 "$DMG" > "${DMG}.sha256"
  ```

- Keep an unversioned `LumenPass-latest.dmg` symlink/redirect for "download latest" links.

---

## 8. One-shot release script

You can paste the following into a file like `release-macos.sh` (or fold it into `flutter-build-prod.sh`) and run `bash release-macos.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

SIGN_ID="Developer ID Application: Tran Tuan (R3YX83R9RQ)"
NOTARY_PROFILE="AC_NOTARY"
APP="build/macos/Build/Products/Release/lumenpass.app"
VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)
DMG="LumenPass-${VERSION}.dmg"

echo "==> Building release .app (v${VERSION})"
flutter clean
flutter pub get
flutter build macos --release --dart-define-from-file=dart_defines.prod.json

echo "==> Verifying universal binary"
lipo -archs "$APP/Contents/MacOS/lumenpass"

echo "==> Code-signing .app"
codesign --deep --force --options runtime --timestamp \
  --sign "$SIGN_ID" \
  --entitlements macos/Runner/Release.entitlements \
  "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Building DMG"
rm -f "$DMG"
create-dmg \
  --volname "LumenPass ${VERSION}" \
  --window-size 600 400 --icon-size 100 \
  --icon "lumenpass.app" 150 200 \
  --app-drop-link 450 200 \
  --hide-extension "lumenpass.app" \
  "$DMG" "$APP"

echo "==> Signing DMG"
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"

echo "==> Notarizing"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> Generating checksum"
shasum -a 256 "$DMG" > "${DMG}.sha256"

echo "Done: $DMG"
```

---

## 9. Verification on a clean Mac

Before announcing the release, test on a Mac that has never run LumenPass:

1. Download the DMG from the public URL (do not copy it locally — Gatekeeper treats local copies differently).
2. Open the DMG, drag `lumenpass.app` to `/Applications`.
3. Launch from `/Applications`. It should open with no Gatekeeper warning.
4. Sign in (Google), unlock a vault, edit an item — verify keychain + cloud sync still work end-to-end.

If Gatekeeper says "damaged / cannot be opened", the most common causes are:
- DMG was not notarized or stapler was not run.
- `.app` was modified after signing (e.g., re-bundled without re-signing).
- Quarantine attribute issues — re-download fresh; do not unzip with third-party tools.

---

## 10. Reference: where each value comes from

| Value | Source |
|---|---|
| Bundle ID `com.tranit.lumenpass.macos` | `macos/Runner/Configs/AppInfo.xcconfig` |
| Team ID `R3YX83R9RQ` | `macos/Runner/Configs/AppInfo.xcconfig` (`DEVELOPMENT_TEAM`) |
| Signing identity | `security find-identity -v -p codesigning` |
| App version | `pubspec.yaml` (`version:`) |
| Entitlements | `macos/Runner/Release.entitlements` |
| Dart defines | `dart_defines.prod.json` |
