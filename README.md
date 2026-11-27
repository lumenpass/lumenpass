# LumenPass

<p align="center">
  <img src="assets/lumenpass-dark-rounded.png" alt="LumenPass app icon" width="160" />
</p>

**Secure access, simplified.**

A free, open-source, local-first password manager built around the KeePass **KDBX** format — for desktops, phones, and browsers. Every feature is included at no cost: no account, no subscription, no feature gates, no item limits.

[Website](https://lumenpass.app) · [Download](https://github.com/lumenpass/lumenpass/releases) · [Source](https://github.com/lumenpass/lumenpass) · [Security policy](source-code/SECURITY.md) · [License](#license)

---

## Table of contents

- [What LumenPass is](#what-lumenpass-is)
- [Features](#features)
- [Repository layout](#repository-layout)
- [Getting started](#getting-started)
- [Architecture](#architecture)
- [Security model and threat scope](#security-model-and-threat-scope)
- [Contributing](#contributing)
- [License](#license)
- [Screenshots](#screenshots)

---

## What LumenPass is

LumenPass is a modern interface around a portable KeePass vault. Your data lives in a standard `.kdbx` file that you own and can open in other KeePass-compatible apps, keep on your own disk, or sync through storage you already trust.

- **Free and open source.** No paid tier, no trial, no upsell. The source is public and licensed permissively.
- **Local-first.** Opening, searching, editing, and generating credentials work offline. There is no LumenPass account and no hosted vault service.
- **Zero-knowledge by design.** Your master password never leaves your device; only encrypted data is written to disk or sync providers.
- **Portable forever.** Because the vault is a standard KDBX file, it outlives this app.
- **Cross-platform.** macOS, Windows, Linux, iOS, Android, and browser extensions for Chrome, Edge, Firefox, and Safari.

> LumenPass is a password manager handling highly sensitive data. Review the [security model](#security-model-and-threat-scope), keep independent backups, and evaluate the code before trusting it with your credentials.

---

## Features

**Everything below is available in the free build — there is no paid plan.**

### Vault items
- Logins and passwords, with a built-in cryptographically secure generator
- Passkeys (store and use passwordless credentials)
- TOTP / 2FA codes, generated inside the app
- Secure notes, recovery codes, and software licenses
- Credit cards, bank accounts, and identities for form filling
- SSH keys, API credentials, server entries, Wi-Fi passwords, passports, and documents

### Unlock and access
- Master password and/or key file unlock
- PIN unlock and biometric unlock (Face ID, Touch ID, Windows Hello, fingerprint)
- Unlock over the local bridge for browser AutoFill
- Configurable auto-lock timer (15 minutes to 24 hours) and automatic encrypted backups
- Clipboard auto-clear (30 seconds, 90 seconds, or never)
- Optional masking of full card numbers in item details
- Website matching by base domain or subdomain
- Menu-bar mode, start-at-login, and start-minimized options

### Organization and insight
- Unlimited vaults / databases
- Categories, tags, favorites, and trash with restore
- Full-text search and quick search overlay
- Password audit views: weak, reused/duplicate, and stale passwords

### Sync and integrations
- Google Drive, Dropbox, OneDrive
- WebDAV, SFTP, and S3-compatible storage — test the connection before saving
- SSH Agent integration for developers
- Browser extensions: Chrome, Edge, Firefox, Safari (desktop and iOS)
- Update check from the About pane (optional; requires `BACKEND_API_URL`)

### Import
Bring existing credentials in from 1Password (`.1pux`/CSV), Bitwarden, Dashlane, NordPass, Proton Pass, Enpass, RoboForm, Chrome, Apple Passwords, or generic CSV.

---

## Repository layout

```
.
├── assets/                     Repository brand assets used by this README
├── screenshots/                Desktop, mobile, and extension screenshots
├── LICENSE                     Apache License 2.0
└── source-code/
    ├── LICENSE, NOTICE         License and attribution for the source tree
    ├── SECURITY.md             Private vulnerability reporting
    ├── TRADEMARKS.md           Name and branding guidance for forks
    ├── apps/
    │   ├── desktop/            Flutter app — macOS, Windows, Linux
    │   ├── mobile/             Flutter app — iOS, Android
    │   └── README.md           Shared app-level notes
    ├── packages/
    │   └── lumenpass_core/     Shared Dart vault, crypto, and domain code
    ├── lumenpass-extension/    Manifest V3 browser extension (Chrome/Edge/Firefox)
    └── lumenpass-safari/       Safari Web Extension Xcode project
```

App-specific documentation: [`source-code/apps/README.md`](source-code/apps/README.md), [`apps/desktop/README.md`](source-code/apps/desktop/README.md), [`apps/mobile/README.md`](source-code/apps/mobile/README.md), [`lumenpass-extension/README.md`](source-code/lumenpass-extension/README.md).

---

## Getting started

### Prerequisites

- **Flutter 3.41+** (stable) with Dart 3.10+ — `flutter doctor` should be clean for your target platform
- Platform toolchains: Xcode (macOS/iOS), Visual Studio with C++ tools (Windows), or the Linux desktop build dependencies
- Node.js 20+ and npm, only if you are building the browser extension

### Build the desktop app

Run these from `source-code/apps/desktop`.

```bash
flutter pub get

# The vendored S3 client ships without generated sources; build them once.
(cd third_party/flutter_aws_s3_client && dart pub get && dart run build_runner build)
```

Then run or build your platform:

```bash
flutter run -d macos
flutter build macos --release
flutter build windows --release
flutter build linux --release
```

For a signed release — `.dmg`, MSIX, `.deb`, or AppImage — follow the packaging guides in `source-code/apps/desktop`: `BUILD_MACOS_DMG_RELEASE.MD`, `BUILD_WINDOWS_MSIX_RELEASE.MD`, and `BUILD_LINUX_DEB_RELEASE.MD`.

### Build the mobile app

Run these from `source-code/apps/mobile`.

```bash
flutter pub get
(cd third_party/flutter_aws_s3_client && dart pub get && dart run build_runner build)
flutter run                 # on a connected device or simulator
```

### Build the browser extension

Run these from `source-code/lumenpass-extension`.

```bash
npm install
npm run build          # Chrome / Edge  -> dist/
npm run build:firefox  # Firefox        -> dist-firefox/
npm run build:safari   # Safari         -> dist-safari/
```

Load `dist/` through your browser's "Load unpacked" developer flow. The extension talks only to a loopback service exposed by the desktop app at `127.0.0.1:19455`, authorized with a token shown in **Settings → Browser Extension**.

### Cloud provider credentials

Google Drive, Dropbox, and OneDrive are compile-time configurations, not bundled secrets. Copy the example file and fill in your own OAuth values:

```bash
cp dart_defines.example.json dart_defines.local.json
flutter run -d macos --dart-define-from-file=dart_defines.local.json
```

`dart_defines.local.json` and `dart_defines.prod.json` are git-ignored. Never commit real OAuth secrets or signing certificates.

`BACKEND_API_URL` powers the optional update check and support contact form. It is optional: leave it unset and those actions report that they are not configured. Production builds require an `https://` URL.

### Run the tests

```bash
cd source-code/packages/lumenpass_core && dart test
cd source-code/apps/desktop && flutter test
cd source-code/apps/mobile && flutter test
cd source-code/lumenpass-extension && npm test
```

---

## Architecture

| Layer | Location | Responsibility |
| --- | --- | --- |
| Shared core | `packages/lumenpass_core` | KDBX read/write, vault models, item classification, platform secret storage |
| Desktop | `apps/desktop` | Vault UI, local AutoFill bridge, SSH agent, tray, updater |
| Mobile | `apps/mobile` | Vault UI, iOS/Android AutoFill and passkey providers |
| Extension | `lumenpass-extension`, `lumenpass-safari` | Autofill UI that proxies to the desktop bridge |

The vault layer wraps the KDBX format through [`package:kdbx`](https://pub.dev/packages/kdbx) and Argon2 for KDBX 4 key derivation. Encrypted vault bytes move between the local file, backups, and any configured sync provider; nothing is sent to LumenPass servers.

**Authentication boundaries.** LumenPass has no application-account login. Authentication in the codebase exists only to (a) unlock a local vault, (b) connect to a storage provider you choose, or (c) authorize platform AutoFill. Those are not LumenPass account credentials.

---

## Security model and threat scope

Vault data is stored in the KeePass-compatible KDBX format, using the Dart `kdbx` library to open, create, and save encrypted databases. KDBX credentials are derived from the master password and/or key file.

This model protects against an attacker who obtains a copy of the encrypted vault from disk, backup, or cloud storage, provided the master password and any key file stay secret and strong.

LumenPass does **not** claim protection against a compromised local device or operating system. Once a vault is unlocked, entry values must be available to the app for search, display, copy, AutoFill, and sync, so decrypted secrets may exist in process memory as ordinary application values until the vault locks, references are cleared, and the runtime collects them. Malware, debuggers, memory dump tools, screen capture, or another user with control of the same machine or session are outside this threat model.

PIN and biometric unlock are convenience features for trusted devices. They rely on platform secure storage — Keychain, Keystore, or Windows-backed storage — to protect the saved unlock secret.

To report a vulnerability, follow [`source-code/SECURITY.md`](source-code/SECURITY.md). Please do not open a public issue for an unpatched flaw.

---

## Contributing

Issues and pull requests are welcome.

1. Open an issue describing the bug or proposal before starting non-trivial work.
2. Keep changes focused; match the existing structure and style.
3. Run the relevant analyzer and tests before opening a pull request.
4. Never include real vault files, credentials, tokens, or signing material in a commit, issue, or test fixture. Use synthetic data.

By submitting a contribution you agree it is licensed under the terms in [License](#license).

---

## License

LumenPass source code is licensed under the **[Apache License 2.0](LICENSE)**. See [`source-code/LICENSE`](source-code/LICENSE) and [`source-code/NOTICE`](source-code/NOTICE).

In plain terms, you may use, modify, and redistribute the code — including commercially and in closed-source products — provided you keep the license and attribution notices and state significant changes. Apache-2.0 also includes an explicit patent grant from contributors.

Third-party components keep their own licenses. See [`source-code/THIRD_PARTY_NOTICES.md`](source-code/THIRD_PARTY_NOTICES.md) for the current inventory and the one outstanding item that must be resolved before redistributing binaries.

Apache-2.0 grants no trademark rights. See [`source-code/TRADEMARKS.md`](source-code/TRADEMARKS.md) before publishing a fork.

> **Note on the KDBX dependency.** The desktop and mobile apps currently depend on `package:kdbx` 2.4.2, which upstream publishes under **GPL-3.0**. A binary that statically includes GPL-3.0 code must be distributed under GPL-3.0, which is incompatible with both Apache-2.0 and the Apple App Store terms. Tracking issue and migration path: [`source-code/THIRD_PARTY_NOTICES.md`](source-code/THIRD_PARTY_NOTICES.md).

---

## Screenshots

### Desktop

**Vault manager** — every vault on this Mac and in connected cloud storage, with the default vault pinned first.

<img src="screenshots/desktop/desktop-vault-manager.webp" alt="LumenPass desktop — vault manager showing local and Google Drive vaults" width="700" />

**Vault overview** — categories, tags, and quick access to TOTP codes, passkeys, and password audits.

<img src="screenshots/desktop/desktop-vault-overview.webp" alt="LumenPass desktop — vault overview with categories and quick access filters" width="700" />

**Vault list** — dense item list with inline username, site, and last-used timestamps.

<img src="screenshots/desktop/desktop-vault-list.webp" alt="LumenPass desktop — vault item list" width="700" />

**Quick search** — a floating search overlay with live matches; press Enter to search the whole vault.

<img src="screenshots/desktop/desktop-quick-search.webp" alt="LumenPass desktop — quick search overlay with live results" width="700" />

**Unlock** — master password or key-file unlock, with advanced options for hardware keys.

<img src="screenshots/desktop/desktop-unlock.webp" alt="LumenPass desktop — unlock screen for a Google Drive vault" width="700" />

**Add an item** — logins, secure notes, credit cards, identities, SSH keys, and bank accounts.

<img src="screenshots/desktop/desktop-add-item-types.webp" alt="LumenPass desktop — item type picker" width="700" />

**New login** — username, password, website, category, notes, TOTP, and attachments in one form.

<img src="screenshots/desktop/desktop-new-login.webp" alt="LumenPass desktop — new login form with 2FA and attachments" width="700" />

**Password generator** — secure random strings or memorable passphrases, with length and character controls.

<img src="screenshots/desktop/desktop-generator.webp" alt="LumenPass desktop — password generator" width="700" />

**Switch vault** — move between a cloud-synced vault and any local KDBX database.

<img src="screenshots/desktop/desktop-switch-vault.webp" alt="LumenPass desktop — vault switcher" width="700" />

**Categories** — organize items into your own categories.

<img src="screenshots/desktop/desktop-add-category.webp" alt="LumenPass desktop — add category dialog" width="700" />

**Storage destinations** — pick a folder on this Mac, or connect Google Drive, Dropbox, OneDrive, WebDAV, SFTP, or S3.

<img src="screenshots/desktop/desktop-storage-destinations.webp" alt="LumenPass desktop — storage destination chooser" width="700" />

**S3 setup** — first-class support for S3-compatible storage, with a connection test before saving.

<img src="screenshots/desktop/desktop-s3-setup.webp" alt="LumenPass desktop — Amazon S3 connection dialog" width="700" />

**Import** — bring credentials in from 1Password, Bitwarden, Proton Pass, NordPass, RoboForm, Enpass, Apple Passwords, Chrome, or Dashlane, parsed locally on your device.

<img src="screenshots/desktop/desktop-import-providers.webp" alt="LumenPass desktop — import provider picker" width="700" />

<img src="screenshots/desktop/desktop-import-upload.webp" alt="LumenPass desktop — drag and drop an export file for local parsing" width="700" />

**Settings** — general, security, advanced, and about panes. Auto-lock, clipboard clearing, card-number masking, and website matching are all configurable.

<img src="screenshots/desktop/desktop-settings-general.webp" alt="LumenPass desktop — general settings" width="700" />

<img src="screenshots/desktop/desktop-settings-security.webp" alt="LumenPass desktop — security settings with auto-lock and clipboard options" width="700" />

<img src="screenshots/desktop/desktop-settings-advanced.webp" alt="LumenPass desktop — advanced settings with SSH agent" width="700" />

<img src="screenshots/desktop/desktop-settings-about.webp" alt="LumenPass desktop — about pane showing version and license" width="700" />

### Mobile

<img src="screenshots/mobile/Screenshot%2001.png" alt="LumenPass mobile — unlock screen" width="180" /> <img src="screenshots/mobile/Screenshot%2002.png" alt="LumenPass mobile — vault list" width="180" /> <img src="screenshots/mobile/Screenshot%2003.png" alt="LumenPass mobile — login detail" width="180" /> <img src="screenshots/mobile/Screenshot%2006.png" alt="LumenPass mobile — TOTP codes" width="180" />

### Browser extension

<img src="screenshots/extension/ext-screenshot-1.png" alt="LumenPass browser extension — popup" width="320" /> <img src="screenshots/extension/ext-screenshot-2.png" alt="LumenPass browser extension — autofill" width="320" /> <img src="screenshots/extension/ext-screenshot-3.png" alt="LumenPass browser extension — passkey sign-in" width="320" />

---

**LumenPass — Secure access, simplified.**

[Get LumenPass](https://github.com/lumenpass/lumenpass/releases) · [lumenpass.app](https://lumenpass.app) · [Report a vulnerability](source-code/SECURITY.md) · [Apache-2.0](LICENSE)
