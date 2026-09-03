$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$contractsRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $contractsRoot "src"

function Fail([string] $Message) {
    throw "Release review check failed: $Message"
}

$sourceFiles = @(
    Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Filter "*.sol" | Sort-Object FullName
)
if ($sourceFiles.Count -eq 0) {
    Fail "no Solidity sources found under src/"
}

$forbiddenPatterns = @(
    @{
        Label = "an upgrade or proxy hook"
        Pattern = "(?i)\b(delegatecall|upgradeTo|upgradeToAndCall|_authorizeUpgrade|__gap|setImplementation)\b"
    },
    @{
        Label = "a self-destruct path"
        Pattern = "(?i)\b(selfdestruct|suicide)\b"
    },
    @{
        Label = "an owner or admin control"
        Pattern = "(?i)\b(Ownable|onlyOwner|AccessControl|onlyRole|transferOwnership)\b"
    },
    @{
        Label = "a test-only import"
        Pattern = "(?i)(forge-std|hardhat/console|console2?\.sol|[""'][^""']*Test\.sol[""'])"
    },
    @{
        Label = "a cheatcode reference"
        Pattern = "(?i)\bvm\.[a-z]"
    },
    @{
        Label = "an unresolved marker"
        Pattern = "\b(TODO|FIXME|XXX|HACK|PLACEHOLDER)\b"
    }
)

$allowedAddressLiterals = @(
    "0x000000000000000000000000000000000000dEaD"
)

foreach ($file in $sourceFiles) {
    $relative = $file.FullName.Substring($contractsRoot.Length + 1).Replace("\", "/")
    $text = [System.IO.File]::ReadAllText($file.FullName)

    foreach ($rule in $forbiddenPatterns) {
        if ($text -match $rule.Pattern) {
            Fail "$relative contains $($rule.Label)"
        }
    }

    foreach ($match in [regex]::Matches($text, "0x[0-9a-fA-F]{40}")) {
        if ($allowedAddressLiterals -ccontains $match.Value) {
            continue
        }
        Fail "$relative contains an unreviewed address literal $($match.Value)"
    }
}

$checkScript = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "check.ps1"))
foreach ($gate in @(
    "check-dependencies.ps1",
    "check-goldens.ps1",
    "check-vectors.ps1",
    "check-deployments.ps1",
    "check-release.ps1",
    "check-sizes.ps1",
    "check-slither.ps1",
    "check-fork.ps1"
)) {
    if ($checkScript.IndexOf($gate, [System.StringComparison]::Ordinal) -lt 0) {
        Fail "check.ps1 no longer invokes $gate"
    }
}

Write-Output "Release review verified."
