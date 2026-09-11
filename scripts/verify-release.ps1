param([switch]$Help)
$ErrorActionPreference = "Stop"
if ($Help) { Write-Host "Usage: ./scripts/verify-release.ps1 (runs the mandatory cross-stack release gate)"; exit 0 }
$root = Split-Path -Parent $PSScriptRoot
node (Join-Path $root "scripts/verify-release.mjs")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
