param(
    [ValidateSet("all", "pins", "fmt", "build", "test", "lint", "size")]
    [string] $Target = "all"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$contractsRoot = Split-Path -Parent $PSScriptRoot
Push-Location $contractsRoot
try {
    function Invoke-Checked([scriptblock] $Command) {
        & $Command
        if ($LASTEXITCODE -ne 0) {
            throw "Contract check failed with exit code $LASTEXITCODE"
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
    if ($Target -in @("all", "test")) {
        Invoke-Checked { forge test }
    }
    if ($Target -in @("all", "lint")) {
        Invoke-Checked { forge lint --severity high med low info -D warnings }
    }
    if ($Target -in @("all", "size")) {
        Invoke-Checked { forge build --sizes }
    }
}
finally {
    Pop-Location
}
