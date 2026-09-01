param(
    [switch] $Write
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$contractsRoot = Split-Path -Parent $PSScriptRoot
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)

function Fail([string] $Message) {
    throw "Golden artifact check failed: $Message"
}

function Invoke-ForgeJson([string[]] $Arguments) {
    $output = (& forge @Arguments | Out-String)
    if ($LASTEXITCODE -ne 0) {
        Fail "forge $($Arguments -join ' ') exited with $LASTEXITCODE"
    }

    return $output | ConvertFrom-Json
}

function Get-Type([object] $Layout, [string] $TypeId) {
    $property = $Layout.types.PSObject.Properties[$TypeId]
    if ($null -eq $property) {
        Fail "storage layout is missing type $TypeId"
    }

    return $property.Value
}

function Normalize-StorageLayout([object] $Layout) {
    $storage = @(
        foreach ($entry in $Layout.storage) {
            $type = Get-Type $Layout $entry.type
            [ordered]@{
                label = [string] $entry.label
                slot = [string] $entry.slot
                offset = [int] $entry.offset
                type = [string] $type.label
                encoding = [string] $type.encoding
                numberOfBytes = [string] $type.numberOfBytes
            }
        }
    )

    $types = @(
        foreach ($property in $Layout.types.PSObject.Properties) {
            $type = $property.Value
            $normalized = [ordered]@{
                label = [string] $type.label
                encoding = [string] $type.encoding
                numberOfBytes = [string] $type.numberOfBytes
            }

            if ($null -ne $type.PSObject.Properties["key"]) {
                $normalized.key = [string] (Get-Type $Layout $type.key).label
            }
            if ($null -ne $type.PSObject.Properties["value"]) {
                $normalized.value = [string] (Get-Type $Layout $type.value).label
            }
            if ($null -ne $type.PSObject.Properties["members"]) {
                $normalized.members = @(
                    foreach ($member in $type.members) {
                        [ordered]@{
                            label = [string] $member.label
                            slot = [string] $member.slot
                            offset = [int] $member.offset
                            type = [string] (Get-Type $Layout $member.type).label
                        }
                    }
                )
            }

            [PSCustomObject] $normalized
        }
    ) | Sort-Object label

    return [ordered]@{
        storage = $storage
        types = @($types)
    }
}

function ConvertTo-StableJson([object] $Value) {
    $json = $Value | ConvertTo-Json -Depth 100 -Compress
    $json = $json.Replace("\u003c", "<").Replace("\u003e", ">").Replace("\u0026", "&")
    return $json + "`n"
}

function Compare-OrWrite([string] $Path, [string] $Expected) {
    if ($Write) {
        $directory = Split-Path -Parent $Path
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null
        [System.IO.File]::WriteAllText($Path, $Expected, $utf8WithoutBom)
        Write-Output "Wrote $Path"
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        Fail "missing $Path; run ./scripts/check-goldens.ps1 -Write"
    }

    $actual = [System.IO.File]::ReadAllText($Path)
    if ($actual -ne $Expected) {
        Fail "$Path has drifted; review and run ./scripts/check-goldens.ps1 -Write"
    }
}

Push-Location $contractsRoot
try {
    $config = Invoke-ForgeJson @("config", "--json")
    if ([string] $config.solc -ne "0.8.36") {
        Fail "solc must remain 0.8.36"
    }
    if ($config.optimizer -ne $true -or [int] $config.optimizer_runs -ne 200) {
        Fail "optimizer must remain enabled with 200 runs"
    }
    if ($config.via_ir -ne $false) {
        Fail "via_ir must remain false"
    }
    if ([string] $config.evm_version -ne "cancun") {
        Fail "evm_version must remain cancun"
    }
    if ([string] $config.deny -ne "warnings") {
        Fail "deny must remain warnings"
    }

    $eventAbi = ConvertTo-StableJson (Invoke-ForgeJson @(
        "inspect", "ILaunchEvents", "abi", "--json"
    ))
    Compare-OrWrite (Join-Path $contractsRoot "abi/v1/ILaunchEvents.json") $eventAbi

    $storageContracts = @(
        "BondingCurveV1Storage",
        "LaunchFactoryStorage",
        "LaunchTokenStorage"
    )
    foreach ($contract in $storageContracts) {
        $layout = Invoke-ForgeJson @("inspect", $contract, "storage-layout", "--json")
        $normalized = Normalize-StorageLayout $layout
        $json = ConvertTo-StableJson $normalized
        $path = Join-Path $contractsRoot "storage-layout/v1/$contract.json"
        Compare-OrWrite $path $json
    }

    if (-not $Write) {
        Write-Output "Golden artifacts verified."
    }
}
finally {
    Pop-Location
}
