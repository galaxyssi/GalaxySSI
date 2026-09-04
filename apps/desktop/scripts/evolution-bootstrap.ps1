param(
  [string]$RepoRoot = "",
  [switch]$EnableAndroidDeviceGate,
  [string]$CandidateApk = ""
)
$ErrorActionPreference = "Stop"
$RepoRoot = if ($RepoRoot) {
  (Resolve-Path $RepoRoot).Path
} else {
  (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
}
$env:GALAXYSSI_SOURCE_ROOT = $RepoRoot
Write-Host "GalaxySSI source: $RepoRoot"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git is required" }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "GitHub CLI is required" }
if (-not (Get-Command python -ErrorAction SilentlyContinue)) { throw "Python is required" }

& gh auth status --hostname github.com
if ($LASTEXITCODE -ne 0) {
  Write-Host "Authenticate on Desktop with: gh auth login" -ForegroundColor Yellow
}

if ($EnableAndroidDeviceGate) {
  if (-not $CandidateApk) {
    throw "-CandidateApk is required with -EnableAndroidDeviceGate"
  }
  $CandidateApk = (Resolve-Path $CandidateApk).Path
  $env:GALAXYSSI_EVOLUTION_ANDROID_DEVICE_TEST = "1"
}

& python (Join-Path $PSScriptRoot "evolution-preflight.py") --repo-root $RepoRoot
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($EnableAndroidDeviceGate) {
  $SnapshotRoot = Join-Path $env:TEMP "galaxyssi-evolution-android"
  & python (Join-Path $RepoRoot "apps/desktop/core/galaxyssi-link/backend/evolution_v2/gate_cli.py") `
    android-device `
    --candidate $CandidateApk `
    --snapshot-root $SnapshotRoot `
    --package com.galaxyssi.chat
  exit $LASTEXITCODE
}

exit 0
