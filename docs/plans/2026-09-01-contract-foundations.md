# Contract Foundations — Task List

> **Workflow:** `AGENTS.md` governs pre-flight, implementation, verification, commit,
> and independent review. Every task in this plan is security-sensitive.

**Status:** Design closed; do not start until the user authorizes implementation and the
contract pre-flight finds no blocker.

**Goal:** Implement and verify the immutable V1 launch engine defined by
`docs/specs/2026-09-01-contract-core-design.md`, including deterministic integer behavior,
pull-based fees/refunds, permissionless-pair defenses, direct LP burn, deployment manifests,
and the authoritative vector artifact consumed by Go.

**Toolchain baseline:** Foundry stable pinned to an exact release/commit in CI, Solidity
0.8.36, OpenZeppelin Contracts 5.7.0 from a release tag, and minimal locally defined
interfaces for the deployed Uniswap v2 Factory/Pair/WETH contracts. Never track a dependency
`master` branch.

Compilation baseline is optimizer enabled with 200 runs, `via_ir = false`, and
`evm_version = "cancun"`. Robinhood testnet deployment and mainnet fork tests must prove that
target before release; changing compiler pipeline, optimizer runs, or EVM target is a
reviewed bytecode change, not a local workaround.

## Global constraints

- No upgradeable proxy, delegatecall extension point, admin reserve withdrawal, arbitrary
  call, rescue, forced graduation, or post-launch parameter setter.
- EIP-1167 clone creation and initialization are atomic. The implementation disables
  initialization.
- External-call paths use reentrancy protection and checks-effects-interactions. Failed ETH
  recipients become pull refunds where the spec requires continued market progress.
- All on-chain amount tests are exact integer assertions. Approximate decimal assertions are
  supplemental only.
- Every task adds its unit/fuzz/invariant tests in the same commit. No later “test task” is
  allowed to make an earlier economic task reviewable.
- Deployment scripts produce manifests; hand-entered production addresses are not accepted.

## Task 1 — Foundry scaffold and pinned dependencies · Risk: high

**Delivers:** `contracts/` Foundry project, formatter/build/test/static-analysis commands,
pinned dependency releases, and contract CI.

**Acceptance criteria:**

- `forge fmt --check`, `forge build`, and `forge test` pass under the pinned compiler/toolchain.
- OpenZeppelin resolves to the exact reviewed tag; a lock/commit check fails on drift.
- CI pins its Foundry action and binary selection rather than following nightly.
- Compiler optimizer/via-IR/EVM target choices are explicit and identical in local and CI.
- A bytecode-size report and warnings-as-fail gate are present.
- No contract implementation beyond minimal compile probes is introduced in this task.

## Task 2 — Interfaces, errors, events, and storage layout · Risk: high

**Delivers:** V1 interfaces and storage declarations matching the normative spec.

**Depends on:** Task 1

**Acceptance criteria:**

- Factory, token, curve, pair, WETH, and pause/claim interfaces compile independently.
- Event ABI matches the contract spec field-for-field and has an ABI golden artifact.
- Custom errors cover invalid initialization, phase, zero output, slippage, deadline,
  oversell, pair mismatch/state, pause, unauthorized claims, transfer restriction, and
  failed invariant.
- Storage-layout output is committed for the implementation and checked for accidental
  changes even though clones are non-upgradeable.
- Engine version is a constant returned by implementation and emitted at launch.

## Task 3 — Fixed-supply launch token · Risk: high

**Delivers:** ERC-20 with one initial mint and curve-phase transfer restrictions.

**Depends on:** Task 2

**Acceptance criteria:**

- Supply is minted exactly once to the curve; no callable mint/burn remains.
- Curve and canonical pair are set once and cannot be changed.
- Before graduation, user-to-user transfers work; direct user transfers into/out of curve
  or pair fail; curve-initiated buy, sell, and LP transfer paths work.
- Initial zero-address mint is allowed and emits the expected Transfer.
- Only the curve can mark graduation, only once; afterward ordinary ERC-20 transfers,
  including pair transfers, work.
- Fuzz tests prove total supply never changes and restrictions cannot be bypassed through
  `transferFrom` or approvals.

## Task 4 — Clone initialization and integer curve primitives · Risk: high

**Delivers:** disabled implementation initializer, one-shot clone initializer, state, exact
parameter validation, checked math, and read-only quote helpers.

**Depends on:** Tasks 2-3

**Acceptance criteria:**

- Direct implementation initialization and second clone initialization revert.
- V1 defaults use exact `y0 = 1066666666666666666666666667` and satisfy both reversible
  graduation equations from the spec; floor-rounded `y0` is rejected.
- `ceilDiv`, fee split, buy, sell, exact-gross-for-net, spot price, tokens sold, and real
  reserve helpers match hand-proven boundary cases.
- Exact-gross formula is proven by fuzz for every fee in the supported range and bounded net
  inputs: computed gross minus floor fee equals requested net.
- State fuzz proves `x*y >= K`, `y >= yFinal`, `x >= x0`, and no uint256 overflow.

## Task 5 — Buy, sell, fees, and pull refunds · Risk: high

**Delivers:** market trading, fee accrual/claims, final-fill refund accounting, deadlines,
and slippage enforcement.

**Depends on:** Task 4

**Acceptance criteria:**

- Normal buy/sell state and events match the exact formulas and operation order.
- Sell rejects any input above `tokensSold`; a full valid sell returns state to `x0/y0`
  subject to the documented ceil rules and never pays virtual ETH.
- Protocol and creator fees reconcile exactly to total fee and never enter `x`.
- Claims are pull-based, CEI-compliant, reentrancy-protected, and available while paused and
  after graduation.
- Reverting ETH recipients receive pending refund credit for sell proceeds/final-buy excess;
  another account's trade remains available.
- Forced ETH does not affect reserve, graduation, fee, or refund accounting.
- Deadline and `minOut` fail before an irreversible state transition.

## Task 6 — Canonical pair and graduation · Risk: high

**Delivers:** pair resolution/validation, WETH wrapping, exact direct liquidity contribution,
one-way phase transition, and direct LP mint to burn address.

**Depends on:** Task 5

**Acceptance criteria:**

- Graduation occurs only inside the exact final buy and at `tokensSold=T_r`,
  `realCurveEth=G`.
- Pair identity, token ordering, factory, empty LP supply, and zero launched-token reserve/
  balance are checked before contribution.
- Exactly `G` ETH is wrapped and exactly `G` WETH plus `L` token is sent; unclaimed fees and
  refunds stay claimable.
- Pair mints directly to `0x000000000000000000000000000000000000dEaD`; curve/factory/user
  never receives the launch LP.
- Pre-created empty pair succeeds. WETH-only synced/unsynced donation succeeds as extra
  liquidity. Existing LP supply or token reserve fails without partial state.
- Router02 is never called by graduation.
- Graduation reentrancy and second graduation fail; any pair/WETH failure reverts the entire
  final buy.

## Task 7 — Factory, engine registry, governance, and launch flow · Risk: high

**Delivers:** atomic launch, optional developer buy, launch-fee accrual, versioned future
engines/defaults, multisig pause hooks, and timelock-controlled configuration.

**Depends on:** Tasks 3-6

**Acceptance criteria:**

- Launch sequence matches the spec and emits TokenLaunched before optional Trade/Graduated;
  the initial mint Transfer may precede TokenLaunched.
- Launch fee and developer-buy value are separated exactly; refund/trader/recipient for the
  launch buy is the creator, not factory.
- Developer buy reverts if output exceeds 1% of total supply.
- Existing clone parameters, treasury, implementation, WETH, and pair do not change when
  factory defaults/engine registry change.
- Immediate multisig pause blocks the specified launch/trade paths only; claims remain open.
- Timelock controls only future defaults, engine enablement, and future treasury selection.
- No deployer retains production authority after ownership-transfer verification.
- Every governance change emits an explicit event.

## Task 8 — Authoritative Solidity vectors · Risk: high

**Delivers:** deterministic Foundry vector generator and V1 JSON artifact for the Go mirror.

**Depends on:** Tasks 4-7

**Acceptance criteria:**

- Schema and cases satisfy Backend Foundations Task 10.
- Generator executes the real implementation/view logic; expected results are not duplicated
  in a second handwritten math implementation.
- Normal/final buys, refund, normal/full sells, fee dust, one-wei inputs, invalid operations,
  and graduation are represented.
- Regeneration is deterministic and CI fails on artifact drift.

## Task 9 — Stateful invariants and adversarial suite · Risk: high

**Delivers:** handler-based invariant suite and explicit attack/regression tests.

**Depends on:** Tasks 5-8

**Acceptance criteria:**

- Proves fixed supply, accounting lower bound, fee/refund conservation, inventory bounds,
  curve invariant, one-way phase, one graduation, and no recoverable launch LP.
- Exercises randomized user transfers, approvals, buys, sells, claims, pauses, forced ETH,
  reverting recipients, reentrancy, pre-created pair, donations, and invalid pair states.
- Revert-path snapshots prove no partial state or asset movement.
- Coverage report identifies and justifies any unreachable branch; line percentage alone is
  not accepted as security evidence.

## Task 10 — Deployment scripts and manifests · Risk: high

**Delivers:** deterministic local/test/production deployment scripts and reviewed manifest
generation.

**Depends on:** Tasks 7-9

**Acceptance criteria:**

- Manifest includes every field required by both specs, deploy transaction, bytecode hashes,
  compiler/tool versions, and governance owners.
- Script validates external WETH/Factory bytecode and pair init-code hash before enabling
  graduation.
- Anvil deploys an isolated test WETH/Uniswap v2 stack.
- Robinhood testnet refuses mainnet addresses and remains disabled until its own dependencies
  are deployed/verified.
- Production dry-run proves deployer-to-multisig/timelock authority transfer.
- Secrets/private keys never enter manifests, command output committed to Git, or test logs.

## Task 11 — Robinhood mainnet fork compatibility · Risk: high

**Delivers:** read-only fork integration against exact production WETH/Factory/Pair behavior.

**Depends on:** Task 10

**Acceptance criteria:**

- Creates a launch, resolves/creates its pair, trades to graduation, confirms exact launch
  contribution, LP burn balance, reserves, event ordering, and post-graduation transfers.
- Covers both token orderings where controllable and verifies Sync immediately precedes Swap.
- Confirms no Router dependency in graduation.
- Records fork block and RPC provider; a missing archive/fork capability fails the explicit
  fork job rather than silently skipping it.

## Task 12 — Contract release gate · Risk: high

**Delivers:** reproducible security verification and clean handoff to the backend vector task.

**Depends on:** Tasks 1-11

**Acceptance criteria:**

- Runs format, build, unit/fuzz/invariant tests, vector regeneration diff, Slither, ABI diff,
  storage-layout diff, bytecode-size check, deployment simulation, and fork compatibility.
- Reviews the final diff for upgrade/rescue paths, unchecked external calls, mutable launch
  fields, dependency drift, placeholder addresses, test-only code, and optimizer mismatch.
- Independent review resolves all BLOCKER/IMPORTANT findings.
- External audit remains a separate mandatory mainnet-release gate; passing this plan is not
  represented as an external audit.

## Toolchain references checked for design closure

- Solidity releases: https://www.soliditylang.org/blog/category/releases/
- OpenZeppelin tagged releases: https://github.com/OpenZeppelin/openzeppelin-contracts/releases
- Foundry installation and stable toolchain pinning:
  https://getfoundry.sh/getting-started/installation
