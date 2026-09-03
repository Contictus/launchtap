param(
    [ValidateSet("all", "pins", "fmt", "build", "goldens", "vectors", "deployments", "test", "lint", "size", "fork")]
    [string] $Target = "all"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$contractsRoot = Split-Path -Parent $PSScriptRoot
Push-Location $contractsRoot
try {
    function Invoke-Checked([scriptblock] $Command) {
        & $Command
        if (-not $?) {
            $exitCode = Get-Variable -Name LASTEXITCODE -ValueOnly -ErrorAction SilentlyContinue
            if ($null -ne $exitCode) {
                throw "Contract check failed with exit code $exitCode"
            }
            throw "Contract check failed"
        }
    }

    if ($Target -in @("all", "pins")) {
        Invoke-Checked { & "$PSScriptRoot/check-dependencies.ps1" }
    }
    if ($Target -in @("all", "fmt")) {
        Invoke-Checked { forge fmt --check }
    }
    if ($Target -in @("all", "build")) {
        Invoke-Checked { forge build }
    }
    if ($Target -in @("all", "goldens")) {
        Invoke-Checked { & "$PSScriptRoot/check-goldens.ps1" }
    }
    if ($Target -in @("all", "vectors")) {
        Invoke-Checked { & "$PSScriptRoot/check-vectors.ps1" }
    }
    if ($Target -in @("all", "deployments")) {
        Invoke-Checked { & "$PSScriptRoot/check-deployments.ps1" }
    }
    if ($Target -in @("all", "test")) {
        Invoke-Checked { forge test }
    }
    if ($Target -in @("all", "lint")) {
        Invoke-Checked { forge lint --severity high med low info -D warnings }
    }
    if ($Target -in @("all", "size")) {
        Invoke-Checked { forge build --sizes }
    }
    if ($Target -eq "fork") {
        Invoke-Checked { & "$PSScriptRoot/check-fork.ps1" }
    }
}
finally {
    Pop-Location
}
