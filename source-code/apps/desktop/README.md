# LumenPass Desktop

LumenPass Desktop is accountless and free to use. Local vault authentication and optional cloud-provider authentication remain because they protect vaults or connect storage chosen by the user.

Source code is licensed under the [Mozilla Public License 2.0](../../LICENSE), except for third-party files carrying their own license notices.

## Local secrets / OAuth keys (dart-defines)

Some integrations (Dropbox, Google Drive) require build-time configuration via `--dart-define` / `--dart-define-from-file`.

- Copy `dart_defines.example.json` → `dart_defines.local.json`
- Fill in values in `dart_defines.local.json` (**this file is gitignored**)

### Run (macOS)

```bash
flutter run -d macos --dart-define-from-file=dart_defines.local.json
```

### Build (release)

```bash
flutter build macos --release --dart-define-from-file=dart_defines.local.json
```

### Run (Linux)

```bash
flutter run -d linux --dart-define-from-file=dart_defines.local.json
```

### Build a Debian .deb (Linux)

```bash
./linux/scripts/build-deb.sh
./linux/scripts/validate-deb.sh
./linux/scripts/test-deb.sh
```

See [`BUILD_LINUX_DEB_RELEASE.MD`](BUILD_LINUX_DEB_RELEASE.MD) for the full Linux packaging workflow, dependencies, and CI integration notes.

