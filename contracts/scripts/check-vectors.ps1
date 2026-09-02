param(
    [switch] $Write
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$contractsRoot = Split-Path -Parent $PSScriptRoot
$artifactPath = Join-Path $contractsRoot "vectors/v1/curve-v1.json"
$schemaPath = Join-Path $contractsRoot "vectors/v1/curve.schema.json"
$generatedDirectory = Join-Path $contractsRoot "vectors/.generated"
$generatedPath = Join-Path $generatedDirectory "curve-v1.json"
$outputPath = if ($Write) { "./vectors/v1/curve-v1.json" } else { "./vectors/.generated/curve-v1.json" }
$previousOutput = [Environment]::GetEnvironmentVariable("CURVE_VECTORS_OUTPUT", "Process")

function Fail([string] $Message) {
    throw "Curve vector check failed: $Message"
}

function To-Amount([object] $Value) {
    $text = [string] $Value
    if ($text -notmatch '^(0|[1-9][0-9]*)$') {
        Fail "invalid uint256 decimal string: $text"
    }
    return [System.Numerics.BigInteger]::Parse($text)
}

function Assert-AmountFields([object] $Object, [string[]] $Fields, [string] $Context) {
    foreach ($field in $Fields) {
        if ($null -eq $Object.PSObject.Properties[$field]) {
            Fail "$Context is missing $field"
        }
        To-Amount $Object.$field | Out-Null
    }
}

function Assert-UnchangedState([object] $Case) {
    $initial = $Case.initialState | ConvertTo-Json -Depth 20 -Compress
    $next = $Case.nextState | ConvertTo-Json -Depth 20 -Compress
    if ($initial -ne $next) {
        Fail "$($Case.id) changed state on a reverting quote"
    }
}

Push-Location $contractsRoot
try {
    if (-not (Test-Path -LiteralPath $schemaPath)) {
        Fail "missing vectors/v1/curve.schema.json"
    }
    Get-Content -Raw -LiteralPath $schemaPath | ConvertFrom-Json | Out-Null

    if (-not $Write) {
        [System.IO.Directory]::CreateDirectory($generatedDirectory) | Out-Null
    }
    [Environment]::SetEnvironmentVariable("CURVE_VECTORS_OUTPUT", $outputPath, "Process")
    & forge script "script/GenerateCurveVectors.s.sol:GenerateCurveVectors" -q
    if ($LASTEXITCODE -ne 0) {
        Fail "Foundry generator exited with $LASTEXITCODE"
    }

    $candidatePath = if ($Write) { $artifactPath } else { $generatedPath }
    if (-not (Test-Path -LiteralPath $candidatePath)) {
        Fail "generator did not write $candidatePath"
    }
    $artifact = Get-Content -Raw -LiteralPath $candidatePath | ConvertFrom-Json

    if ($artifact.'$schema' -ne "./curve.schema.json") {
        Fail "artifact must reference ./curve.schema.json"
    }
    if ([int] $artifact.schemaVersion -ne 1 -or [int] $artifact.engineVersion -ne 1) {
        Fail "schemaVersion and engineVersion must both remain 1"
    }
    if ($artifact.amountEncoding -ne "uint256-decimal-string") {
        Fail "amountEncoding must remain uint256-decimal-string"
    }

    Assert-AmountFields $artifact.parameters @(
        "totalSupply",
        "curveTokens",
        "lpTokens",
        "graduationEth",
        "initialVirtualEth",
        "initialVirtualToken"
    ) "parameters"

    $expectedIds = @(
        "buy_normal",
        "buy_one_wei",
        "buy_fee_split_dust",
        "buy_final_exact",
        "buy_final_refund_and_graduation",
        "sell_normal",
        "sell_full",
        "invalid_buy_zero_input",
        "invalid_sell_zero_input",
        "invalid_sell_oversell",
        "invalid_sell_one_wei_zero_output"
    )
    $actualIds = @($artifact.cases | ForEach-Object { [string] $_.id })
    if (($actualIds -join "`n") -ne ($expectedIds -join "`n")) {
        Fail "case set or deterministic order has drifted"
    }

    $stateFields = @(
        "virtualEth",
        "virtualToken",
        "tokensSold",
        "realCurveEth",
        "protocolFees",
        "creatorFees"
    )
    $outputFields = @(
        "ethGross",
        "ethRefund",
        "ethOut",
        "tokenAmount",
        "protocolFee",
        "creatorFee"
    )
    foreach ($case in $artifact.cases) {
        Assert-AmountFields $case.initialState $stateFields "$($case.id).initialState"
        Assert-AmountFields $case.input @("ethGross", "tokensIn") "$($case.id).input"
        Assert-AmountFields $case.nextState $stateFields "$($case.id).nextState"

        if ($null -eq $case.expectedRevert) {
            if ($null -eq $case.output) {
                Fail "$($case.id) is missing a successful output"
            }
            Assert-AmountFields $case.output $outputFields "$($case.id).output"
            if ($case.operation -eq "buy") {
                $supplied = To-Amount $case.input.ethGross
                $consumed = (To-Amount $case.output.ethGross) + (To-Amount $case.output.ethRefund)
                if ($supplied -ne $consumed) {
                    Fail "$($case.id) does not conserve supplied buy ETH"
                }
            }
            elseif ($case.operation -eq "sell") {
                if ((To-Amount $case.output.ethRefund) -ne 0) {
                    Fail "$($case.id) records a sell refund"
                }
                if ((To-Amount $case.output.tokenAmount) -ne (To-Amount $case.input.tokensIn)) {
                    Fail "$($case.id) sell token amount differs from its input"
                }
            }
            else {
                Fail "$($case.id) has an unknown operation"
            }
        }
        else {
            if ($null -ne $case.output) {
                Fail "$($case.id) has both an output and an expected revert"
            }
            if ([string] $case.expectedRevert.data -notmatch '^0x[0-9a-f]+$') {
                Fail "$($case.id) has invalid revert data"
            }
            Assert-UnchangedState $case
        }
    }

    $oneWei = $artifact.cases | Where-Object id -eq "buy_one_wei"
    if ((To-Amount $oneWei.input.ethGross) -ne 1) {
        Fail "buy_one_wei no longer covers the one-wei buy boundary"
    }
    $feeDust = $artifact.cases | Where-Object id -eq "buy_fee_split_dust"
    if ((To-Amount $feeDust.output.protocolFee) -eq (To-Amount $feeDust.output.creatorFee)) {
        Fail "buy_fee_split_dust no longer exposes fee-split dust"
    }
    $finalExact = $artifact.cases | Where-Object id -eq "buy_final_exact"
    if (-not $finalExact.output.graduates -or (To-Amount $finalExact.output.ethRefund) -ne 0) {
        Fail "buy_final_exact must graduate without a refund"
    }
    $finalRefund = $artifact.cases | Where-Object id -eq "buy_final_refund_and_graduation"
    $finalRefundInvalid = -not $finalRefund.output.graduates
    $finalRefundInvalid = $finalRefundInvalid -or (To-Amount $finalRefund.output.ethRefund) -le 0
    $finalRefundInvalid = $finalRefundInvalid -or $finalRefund.nextState.phase -ne "graduated"
    if ($finalRefundInvalid) {
        Fail "buy_final_refund_and_graduation must refund and enter the graduated phase"
    }
    $fullSell = $artifact.cases | Where-Object id -eq "sell_full"
    if ((To-Amount $fullSell.nextState.tokensSold) -ne 0) {
        Fail "sell_full must restore zero tokens sold"
    }

    if (-not $Write) {
        if (-not (Test-Path -LiteralPath $artifactPath)) {
            Fail "missing vectors/v1/curve-v1.json; run ./scripts/check-vectors.ps1 -Write"
        }
        $expected = [System.IO.File]::ReadAllText($artifactPath)
        $actual = [System.IO.File]::ReadAllText($generatedPath)
        if ($actual -ne $expected) {
            Fail "vectors/v1/curve-v1.json has drifted; review and regenerate it"
        }
        Write-Output "Curve vectors verified."
    }
    else {
        Write-Output "Wrote $artifactPath"
    }
}
finally {
    if ($null -eq $previousOutput) {
        [Environment]::SetEnvironmentVariable("CURVE_VECTORS_OUTPUT", $null, "Process")
    }
    else {
        [Environment]::SetEnvironmentVariable("CURVE_VECTORS_OUTPUT", $previousOutput, "Process")
    }
    if (Test-Path -LiteralPath $generatedPath) {
        Remove-Item -LiteralPath $generatedPath -Force
    }
    if (Test-Path -LiteralPath $generatedDirectory) {
        Remove-Item -LiteralPath $generatedDirectory -Force
    }
    Pop-Location
}
