$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$contractsRoot = Split-Path -Parent $PSScriptRoot
$deploymentsRoot = Join-Path $contractsRoot "deployments"
$sender = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
$pauseAuthority = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
$timelock = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
$protocolTreasury = "0x90F79bf6EB2c4f870365E785982E1f101E93b906"
$deploymentId = "release-simulation-v1"
$manifestPath = Join-Path $deploymentsRoot ".generated/$deploymentId.json"
$anvilProcess = $null

function Fail([string] $Message) {
    throw "Deployment simulation failed: $Message"
}

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new(
        [System.Net.IPAddress]::Loopback,
        0
    )
    try {
        $listener.Start()
        return ([System.Net.IPEndPoint] $listener.LocalEndpoint).Port
    }
    finally {
        $listener.Stop()
    }
}

$anvil = Get-Command anvil -ErrorAction SilentlyContinue
if ($null -eq $anvil) {
    Fail "anvil is not on PATH"
}
if (-not (Get-Command cast -ErrorAction SilentlyContinue)) {
    Fail "cast is not on PATH"
}

$port = Get-FreeTcpPort
$rpcUrl = "http://127.0.0.1:$port"
$processStart = New-Object System.Diagnostics.ProcessStartInfo
$processStart.FileName = $anvil.Source
$processStart.Arguments = "--host 127.0.0.1 --port $port --chain-id 31337 --silent"
$processStart.UseShellExecute = $false
$processStart.CreateNoWindow = $true

try {
    if (Test-Path -LiteralPath $manifestPath) {
        Remove-Item -LiteralPath $manifestPath -Force
    }

    $anvilProcess = [System.Diagnostics.Process]::Start($processStart)
    if ($null -eq $anvilProcess) {
        Fail "could not start Anvil"
    }

    $ready = $false
    for ($attempt = 0; $attempt -lt 100; ++$attempt) {
        if ($anvilProcess.HasExited) {
            Fail "Anvil exited before its RPC endpoint became ready"
        }

        $chainId = (& cast chain-id --rpc-url $rpcUrl 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $chainId -eq "31337") {
            $ready = $true
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not $ready) {
        Fail "Anvil RPC did not become ready at $rpcUrl"
    }

    & "$PSScriptRoot/deploy.ps1" `
        -Target anvil `
        -RpcUrl $rpcUrl `
        -DeploymentId $deploymentId `
        -Sender $sender `
        -PauseAuthority $pauseAuthority `
        -Timelock $timelock `
        -ProtocolTreasury $protocolTreasury `
        -Broadcast `
        -Unlocked `
        -OutputPath $manifestPath
    if (-not $?) {
        Fail "deploy.ps1 returned an unsuccessful status"
    }

    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Fail "deploy.ps1 did not generate the candidate manifest"
    }
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    if (
        [uint64] $manifest.chainId -ne 31337 -or
        [string] $manifest.environment -cne "local" -or
        [string] $manifest.deploymentId -cne $deploymentId -or
        [uint64] $manifest.startBlock -eq 0
    ) {
        Fail "generated manifest does not describe the simulated Anvil deployment"
    }
    foreach ($field in @("factory", "curveImplementation", "uniswapV2Factory", "weth")) {
        $address = [string] $manifest.$field
        if ($address -notmatch "^0x[0-9a-fA-F]{40}$") {
            Fail "generated manifest field $field is not an address"
        }
        $runtimeCode = (& cast code $address --rpc-url $rpcUrl | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $runtimeCode -eq "0x") {
            Fail "generated manifest field $field has no deployed runtime code"
        }
    }
    if (
        $manifest.verification.dependenciesReviewed -ne $true -or
        $manifest.verification.pairInitCodeHashVerified -ne $true -or
        $manifest.verification.noResidualDeployerAuthority -ne $true
    ) {
        Fail "generated manifest does not contain complete deployment verification evidence"
    }

    Write-Output "Anvil deployment simulation verified."
}
finally {
    if (Test-Path -LiteralPath $manifestPath) {
        Remove-Item -LiteralPath $manifestPath -Force
    }
    if ($null -ne $anvilProcess) {
        if (-not $anvilProcess.HasExited) {
            $anvilProcess.Kill()
            $anvilProcess.WaitForExit()
        }
        $anvilProcess.Dispose()
    }
}
