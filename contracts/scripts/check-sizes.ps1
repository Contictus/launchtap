param(
    [switch] $Write
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$contractsRoot = Split-Path -Parent $PSScriptRoot
$baselinePath = Join-Path $contractsRoot "sizes/v1/sizes.json"
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
$trackedContracts = @("BondingCurveV1", "LaunchFactory", "LaunchToken")

function Fail([string] $Message) {
    throw "Bytecode size check failed: $Message"
}

function Invoke-ForgeJson([string[]] $Arguments) {
    $output = (& forge @Arguments | Out-String)
    if ($LASTEXITCODE -ne 0) {
        Fail "forge $($Arguments -join ' ') exited with $LASTEXITCODE"
    }

    return $output | ConvertFrom-Json
}

function ConvertTo-StableJson([object] $Value) {
    return ($Value | ConvertTo-Json -Depth 100 -Compress) + "`n"
}

Push-Location $contractsRoot
try {
    & forge build --sizes | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Fail "forge build --sizes exited with $LASTEXITCODE"
    }

    $report = Invoke-ForgeJson @("build", "--sizes", "--json")

    $observed = [ordered]@{}
    foreach ($name in $trackedContracts) {
        $entry = $report.PSObject.Properties[$name]
        if ($null -eq $entry) {
            Fail "forge did not report a size for $name"
        }
        $observed[$name] = [ordered]@{
            runtime_size = [int] $entry.Value.runtime_size
            init_size = [int] $entry.Value.init_size
        }
    }

    $expectedJson = ConvertTo-StableJson ([PSCustomObject] $observed)

    if ($Write) {
        [System.IO.Directory]::CreateDirectory((Split-Path -Parent $baselinePath)) | Out-Null
        [System.IO.File]::WriteAllText($baselinePath, $expectedJson, $utf8WithoutBom)
        Write-Output "Wrote $baselinePath"
        return
    }

    if (-not (Test-Path -LiteralPath $baselinePath)) {
        Fail "missing $baselinePath; run ./scripts/check-sizes.ps1 -Write"
    }

    $actualJson = [System.IO.File]::ReadAllText($baselinePath)
    if ($actualJson -ne $expectedJson) {
        Fail "$baselinePath has drifted; review and run ./scripts/check-sizes.ps1 -Write"
    }

    Write-Output "Bytecode sizes verified."
}
finally {
    Pop-Location
}
