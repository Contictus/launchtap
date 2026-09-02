$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$contractsRoot = Split-Path -Parent $PSScriptRoot
$deploymentsRoot = Join-Path $contractsRoot "deployments"

function Fail([string] $Message) {
    throw "Deployment artifact check failed: $Message"
}

$schema = Get-Content -Raw -LiteralPath (Join-Path $deploymentsRoot "deployment.schema.json") |
    ConvertFrom-Json
$expectedRequired = @(
    "schemaVersion",
    "deploymentId",
    "name",
    "environment",
    "chainId",
    "factory",
    "startBlock",
    "engineVersion",
    "curveImplementation",
    "uniswapV2Factory",
    "uniswapV2Router02",
    "weth",
    "pairInitCodeHash",
    "lpBurnAddress",
    "explorerBase",
    "graduationEnabled",
    "deployTransaction",
    "bytecodeHashes",
    "compiler",
    "toolchain",
    "governance",
    "verification"
)
if ((@($schema.required) -join "`n") -ne ($expectedRequired -join "`n")) {
    Fail "deployment manifest required fields drifted"
}
if ($schema.additionalProperties -ne $false) {
    Fail "deployment manifest must reject unknown top-level fields"
}

$mainnet = Get-Content -Raw -LiteralPath (
    Join-Path $deploymentsRoot "config/robinhood-mainnet.json"
) | ConvertFrom-Json
if ([uint64] $mainnet.chainId -ne 4663) { Fail "mainnet chain id must remain 4663" }
if ([string] $mainnet.weth -cne "0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73") {
    Fail "mainnet WETH drifted from the reviewed dependency record"
}
if ([string] $mainnet.uniswapV2Factory -cne "0x8BceAA40b9aCdfAeDf85AdF4fF01f5ad6517937F") {
    Fail "mainnet Uniswap v2 factory drifted from the reviewed dependency record"
}
if ([string] $mainnet.uniswapV2Router02 -cne "0x89e5dB8B5aA49Aa85aC63F691524311aeB649eBA") {
    Fail "mainnet Uniswap v2 Router02 drifted from the reviewed dependency record"
}
if ([string] $mainnet.pairInitCodeHash -cne "0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f") {
    Fail "canonical Uniswap v2 pair init-code hash drifted"
}
foreach ($forbidden in @("factory", "curveImplementation", "pauseAuthority", "timelock")) {
    if ($null -ne $mainnet.PSObject.Properties[$forbidden]) {
        Fail "mainnet dependency config must not hand-enter deployment field $forbidden"
    }
}

$testnetDisabledPath = Join-Path $deploymentsRoot "config/robinhood-testnet.disabled.json"
$testnetActivePath = Join-Path $deploymentsRoot "config/robinhood-testnet.json"
if (Test-Path -LiteralPath $testnetActivePath) {
    if (Test-Path -LiteralPath $testnetDisabledPath) {
        Fail "active and disabled Robinhood testnet configs cannot coexist"
    }
    $testnetActive = Get-Content -Raw -LiteralPath $testnetActivePath | ConvertFrom-Json
    if ([uint64] $testnetActive.chainId -ne 46630 -or $testnetActive.reviewed -ne $true) {
        Fail "active Robinhood testnet dependencies must be explicitly reviewed"
    }
    if (
        [string] $testnetActive.weth -ieq [string] $mainnet.weth -or
        [string] $testnetActive.uniswapV2Factory -ieq [string] $mainnet.uniswapV2Factory
    ) {
        Fail "Robinhood testnet cannot reuse mainnet dependencies"
    }
}
else {
    if (-not (Test-Path -LiteralPath $testnetDisabledPath)) {
        Fail "Robinhood testnet requires an active reviewed config or an explicit disabled marker"
    }
    $testnetDisabled = Get-Content -Raw -LiteralPath $testnetDisabledPath | ConvertFrom-Json
    if ([uint64] $testnetDisabled.chainId -ne 46630 -or $testnetDisabled.enabled -ne $false) {
        Fail "Robinhood testnet must remain explicitly disabled until reviewed dependencies exist"
    }
    foreach ($forbidden in @("weth", "uniswapV2Factory", "uniswapV2Router02", "pairInitCodeHash")) {
        if ($null -ne $testnetDisabled.PSObject.Properties[$forbidden]) {
            Fail "disabled testnet config must not contain $forbidden"
        }
    }
}

$deploymentScripts = @(
    (Join-Path $contractsRoot "scripts/deploy.ps1"),
    (Join-Path $contractsRoot "scripts/bootstrap-testnet-dependencies.ps1")
)
foreach ($deploymentScript in $deploymentScripts) {
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $deploymentScript,
        [ref] $tokens,
        [ref] $parseErrors
    )
    if ($parseErrors.Count -ne 0) { Fail "$deploymentScript does not parse" }
    $parameterNames = @(
        $ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }
    )
    foreach ($forbiddenParameter in @("PrivateKey", "Mnemonic", "KeystorePassword", "Secret")) {
        if ($parameterNames -contains $forbiddenParameter) {
            Fail "$deploymentScript must not accept $forbiddenParameter"
        }
    }
    if ((Get-Content -Raw -LiteralPath $deploymentScript) -match "--private-key") {
        Fail "$deploymentScript must not pass raw private keys"
    }
}

$gitignore = Get-Content -Raw -LiteralPath (Join-Path $contractsRoot "../.gitignore")
if ($gitignore -notmatch "(?m)^/contracts/deployments/\.generated/$") {
    Fail "generated deployment candidates must remain git-ignored"
}

$trackedManifestCandidates = @(
    Get-ChildItem -LiteralPath $deploymentsRoot -File -Recurse -Filter "*.json" |
        Where-Object {
            $_.FullName -notmatch "[\\/]config[\\/]" -and
            $_.Name -ne "deployment.schema.json" -and
            $_.FullName -notmatch "[\\/]\.generated[\\/]"
        }
)
if ($trackedManifestCandidates.Count -ne 0) {
    Fail "generated deployment manifests must be reviewed before moving outside .generated"
}

Write-Output "Deployment scripts and manifest boundaries verified."
