#requires -Version 5.1
<#
.SYNOPSIS
  Build & package LumenPass desktop as a Microsoft Store-ready MSIX bundle (.msixupload)
  or as a sideload-test MSIX (.msix).

.DESCRIPTION
  Windows counterpart of release-macos.sh. Default produces:
    build\dist\LumenPass-<version>.msixupload
    build\dist\LumenPass-<version>.msixupload.sha256
  With -Output msix it produces .msix instead of .msixupload (for local sideload tests).

  Steps:
    1. Preflight checks (flutter, MSVC toolchain, msix package, pubspec values).
    2. flutter clean + flutter pub get.
    3. flutter build windows --release --dart-define-from-file=dart_defines.prod.json.
    4. flutter pub run msix:create (with --store for msixupload, optional cert for msix).
    5. Locate produced artifact, copy to build\dist, generate SHA-256.

  All MSIX identity values (identity_name, publisher, publisher_display_name,
  msix_version, capabilities, logo_path) are read from pubspec.yaml -> msix_config.
  Update them there, not here, so they stay in sync with `pubspec.yaml`'s `version:`.

.PARAMETER SkipClean
  Skip `flutter clean` and `flutter pub get` to iterate faster while debugging
  packaging issues. Use only when you know the build directory is fresh.

.PARAMETER SkipBuild
  Skip `flutter build windows --release`. Pairs with -SkipClean when you just
  want to repackage an existing Release build.

.PARAMETER OutputDir
  Output directory for the final artifact. Defaults to `build\dist`.

.PARAMETER Output
  Artifact format.
    msixupload (default) - Store-ready bundle for Partner Center upload.
    msix                 - Single .msix package (for sideload / local install testing).
                           NOTE: a .msix built with the Store publisher cannot be installed
                           locally unless signed by a cert matching that publisher. Use
                           -CertificatePath / -CertificatePassword to sign with a self-signed
                           cert (you must temporarily change pubspec.yaml -> publisher to
                           match the cert subject for local install to succeed).

.PARAMETER CertificatePath
  Optional path to a .pfx code-signing cert. Only used when -Output msix.
  When omitted, msix:create produces an unsigned .msix.

.PARAMETER CertificatePassword
  Password for the .pfx. Required when -CertificatePath is provided.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\release-windows-msix.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\release-windows-msix.ps1 -SkipClean -SkipBuild

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\release-windows-msix.ps1 -Output msix -CertificatePath .\dev-cert.pfx -CertificatePassword 'pw'
#>

[CmdletBinding()]
param(
  [switch]$SkipClean,
  [switch]$SkipBuild,
  [string]$OutputDir = 'build\dist',
  [ValidateSet('msixupload', 'msix')]
  [string]$Output = 'msixupload',
  [string]$CertificatePath,
  [string]$CertificatePassword
)

$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

# ---- helpers --------------------------------------------------------------

function Write-Step([string]$msg) {
  Write-Host ""
  Write-Host "==> $msg" -ForegroundColor Cyan
}

function Write-Fail([string]$msg) {
  Write-Host ""
  Write-Host "!! $msg" -ForegroundColor Red
  exit 1
}

function Require-Cmd([string]$name, [string]$hint = '') {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if (-not $cmd) {
    $h = if ($hint) { " ($hint)" } else { '' }
    Write-Fail "Required command not found: $name$h"
  }
}

function Get-PubspecValue([string]$pattern) {
  $line = Select-String -Path 'pubspec.yaml' -Pattern $pattern | Select-Object -First 1
  if (-not $line) { return $null }
  return ($line.Line -replace $pattern, '').Trim()
}

# ---- config (read from pubspec.yaml; do not hard-code) --------------------

$DartDefines    = 'dart_defines.prod.json'
$PubspecPath    = 'pubspec.yaml'
$ReleaseDir     = 'build\windows\x64\runner\Release'
$AppName        = 'LumenPass'

if (-not (Test-Path $PubspecPath))   { Write-Fail "Missing $PubspecPath" }
if (-not (Test-Path $DartDefines))   { Write-Fail "Missing $DartDefines (production dart-defines)" }

# pubspec.yaml -> version: 1.0.1+2
$RawVersion = Get-PubspecValue '^version:\s*'
if (-not $RawVersion) { Write-Fail "Could not read 'version:' from $PubspecPath" }
$Version    = ($RawVersion -split '\+')[0]
$BuildNum   = if ($RawVersion -match '\+(\d+)') { $Matches[1] } else { '0' }

# pubspec.yaml -> msix_config.msix_version: X.Y.Z.0
$MsixVersion = Get-PubspecValue '^\s*msix_version:\s*'
if (-not $MsixVersion) {
  Write-Fail "msix_config.msix_version missing in $PubspecPath. Add e.g. 'msix_version: $Version.0' under msix_config."
}
if ($MsixVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') {
  Write-Fail "msix_version must be 4 numeric segments (got: '$MsixVersion'). Example: $Version.0"
}
if (-not $MsixVersion.EndsWith('.0')) {
  Write-Fail "Microsoft Store requires the last segment of msix_version to be 0 (got: '$MsixVersion')."
}

$IdentityName       = Get-PubspecValue '^\s*identity_name:\s*'
$Publisher          = Get-PubspecValue '^\s*publisher:\s*'
$PublisherDisplay   = Get-PubspecValue '^\s*publisher_display_name:\s*'
$DisplayName        = Get-PubspecValue '^\s*display_name:\s*'
$StoreFlag          = Get-PubspecValue '^\s*store:\s*'

if (-not $IdentityName)     { Write-Fail "msix_config.identity_name missing in $PubspecPath." }
if (-not $Publisher)        { Write-Fail "msix_config.publisher missing in $PubspecPath." }
if (-not $PublisherDisplay) { Write-Fail "msix_config.publisher_display_name missing in $PubspecPath." }
if ($Output -eq 'msixupload' -and $StoreFlag -ne 'true') {
  Write-Fail "msix_config.store must be 'true' in $PubspecPath for Store submissions (-Output msixupload)."
}

# Validate cert params for sideload .msix builds.
if ($Output -eq 'msix') {
  if ($CertificatePath -and -not (Test-Path $CertificatePath)) {
    Write-Fail "CertificatePath not found: $CertificatePath"
  }
  if ($CertificatePath -and -not $CertificatePassword) {
    Write-Fail "-CertificatePassword is required when -CertificatePath is provided."
  }
  if (-not $CertificatePath) {
    Write-Host "WARNING: Building .msix without a signing certificate. The artifact will be UNSIGNED and Add-AppxPackage will refuse to install it. Pass -CertificatePath / -CertificatePassword to sign." -ForegroundColor Yellow
  }
}

# ---- preflight ------------------------------------------------------------

Write-Step "Preflight checks"
Require-Cmd 'flutter'
Require-Cmd 'dart'

# MSVC: try to detect a usable cl.exe via Visual Studio installer (vswhere)
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) {
  $vswhere = Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe'
}
if (Test-Path $vswhere) {
  $vsInstall = & $vswhere -latest -products * `
    -requires Microsoft.VisualStudio.Workload.NativeDesktop `
    -property installationPath 2>$null
  if (-not $vsInstall) {
    Write-Fail "Visual Studio with the 'Desktop development with C++' workload is required (MSVC v143 + Windows 10/11 SDK)."
  } else {
    Write-Host "Visual Studio found at: $vsInstall"
  }
} else {
  Write-Host "vswhere.exe not found; relying on flutter doctor to validate MSVC toolchain." -ForegroundColor Yellow
}

Write-Host "App version (pubspec):    $Version (+$BuildNum)"
Write-Host "MSIX version:             $MsixVersion"
Write-Host "Display name:             $DisplayName"
Write-Host "Identity name:            $IdentityName"
Write-Host "Publisher:                $Publisher"
Write-Host "Publisher display name:   $PublisherDisplay"
Write-Host "store:                    $StoreFlag"

# Sanity: warn if msix_version's first three segments differ from app version.
$appV  = $Version.Split('.')
$msixV = $MsixVersion.Split('.')
if (($msixV[0] -ne $appV[0]) -or ($msixV[1] -ne $appV[1]) -or ($msixV[2] -ne $appV[2])) {
  Write-Host "WARNING: msix_version ($MsixVersion) does not match pubspec version ($Version.0). Continuing anyway." -ForegroundColor Yellow
}

# Sanity: publisher must be the CN=... value from Partner Center -> Product identity.
if ($Publisher -notmatch '^CN=') {
  Write-Fail "msix_config.publisher must start with 'CN=' (got: '$Publisher'). Copy it verbatim from Partner Center -> Product identity."
}

# ---- build ----------------------------------------------------------------

if (-not $SkipClean) {
  Write-Step "flutter clean"
  flutter clean
  if ($LASTEXITCODE -ne 0) { Write-Fail "flutter clean failed" }

  Write-Step "flutter pub get"
  flutter pub get
  if ($LASTEXITCODE -ne 0) { Write-Fail "flutter pub get failed" }
}

if (-not $SkipBuild) {
  Write-Step "flutter build windows --release (v$Version)"
  flutter build windows --release --dart-define-from-file=$DartDefines
  if ($LASTEXITCODE -ne 0) { Write-Fail "flutter build windows failed" }
}

$Exe = Join-Path $ReleaseDir 'lumenpass.exe'
if (-not (Test-Path $Exe)) {
  Write-Fail "Build did not produce $Exe"
}
Write-Host "Built: $Exe"

# ---- package MSIX (Store) -------------------------------------------------

Write-Step "Packaging MSIX (mode: $Output)"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$OutName = "$AppName-$Version"

$msixArgs = @(
  'pub', 'run', 'msix:create',
  '--build-windows', 'false',
  '--output-path', $OutputDir,
  '--output-name', $OutName
)

if ($Output -eq 'msixupload') {
  $msixArgs += '--store'
} else {
  if ($CertificatePath) {
    $msixArgs += @('--certificate-path', $CertificatePath, '--certificate-password', $CertificatePassword)
  }
}

& flutter @msixArgs
if ($LASTEXITCODE -ne 0) { Write-Fail "msix:create failed" }

# msix:create may produce .msixupload (multi-arch bundle) OR a single .msix
# (single-arch, e.g. x64-only). Partner Center accepts both for MSIX apps.
if ($Output -eq 'msixupload') {
  # Prefer .msixupload if produced; fall back to .msix.
  $CandidateExts = @('msixupload', 'msix')
} else {
  $CandidateExts = @('msix')
}

$Artifact = $null
foreach ($ext in $CandidateExts) {
  $Artifact = Get-ChildItem -Path $OutputDir -Filter "$OutName.$ext" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($Artifact) { break }

  # Fallback: some versions of the package write to build\windows\x64\runner\Release\
  $Fallback = Get-ChildItem -Path $ReleaseDir -Filter "*.$ext" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($Fallback) {
    $Target = Join-Path $OutputDir "$OutName.$ext"
    Copy-Item -Path $Fallback.FullName -Destination $Target -Force
    $Artifact = Get-Item $Target
    break
  }
}

if (-not $Artifact) {
  $extList = ($CandidateExts | ForEach-Object { ".$_" }) -join ' or '
  Write-Fail "Expected artifact not found. Looked for $extList in $OutputDir and $ReleaseDir."
}

$ProducedExt = $Artifact.Extension.TrimStart('.')
if ($Output -eq 'msixupload' -and $ProducedExt -eq 'msix') {
  Write-Host "NOTE: msix:create produced a single .msix (single-arch build). Partner Center accepts this directly for the upload." -ForegroundColor Yellow
}

# ---- verify & checksum ----------------------------------------------------

Write-Step "Verifying artifact"
Write-Host "Artifact:  $($Artifact.FullName)"
Write-Host "Size:      $([math]::Round($Artifact.Length / 1MB, 2)) MB"

# Peek inside the artifact (it's a zip) and validate its shape.
try {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead($Artifact.FullName)
  try {
    $entries = $zip.Entries | ForEach-Object { $_.FullName }
    if ($ProducedExt -eq 'msixupload') {
      Write-Host "Bundle contents:"
      $entries | ForEach-Object { Write-Host "  - $_" }
      if (-not ($entries | Where-Object { $_ -match '\.msix$' })) {
        Write-Host "WARNING: No .msix found inside the .msixupload. Partner Center will reject this." -ForegroundColor Yellow
      }
    } else {
      $hasManifest = $entries | Where-Object { $_ -match '^AppxManifest\.xml$' }
      if (-not $hasManifest) {
        Write-Host "WARNING: AppxManifest.xml not found at the root of the .msix." -ForegroundColor Yellow
      } else {
        Write-Host ".msix package looks well-formed (AppxManifest.xml present)."
      }
    }
  } finally {
    $zip.Dispose()
  }
} catch {
  Write-Host "Could not inspect bundle contents: $_" -ForegroundColor Yellow
}

Write-Step "Generating SHA-256"
$ChecksumPath = "$($Artifact.FullName).sha256"
$hash = Get-FileHash -Algorithm SHA256 -Path $Artifact.FullName
"$($hash.Hash)  $($Artifact.Name)" | Out-File -Encoding ascii -FilePath $ChecksumPath
Write-Host "Checksum:  $ChecksumPath"
Write-Host "SHA-256:   $($hash.Hash)"

# ---- done -----------------------------------------------------------------

Write-Step "Done"
Write-Host "Artifact:  $($Artifact.FullName)"
Write-Host "Checksum:  $ChecksumPath"
Write-Host ""
if ($Output -eq 'msixupload') {
  Write-Host "Next: open Partner Center -> Apps and games -> $DisplayName -> Packages, drag the .$ProducedExt file to upload." -ForegroundColor Green
} else {
  Write-Host "Next (local sideload test):" -ForegroundColor Green
  if ($CertificatePath) {
    Write-Host "  Add-AppxPackage -Path '$($Artifact.FullName)'" -ForegroundColor Green
    Write-Host "  Get-AppxPackage *LumenPass* | Remove-AppxPackage    # to uninstall" -ForegroundColor Green
  } else {
    Write-Host "  This .msix is UNSIGNED. Sign it (or rerun with -CertificatePath/-CertificatePassword) before Add-AppxPackage." -ForegroundColor Yellow
  }
}
