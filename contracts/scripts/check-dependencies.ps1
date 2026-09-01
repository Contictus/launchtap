$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$contractsRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $contractsRoot
$lockPath = Join-Path $contractsRoot "dependencies.lock"
$foundryLockPath = Join-Path $contractsRoot "foundry.lock"
$workflowPath = Join-Path $repositoryRoot ".github/workflows/contracts.yml"

function Fail([string] $Message) {
    throw "Dependency pin check failed: $Message"
}

$pins = @{}
foreach ($line in Get-Content -LiteralPath $lockPath) {
    $trimmed = $line.Trim()
    if ($trimmed.Length -eq 0 -or $trimmed.StartsWith("#")) {
        continue
    }

    $parts = $trimmed.Split("=", 2)
    if ($parts.Count -ne 2 -or $pins.ContainsKey($parts[0])) {
        Fail "invalid or duplicate lock entry '$trimmed'"
    }
    $pins[$parts[0]] = $parts[1]
}

$requiredPins = @(
    "FOUNDRY_VERSION",
    "FOUNDRY_COMMIT",
    "FOUNDRY_TOOLCHAIN_ACTION_VERSION",
    "FOUNDRY_TOOLCHAIN_ACTION_COMMIT",
    "OPENZEPPELIN_VERSION",
    "OPENZEPPELIN_COMMIT",
    "FORGE_STD_VERSION",
    "FORGE_STD_COMMIT"
)
foreach ($requiredPin in $requiredPins) {
    if (-not $pins.ContainsKey($requiredPin)) {
        Fail "missing $requiredPin"
    }
}

$forge = Get-Command forge -ErrorAction SilentlyContinue
if ($null -eq $forge) {
    Fail "forge is not on PATH"
}

$forgeVersion = (& forge --version | Out-String)
if ($LASTEXITCODE -ne 0) {
    Fail "forge --version exited with $LASTEXITCODE"
}
$expectedVersion = $pins["FOUNDRY_VERSION"].TrimStart("v")
if ($forgeVersion -notmatch "Version:\s+$([regex]::Escape($expectedVersion))(\s|$)") {
    Fail "expected Foundry $($pins['FOUNDRY_VERSION'])"
}
if ($forgeVersion -notmatch "Commit SHA:\s+$([regex]::Escape($pins['FOUNDRY_COMMIT']))(\s|$)") {
    Fail "expected Foundry commit $($pins['FOUNDRY_COMMIT'])"
}

$dependencies = @(
    @{
        Name = "OpenZeppelin Contracts"
        Path = Join-Path $contractsRoot "lib/openzeppelin-contracts"
        Submodule = "contracts/lib/openzeppelin-contracts"
        Url = "https://github.com/OpenZeppelin/openzeppelin-contracts.git"
        Commit = $pins["OPENZEPPELIN_COMMIT"]
    },
    @{
        Name = "forge-std"
        Path = Join-Path $contractsRoot "lib/forge-std"
        Submodule = "contracts/lib/forge-std"
        Url = "https://github.com/foundry-rs/forge-std.git"
        Commit = $pins["FORGE_STD_COMMIT"]
    }
)

foreach ($dependency in $dependencies) {
    if (-not (Test-Path -LiteralPath $dependency.Path)) {
        Fail "$($dependency.Name) is not installed"
    }

    $actualCommit = (& git -C $dependency.Path rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $actualCommit -ne $dependency.Commit) {
        Fail "$($dependency.Name) expected $($dependency.Commit), got $actualCommit"
    }

    $dirty = (& git -C $dependency.Path status --porcelain | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $dirty.Length -ne 0) {
        Fail "$($dependency.Name) has local changes"
    }

    $urlKey = "submodule.$($dependency.Submodule).url"
    $actualUrl = (& git -C $repositoryRoot config -f .gitmodules --get $urlKey).Trim()
    if ($LASTEXITCODE -ne 0 -or $actualUrl -ne $dependency.Url) {
        Fail "$($dependency.Name) expected URL $($dependency.Url), got $actualUrl"
    }
}

$foundryLock = Get-Content -Raw -LiteralPath $foundryLockPath | ConvertFrom-Json -AsHashtable
$foundryDependencies = @(
    @{
        Path = "lib/openzeppelin-contracts"
        Version = $pins["OPENZEPPELIN_VERSION"]
        Commit = $pins["OPENZEPPELIN_COMMIT"]
    },
    @{
        Path = "lib/forge-std"
        Version = $pins["FORGE_STD_VERSION"]
        Commit = $pins["FORGE_STD_COMMIT"]
    }
)
foreach ($dependency in $foundryDependencies) {
    if (-not $foundryLock.ContainsKey($dependency.Path)) {
        Fail "foundry.lock is missing $($dependency.Path)"
    }

    $entry = $foundryLock[$dependency.Path]
    if ($entry.tag.name -ne $dependency.Version -or $entry.tag.rev -ne $dependency.Commit) {
        Fail "foundry.lock drift for $($dependency.Path)"
    }
}

$workflow = Get-Content -Raw -LiteralPath $workflowPath
$actionReference = "foundry-rs/foundry-toolchain@$($pins['FOUNDRY_TOOLCHAIN_ACTION_COMMIT'])"
if (-not $workflow.Contains($actionReference)) {
    Fail "contract CI does not pin $actionReference"
}
$versionInput = "version: $($pins['FOUNDRY_VERSION'])"
if (-not $workflow.Contains($versionInput)) {
    Fail "contract CI does not select $versionInput"
}

Write-Output "Dependency pins verified."
