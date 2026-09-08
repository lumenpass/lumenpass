# LumenPass Mobile

LumenPass Mobile is the Flutter application for iOS and Android. It works without a LumenPass account or subscription and supports local and user-configured cloud-backed KeePass-compatible vaults.

Local master-password, PIN, and biometric prompts authenticate encrypted vaults. Google Drive, Dropbox, OneDrive, WebDAV, SFTP, and S3 authentication connects directly to storage selected by the user; it is not an application login.

## Getting started

```bash
flutter pub get
cp dart_defines.example.json dart_defines.local.json
flutter run --dart-define-from-file=dart_defines.local.json
```

Keep `dart_defines.local.json` and production credentials out of source control. Use provider-specific credentials for your own builds rather than credentials associated with official LumenPass releases.

## Validation

```bash
dart analyze lib test
flutter test
flutter build apk --debug --dart-define-from-file=dart_defines.example.json
flutter build ios --debug --no-codesign --dart-define-from-file=dart_defines.example.json
```

Platform toolchains and signing configuration are required for device and release builds.

## License

Source code is licensed under the [Mozilla Public License 2.0](../../LICENSE), except for third-party files carrying their own license notices. The code license does not grant permission to present modified builds as official LumenPass releases; see [`TRADEMARKS.md`](../../TRADEMARKS.md).
