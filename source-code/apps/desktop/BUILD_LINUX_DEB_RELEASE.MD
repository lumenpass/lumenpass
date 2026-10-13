# Build & Release: Linux .deb

This document describes how to build, validate, install, and test the
Debian (`.deb`) package for the LumenPass desktop application.

## 1. Layout

All Linux-specific assets live under `linux/`:

```
linux/
├── CMakeLists.txt            # Top-level Linux CMake project (mirrors windows/)
├── flutter/                  # Flutter Linux engine glue (managed by the tool)
│   ├── CMakeLists.txt
│   ├── generated_plugin_registrant.cc
│   ├── generated_plugin_registrant.h
│   └── generated_plugins.cmake
├── runner/                   # GTK application entry point
│   ├── CMakeLists.txt        # (auto-discovered via add_subdirectory)
│   ├── main.cc
│   ├── my_application.cc
│   └── my_application.h
├── packaging/                # Everything required to ship a .deb
│   ├── debian/               # Standard debian/ tree (control, rules, etc.)
│   ├── assets/               # Desktop entry, icons, AppStream metadata
│   ├── staging/              # Populated by build-deb.sh; .gitignored
│   └── dist/                 # Output .deb files; .gitignored
└── scripts/
    ├── build-deb.sh          # Produces a .deb
    ├── validate-deb.sh       # Runs lintian + structural checks
    └── test-deb.sh           # Install / uninstall flow on host or docker
```

## 2. Build host requirements

Tested on Ubuntu 22.04 LTS, Ubuntu 24.04 LTS, and Debian 12 (Bookworm).

### Toolchain

```bash
sudo apt-get update
sudo apt-get install -y \
  curl git unzip xz-utils zip libglu1-mesa \
  cmake ninja-build clang pkg-config \
  libgtk-3-dev liblzma-dev libsecret-1-dev libstdc++-12-dev \
  libayatana-appindicator3-dev libjsoncpp-dev \
  dpkg-dev debhelper fakeroot lintian \
  desktop-file-utils appstream \
  imagemagick
```

For the default in-package signing mode, install `dpkg-sig` as well.
Some Ubuntu/Debian repositories do not ship it; in that case install it
from your distro backports, a maintained package mirror, or run
`release-deb.sh` inside a container image that includes it.

### Flutter

Install Flutter `>=3.19.0` (matches `pubspec.yaml`). The
`flutter` binary must be on `PATH`. Verify with:

```bash
flutter doctor -v
flutter config --enable-linux-desktop
```

### Optional (for `test-deb.sh --mode docker`)

```bash
sudo apt-get install -y docker.io
sudo usermod -aG docker "$USER"   # log out / back in afterwards
```

## 3. One-shot release: `release-deb.sh`

The recommended way to cut a public release is the orchestrator
`apps/desktop/release-deb.sh`. It is the Linux mirror of
`release-macos.sh` and chains the lower-level scripts described in §4
into a single, fail-fast pipeline:

1. Preflight tooling and packaging-tree checks.
2. Cross-checks `version:` in `pubspec.yaml` against the top entry of
   `linux/packaging/debian/changelog` and refuses to release on
   mismatch.
3. `flutter clean` → `flutter pub get` →
   `flutter build linux --release --dart-define-from-file=dart_defines.prod.json`.
4. Wipes `linux/packaging/dist/` and runs `build-deb.sh` with
   `SKIP_FLUTTER_BUILD=1` so the freshly-built bundle is reused
   (the helper script itself does not pass `--dart-define-from-file`).
5. Runs `validate-deb.sh` against the produced `.deb`.
6. When `GPG_KEY_ID` is set, signs the `.deb` in-place with `dpkg-sig`
   by default, then optionally produces a detached GPG signature
   (`<file>.deb.asc`) for download-page verification.
7. Optionally runs `test-deb.sh --mode docker` against the default
   distro matrix (Ubuntu 22.04, Ubuntu 24.04, Debian 12).
8. Writes a `<file>.deb.sha256` checksum next to the artifact.

### Usage

```bash
# release host with signing and the full docker test matrix
GPG_KEY_ID=ABCDEF1234567890 ./release-deb.sh

# fast local dry-run: no signing, no docker
SKIP_DOCKER_TESTS=1 ./release-deb.sh

# narrow the docker matrix
GPG_KEY_ID=ABCDEF1234567890 \
DOCKER_TEST_TARGETS=ubuntu:24.04 \
./release-deb.sh
```

### Environment knobs

| Variable                    | Default                               | Purpose                                                                                          |
| --------------------------- | ------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `GPG_KEY_ID`                | _unset_                               | GPG secret key id used for `dpkg-sig` and optional detached `.asc` signing. When unset the build is left unsigned and a warning is printed. |
| `DEB_SIGN_MODE`             | `dpkg-sig`                            | Signing mode when `GPG_KEY_ID` is set. Use `dpkg-sig` for in-package signing, `detached-only` for only `<file>.deb.asc`, or `none` to skip signing. |
| `CREATE_DETACHED_SIGNATURE` | `1`                                   | Set to `0` to skip the extra `<file>.deb.asc` signature after `dpkg-sig`.                         |
| `SKIP_DOCKER_TESTS`         | `0`                                   | Set to `1` to skip the docker install / uninstall matrix (useful during local development).      |
| `DOCKER_TEST_TARGETS`       | `ubuntu:22.04,ubuntu:24.04,debian:12` | Comma-separated list passed to `test-deb.sh --targets`.                                          |

### Signing model

By default, when `GPG_KEY_ID` is set, `release-deb.sh` signs the
package twice:

1. **In-package `dpkg-sig` signature** — `dpkg-sig --sign builder -k
   "$GPG_KEY_ID" <file>.deb`. This embeds a signature record inside the
   `.deb` archive itself and verifies it with `dpkg-sig --verify`.
2. **Detached GPG signature** — `gpg --detach-sign --armor`, producing
   `<file>.deb.asc` next to the final `.deb`. This is useful for
   download pages because users can verify it with stock `gpg`.

Install `dpkg-sig` on the release host before using the default signing
mode. If your distro does not ship it in apt, install it from your distro
backports, a maintained package mirror, or run the release in a container
that has `dpkg-sig` available.

Verification commands:

```bash
# verify in-package signature
dpkg-sig --verify lumenpass_1.0.3-1_amd64.deb

# verify detached signature
gpg --verify lumenpass_1.0.3-1_amd64.deb.asc lumenpass_1.0.3-1_amd64.deb
```

When you are ready to sign:

```bash
gpg --full-generate-key                                # one-time
gpg --list-secret-keys --keyid-format LONG             # copy the long key id
export GPG_KEY_ID=ABCDEF1234567890ABCDEF
gpg --armor --export "$GPG_KEY_ID" > LumenPass-release.pub.asc
# publish LumenPass-release.pub.asc on your download page
./release-deb.sh
```

### Outputs

After a successful run, `linux/packaging/dist/` contains:

```
lumenpass_<VERSION>-1_<ARCH>.deb
lumenpass_<VERSION>-1_<ARCH>.deb.sha256
lumenpass_<VERSION>-1_<ARCH>.deb.asc          # only when GPG_KEY_ID is set
lumenpass_<VERSION>-1_<ARCH>.buildinfo
lumenpass_<VERSION>-1_<ARCH>.changes
```

Architecture is taken from `dpkg --print-architecture` (currently
`amd64` or `arm64`). To build for a different architecture, run the
script inside a container or under QEMU/binfmt for that arch.

## 4. Lower-level: `build-deb.sh` directly

If you only want a build without signing, validation, docker matrix,
and checksum, invoke the underlying script:

```bash
./linux/scripts/build-deb.sh
```

Environment knobs (already documented inside the script):

| Variable               | Default   | Purpose                                        |
| ---------------------- | --------- | ---------------------------------------------- |
| `FLUTTER_BUILD_MODE`   | `release` | Set to `profile` or `debug` for non-release.   |
| `SKIP_FLUTTER_BUILD`   | `0`       | Skip the `flutter build linux` step.           |

> Note: `build-deb.sh` does **not** apply
> `--dart-define-from-file=dart_defines.prod.json`. If your release
> requires production dart-defines, build with
> `flutter build linux --release --dart-define-from-file=...` first
> and then call `SKIP_FLUTTER_BUILD=1 ./linux/scripts/build-deb.sh`.
> `release-deb.sh` does this for you automatically.

## 5. Package layout inside the .deb

```
/opt/lumenpass/
  lumenpass                  # main binary
  data/                      # icudtl.dat + flutter_assets/
  lib/                       # libflutter_linux_gtk.so + plugins
/usr/bin/lumenpass           # wrapper that exec's /opt/lumenpass/lumenpass
/usr/share/applications/lumenpass.desktop
/usr/share/metainfo/studio.trantech.lumenpass.metainfo.xml (named lumenpass.metainfo.xml)
/usr/share/icons/hicolor/{16,32,48,64,128,256,512}x*/apps/lumenpass.png
```

The choice of `/opt/lumenpass` follows the FHS recommendation for
self-contained third-party application bundles. The
`debian/lintian-overrides` file silences the corresponding policy notice.

## 6. Validation

```bash
./linux/scripts/validate-deb.sh
```

This runs:

1. `dpkg-deb --info` and `--contents` for structural sanity.
2. A check that all required paths are present in the archive.
3. `desktop-file-validate` against the installed `.desktop` file.
4. `appstreamcli validate --pedantic` against the AppStream metadata.
5. `lintian --info --display-info --pedantic` against the package.

Any errors from `lintian` (severity `E:`) cause the script to exit
non-zero, suitable for CI gating.

## 7. Install / uninstall test workflow

### Host install (mutates `/opt` and `/usr`)

```bash
./linux/scripts/test-deb.sh --mode native
```

### Docker matrix (recommended)

Default matrix: `ubuntu:22.04`, `ubuntu:24.04`, `debian:12`.

```bash
./linux/scripts/test-deb.sh                                   # all defaults
./linux/scripts/test-deb.sh --targets ubuntu:24.04,debian:12  # subset
```

Each container performs:

1. `apt-get install -y /tmp/<file>.deb` (resolves all declared `Depends:`).
2. Verifies that `/opt/lumenpass/lumenpass`, `/usr/bin/lumenpass`,
   `lumenpass.desktop`, and the AppStream metadata are present.
3. Runs `desktop-file-validate`.
4. Runs `apt-get purge -y lumenpass` and asserts the binary is gone.

A non-zero exit in any container fails the whole run.

## 8. CI integration sketch

```yaml
# .github/workflows/linux-deb.yml (sketch)
jobs:
  deb:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - name: Install build deps
        run: |
          sudo apt-get update
          sudo apt-get install -y cmake ninja-build clang pkg-config \
            libgtk-3-dev liblzma-dev libsecret-1-dev \
            libayatana-appindicator3-dev libjsoncpp-dev \
            dpkg-dev debhelper fakeroot lintian \
            desktop-file-utils appstream imagemagick
      - name: Import release GPG key
        env:
          GPG_PRIVATE_KEY: ${{ secrets.LUMENPASS_GPG_PRIVATE_KEY }}
        run: |
          echo "$GPG_PRIVATE_KEY" | gpg --batch --import
      - name: Provision dart_defines.prod.json
        env:
          DART_DEFINES_PROD: ${{ secrets.DART_DEFINES_PROD }}
        run: |
          printf '%s' "$DART_DEFINES_PROD" \
            > apps/desktop/dart_defines.prod.json
      - name: Build, validate, sign, test, checksum
        env:
          GPG_KEY_ID: ${{ secrets.LUMENPASS_GPG_KEY_ID }}
        working-directory: apps/desktop
        run: ./release-deb.sh
      - uses: actions/upload-artifact@v4
        with:
          name: lumenpass-deb
          path: |
            apps/desktop/linux/packaging/dist/*.deb
            apps/desktop/linux/packaging/dist/*.deb.asc
            apps/desktop/linux/packaging/dist/*.deb.sha256
```

The lower-level `build-deb.sh` / `validate-deb.sh` / `test-deb.sh`
calls remain available if a job needs to run only one step.

## 9. Maintenance checklist

When bumping the application version:

1. Update `version:` in `pubspec.yaml`.
2. Prepend a new entry to `linux/packaging/debian/changelog`. Use
   `dch -i` if `devscripts` is installed, or edit by hand and bump the
   `lumenpass (X.Y.Z-1)` header. The two values must match — `release-deb.sh`
   refuses to release on mismatch.
3. Add a new `<release>` block to
   `linux/packaging/assets/lumenpass.metainfo.xml`.
4. Re-run `./release-deb.sh` (or the lower-level
   `./linux/scripts/build-deb.sh && ./linux/scripts/validate-deb.sh`).

When adding native dependencies (a new Flutter plugin that pulls in a
shared library):

1. Add the development package to `Build-Depends` in
   `linux/packaging/debian/control`.
2. Add the runtime package to `Depends`.
3. Re-run `validate-deb.sh`; lintian will flag missing `${shlibs:Depends}`
   entries if anything is wrong.

## 10. Snap-installed Flutter linker workaround

When Flutter is installed via the Ubuntu/Debian `snap` package (the
default on recent Ubuntu releases), `flutter build linux` invokes a
`clang`/`ld` that is shipped *inside* the snap's confined runtime
(`/snap/flutter/current/usr/bin/`). The snap bundles its own GLib,
which is older than the system GLib that ships with Ubuntu 24.04+.

Several host shared libraries pulled in transitively by our plugins
(notably `libsecret-1.so.0` for `flutter_secure_storage` and
`libayatana-ido3-0.4.so.0` for `tray_manager`) reference newer GLib
symbols such as `g_task_set_static_name`, `g_once_init_enter_pointer`,
`g_string_free_and_steal`, and `g_time_zone_new_identifier`. The
snap's bundled `ld` cannot resolve those symbols at link time, even
though they resolve correctly at runtime against the system loader,
which produces:

```
/snap/flutter/current/usr/bin/ld: /lib/x86_64-linux-gnu/libsecret-1.so.0:
  undefined reference to `g_task_set_static_name'
/snap/flutter/current/usr/bin/ld: /lib/x86_64-linux-gnu/libayatana-ido3-0.4.so.0:
  undefined reference to `g_time_zone_new_identifier'
clang: error: linker command failed with exit code 1
```

`linux/runner/CMakeLists.txt` applies the standard fix:

```cmake
target_link_options(${BINARY_NAME} PRIVATE
  "-Wl,--unresolved-symbols=ignore-in-shared-libs")
```

This relaxes only the symbols defined by **other shared libraries**
(not symbols our own code references), so a genuine missing dependency
in our code still fails the link. The flag is a no-op on macOS and is
not parsed on Windows, so it is safe to leave in even if Flutter is
later installed from the tarball instead of the snap.

Verified on Ubuntu 24.04.3 LTS with `flutter` 3.44 from the snap store:
`flutter build linux --debug` succeeds and the resulting binary
launches under GTK, brings up the Dart VM service, and exits cleanly on
`SIGTERM` from a smoke-test `timeout` wrapper.

## 11. Cross-platform compatibility note

Adding the Linux platform does not modify any shared Dart code or any of
the existing `windows/`, `macos/`, `ios/`, or `android/` directories.
`lib/main.dart` already gates Linux-only behavior on
`Platform.isLinux`, so the macOS DMG and Windows MSIX release pipelines
(`release-macos.sh`, `release-windows-msix.ps1`,
`flutter-build-prod.sh`) continue to function unchanged. The new
`release-deb.sh` orchestrator sits alongside them as the Linux peer of
`release-macos.sh`.
