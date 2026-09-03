# Task 12 contract release gate coverage

## Reproduction

Run the full release gate from `contracts/` with Python, the pinned `slither-analyzer` from
`slither/v1/slither-version.txt` on `PATH`, and the archive RPC endpoint set:

```powershell
$archiveRpc = Read-Host "QuickNode Robinhood archive RPC URL" -AsSecureString
$env:ROBINHOOD_MAINNET_ARCHIVE_RPC_URL =
  [System.Net.NetworkCredential]::new("", $archiveRpc).Password
./scripts/check.ps1 release
Remove-Item Env:ROBINHOOD_MAINNET_ARCHIVE_RPC_URL
Remove-Variable archiveRpc
```

`check.ps1 release` runs, in order, `check-dependencies.ps1`, `forge fmt --check`,
`forge build`, `check-goldens.ps1`, `check-vectors.ps1`, `check-deployments.ps1`,
`check-release.ps1`, `forge test`, `forge lint`, `check-sizes.ps1`, `check-slither.ps1`, and
`check-fork.ps1`. Every sub-check fails closed: a missing tool, missing baseline, missing
archive endpoint, or any drift aborts the run with a non-zero exit. The GitHub Actions
`Release gate` job invokes this exact command on `workflow_dispatch` and never converts a
missing capability into a skipped step.

## Proved by Task 12

- The reproducible security verification of the immutable V1 engine runs as one gate:
  formatting, warnings-as-error build, unit/fuzz/invariant tests, the deterministic curve
  vector regeneration diff, Slither, the frozen event ABI and callable allowlists, the
  frozen storage layouts, the frozen runtime and init bytecode sizes, the deployment
  simulation, and the pinned Robinhood mainnet fork suite.
- `check-sizes.ps1` records the runtime and init byte counts of `BondingCurveV1`,
  `LaunchFactory`, and `LaunchToken` in `sizes/v1/sizes.json` and fails on any byte drift,
  so an unintended bytecode change cannot pass unreviewed even when it stays under the
  EIP-170 limit that `forge build --sizes` already enforces.
- `check-release.ps1` statically rejects, in `src/`, an upgrade or proxy hook, a
  self-destruct path, an owner or admin control, a test-only import or cheatcode reference,
  an unresolved marker, and any address literal other than the reviewed LP burn sink. It
  also fails if `check.ps1` stops invoking any required gate.
- `check-slither.ps1` refuses to run without the pinned analyzer version, applies
  `slither.config.json`, and fails on any finding of medium or higher impact that is not
  recorded in the reviewed `slither.db.json` triage database.
- `check.ps1 all` (the push and pull-request gate) gains the release review and the size
  freeze; Slither and the fork suite remain in `release` only because they need Python and
  the archive secret.

## Final diff review

The independent review of the Task 12 diff and the frozen V1 surface against the acceptance
checklist:

- **Upgrade or rescue paths** — none. No proxy, `delegatecall`, `selfdestruct`,
  `_authorizeUpgrade`, admin withdrawal, or arbitrary call in `src/`; `check-release.ps1`
  enforces this and the `LaunchFactory` and `LaunchToken` callable allowlists in
  `check-goldens.ps1` reject authority-transfer and rescue selectors.
- **Unchecked external calls** — none unguarded. Market-delivery ETH sends use a capped gas
  probe and fall back to pull refunds; explicit claims revert on failure;
  `BondingCurveV1Storage` retains the storage `ReentrancyGuard` (asserted by
  `check-goldens.ps1`); Slither's low-level-call and reentrancy detectors run at medium
  impact with triage recorded in `slither.db.json`.
- **Mutable launch fields** — none. Clones initialize atomically and disable
  re-initialization; there is no post-launch parameter setter in the frozen ABI.
- **Dependency drift** — `check-dependencies.ps1` pins the Foundry binary and commit, the
  toolchain action, OpenZeppelin, and forge-std; `check-goldens.ps1` pins solc `0.8.36`,
  optimizer 200 runs, `via_ir = false`, `evm_version = cancun`, and `deny = warnings`.
- **Placeholder addresses** — none. The only 40-hex literal in `src/` is
  `0x000000000000000000000000000000000000dEaD`; deployment dependencies are constructor
  inputs validated by `check-deployments.ps1` against the reviewed mainnet record.
- **Test-only code** — none in `src/`. `check-release.ps1` rejects `forge-std`, `console`,
  `*Test.sol` imports, and `vm.` cheatcode references.
- **Optimizer mismatch** — none. The compiler pipeline assertion in `check-goldens.ps1` and
  the size freeze in `check-sizes.ps1` both fail if the optimizer configuration changes.

## Slither

Slither runs with the pinned `slither-analyzer` recorded in
`slither/v1/slither-version.txt`, installed in CI as
`pipx install slither-analyzer==<pinned>`. `slither.config.json` filters `lib/`, `test/`,
`fork-test/`, and `script/`, excludes dependency results, and disables the informational
naming, pragma, and digit detectors that the pinned compiler and locked economics make
noise. The gate uses `--fail-on medium`, so a low or informational finding does not fail the
build but any unresolved medium or high finding does. Reviewed false positives are recorded
in `slither.db.json`; each entry is justified against the checklist above.

## Deferred

An external audit remains a separate mandatory gate before mainnet funds are accepted.
Passing this gate is reproducible in-house verification and independent model review only;
it is not represented as an external audit. Production authority selection, the audit
vendor, monitoring, and the mainnet deployment checklist stay tracked under the
"Production governance and audit inputs" backlog item.

## Accepted release-gate run

_Pending: fill with the GitHub Actions `workflow_dispatch` run id and commit hash once the
`Foundry`, `Release gate`, and `Robinhood mainnet fork` jobs pass green._
