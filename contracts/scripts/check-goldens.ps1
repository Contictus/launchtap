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

    $curveStoragePath = Join-Path $contractsRoot "src/storage/BondingCurveV1Storage.sol"
    $curveStorageSource = [System.IO.File]::ReadAllText($curveStoragePath)
    if ($curveStorageSource -match "ReentrancyGuardTransient") {
        Fail "BondingCurveV1Storage must not use transient reentrancy storage"
    }
    if ($curveStorageSource -notmatch "is\s+ReentrancyGuard") {
        Fail "BondingCurveV1Storage must retain the storage-based ReentrancyGuard"
    }

    $eventAbi = ConvertTo-StableJson (Invoke-ForgeJson @(
        "inspect", "ILaunchEvents", "abi", "--json"
    ))
    Compare-OrWrite (Join-Path $contractsRoot "abi/v1/ILaunchEvents.json") $eventAbi

    $tokenAbiObject = Invoke-ForgeJson @("inspect", "LaunchToken", "abi", "--json")
    $tokenCallables = @(
        foreach ($entry in $tokenAbiObject) {
            if ($entry.type -eq "function") {
                $inputTypes = @($entry.inputs | ForEach-Object { [string] $_.type })
                "$($entry.name)($($inputTypes -join ','))"
            }
            elseif ($entry.type -in @("fallback", "receive")) {
                [string] $entry.type
            }
        }
    ) | Sort-Object
    $expectedTokenCallables = @(
        "allowance(address,address)",
        "approve(address,uint256)",
        "balanceOf(address)",
        "curve()",
        "decimals()",
        "graduated()",
        "initializePair(address)",
        "lpPair()",
        "markGraduated()",
        "name()",
        "symbol()",
        "totalSupply()",
        "transfer(address,uint256)",
        "transferFrom(address,address,uint256)"
    ) | Sort-Object
    if (($tokenCallables -join "`n") -ne ($expectedTokenCallables -join "`n")) {
        Fail "LaunchToken callable ABI must remain fixed and must not expose mint or burn paths"
    }
    $tokenAbi = ConvertTo-StableJson $tokenAbiObject
    Compare-OrWrite (Join-Path $contractsRoot "abi/v1/LaunchToken.json") $tokenAbi

    $factoryAbiObject = Invoke-ForgeJson @("inspect", "LaunchFactory", "abi", "--json")
    $factoryCallables = @(
        foreach ($entry in $factoryAbiObject) {
            if ($entry.type -eq "function") {
                $inputTypes = @($entry.inputs | ForEach-Object { [string] $_.type })
                "$($entry.name)($($inputTypes -join ','))"
            }
            elseif ($entry.type -in @("fallback", "receive")) {
                [string] $entry.type
            }
        }
    ) | Sort-Object
    $expectedFactoryCallables = @(
        "claimLaunchFees()",
        "configureEngine(uint16,address,bool)",
        "curveImplementation(uint16)",
        "engineEnabled(uint16)",
        "futureDefaults()",
        "futureDefaultsHash()",
        "launch(tuple)",
        "launchFee()",
        "launchFeesByTreasury(address)",
        "launchesPaused()",
        "pauseAuthority()",
        "protocolTreasury()",
        "setFutureDefaults(tuple)",
        "setFutureTreasury(address)",
        "setLaunchesPaused(bool)",
        "setTradingPaused(bool)",
        "timelock()",
        "tradingPaused()",
        "uniswapFactory()",
        "weth()"
    ) | Sort-Object
    if (($factoryCallables -join "`n") -ne ($expectedFactoryCallables -join "`n")) {
        Fail "LaunchFactory callable ABI must remain fixed and must not expose authority transfer or rescue paths"
    }
    $factoryAbi = ConvertTo-StableJson $factoryAbiObject
    Compare-OrWrite (Join-Path $contractsRoot "abi/v1/LaunchFactory.json") $factoryAbi

    $storageContracts = @(
        [PSCustomObject]@{
            Contract = "BondingCurveV1"
            Golden = "BondingCurveV1"
        },
        [PSCustomObject]@{
            Contract = "LaunchFactory"
            Golden = "LaunchFactory"
        },
        [PSCustomObject]@{
            Contract = "LaunchToken"
            Golden = "LaunchToken"
        }
    )
    foreach ($entry in $storageContracts) {
        $layout = Invoke-ForgeJson @("inspect", $entry.Contract, "storage-layout", "--json")
        $normalized = Normalize-StorageLayout $layout
        $json = ConvertTo-StableJson $normalized
        $path = Join-Path $contractsRoot "storage-layout/v1/$($entry.Golden).json"
        Compare-OrWrite $path $json
    }

    if (-not $Write) {
        Write-Output "Golden artifacts verified."
    }
}
finally {
    Pop-Location
}
