param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("anvil", "robinhood-testnet", "robinhood-mainnet")]
    [string] $Target,

    [Parameter(Mandatory = $true)]
    [string] $RpcUrl,

    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[a-z0-9][a-z0-9._-]{2,63}$")]
    [string] $DeploymentId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern("^0x[0-9a-fA-F]{40}$")]
    [string] $Sender,

    [Parameter(Mandatory = $true)]
    [ValidatePattern("^0x[0-9a-fA-F]{40}$")]
    [string] $PauseAuthority,

    [Parameter(Mandatory = $true)]
    [ValidatePattern("^0x[0-9a-fA-F]{40}$")]
    [string] $Timelock,

    [Parameter(Mandatory = $true)]
    [ValidatePattern("^0x[0-9a-fA-F]{40}$")]
    [string] $ProtocolTreasury,

    [switch] $Broadcast,
    [switch] $Unlocked,
    [string] $Account,
    [string] $OutputPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$contractsRoot = Split-Path -Parent $PSScriptRoot
$deploymentsRoot = Join-Path $contractsRoot "deployments"
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)

function Fail([string] $Message) {
    throw "Deployment failed: $Message"
}

function Invoke-Checked([string] $Command, [string[]] $Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        Fail "$Command exited with $LASTEXITCODE"
    }
}

function Get-CodeHash([string] $Address) {
    $value = (& cast codehash $Address --rpc-url $RpcUrl | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $value -notmatch "^0x[0-9a-fA-F]{64}$") {
        Fail "could not read runtime code hash for $Address"
    }
    if ($value -eq ("0x" + ("0" * 64))) {
        Fail "runtime code is absent at $Address"
    }
    return $value
}

function Get-Creation([object] $BroadcastRecord, [string] $ContractName) {
    $matches = @(
        $BroadcastRecord.transactions | Where-Object {
            $_.contractName -eq $ContractName -and $_.transactionType -eq "CREATE"
        }
    )
    if ($matches.Count -ne 1) {
        Fail "expected exactly one $ContractName creation transaction, found $($matches.Count)"
    }
    return $matches[0]
}

function Get-CreationReceipt([object] $BroadcastRecord, [string] $ContractAddress) {
    $matches = @(
        $BroadcastRecord.receipts | Where-Object {
            [string] $_.contractAddress -ieq $ContractAddress
        }
    )
    if ($matches.Count -ne 1) {
        Fail "expected exactly one creation receipt for $ContractAddress, found $($matches.Count)"
    }
    return $matches[0]
}

function Convert-HexNumber([string] $Value) {
    if ($Value -notmatch "^0x[0-9a-fA-F]+$") {
        Fail "expected a hexadecimal quantity, got $Value"
    }
    return [Convert]::ToUInt64($Value.Substring(2), 16)
}

if ($Target -eq "robinhood-mainnet" -and $Broadcast) {
    Fail "mainnet broadcast is disabled until Task 11 fork verification and the external audit gate"
}
if ($Unlocked -and -not [string]::IsNullOrWhiteSpace($Account)) {
    Fail "choose either -Unlocked or -Account, not both"
}
if ($Broadcast -and -not $Unlocked -and [string]::IsNullOrWhiteSpace($Account)) {
    Fail "broadcast requires -Unlocked for Anvil or a named Foundry -Account"
}

$chainIdText = (& cast chain-id --rpc-url $RpcUrl | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $chainIdText -notmatch "^[0-9]+$") {
    Fail "could not read chain id"
}
$chainId = [uint64] $chainIdText

$name = "Local Anvil"
$environment = "local"
$explorerBase = ""
$weth = $null
$uniswapFactory = $null
$uniswapRouter = $null
$pairInitCodeHash = $null
$expectedWethRuntimeCodeHash = "0x" + ("0" * 64)
$expectedUniswapFactoryRuntimeCodeHash = "0x" + ("0" * 64)
$dependenciesReviewed = $Target -eq "anvil"

if ($Target -eq "anvil") {
    if ($chainId -ne 31337) { Fail "anvil target requires chain id 31337, got $chainId" }
}
elseif ($Target -eq "robinhood-testnet") {
    if ($chainId -ne 46630) { Fail "Robinhood testnet requires chain id 46630, got $chainId" }
    $activeConfigPath = Join-Path $deploymentsRoot "config/robinhood-testnet.json"
    $disabledConfigPath = Join-Path $deploymentsRoot "config/robinhood-testnet.disabled.json"
    if (Test-Path -LiteralPath $disabledConfigPath) {
        Fail "Robinhood testnet remains disabled; remove the marker only in the dependency-review commit"
    }
    if (-not (Test-Path -LiteralPath $activeConfigPath)) {
        Fail "Robinhood testnet is disabled; deploy and review testnet-specific dependencies first"
    }
    $config = Get-Content -Raw -LiteralPath $activeConfigPath | ConvertFrom-Json
    $name = [string] $config.name
    $environment = "testnet"
    $explorerBase = [string] $config.explorerBase
    $weth = [string] $config.weth
    $uniswapFactory = [string] $config.uniswapV2Factory
    if ($null -ne $config.PSObject.Properties["uniswapV2Router02"]) {
        $uniswapRouter = [string] $config.uniswapV2Router02
    }
    $pairInitCodeHash = [string] $config.pairInitCodeHash
    if ($config.reviewed -ne $true) { Fail "Robinhood testnet dependency config is not reviewed" }
    $expectedWethRuntimeCodeHash = [string] $config.bytecodeHashes.weth
    $expectedUniswapFactoryRuntimeCodeHash = [string] $config.bytecodeHashes.uniswapV2Factory
    $dependenciesReviewed = $true
}
else {
    if ($chainId -ne 4663) { Fail "Robinhood mainnet requires chain id 4663, got $chainId" }
    $configPath = Join-Path $deploymentsRoot "config/robinhood-mainnet.json"
    $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
    $name = [string] $config.name
    $environment = "production"
    $explorerBase = [string] $config.explorerBase
    $weth = [string] $config.weth
    $uniswapFactory = [string] $config.uniswapV2Factory
    $uniswapRouter = [string] $config.uniswapV2Router02
    $pairInitCodeHash = [string] $config.pairInitCodeHash
    if ($null -ne $config.PSObject.Properties["bytecodeHashes"]) {
        $expectedWethRuntimeCodeHash = [string] $config.bytecodeHashes.weth
        $expectedUniswapFactoryRuntimeCodeHash = [string] $config.bytecodeHashes.uniswapV2Factory
    }
    $dependenciesReviewed = $true
}

$previousEnvironment = @{}
$deploymentEnvironment = [ordered]@{
    DEPLOYMENT_TARGET = $Target
    DEPLOYER = $Sender
    PAUSE_AUTHORITY = $PauseAuthority
    TIMELOCK = $Timelock
    PROTOCOL_TREASURY = $ProtocolTreasury
}
if ($Target -ne "anvil") {
    $deploymentEnvironment.WETH = $weth
    $deploymentEnvironment.UNISWAP_V2_FACTORY = $uniswapFactory
    $deploymentEnvironment.PAIR_INIT_CODE_HASH = $pairInitCodeHash
    $deploymentEnvironment.EXPECTED_WETH_RUNTIME_CODE_HASH = $expectedWethRuntimeCodeHash
    $deploymentEnvironment.EXPECTED_UNISWAP_FACTORY_RUNTIME_CODE_HASH = $expectedUniswapFactoryRuntimeCodeHash
    $deploymentEnvironment.DEPENDENCIES_REVIEWED = "true"
}

Push-Location $contractsRoot
try {
    foreach ($entry in $deploymentEnvironment.GetEnumerator()) {
        $previousEnvironment[$entry.Key] = [Environment]::GetEnvironmentVariable(
            $entry.Key,
            [EnvironmentVariableTarget]::Process
        )
        [Environment]::SetEnvironmentVariable(
            $entry.Key,
            [string] $entry.Value,
            [EnvironmentVariableTarget]::Process
        )
    }

    $forgeArguments = @(
        "script",
        "script/DeployLaunchpad.s.sol:DeployLaunchpad",
        "--rpc-url", $RpcUrl,
        "--sender", $Sender
    )
    if ($Broadcast) {
        $forgeArguments += "--broadcast"
        if ($Unlocked) { $forgeArguments += "--unlocked" }
        else { $forgeArguments += @("--account", $Account) }
    }
    Invoke-Checked "forge" $forgeArguments

    if (-not $Broadcast) {
        Write-Output "Dry-run verified for $Target. No manifest was generated because no deployment transaction exists."
        return
    }

    $broadcastPath = Join-Path $contractsRoot "broadcast/DeployLaunchpad.s.sol/$chainId/run-latest.json"
    if (-not (Test-Path -LiteralPath $broadcastPath)) {
        Fail "missing Foundry broadcast record $broadcastPath"
    }
    $record = Get-Content -Raw -LiteralPath $broadcastPath | ConvertFrom-Json
    $factoryCreation = Get-Creation $record "LaunchFactory"
    $curveCreation = Get-Creation $record "BondingCurveV1"
    $factoryReceipt = Get-CreationReceipt $record ([string] $factoryCreation.contractAddress)

    $factory = [string] $factoryCreation.contractAddress
    $curveImplementation = [string] $curveCreation.contractAddress
    if ($Target -eq "anvil") {
        $weth = [string] (Get-Creation $record "LocalWETH").contractAddress
        $uniswapFactory = [string] (Get-Creation $record "LocalUniswapV2Factory").contractAddress
        $pairInitCodeHash = (& cast call $uniswapFactory "pairCodeHash()(bytes32)" --rpc-url $RpcUrl | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { Fail "could not read local pair init-code hash" }
    }

    $forgeVersionOutput = (& forge --version | Out-String)
    if ($forgeVersionOutput -notmatch "Version:\s+([0-9]+\.[0-9]+\.[0-9]+)") {
        Fail "could not determine Foundry version"
    }
    $foundryVersion = $Matches[1]

    $manifest = [ordered]@{
        schemaVersion = 1
        deploymentId = $DeploymentId
        name = $name
        environment = $environment
        chainId = $chainId
        factory = $factory
        startBlock = Convert-HexNumber ([string] $factoryReceipt.blockNumber)
        engineVersion = 1
        curveImplementation = $curveImplementation
        uniswapV2Factory = $uniswapFactory
        uniswapV2Router02 = $uniswapRouter
        weth = $weth
        pairInitCodeHash = $pairInitCodeHash
        lpBurnAddress = "0x000000000000000000000000000000000000dEaD"
        explorerBase = $explorerBase
        graduationEnabled = $true
        deployTransaction = [string] $factoryReceipt.transactionHash
        bytecodeHashes = [ordered]@{
            launchFactory = Get-CodeHash $factory
            bondingCurveV1 = Get-CodeHash $curveImplementation
            uniswapV2Factory = Get-CodeHash $uniswapFactory
            weth = Get-CodeHash $weth
        }
        compiler = [ordered]@{
            solcVersion = "0.8.36"
            optimizer = $true
            optimizerRuns = 200
            viaIr = $false
            evmVersion = "cancun"
        }
        toolchain = [ordered]@{ foundryVersion = $foundryVersion }
        governance = [ordered]@{
            pauseAuthority = $PauseAuthority
            timelock = $Timelock
            protocolTreasury = $ProtocolTreasury
            deployer = $Sender
        }
        verification = [ordered]@{
            dependenciesReviewed = $dependenciesReviewed
            pairInitCodeHashVerified = $true
            noResidualDeployerAuthority = $true
        }
    }

    $json = ($manifest | ConvertTo-Json -Depth 20) + "`n"
    if ($json -match '(?i)"(privateKey|mnemonic|keystorePassword|secret)"\s*:') {
        Fail "manifest contains a forbidden secret-bearing field"
    }
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = Join-Path $deploymentsRoot ".generated/$DeploymentId.json"
    }
    $resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
    $generatedRoot = [System.IO.Path]::GetFullPath((Join-Path $deploymentsRoot ".generated"))
    $generatedPrefix = $generatedRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedOutput.StartsWith($generatedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        Fail "candidate manifests must be written under deployments/.generated for review"
    }
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $resolvedOutput)) | Out-Null
    [System.IO.File]::WriteAllText($resolvedOutput, $json, $utf8WithoutBom)
    Write-Output "Generated candidate manifest $resolvedOutput"
}
finally {
    foreach ($entry in $deploymentEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable(
            $entry.Key,
            $previousEnvironment[$entry.Key],
            [EnvironmentVariableTarget]::Process
        )
    }
    Pop-Location
}
