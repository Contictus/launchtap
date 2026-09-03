param(
    [string] $RpcUrl = $env:ROBINHOOD_MAINNET_ARCHIVE_RPC_URL
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$contractsRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $contractsRoot "deployments/config/robinhood-mainnet.json"
$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json

function Fail([string] $Message) {
    throw "Robinhood mainnet fork check failed: $Message"
}

function Invoke-Text([string] $Command, [string[]] $Arguments) {
    $value = (& $Command @Arguments | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { Fail "$Command exited with $LASTEXITCODE" }
    return $value
}

if ([string]::IsNullOrWhiteSpace($RpcUrl)) {
    Fail "ROBINHOOD_MAINNET_ARCHIVE_RPC_URL is required; the fork test is never skipped"
}

$rpcUri = [Uri] $RpcUrl
$quickNodeHostSuffix = ".robinhood-mainnet.quiknode.pro"
if (
    $rpcUri.Scheme -ne "https" -or
    $rpcUri.Host.Length -le $quickNodeHostSuffix.Length -or
    -not $rpcUri.Host.EndsWith(
        $quickNodeHostSuffix,
        [StringComparison]::OrdinalIgnoreCase
    )
) {
    Fail "the recorded Task 11 archive provider is QuickNode; configure its HTTPS Robinhood mainnet endpoint"
}

$chainId = Invoke-Text "cast" @("chain-id", "--rpc-url", $RpcUrl)
if ($chainId -ne "4663") { Fail "expected chain id 4663, got $chainId" }

$forkBlock = [uint64] $config.forkVerification.blockNumber
$blockHash = Invoke-Text "cast" @(
    "block", [string] $forkBlock, "--field", "hash", "--rpc-url", $RpcUrl
)
if ($blockHash -cne [string] $config.forkVerification.blockHash) {
    Fail "fork block hash does not match the reviewed evidence"
}

foreach ($dependency in @(
    @{ Name = "WETH"; Address = [string] $config.weth; Hash = [string] $config.bytecodeHashes.weth },
    @{
        Name = "Uniswap v2 Factory"
        Address = [string] $config.uniswapV2Factory
        Hash = [string] $config.bytecodeHashes.uniswapV2Factory
    }
)) {
    $actual = Invoke-Text "cast" @(
        "codehash", $dependency.Address, "--block", [string] $forkBlock,
        "--rpc-url", $RpcUrl
    )
    if ($actual -cne $dependency.Hash) {
        Fail "$($dependency.Name) runtime code hash does not match the reviewed evidence"
    }
}

$previousProfile = [Environment]::GetEnvironmentVariable(
    "FOUNDRY_PROFILE", [EnvironmentVariableTarget]::Process
)
[Environment]::SetEnvironmentVariable(
    "FOUNDRY_PROFILE", "fork", [EnvironmentVariableTarget]::Process
)
Push-Location $contractsRoot
try {
    & forge test --fork-url $RpcUrl --fork-block-number $forkBlock -vvv
    if ($LASTEXITCODE -ne 0) { Fail "forge fork suite exited with $LASTEXITCODE" }
}
finally {
    Pop-Location
    [Environment]::SetEnvironmentVariable(
        "FOUNDRY_PROFILE", $previousProfile, [EnvironmentVariableTarget]::Process
    )
}

Write-Output "Robinhood mainnet fork compatibility verified at block $forkBlock via QuickNode."
