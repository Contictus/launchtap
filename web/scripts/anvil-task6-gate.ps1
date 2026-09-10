param(
    [int]$Port = 0,
    [switch]$KeepAnvil
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Reproducible local transaction gate. It uses the repository's reviewed deployment script and
# Anvil's unlocked deterministic account; no private key, mnemonic, or production endpoint is read.
$webRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $webRoot
$contractsRoot = Join-Path $repoRoot "contracts"
$manifestPath = Join-Path $contractsRoot "deployments/.generated/task6-anvil.json"
$sender = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
$pauseAuthority = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
$timelock = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
$protocolTreasury = "0x90F79bf6EB2c4f870365E785982E1f101E93b906"
$anvilCommand = Get-Command anvil -ErrorAction SilentlyContinue
$forgeCommand = Get-Command forge -ErrorAction SilentlyContinue
$castCommand = Get-Command cast -ErrorAction SilentlyContinue
$anvilPath = if ($anvilCommand) { $anvilCommand.Path } else { $null }
$forgePath = if ($forgeCommand) { $forgeCommand.Path } else { $null }
$castPath = if ($castCommand) { $castCommand.Path } else { $null }
if (-not $anvilPath) { $anvilPath = "C:\Users\$env:USERNAME\.foundry\bin\anvil.exe" }
if (-not $forgePath) { $forgePath = "C:\Users\$env:USERNAME\.foundry\bin\forge.exe" }
if (-not $castPath) { $castPath = "C:\Users\$env:USERNAME\.foundry\bin\cast.exe" }
foreach ($path in @($anvilPath, $forgePath, $castPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Foundry executable not found: $path" }
}
$foundryBin = Split-Path -Parent $anvilPath
$env:Path = "$foundryBin;$env:Path"

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try { $listener.Start(); return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

if ($Port -eq 0) { $Port = Get-FreeTcpPort }
if ($Port -lt 1024 -or $Port -gt 65535) { throw "Port must be between 1024 and 65535" }
$rpcUrl = "http://127.0.0.1:$Port"
$process = $null
try {
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $anvilPath
    $start.Arguments = "--host 127.0.0.1 --port $Port --chain-id 31337 --silent --allow-origin http://127.0.0.1:3000"
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($start)
    for ($attempt = 0; $attempt -lt 100; $attempt++) {
        $chain = (& $castPath chain-id --rpc-url $rpcUrl 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $chain -eq "31337") { break }
        if ($process.HasExited) { throw "Anvil exited before RPC became ready" }
        Start-Sleep -Milliseconds 100
        if ($attempt -eq 99) { throw "Anvil RPC did not become ready" }
    }

    if (Test-Path -LiteralPath $manifestPath) { Remove-Item -LiteralPath $manifestPath -Force }
    & (Join-Path $contractsRoot "scripts/deploy.ps1") -Target anvil -RpcUrl $rpcUrl `
        -DeploymentId task6-anvil -Sender $sender -PauseAuthority $pauseAuthority `
        -Timelock $timelock -ProtocolTreasury $protocolTreasury -Broadcast -Unlocked `
        -OutputPath $manifestPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $manifestPath)) {
        throw "Authoritative local deployment did not produce a manifest"
    }
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    $factory = [string]$manifest.factory
    if ($factory -notmatch "^0x[0-9a-fA-F]{40}$") { throw "Invalid generated factory address" }
    $launchFee = (& $castPath call $factory "launchFee()(uint256)" --rpc-url $rpcUrl | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $launchFee -notmatch "^[0-9]+$") { throw "Could not read launch fee" }
    & $castPath send $factory "launch((string,string,uint16,uint256,uint256,uint256))" `
        '("Task6","T6",1,0,0,9999999999)' --value $launchFee `
        --from $sender --unlocked --rpc-url $rpcUrl | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Anvil launch write failed" }
    $env:TASK6_ANVIL_RPC_URL = $rpcUrl
    $env:TASK6_ANVIL_FACTORY = $factory
    Push-Location $webRoot
    try {
        npm.cmd run test:e2e -- e2e/task6-anvil.spec.ts
        if ($LASTEXITCODE -ne 0) { throw "Playwright Anvil transaction gate failed with exit code $LASTEXITCODE" }
    }
    finally { Pop-Location }
}
finally {
    Remove-Item Env:TASK6_ANVIL_RPC_URL -ErrorAction SilentlyContinue
    Remove-Item Env:TASK6_ANVIL_FACTORY -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $manifestPath) { Remove-Item -LiteralPath $manifestPath -Force }
    if ($null -ne $process -and -not $KeepAnvil -and -not $process.HasExited) {
        $process.Kill(); $process.WaitForExit(); $process.Dispose()
    }
}
