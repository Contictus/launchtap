param(
    [ValidateSet("all", "release", "pins", "fmt", "build", "goldens", "vectors", "deployments", "review", "test", "lint", "size", "slither", "fork")]
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

    if ($Target -in @("all", "release", "pins")) {
        Invoke-Checked { & "$PSScriptRoot/check-dependencies.ps1" }
    }
    if ($Target -in @("all", "release", "fmt")) {
        Invoke-Checked { forge fmt --check }
    }
    if ($Target -in @("all", "release", "build")) {
        Invoke-Checked { forge build }
    }
    if ($Target -in @("all", "release", "goldens")) {
        Invoke-Checked { & "$PSScriptRoot/check-goldens.ps1" }
    }
    if ($Target -in @("all", "release", "vectors")) {
        Invoke-Checked { & "$PSScriptRoot/check-vectors.ps1" }
    }
    if ($Target -in @("all", "release", "deployments")) {
        Invoke-Checked { & "$PSScriptRoot/check-deployments.ps1" }
    }
    if ($Target -in @("all", "release", "review")) {
        Invoke-Checked { & "$PSScriptRoot/check-release.ps1" }
    }
    if ($Target -in @("all", "release", "test")) {
        Invoke-Checked { forge test }
    }
    if ($Target -in @("all", "release", "lint")) {
        Invoke-Checked { forge lint --severity high med low info -D warnings }
    }
    if ($Target -in @("all", "release", "size")) {
        Invoke-Checked { & "$PSScriptRoot/check-sizes.ps1" }
    }
    if ($Target -in @("release", "slither")) {
        Invoke-Checked { & "$PSScriptRoot/check-slither.ps1" }
    }
    if ($Target -in @("release", "fork")) {
        Invoke-Checked { & "$PSScriptRoot/check-fork.ps1" }
    }
}
finally {
    Pop-Location
}
