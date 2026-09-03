$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$contractsRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $contractsRoot "slither.config.json"
$versionPath = Join-Path $contractsRoot "slither/v1/slither-version.txt"

function Fail([string] $Message) {
    throw "Slither check failed: $Message"
}

if (-not (Get-Command slither -ErrorAction SilentlyContinue)) {
    Fail "slither is not on PATH; install the pinned slither-analyzer"
}
if (-not (Test-Path -LiteralPath $configPath)) {
    Fail "missing $configPath"
}
if (-not (Test-Path -LiteralPath $versionPath)) {
    Fail "missing $versionPath"
}

$expectedVersion = ([System.IO.File]::ReadAllText($versionPath)).Trim()
$reportedVersion = (& slither --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) {
    Fail "slither --version exited with $LASTEXITCODE"
}
if ($reportedVersion -ne $expectedVersion) {
    Fail "slither $expectedVersion is required, found $reportedVersion"
}

Push-Location $contractsRoot
try {
    & slither . --config-file $configPath --fail-medium
    if ($LASTEXITCODE -ne 0) {
        Fail "slither reported unresolved findings at medium or higher impact"
    }

    Write-Output "Slither analysis verified."
}
finally {
    Pop-Location
}
