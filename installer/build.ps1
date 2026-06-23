<#
.SYNOPSIS
    Builds the Shop+ Windows release and compiles the Inno Setup installer.

.DESCRIPTION
    1. Reads the app version from pubspec.yaml.
    2. Runs `flutter build windows --release`.
    3. Locates ISCC.exe (Inno Setup compiler).
    4. Compiles installer\shop_plus.iss -> installer\Output\ShopPlus-Setup-<ver>.exe

.PARAMETER SupabaseUrl
    Optional. Overrides the baked-in Supabase URL via --dart-define.

.PARAMETER SupabaseAnonKey
    Optional. Overrides the baked-in Supabase anon key via --dart-define.

.PARAMETER SkipBuild
    Skip the Flutter build and only (re)compile the installer.

.EXAMPLE
    pwsh installer\build.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File installer\build.ps1
#>
param(
    [string]$SupabaseUrl,
    [string]$SupabaseAnonKey,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$RepoRoot   = Split-Path $PSScriptRoot -Parent
$IssScript  = Join-Path $PSScriptRoot 'shop_plus.iss'
$ReleaseDir = Join-Path $RepoRoot 'build\windows\x64\runner\Release'

# ── 1. Version from pubspec.yaml ────────────────────────────────────────────
$pubspec = Get-Content (Join-Path $RepoRoot 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)') {
    throw 'Could not read version from pubspec.yaml'
}
$Version = $Matches[1]
Write-Host "Shop+ version: $Version" -ForegroundColor Cyan

# ── 2. Flutter build ────────────────────────────────────────────────────────
if (-not $SkipBuild) {
    Push-Location $RepoRoot
    try {
        $buildArgs = @('build', 'windows', '--release')
        if ($SupabaseUrl)     { $buildArgs += "--dart-define=SUPABASE_URL=$SupabaseUrl" }
        if ($SupabaseAnonKey) { $buildArgs += "--dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey" }

        Write-Host "Running: flutter $($buildArgs -join ' ')" -ForegroundColor Cyan
        & flutter @buildArgs
        if ($LASTEXITCODE -ne 0) { throw "flutter build failed (exit $LASTEXITCODE)" }
    }
    finally {
        Pop-Location
    }
}

if (-not (Test-Path (Join-Path $ReleaseDir 'flutter_app.exe'))) {
    throw "Release build not found at $ReleaseDir. Run without -SkipBuild first."
}

# ── 3. Locate ISCC.exe ──────────────────────────────────────────────────────
$Iscc = $null
$candidate = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
if ($candidate) { $Iscc = $candidate.Source }
if (-not $Iscc) {
    foreach ($p in @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
        "${env:LOCALAPPDATA}\Programs\Inno Setup 6\ISCC.exe"
    )) {
        if ($p -and (Test-Path $p)) { $Iscc = $p; break }
    }
}
if (-not $Iscc) {
    throw "ISCC.exe not found. Install Inno Setup 6 (winget install JRSoftware.InnoSetup)."
}
Write-Host "Using Inno Setup: $Iscc" -ForegroundColor Cyan

# ── 4. Compile installer ────────────────────────────────────────────────────
& $Iscc "/DMyAppVersion=$Version" $IssScript
if ($LASTEXITCODE -ne 0) { throw "ISCC failed (exit $LASTEXITCODE)" }

$Output = Join-Path $PSScriptRoot "Output\ShopPlus-Setup-$Version.exe"
Write-Host ""
Write-Host "Installer created:" -ForegroundColor Green
Write-Host "  $Output" -ForegroundColor Green
