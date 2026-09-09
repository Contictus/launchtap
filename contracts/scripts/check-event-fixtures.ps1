param([switch] $Write)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$contractsRoot = Split-Path -Parent $PSScriptRoot
$artifactPath = Join-Path $contractsRoot "fixtures/v1/event-logs-v1.json"
$generatedRoot = Join-Path $contractsRoot "fixtures/.generated"
$generatedPath = Join-Path $generatedRoot "event-logs-v1.json"
$previousOutput = [Environment]::GetEnvironmentVariable("EVENT_FIXTURES_OUTPUT", "Process")

function Fail([string] $Message) { throw "Event fixture check failed: $Message" }

Push-Location $contractsRoot
try {
    [System.IO.Directory]::CreateDirectory($generatedRoot) | Out-Null
    [Environment]::SetEnvironmentVariable(
        "EVENT_FIXTURES_OUTPUT",
        $generatedPath,
        "Process"
    )
    & forge script script/GenerateEventFixtures.s.sol:GenerateEventFixtures --silent
    if ($LASTEXITCODE -ne 0) { Fail "generator exited with $LASTEXITCODE" }
    if (-not (Test-Path -LiteralPath $generatedPath)) { Fail "generator wrote no artifact" }

    if ($Write) {
        [System.IO.Directory]::CreateDirectory((Split-Path -Parent $artifactPath)) | Out-Null
        Copy-Item -LiteralPath $generatedPath -Destination $artifactPath -Force
        Write-Output "Wrote $artifactPath"
    }
    else {
        if (-not (Test-Path -LiteralPath $artifactPath)) {
            Fail "missing fixture; run ./scripts/check-event-fixtures.ps1 -Write"
        }
        $expected = [System.IO.File]::ReadAllBytes($artifactPath)
        $actual = [System.IO.File]::ReadAllBytes($generatedPath)
        if (-not [System.Linq.Enumerable]::SequenceEqual[byte]($expected, $actual)) {
            Fail "fixtures/v1/event-logs-v1.json has drifted"
        }
        Write-Output "Event fixtures verified."
    }
}
finally {
    [Environment]::SetEnvironmentVariable("EVENT_FIXTURES_OUTPUT", $previousOutput, "Process")
    if (Test-Path -LiteralPath $generatedRoot) {
        Remove-Item -LiteralPath $generatedRoot -Recurse -Force
    }
    Pop-Location
}
