$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$backendRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $backendRoot
$contractsRoot = Join-Path $repositoryRoot "contracts"
$deploymentId = "anvil-indexer-e2e"
$manifestPath = Join-Path $contractsRoot "deployments/.generated/$deploymentId.json"
$sender = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
$pauseAuthority = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
$timelock = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
$protocolTreasury = "0x90F79bf6EB2c4f870365E785982E1f101E93b906"
$anvilProcess = $null

function Fail([string] $Message) { throw "Anvil indexer E2E failed: $Message" }

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try { $listener.Start(); return ([System.Net.IPEndPoint] $listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

foreach ($command in @("anvil", "cast", "forge")) {
    if ($null -eq (Get-Command $command -ErrorAction SilentlyContinue)) { Fail "$command is not on PATH" }
}

$port = Get-FreeTcpPort
$rpcURL = "http://127.0.0.1:$port"
$start = [System.Diagnostics.ProcessStartInfo]::new()
$start.FileName = (Get-Command anvil).Source
$start.Arguments = "--host 127.0.0.1 --port $port --chain-id 31337 --silent"
$start.UseShellExecute = $false
$start.CreateNoWindow = $true

try {
    if (Test-Path -LiteralPath $manifestPath) { Remove-Item -LiteralPath $manifestPath -Force }
    $anvilProcess = [System.Diagnostics.Process]::Start($start)
    if ($null -eq $anvilProcess) { Fail "could not start Anvil" }
    for ($attempt = 0; $attempt -lt 100; ++$attempt) {
        $chainID = (& cast chain-id --rpc-url $rpcURL 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $chainID -eq "31337") { break }
        if ($anvilProcess.HasExited) { Fail "Anvil exited before becoming ready" }
        Start-Sleep -Milliseconds 100
        if ($attempt -eq 99) { Fail "Anvil RPC did not become ready" }
    }

    & "$contractsRoot/scripts/deploy.ps1" -Target anvil -RpcUrl $rpcURL -DeploymentId $deploymentId -Sender $sender -PauseAuthority $pauseAuthority -Timelock $timelock -ProtocolTreasury $protocolTreasury -Broadcast -Unlocked -OutputPath $manifestPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $manifestPath)) { Fail "deployment did not produce a manifest" }
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    $factory = [string]$manifest.factory
    & cast send $factory "launch((string,string,uint16,uint256,uint256,uint256))" '("Anvil","ANVL",1,0,0,9999999999)' --from $sender --unlocked --rpc-url $rpcURL | Out-Host
    if ($LASTEXITCODE -ne 0) { Fail "launch transaction failed" }

    $env:ANVIL_INDEXER_RPC_URL = $rpcURL
    $env:ANVIL_INDEXER_FACTORY = $factory
    $env:ANVIL_INDEXER_START_BLOCK = [string]$manifest.startBlock
    Push-Location $backendRoot
    try {
        go test -tags=integration -race -run '^TestAnvilIndexerEndToEnd$' ./internal/indexer/...
        if ($LASTEXITCODE -ne 0) { Fail "Go indexer test failed" }
    }
    finally { Pop-Location }
}
finally {
    Remove-Item Env:ANVIL_INDEXER_RPC_URL -ErrorAction SilentlyContinue
    Remove-Item Env:ANVIL_INDEXER_FACTORY -ErrorAction SilentlyContinue
    Remove-Item Env:ANVIL_INDEXER_START_BLOCK -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $manifestPath) { Remove-Item -LiteralPath $manifestPath -Force }
    if ($null -ne $anvilProcess) {
        if (-not $anvilProcess.HasExited) { $anvilProcess.Kill(); $anvilProcess.WaitForExit() }
        $anvilProcess.Dispose()
    }
}
