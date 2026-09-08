# LumenPass

LumenPass is an open-source, cross-platform password manager for KeePass-compatible KDBX vaults. The repository contains desktop applications for macOS, Windows, and Linux; mobile applications for iOS and Android; shared Dart packages; and browser-extension integrations.

LumenPass is local-first and does not require a LumenPass account or subscription. Features that were previously restricted—including multiple vaults, PIN and biometric unlock, password auditing, SSH Agent support, vault switching, and supported cloud providers—are available without a paid plan.

## Repository layout

- `apps/desktop` — Flutter desktop application for macOS, Windows, and Linux
- `apps/mobile` — Flutter mobile application for iOS and Android
- `packages/lumenpass_core` — shared vault and domain code
- `lumenpass-extension` — browser extension
- `lumenpass-safari` — Safari integration

## Authentication boundaries

LumenPass has no application-account login flow. Authentication that remains in the project serves one of these purposes:

- unlocking a local encrypted vault with a master password, key file, PIN, or biometrics;
- connecting directly to a user-selected cloud provider such as Google Drive, Dropbox, or OneDrive;
- authenticating WebDAV, SFTP, or S3 storage selected by the user;
- operating platform AutoFill and passkey integrations.

Cloud-provider credentials and vault secrets are stored using platform security facilities. They are not LumenPass account credentials.

## Getting started

Install Flutter and the platform toolchain required by your target, then fetch dependencies from the relevant app directory.

Desktop:

```bash
cd apps/desktop
flutter pub get
flutter run -d macos
```

Mobile:

```bash
cd apps/mobile
flutter pub get
flutter run
```

Cloud integrations require provider-specific OAuth or storage configuration. Start from each app's `dart_defines.example.json`; keep local and production values out of source control.

Additional app-specific guidance is available in [`apps/README.md`](apps/README.md), [`apps/desktop/README.md`](apps/desktop/README.md), and [`apps/mobile/README.md`](apps/mobile/README.md).

## Security

LumenPass handles sensitive local data. Do not report suspected vulnerabilities in a public issue. Follow [`SECURITY.md`](SECURITY.md) to report them privately.

The project is provided without warranty. Review the code, understand your storage and backup configuration, and keep independent backups of important vaults.

## License

LumenPass source code is licensed under the [Mozilla Public License 2.0](LICENSE), except for third-party files that carry their own license notices. MPL-2.0 requires distributed modifications to covered source files to remain available under MPL-2.0 while allowing those files to be combined with separately licensed larger works.

The license does not grant rights to use LumenPass names, logos, signing identities, or store listings to imply endorsement or an official release. See [`TRADEMARKS.md`](TRADEMARKS.md).

Official source for a distributed LumenPass release should be made available from this repository or the corresponding release source archive, as required by MPL-2.0.
