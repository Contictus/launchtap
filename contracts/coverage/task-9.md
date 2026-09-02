# Task 9 invariant and adversarial coverage

## Reproduction

Run the production gate and the coverage report from `contracts/`:

```powershell
./scripts/check.ps1 all
forge coverage --ir-minimum --report summary
```

Plain `forge coverage` disables the optimizer and via-IR, then fails with `Stack too deep`
in the `LaunchFactory` event encoder. `--ir-minimum` is Foundry's documented workaround for
that coverage-only compilation. It does not change the production compiler configuration.
Foundry warns that this mode can produce inaccurate source mappings; the inline assembly in
`LaunchFactory._emitTokenLaunched` is the main affected region.

## Measured result

The 2026-09-02 run used Foundry v1.8.1 and Solidity 0.8.36. All 87 tests passed, including
256 invariant runs at depth 100: 25,600 handler calls with zero unexpected handler reverts.

| Production file | Lines | Statements | Branches | Functions |
|---|---:|---:|---:|---:|
| `BondingCurveV1.sol` | 92.89% | 91.92% | 72.97% | 100.00% |
| `LaunchFactory.sol` | 72.20% | 73.50% | 66.67% | 88.24% |
| `LaunchToken.sol` | 100.00% | 100.00% | 100.00% | 100.00% |
| `CurveMath.sol` | 96.81% | 92.17% | 64.00% | 100.00% |
| Production aggregate | 86.21% | 86.30% | 71.28% | 95.51% |

The aggregate excludes scripts, test fixtures, and harnesses. Percentages are diagnostic,
not the security acceptance criterion. The stateful properties and explicit failure-path
assertions below are the acceptance evidence.

## Stateful properties

`BondingCurveV1Invariant.t.sol` targets one handler and thirteen selectors. The handler uses
real curve clone, token, buy, sell, claim, and graduation calls. It randomizes user transfers,
approvals, `transferFrom`, buys, sells, fee/refund claims, pause state, forced ETH, synced and
unsynced WETH donations, rejecting/reentering ETH recipients, oversells, and slippage reverts.

The six invariants prove:

- fixed total supply and complete token-balance accounting;
- the ETH accounting lower bound, exact forced-ETH surplus, fee accrual/claim conservation,
  buy gross/refund conservation, and sell gross/output/fee conservation;
- curve inventory bounds and `virtualEth * virtualToken >= K` with bounded ceil rounding;
- one-way phase, at most one graduation, and token/curve phase agreement;
- exactly one initial LP mint, directly and entirely to the burn address;
- no partial reserve, token, fee, refund, ETH, or LP mutation on sampled reverting paths.

`testHandlerAdversarialPathsAreLive` deterministically proves the snapshot actions execute,
rejected ETH becomes claimable, the claim clears only after acceptance, and reentry is attempted
but never succeeds.

## Explicit adversarial coverage

The existing focused suites remain part of Task 9's adversarial gate:

- `LaunchFactory.t.sol`: pre-created canonical pair, atomic launch rollback, pair-factory and
  launch-fee claim reentrancy, developer cap rollback, pause/authority separation, and pair
  preseeding restrictions.
- `BondingCurveV1Graduation.t.sol`: synced/unsynced WETH donations, reverse token order,
  canonical-pair replacement, token/pair mismatch, existing LP supply, token reserve/balance,
  WETH deposit/transfer failure, zero liquidity, mint reentrancy, and full final-buy snapshots.
- `BondingCurveV1Trading.t.sol`: reverting recipients, credited refunds, reentrant claims,
  forced ETH, pause/deadline/slippage rollback, oversell-before-transfer, full sell, and exact
  fee/refund bucket accounting.
- `LaunchToken.t.sol`: fixed supply, restricted curve/pair endpoints, randomized transfers and
  approvals, and irreversible graduation.

## Unreachable or defensive branches

- `AccountingInvariantFailed` cannot be reached through a valid public sequence: every ETH
  outflow first clears or reduces its matching obligation and the contract exposes no rescue or
  arbitrary transfer. The handler checks the exact balance equation after every sequence. The
  branch remains as a corruption/integration guard.
- `TokenTransferFailed` after a `false` return is unreachable for the concrete OpenZeppelin-based
  `LaunchToken`, which returns `true` or reverts. The guard remains for explicit ERC-20 boundary
  handling; revert rollback is covered through other external-call failures.
- The factory's post-developer-buy quote/result and gross mismatch guards are unreachable for the
  immutable canonical V1 implementation because quote and execution share the same state and math.
  They remain defensive checks for a future timelock-listed engine that violates the engine
  contract.
- A phase regression, second graduation, or second initial LP mint has no production transition.
  The stateful phase and LP invariants cover arbitrary reachable sequences instead of introducing
  a storage-corrupting test backdoor.
- Checked-arithmetic overflow after successful parameter validation is unreachable within the
  locked V1 reserve and inventory bounds. Direct helper and initialization overflow tests cover
  the rejection boundary.

The assembly encoder's low reported coverage is a coverage-source-mapping limitation under
`--ir-minimum`, not an unexecuted path. Empty and multiword payloads, exact field values, event
ordering, and the frozen ABI artifact are asserted separately.
