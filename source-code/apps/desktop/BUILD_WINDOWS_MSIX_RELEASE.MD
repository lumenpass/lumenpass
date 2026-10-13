# Build & Release LumenPass Desktop (Windows MSIX → Microsoft Store)

End-to-end guide for producing a Microsoft Store-ready `.msix` of LumenPass desktop and submitting it through Partner Center.

All commands assume PowerShell, run from this directory:

```powershell
cd "C:\Users\tuant\workspace\LumenPass Workspaces\lumenpass\apps\desktop"
```

The project already has the `msix` Dart package wired up (see `dev_dependencies` and `msix_config` in `pubspec.yaml`), so the workflow is:

1. Reserve the app in Partner Center to get the real `Identity Name` / `Publisher`.
2. Update `msix_config` in `pubspec.yaml`.
3. Build a release Flutter Windows binary.
4. Package it into a Store-ready `.msix` with `flutter pub run msix:create --store`.
5. Upload through Partner Center.

---

## 0. Architecture & MSIX vs MSIXUPLOAD

- `flutter build windows --release` produces an **x64** binary by default. The Microsoft Store accepts a single x64 MSIX; ARM64 is optional and requires a separate build on (or cross-compiled for) ARM64.
- For Store submissions you upload an `.msixupload` bundle (a zip that contains the `.msix` plus its symbols). The `msix` Dart package emits this automatically when `store: true` is set.
- Side-loaded MSIX (signed with your own cert) is **not** what the Store wants. Do not sign the package yourself when targeting the Store — Partner Center re-signs it with the Microsoft Store certificate during ingestion.

---

## 1. Prerequisites (one-time setup)

### 1.1 Microsoft Partner Center account

- A **Microsoft Partner Center** developer account (individual or company). One-time fee: ~$19 individual, ~$99 company.
  - Sign up at https://partner.microsoft.com/dashboard/registration
- Account must be verified before you can submit. Company accounts require domain/identity verification (can take several days).

### 1.2 Reserve the app name

1. Go to Partner Center → **Apps and games** → **New product** → **MSIX or PWA app**.
2. Reserve the name `LumenPass` (or `LumenPass - Password Manager` if available).
3. Open the new app → **Product identity**. Note these three values:

   | Field | Example value |
   |---|---|
   | Package/Identity Name | `TranTechStudio.LumenPass-PasswordManager` |
   | Publisher | `CN=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX` |
   | Publisher display name | `TranTech Studio` |

   These **must** match what you put in `pubspec.yaml` exactly, otherwise the Store will reject the upload with `Package identity does not match`.

### 1.3 Tools

```powershell
# Flutter
flutter --version

# Windows desktop support
flutter config --enable-windows-desktop

# Visual Studio 2022 with the "Desktop development with C++" workload
#   - MSVC v143 build tools
#   - Windows 10/11 SDK (latest)
#   - C++ CMake tools for Windows
# Install/modify via the Visual Studio Installer GUI.

# Confirm the Flutter doctor section for Windows is green
flutter doctor -v
```

The `msix` Dart package is already pinned in `pubspec.yaml` (`msix: ^3.16.13`) so no separate global install is required.

---

## 2. Configure `msix_config` in `pubspec.yaml`

Open `pubspec.yaml` and update the `msix_config` block with the values from Partner Center → Product identity. Current values look like this:

```yaml
msix_config:
  display_name: LumenPass - Password Manager
  publisher_display_name: TranTech Studio
  identity_name: TranTechStudio.LumenPass-PasswordManager
  msix_version: 1.0.0.0
  publisher: CN=E7C3DEED-03E7-4777-AC12-FDEB611FA59C
  logo_path: windows\runner\resources\app_icon.ico
  capabilities: internetClient, removableStorage, documentsLibrary
  store: true
```

Required edits:

- `identity_name` → exact `Package/Identity Name` from Partner Center.
- `publisher` → exact `Publisher` string (`CN=…`) from Partner Center.
- `publisher_display_name` → exact `Publisher display name` from Partner Center.
- `msix_version` → must be **four numeric segments** (e.g. `1.0.1.0`). The Store requires the **last segment to be `0`** for normal submissions.
- `display_name` → user-facing app name shown in Start menu / Store listing.
- `logo_path` → existing icon at `windows\runner\resources\app_icon.ico` is fine, but for a polished Store listing you should also generate the full Store asset set (see §3).
- `store: true` → keeps the package compatible with Store ingestion (no self-signing, correct manifest flags).

> Keep `pubspec.yaml`'s top-level `version:` (currently `1.0.1+2`) in sync with `msix_version` (e.g. bump to `1.0.1.0`) so Flutter's about dialog, the Win32 `Runner.rc` version block, and the MSIX manifest all agree.

### 2.1 Capabilities sanity check

`internetClient, removableStorage, documentsLibrary` are all **regular** (non-restricted) capabilities, so they don't trigger extra Store review. If you ever add `runFullTrust`, `broadFileSystemAccess`, or any `restricted` capability, expect a longer review and extra justification questions.

### 2.2 Logo / Store assets (recommended)

The Store listing wants more than a single `.ico`. The `msix` package can generate the full tile set if you point `logo_path` at a 1240×1240 transparent PNG and add:

```yaml
msix_config:
  logo_path: windows\runner\resources\app_icon_1240.png
  # Optional, but strongly recommended for Store listings:
  # trim_logo: false
  # icons_background_color: transparent
```

If you keep the `.ico`, the Store listing tiles will look low-resolution; not blocking, just ugly.

---

## 3. Build the release Windows binary

```powershell
flutter clean
flutter pub get

flutter build windows --release `
  --dart-define-from-file=dart_defines.prod.json
```

Output:

```
build\windows\x64\runner\Release\lumenpass.exe
build\windows\x64\runner\Release\data\
build\windows\x64\runner\Release\*.dll
```

Quick sanity checks:

```powershell
# Run the built exe locally to make sure it launches and the Riverpod/secure-storage flows work
& ".\build\windows\x64\runner\Release\lumenpass.exe"
```

---

## 4. Build the Store-ready MSIX

Because `store: true` is set, the `msix` package will emit an `.msixupload` bundle (the artifact Partner Center accepts) instead of a self-signed `.msix`.

```powershell
flutter pub run msix:create --store
```

Output (path printed at the end of the command):

```
build\windows\x64\runner\Release\lumenpass.msixupload
```

Useful flags:

- `--build-windows false` → skip the implicit `flutter build windows` step if you just ran it (faster iteration).
- `--output-name LumenPass-1.0.1` → custom file name.
- `--output-path build\dist` → custom directory.

Example full command for a release artifact directory:

```powershell
$Version = (Select-String -Path pubspec.yaml -Pattern '^version:').Line.Split(' ')[1].Split('+')[0]
New-Item -ItemType Directory -Force -Path build\dist | Out-Null

flutter pub run msix:create `
  --store `
  --build-windows false `
  --output-path build\dist `
  --output-name "LumenPass-$Version"
```

Verify:

```powershell
# The bundle should exist and be a non-trivial size (50–150 MB for a Flutter app is normal)
Get-Item "build\dist\LumenPass-$Version.msixupload" | Format-List FullName, Length

# The bundle is a zip; you can peek inside without extracting
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::OpenRead("$PWD\build\dist\LumenPass-$Version.msixupload").Entries | Select-Object FullName
```

You should see one or more `.msix` files inside, plus `.appxsym` symbol files.

> Do **not** sign the `.msixupload` yourself. The Store re-signs with its own certificate. Self-signing produces a side-load-only artifact that Partner Center will reject.

---

## 5. (Optional) Local install test before uploading

You can install the package locally to smoke-test, but it requires either:

- A trusted certificate matching the `publisher` string in the manifest (you don't have one for `CN=E7C3DEED-…` — that's the Store's), **or**
- Generating a separate side-loadable build with `store: false` and a self-signed cert.

For a quick side-load test, temporarily flip the config and rebuild into a different directory:

```powershell
# Side-load test build (do NOT submit this to the Store)
flutter pub run msix:create `
  --output-path build\sideload `
  --output-name LumenPass-sideload `
  --store false `
  --certificate-path .\dev-cert.pfx `
  --certificate-password "your-pfx-password"
```

Generate `dev-cert.pfx` once with:

```powershell
$cert = New-SelfSignedCertificate `
  -Type CodeSigningCert `
  -Subject "CN=LumenPass Dev" `
  -KeyUsage DigitalSignature `
  -FriendlyName "LumenPass Dev" `
  -CertStoreLocation "Cert:\CurrentUser\My"

$pwd = ConvertTo-SecureString -String "your-pfx-password" -Force -AsPlainText
Export-PfxCertificate -Cert "Cert:\CurrentUser\My\$($cert.Thumbprint)" -FilePath .\dev-cert.pfx -Password $pwd

# Trust it on this machine
Import-PfxCertificate -FilePath .\dev-cert.pfx -CertStoreLocation Cert:\LocalMachine\TrustedPeople -Password $pwd
```

Install the side-load MSIX:

```powershell
Add-AppxPackage -Path "build\sideload\LumenPass-sideload.msix"
```

Uninstall:

```powershell
Get-AppxPackage *LumenPass* | Remove-AppxPackage
```

Always re-flip `store: true` and rebuild before uploading to Partner Center.

---

## 6. Submit to Microsoft Partner Center

1. Open https://partner.microsoft.com/dashboard → **Apps and games** → select **LumenPass**.
2. Click **Start your submission** (or **Update** for a new version).
3. **Pricing and availability** → set price (Free), markets, and visibility.
4. **Properties** → category (`Productivity`), subcategory, support contact info, privacy policy URL (required for any app that handles credentials).
5. **Age ratings** → fill in the IARC questionnaire.
6. **Packages** → drag-and-drop the `.msixupload` from §4. Wait for validation:
   - Partner Center runs **Windows App Certification Kit (WACK)** automatically.
   - Common failures:
     - `Package identity does not match` → `identity_name` / `publisher` in `pubspec.yaml` are wrong.
     - `Version already used` → bump `msix_version` (and `pubspec.yaml` `version:`).
     - `runFullTrust capability requires approval` → only if you added it.
7. **Store listing** → app description, screenshots (min 1, max 10, 1366×768 or 1920×1080 PNG/JPG), feature graphic, search terms.
8. **Submission options** → publishing schedule (manual vs as-soon-as-possible), notes for certification (mention any test credentials if reviewers need to sign in).
9. **Review and publish** → submit.

Typical certification time: a few hours to a few days for the first submission, much faster for updates.

---

## 7. Updating an existing Store listing

For every new release:

1. Bump `version:` in `pubspec.yaml` (e.g. `1.0.2+3`).
2. Bump `msix_config.msix_version` to a value strictly greater than the last one published, keeping the trailing `.0` (e.g. `1.0.2.0`).
3. Run §3 + §4.
4. In Partner Center → app → **Update**, upload the new `.msixupload`.
5. Fill **What's new in this version** in the Store listing.
6. Submit.

The Store rejects packages whose 4-part `Version` is ≤ the currently published one, so always increase it.

---

## 8. One-shot release script

A ready-to-run script lives next to `release-macos.sh` at [release-windows-msix.ps1](file:///c:/Users/tuant/workspace/LumenPass%20Workspaces/lumenpass/apps/desktop/release-windows-msix.ps1). It performs all of §3 + §4, plus preflight checks (Visual Studio C++ workload, `pubspec.yaml` `msix_config` validation, version sanity), and emits a SHA-256 checksum.

Run it from this directory:

```powershell
powershell -ExecutionPolicy Bypass -File .\release-windows-msix.ps1
```

Iterate faster while debugging packaging by skipping the build steps:

```powershell
powershell -ExecutionPolicy Bypass -File .\release-windows-msix.ps1 -SkipClean -SkipBuild
```

The reference implementation is below for inspection:

```powershell
# release-windows-msix.ps1
$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

$Version = (Select-String -Path pubspec.yaml -Pattern '^version:').Line.Split(' ')[1].Split('+')[0]
$OutDir  = Join-Path $PSScriptRoot 'build\dist'
$OutName = "LumenPass-$Version"

Write-Host "==> Cleaning"
flutter clean
flutter pub get

Write-Host "==> Building Windows release (v$Version)"
flutter build windows --release `
  --dart-define-from-file=dart_defines.prod.json

Write-Host "==> Packaging MSIX (Store)"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
flutter pub run msix:create `
  --store `
  --build-windows false `
  --output-path $OutDir `
  --output-name $OutName

$Artifact = Join-Path $OutDir "$OutName.msixupload"
if (-not (Test-Path $Artifact)) {
  throw "Expected artifact not found: $Artifact"
}

Write-Host "==> Generating SHA-256"
$hash = Get-FileHash -Algorithm SHA256 $Artifact
"$($hash.Hash)  $($OutName).msixupload" | Out-File -Encoding ascii "$Artifact.sha256"

Write-Host "Done: $Artifact"
Write-Host "Upload this file to Partner Center → LumenPass → Packages."
```

Run it with:

```powershell
powershell -ExecutionPolicy Bypass -File .\release-windows-msix.ps1
```

---

## 9. Verification on a clean Windows machine

Once the submission is **Published**:

1. On a Windows machine that has never run LumenPass, open the **Microsoft Store** app.
2. Search for `LumenPass` (or use the deep link Partner Center gave you: `ms-windows-store://pdp/?productid=…`).
3. Install. The Store handles signing/trust — no SmartScreen warning.
4. Launch from Start menu and verify:
   - Tray icon (`tray_manager`) appears.
   - `flutter_secure_storage` reads/writes credentials (login flow).
   - `google_sign_in` opens the system browser and completes OAuth.
   - `local_auth` Windows Hello prompt works.
   - Cloud sync (Google Drive / Dropbox via the IDs in `dart_defines.prod.json`) succeeds.
5. Uninstall via **Settings → Apps** to confirm a clean removal (no leftover files in `%LOCALAPPDATA%\Packages\TranTechStudio.LumenPass-PasswordManager_*`).

---

## 10. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `error : MSB3073: ... msix:create exited with code 1` | Stale Flutter build | `flutter clean` then redo §3 + §4. |
| `The package identity in the manifest does not match the one expected by the Store.` | `identity_name` or `publisher` mismatch | Copy them verbatim from Partner Center → Product identity. |
| `App package must be version X.Y.Z.0 with last digit 0` | `msix_version` last segment ≠ 0 | Set it to `X.Y.Z.0`. |
| `Failed to find: cl.exe` during `flutter build windows` | Missing MSVC toolchain | Install **Desktop development with C++** in VS 2022. |
| `flutter_secure_storage` returns null after Store install | `flutter_secure_storage_windows` override path missing in MSIX | Confirm `dependency_overrides` in `pubspec.yaml` resolved before packaging; rerun `flutter pub get`. |
| `runFullTrust required` when calling some Win32 API | Capability not declared | Either avoid the API or add `runFullTrust` (requires Store approval). |
| Store rejects with `Privacy policy URL required` | Listing field empty | Fill **Properties → Privacy policy URL** with a publicly reachable URL. |

---

## 11. Reference: where each value comes from

| Value | Source |
|---|---|
| Package/Identity name | Partner Center → app → **Product identity** → `Package/Identity Name` |
| Publisher (`CN=…`) | Partner Center → app → **Product identity** → `Publisher` |
| Publisher display name | Partner Center → app → **Product identity** → `Publisher display name` |
| App version (`X.Y.Z+B`) | `pubspec.yaml` (`version:`) |
| MSIX version (`X.Y.Z.0`) | `pubspec.yaml` (`msix_config.msix_version`) |
| Capabilities | `pubspec.yaml` (`msix_config.capabilities`) |
| App icon | `windows\runner\resources\app_icon.ico` (referenced from `Runner.rc` and `msix_config.logo_path`) |
| Dart defines | `dart_defines.prod.json` |
| Win32 version block | `windows\runner\Runner.rc` (auto-populated from Flutter's `version:`) |
