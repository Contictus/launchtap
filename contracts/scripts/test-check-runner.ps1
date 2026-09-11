$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "check-runner.ps1")

$failureObserved = $false
try {
    Invoke-Checked { & pwsh -NoProfile -Command "exit 17" }
}
catch {
    $failureObserved = $true
    if ($_.Exception.Message -notmatch "exit code 17") {
        throw "Checked-runner regression produced the wrong error: $($_.Exception.Message)"
    }
}

if (-not $failureObserved) {
    throw "Checked-runner regression failed: a native exit code of 17 was accepted"
}

# The failing child was intentionally observed; leave a successful status for
# callers that wrap this harness in Invoke-Checked.
$global:LASTEXITCODE = 0
Write-Output "Checked-runner regression verified."
