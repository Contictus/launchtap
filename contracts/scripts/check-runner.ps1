function Invoke-Checked([scriptblock] $Command) {
    # Reset the inherited native status so a scriptblock that does not invoke a
    # native process cannot accidentally inherit an earlier failure.
    $global:LASTEXITCODE = 0
    & $Command
    $commandSucceeded = $?
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Contract check failed with exit code $exitCode"
    }
    if (-not $commandSucceeded) {
        throw "Contract check failed"
    }
}
