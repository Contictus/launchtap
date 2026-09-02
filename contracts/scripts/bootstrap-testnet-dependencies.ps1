param(
    [Parameter(Mandatory = $true)]
    [string] $RpcUrl,

    [Parameter(Mandatory = $true)]
    [ValidatePattern("^0x[0-9a-fA-F]{40}$")]
    [string] $Sender,

    [switch] $Broadcast,
    [switch] $Unlocked,
    [string] $Account
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$contractsRoot = Split-Path -Parent $PSScriptRoot
$candidatePath = Join-Path $contractsRoot "deployments/.generated/robinhood-testnet-dependencies.json"
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)

function Fail([string] $Message) {
    throw "Testnet dependency bootstrap failed: $Message"
}

function Get-Creation([object] $Record, [string] $ContractName) {
    $matches = @(
        $Record.transactions | Where-Object {
            $_.contractName -eq $ContractName -and $_.transactionType -eq "CREATE"
        }
    )
    if ($matches.Count -ne 1) {
        Fail "expected exactly one $ContractName creation transaction, found $($matches.Count)"
    }
    return $matches[0]
}

function Get-CreationReceipt([object] $Record, [string] $ContractAddress) {
    $matches = @(
        $Record.receipts | Where-Object {
            [string] $_.contractAddress -ieq $ContractAddress
        }
    )
    if ($matches.Count -ne 1) {
        Fail "expected exactly one creation receipt for $ContractAddress, found $($matches.Count)"
    }
    return $matches[0]
}

if ($Unlocked -and -not [string]::IsNullOrWhiteSpace($Account)) {
    Fail "choose either -Unlocked or -Account, not both"
}
if ($Broadcast -and -not $Unlocked -and [string]::IsNullOrWhiteSpace($Account)) {
    Fail "broadcast requires -Unlocked or a named Foundry -Account"
}

$chainId = (& cast chain-id --rpc-url $RpcUrl | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $chainId -ne "46630") {
    Fail "expected Robinhood testnet chain id 46630, got $chainId"
}

$previousDeployer = [Environment]::GetEnvironmentVariable(
    "DEPLOYER",
    [EnvironmentVariableTarget]::Process
)
[Environment]::SetEnvironmentVariable(
    "DEPLOYER",
    $Sender,
    [EnvironmentVariableTarget]::Process
)

Push-Location $contractsRoot
try {
    $arguments = @(
        "script",
        "script/DeployTestnetDependencies.s.sol:DeployTestnetDependencies",
        "--rpc-url", $RpcUrl,
        "--sender", $Sender
    )
    if ($Broadcast) {
        $arguments += "--broadcast"
        if ($Unlocked) { $arguments += "--unlocked" }
        else { $arguments += @("--account", $Account) }
    }
    & forge @arguments
    if ($LASTEXITCODE -ne 0) { Fail "forge script exited with $LASTEXITCODE" }

    if (-not $Broadcast) {
        Write-Output "Testnet dependency bootstrap dry-run verified. Nothing was broadcast."
        return
    }

    $broadcastPath = Join-Path $contractsRoot "broadcast/DeployTestnetDependencies.s.sol/46630/run-latest.json"
    $record = Get-Content -Raw -LiteralPath $broadcastPath | ConvertFrom-Json
    $wethCreation = Get-Creation $record "LocalWETH"
    $factoryCreation = Get-Creation $record "LocalUniswapV2Factory"
    $weth = [string] $wethCreation.contractAddress
    $factory = [string] $factoryCreation.contractAddress
    $wethReceipt = Get-CreationReceipt $record $weth
    $factoryReceipt = Get-CreationReceipt $record $factory
    $pairInitCodeHash = (& cast call $factory "pairCodeHash()(bytes32)" --rpc-url $RpcUrl | Out-String).Trim()
    $wethCodeHash = (& cast codehash $weth --rpc-url $RpcUrl | Out-String).Trim()
    $factoryCodeHash = (& cast codehash $factory --rpc-url $RpcUrl | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { Fail "could not read deployed dependency evidence" }

    $candidate = [ordered]@{
        schemaVersion = 1
        target = "robinhood-testnet"
        chainId = 46630
        name = "Robinhood Chain Testnet"
        explorerBase = "https://explorer.testnet.chain.robinhood.com"
        reviewed = $false
        weth = $weth
        uniswapV2Factory = $factory
        uniswapV2Router02 = $null
        pairInitCodeHash = $pairInitCodeHash
        deployTransactions = [ordered]@{
            weth = [string] $wethReceipt.transactionHash
            uniswapV2Factory = [string] $factoryReceipt.transactionHash
        }
        bytecodeHashes = [ordered]@{
            weth = $wethCodeHash
            uniswapV2Factory = $factoryCodeHash
        }
    }
    $json = ($candidate | ConvertTo-Json -Depth 10) + "`n"
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $candidatePath)) | Out-Null
    [System.IO.File]::WriteAllText($candidatePath, $json, $utf8WithoutBom)
    Write-Output "Generated unreviewed testnet dependency candidate $candidatePath"
}
finally {
    [Environment]::SetEnvironmentVariable(
        "DEPLOYER",
        $previousDeployer,
        [EnvironmentVariableTarget]::Process
    )
    Pop-Location
}
