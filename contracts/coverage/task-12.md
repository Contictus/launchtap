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
  `slither.config.json`, runs `slither . --fail-medium`, and fails on any finding of medium
  or higher impact that is not recorded in the reviewed `slither.db.json` triage database.
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
  `check-goldens.ps1`). Slither reports only `reentrancy-benign`, `low-level-calls`, and
  `arbitrary-send-eth` on these paths; each is triaged in `slither.db.json` with the
  rationale in the Slither section below.
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

Slither runs with `slither-analyzer` `0.11.6`, recorded in `slither/v1/slither-version.txt`
and installed in CI as `pipx install slither-analyzer==0.11.6`. `slither.config.json`
filters `lib/`, `test/`, `fork-test/`, and `script/`, excludes dependency results, and
disables the informational naming, pragma, and digit detectors that the pinned compiler and
locked economics turn into noise. The gate runs `slither . --fail-medium`: a low,
informational, or optimization finding does not fail the build, but any medium or high
finding that is not in `slither.db.json` does.

The 2026-09-04 run (35 contracts, 98 detectors) produced 20 results: 11 low, 3
informational, 1 optimization group, and the 5 medium-or-higher findings below. All 5 are
false positives for the locked immutable V1 design and are triaged into `slither.db.json` by
result id; a new medium or high finding outside that set still fails the gate.

- `arbitrary-send-eth` (High, Medium confidence) — `BondingCurveV1._graduate` sends
  `_graduationEth` via `IWETH(_weth).deposit{value: ...}()`. `_weth` is set once in
  `initialize()` from the factory snapshot and is the reviewed canonical WETH
  (`check-deployments.ps1` and the fork test pin its address and runtime hash); it is not a
  call-time argument.
- `arbitrary-send-eth` (High, Medium confidence) — `LaunchFactory._callDeveloperBuy` sends
  the developer buy value to `curve.buyFor`. `curve` is the clone created earlier in the
  same `launch()` transaction from the timelock-listed implementation, not caller input.
- `uninitialized-local` (Medium) — `LaunchFactory.launch`'s `eventData` struct is populated
  field by field before the `_emitTokenLaunched` assembly encoder reads it; there is no read
  of an unset field.
- `unused-return` (Medium) — `BondingCurveV1._validateGraduationPair` destructures
  `(reserve0, reserve1, ) = pair.getReserves()` and intentionally drops
  `blockTimestampLast`.
- `unused-return` (Medium) — `LaunchFactory._validateDeveloperBuy` takes only `tokensOut`
  from `quoteBuy` and drops the fee/refund tuple members it does not validate.

These five triage decisions, together with the rest of the Task 12 diff, are the subject of
the independent review required by the third acceptance criterion.

## Deferred

An external audit remains a separate mandatory gate before mainnet funds are accepted.
Passing this gate is reproducible in-house verification and independent model review only;
it is not represented as an external audit. Production authority selection, the audit
vendor, monitoring, and the mainnet deployment checklist stay tracked under the
"Production governance and audit inputs" backlog item.

## Local verification

The 2026-09-04 run used Foundry `1.8.1` (`982849d3140c01fd3b72905759581a132df7aa98`),
Solidity `0.8.36`, and `slither-analyzer` `0.11.6`.

- `./scripts/check.ps1 all` exits 0: pins, `forge fmt --check`, `forge build`,
  `check-goldens.ps1`, `check-vectors.ps1`, `check-deployments.ps1`, `check-release.ps1`,
  `forge test` (96 tests, 0 failed), `forge lint`, and `check-sizes.ps1` all pass.
- `./scripts/check.ps1 slither` exits 0 (15 non-failing results after triage).
- `./scripts/check.ps1 review` and `./scripts/check.ps1 size` exit 0.
- `./scripts/check.ps1 release` without `ROBINHOOD_MAINNET_ARCHIVE_RPC_URL` runs every step
  through Slither and then fails at `check-fork.ps1` with
  `ROBINHOOD_MAINNET_ARCHIVE_RPC_URL is required; the fork test is never skipped`,
  confirming the gate does not skip the fork step.
- Frozen sizes (runtime / init bytes): `BondingCurveV1` 11487 / 11581, `LaunchFactory`
  12187 / 15041, `LaunchToken` 2502 / 3953.

The pinned Robinhood mainnet fork suite itself was accepted under Task 11 (GitHub Actions
`workflow_dispatch` run `33733283872` on commit `d09ba9a`).

## Accepted release-gate run

On 2026-09-04 GitHub Actions `workflow_dispatch` run `33811377759` tested commit `e663eb0`.
All three jobs passed: `Foundry` (`check.ps1 all`), `Release gate` (`check.ps1 release`
with Python and `slither-analyzer` `0.11.6`), and `Robinhood mainnet fork`
(`check.ps1 fork` against the pinned QuickNode archive block). This run satisfies the Task 12
release-gate acceptance requirement. The independent review of the diff and the five Slither
triage decisions remains the third acceptance criterion; an external audit remains a
separate mandatory mainnet-release gate.
