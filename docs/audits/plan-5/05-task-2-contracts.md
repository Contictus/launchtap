# Plan 5 Task 2 — Smart-contract and economic-security audit

## Result

Audited immutable product baseline `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`. The source review found one validated low-severity economic/configuration discrepancy, rejected two source-backed threat hypotheses, and deferred one release-time governance/dependency verification item because no reviewed production deployment inputs exist. No product, test, config, dependency, or generated files were changed.

| State | Count |
| --- | ---: |
| Validated finding | 1 |
| Rejected/suppressed hypothesis | 2 |
| Deferred release verification | 1 |

The counts above preserve the four previously recorded Task 2 dispositions. Separately, all five baseline High/Medium rows in `contracts/slither.db.json` were re-justified against source and suppressed as non-reportable scanner classifications; none adds a fifth finding.

This is not a production-readiness assessment. No production RPC, network access, secrets, deployment transactions, or tool installations were used.

## Baseline and ownership boundary

The immutable comparison target is `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`. Repository code paths and findings below refer to that baseline. The Task 2 ownership rows are `docs/audits/plan-5/01-surface-ownership.md:9-15,33`; Task 1 policy and canonical record schema are in `docs/audits/plan-5/03-policy-and-finding-template.md`.

Task 2 owns the Solidity runtime, first-party contract tests and fork test, `contracts/script/deployment/`, root `contracts/script/*.s.sol` generators/deploy scripts, contract evidence artifacts, and `backend/internal/curve/`. Task 7 owns local deployment fixtures (`contracts/script/local/`), deployment manifests, vendored libraries, Foundry/tool configuration, scanner evidence, and bootstrap/release automation. Those Task 7 surfaces were not audited as Task 2 paths; only their interaction assumptions visible through the Task 2 callers were considered.

## Coverage and reasoning

### Contract behavior and authority

Inspected every public/external function in the assigned first-party Solidity runtime and interfaces, plus public/external deployment validation entry points and first-party tests. The externally reachable state-changing paths are `LaunchFactory.launch`, `claimLaunchFees`, pause setters, `configureEngine`, future-default/treasury setters (`contracts/src/LaunchFactory.sol:76-186`); `BondingCurveV1.buy`, factory-only `buyFor`, `sell`, creator/protocol/refund claims (`contracts/src/BondingCurveV1.sol:89-181`); and token pair initialization/graduation (`contracts/src/LaunchToken.sol:40-71`). View surfaces and interface declarations were also reviewed (`LaunchFactory.sol:188-238`, `BondingCurveV1.sol:182-275`, `LaunchToken.sol:25-38`, `contracts/src/interfaces/`).

The constructor rejects zero/equal authority combinations; the pause authority can only pause, timelock-gated transitions own engine/default/treasury changes, and treasury claims are caller-bound (`contracts/src/LaunchFactory.sol:51-74,135-186`). Launch configuration is copied into each clone at creation; later registry/default/treasury changes affect future launches, not an existing clone (`LaunchFactory.sol:76-131,240-262`; regression test `contracts/test/LaunchFactory.t.sol:571-605`). Same-version engine replacement is therefore a governance-controlled future-launch transition, not an existing-clone upgrade.

Trading entry points apply pause/deadline/slippage/phase checks; buy/sell state accounting precedes external asset delivery and state-changing trade/claim paths are reentrancy guarded (`contracts/src/BondingCurveV1.sol:89-181,276-369`). Failed immediate refunds are credited for later pull claim; claim state is cleared before a full-gas call whose failure reverts (`BondingCurveV1.sol:345-368`). Graduation changes phase/token state before WETH and pair calls, then verifies canonical factory/pair identity, token ordering, zero pre-existing LP supply, and zero launch-token pair reserve/balance; LP is sent to the dead address (`BondingCurveV1.sol:370-457`). Forced ETH is treated as surplus, not curve reserve or fee revenue, and accounting only requires the balance to cover accounted buckets (`BondingCurveV1.sol:426-436`; test `contracts/test/BondingCurveV1Trading.t.sol:679-704`). These checks are consistent with the threat model’s stated asset/accounting boundaries; no public attacker path to a privileged transition or reserve theft was established.

`LaunchToken` mints the fixed total supply once to its curve, permits one factory-selected pair and curve-only graduation, and blocks pre-graduation transfers that touch the curve/pair unless the curve is the operator; post-graduation transfers are unrestricted (`contracts/src/LaunchToken.sol:40-71`; `contracts/test/LaunchToken.t.sol:28-188`).

### Economic derivation and Go mirror

Re-derived the integer arithmetic in `contracts/src/libraries/CurveMath.sol:45-205` and compared it with `backend/internal/curve/math.go:253-604` and the shared vectors. Trade fee is `floor(gross * feeBps / 10_000)`; protocol share is `floor(totalFee * protocolShareBps / 10_000)`, with the rounding remainder assigned to the creator. A buy applies the fee before the constant-product quote, rounds the new virtual token reserve upward, clamps the final fill to the configured curve allocation, and refunds unused supplied ETH. The minimal gross value for an exact net is `floor((net - 1) * 10_000 / (10_000 - feeBps)) + 1`. A sell adds sold tokens to the virtual token reserve, rounds the invariant-derived ETH reserve upward, then deducts the trade fee from gross ETH out. Parameter validation checks full-supply allocation, nonzero/bounded reserves and fees, and the rounded graduation-boundary identity.

The Go mirror uses bounded `big.Int` operations and defensive input/output copies; vector decoding rejects malformed/trailing or unknown data and validates version/schema and uint256 values (`backend/internal/curve/math.go`, `vectors.go`). The 1,000-seed property/differential coverage, boundary, rounding, overflow, and vector-copy tests were inspected and the package suite passed locally (test details below). The Solidity/Go curve vectors and schemas are byte-identical at SHA-256 `E3B3FCEF8C6130AF82CF535B1D84E022B80C0A5196DE40E2F700421C8321B83E` and `2BB268F8C11E8C8C83D4C5E7CE76BDC435EC9B080D7A8EB4619B72DE2348330A`, respectively.

### First-party tests and deployment semantics

Reviewed unit/fuzz/invariant coverage for initialization and clone wiring; parameter boundaries and arithmetic; fee/refund conservation; buy/sell and oversell; reentrancy and failed-delivery recovery; pause/slippage/deadline; graduation rollback, pair validation and token order; fixed supply/transfer policy; governance authorization/snapshots; deployment chain/dependency/authority validation; and event/interface encoding. The stateful invariant suite checks supply/accounting, reserve/product bounds, one-way graduation, burned LP, and revert atomicity (`contracts/test/BondingCurveV1Invariant.t.sol:582-672`). Fork tests assert both token orderings and no router dependency (`contracts/fork-test/RobinhoodMainnetFork.t.sol:111-116`), but were not executed.

`DeployLaunchpad.run` validates chain and authority inputs, resolves dependencies, validates dependency code and pair identity, then begins broadcast to deploy the implementation/factory (`contracts/script/DeployLaunchpad.s.sol:40-108`). Mainnet dependency addresses and canonical pair hash are pinned in the validator (`contracts/script/deployment/DeploymentValidation.sol:8-16,152-169`). The explicit release-time authority/dependency evidence boundary is recorded as deferred below; the source cannot prove absent production values.

## Finding and disposition records

### P5-T2-001 — Deployment script defaults the specified launch fee to zero

- State: validated finding
- Severity: Low
- Confidence: medium
- Primary audit task: Task 2
- Affected asset/surface: root deployment script `contracts/script/DeployLaunchpad.s.sol`, Task 2 ownership row `docs/audits/plan-5/01-surface-ownership.md:14`; future-launch protocol revenue/configuration.
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Attacker/failure actor and prerequisites: no public attacker or privilege escalation. A deployment operator selects this first-party script for a target and does not correct future defaults before launches.
- Source-to-sink or failure path: `DeployLaunchpad.run` passes `_defaults(result.weth, result.uniswapFactory)` into the new factory (`contracts/script/DeployLaunchpad.s.sol:96-107`); `_defaults` sets `launchFee: 0` (`DeployLaunchpad.s.sol:130-149`). The normative V1 default is `0.0005 ether` (`docs/specs/2026-09-01-contract-core-design.md:99`; also `notes.md:400-401`). `LaunchFactory.launch` requires exactly the snapshotted launch fee plus developer-buy gross and accrues the snapshotted fee to the treasury (`contracts/src/LaunchFactory.sol:85-86,114-116`). Thus launches using the script begin with no launch charge and accrue no launch-fee revenue until governance changes the future defaults.
- Exact evidence: `contracts/script/DeployLaunchpad.s.sol:130-149` (`_defaults`); `DeployLaunchpad.s.sol:115-128` (`_assertDeployment` checks roles/engine/dependencies but not `launchFee`); `contracts/src/LaunchFactory.sol:85-86,114-116`; `docs/specs/2026-09-01-contract-core-design.md:99`; `contracts/test/LaunchFactory.t.sol:176,259,340,571-605` (factory tests use `LAUNCH_FEE = 0.0005 ether` and snapshot behavior). The fork fixture also uses zero (`contracts/fork-test/RobinhoodMainnetFork.t.sol:390`), but is a test fixture and does not document a production waiver.
- Impact: under-collection of `0.0005 ETH` per launch relative to the specified fixed V1 launch fee for any deployment using the script without a pre-launch governance correction. No trader reserve or token-supply impact.
- Counterevidence and assumptions: the timelock can set future defaults before the first launch; zero could be an intentional fee waiver, but no target-specific waiver is documented and the production script is not target-specific in `_defaults`. No deployed production manifest or first live launch was in scope/available, so realized revenue impact is unknown.
- Reproduction/proof method: static source proof: compare the value returned by `DeployLaunchpad._defaults` at `DeployLaunchpad.s.sol:130-149` with the specified table and trace its use at `LaunchFactory.sol:85-86,114-116`. No runtime deployment was performed.
- Proposed remediation: set the intended fee explicitly for each target (or document and encode an intentional waiver), and assert the resulting factory `launchFee()` in `_assertDeployment`.
- Required regression test: a deployment-script test must assert `factory.launchFee()` equals the target’s reviewed expected value and fail if the script silently returns zero against the V1 default; a separately documented waiver target should assert zero explicitly.
- Disposition/owner: validated; route to Task 8/product owner for an explicit economic decision before changing code. Do not remediate as part of this audit-only task.
- Related findings and cross-task references: Task 7 should bind deployment-target defaults to the reviewed release manifest; no duplicate finding identified.

### P5-T2-002 — Production timelock and dependency evidence remains unverified

- State: deferred
- Severity: Medium
- Confidence: low
- Primary audit task: Task 2
- Affected asset/surface: deployment validation and release configuration, `contracts/script/deployment/DeploymentValidation.sol` and `contracts/script/DeployLaunchpad.s.sol`; Task 2 row `docs/audits/plan-5/01-surface-ownership.md:12,14` with Task 7 release evidence boundary.
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Attacker/failure actor and prerequisites: privileged release operator supplies an EOA or policy-incompatible address as `TIMELOCK`, or supplies zero expected dependency runtime hashes while setting `DEPENDENCIES_REVIEWED=true`; an actor controlling the selected timelock address could then invoke privileged transitions. This is conditional; no production address or on-chain deployment was available to establish that it occurred.
- Source-to-sink or failure path: deployment inputs provide `TIMELOCK`, pause authority and treasury (`DeployLaunchpad.s.sol:40-53`). `validateAuthorities` rejects zero/shared/deployer addresses but does not establish code type or delay policy (`DeploymentValidation.sol:60-75`). The factory stores the timelock and gates future engine/default/treasury changes by caller equality (`LaunchFactory.sol:51-74,160-186`). Runtime code-hash checks are skipped when the expected hash is zero (`DeploymentValidation.sol:181-189`); the deployment script reads expected hashes from environment and the review boolean separately (`DeployLaunchpad.s.sol:75-94`).
- Exact evidence: `contracts/script/DeployLaunchpad.s.sol:40-53,75-94`; `contracts/script/deployment/DeploymentValidation.sol:60-75,81-109,181-189`; `contracts/src/LaunchFactory.sol:51-74,160-186`; `contracts/test/Deployment.t.sol:261-280` (nonzero mismatches fail closed); `docs/specs/2026-09-11-security-threat-model.md:58,136-138` (signer custody/timelock policy remain external); `docs/audits/plan-5/04-exclusions-and-unknowns.md:71-75` (reviewed production/testnet deployment and authority evidence unavailable).
- Impact: only if release values violate the intended governance policy, an immediate controller could change future launch engine/economics/treasury or pause trading without the intended delay; existing launch snapshots remain isolated. If expected hashes are zero, the release check does not bind code to an independently expected digest.
- Counterevidence and assumptions: caller checks, role separation, chain/address validation, explicit non-Anvil dependency-review gate, runtime bytecode presence checks, mainnet fixed dependency addresses/hash, and nonzero expected-hash mismatch rejection are present. The threat model explicitly leaves signer custody and timelock policy external. No production/testnet manifest, actual timelock implementation, expected hash values, or broadcast was available; therefore this is not asserted as a current vulnerability.
- Reproduction/proof method: source inspection proves the validation conditions and zero-hash skip. Resolution requires a reviewed chain-46630/production candidate manifest, not a fabricated local fixture or live RPC query.
- Proposed remediation: before any target release, record and independently verify the actual authority contract/policy, expected nonzero dependency runtime hashes, reviewed source/build provenance, and the resulting deployment addresses in the signed/reviewed manifest. Only add a generic on-chain validator predicate after the intended timelock policy/interface is selected.
- Required regression test: once the release policy is defined, add a validator/release-gate test that rejects a missing/unreviewed timelock policy and omitted expected code hashes, while accepting the reviewed candidate; assert the deployed factory’s configured authority and dependencies match the reviewed record.
- Disposition/owner: deferred. Owner: product owner and release operator, with Task 7 owning manifest/gate evidence. Prerequisite: actual reviewed target manifest and governance policy. Resume by verifying its addresses, timelock semantics, and nonzero code hashes before any broadcast.
- Related findings and cross-task references: distinct from P5-T2-001’s launch-fee default mismatch; coordinate release evidence with Task 7.

### P5-T2-003 — Pair-hash fallback `createPair` is not broadcast by first-party deployment callers

- State: rejected/suppressed
- Severity: Low
- Confidence: high
- Primary audit task: Task 2
- Affected asset/surface: `DeploymentValidation._verifyPairInitCodeHash`, Task 2 ownership row `docs/audits/plan-5/01-surface-ownership.md:12,14`.
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Attacker/failure actor and prerequisites: hypothesis was that a deployment operator could persist an unexpected probe pair by reaching the no-`pairCodeHash()` fallback during broadcast. No attacker privilege was proposed; the claim depended on validator invocation occurring inside a broadcast window.
- Source-to-sink or failure path: the fallback calls `createPair` for fixed probe-token addresses when `pairCodeHash()` is missing (`DeploymentValidation.sol:127-149`). In `DeployLaunchpad`, Anvil dependency deployment ends with `vm.stopBroadcast()` before validation, while non-Anvil validation occurs before the later `vm.startBroadcast()` (`DeployLaunchpad.s.sol:56-96`). `DeployTestnetDependencies` also stops broadcast before dependency validation (`DeployTestnetDependencies.s.sol:15-31`). The suspected pair-creation sink is therefore outside the first-party deployment broadcast boundaries.
- Exact evidence: `contracts/script/deployment/DeploymentValidation.sol:127-149`; `contracts/script/DeployLaunchpad.s.sol:56-96`; `contracts/script/DeployTestnetDependencies.s.sol:15-31`; `contracts/test/Deployment.t.sol:215-258` (fallback acceptance/rejection behavior).
- Impact: no persisted production/testnet pair side effect established through current first-party deployment callers. Local validator simulation may mutate only its local test/script state.
- Counterevidence and assumptions: static call-order evidence covers every assigned caller found by repository search; the fork test invokes no deployment validator. Foundry broadcast serialization itself could not be executed here, but the source calls are outside `startBroadcast`/`stopBroadcast` spans.
- Reproduction/proof method: trace each `validateDependencies` caller and its surrounding broadcast start/stop calls; inspect `testPairInitCodeHashFallbackAcceptsCreate2Match` and mismatch regression in `Deployment.t.sol:215-258`.
- Proposed remediation: none for the rejected hypothesis. Preserve call-order coverage; do not remove the fallback based on this claim alone.
- Required regression test: no new test required for this rejected item; existing fallback tests should remain, and any future deployment caller should validate before broadcast or after `stopBroadcast`.
- Disposition/owner: rejected/suppressed with source-backed counterevidence; no fix assigned.
- Related findings and cross-task references: Task 7 owns release invocation semantics and should retain review of broadcast boundaries.

### P5-T2-004 — Same-version engine reconfiguration does not upgrade existing launch clones

- State: rejected/suppressed
- Severity: Low
- Confidence: high
- Primary audit task: Task 2
- Affected asset/surface: `LaunchFactory.configureEngine` and per-launch clone/snapshot behavior, Task 2 ownership row `docs/audits/plan-5/01-surface-ownership.md:9`.
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Attacker/failure actor and prerequisites: hypothesis treated a timelock-authorized replacement under an existing engine version as mutating already deployed launches. It requires timelock control; there is no public attacker privilege path.
- Source-to-sink or failure path: `configureEngine` changes the registry entry for future launches (`LaunchFactory.sol:160-166,373-389`). `launch` resolves the current implementation and creates a clone with that implementation address; the clone stores its own initialization snapshot (`LaunchFactory.sol:76-131,240-262`). Rebinding the registry does not rewrite a clone’s embedded implementation address or initialized storage.
- Exact evidence: `contracts/src/LaunchFactory.sol:76-131,160-166,240-262,373-389`; `contracts/test/LaunchFactory.t.sol:571-605` explicitly reconfigures the same version, asserts the old clone keeps its original implementation/configuration, and asserts a later launch receives the new implementation.
- Impact: none from same-version registry rebinding to existing clones. Timelock can intentionally affect future launch behavior, already part of its authorized role.
- Counterevidence and assumptions: implementation addresses are embedded in the minimal-proxy clone code and `initialize` records the implementation in clone storage; existing-launch regression test covers the exact rebind scenario. This conclusion concerns the baseline clone design, not future proxy types.
- Reproduction/proof method: follow the clone creation and initialization path, then the existing/new launch assertions in `testExistingLaunchKeepsAllSnapshotsAfterGovernanceChanges` (`LaunchFactory.t.sol:571-605`).
- Proposed remediation: none; preserve the registry-vs-instance distinction and regression test.
- Required regression test: existing `testExistingLaunchKeepsAllSnapshotsAfterGovernanceChanges` should continue to pass and assert old and new clone implementations separately.
- Disposition/owner: rejected/suppressed with direct source and test counterevidence; no fix assigned.
- Related findings and cross-task references: timelock release-policy evidence remains separately deferred in P5-T2-002.

## Re-justification of all baseline Slither High/Medium rows

Although `contracts/slither.db.json` is Task 7-owned under `docs/audits/plan-5/01-surface-ownership.md:17`, Plan 5 Task 2 explicitly requires source re-justification of existing Slither suppressions (`docs/plans/2026-09-11-full-codebase-audit-hardening.md:109-112,121-123`). The baseline artifact blob is `9904fdb0058a21a8281f93fe56d88d8fd3169814`; the checked-out artifact has the same blob. The assigned Solidity source paths were diffed against the fixed baseline and have no differences. All five rows, their scanner ids, and current-source dispositions are retained here.

Validation rubric applied independently to each row:

- [x] Confirm the exact baseline scanner row/id, check, severity, and source anchor.
- [x] Trace the concrete caller/input, closest authorization or configuration boundary, and operation/sink in current baseline source.
- [x] Distinguish public user/creator inputs from governance-selected code and snapshotted dependencies.
- [x] Assess the claimed impact against Task 1 reportability policy and source-backed counterevidence.
- [x] Check relevant existing tests/source comments and record runtime proof limits; no Foundry test is represented as run.

| Baseline id / Slither check | Scanner impact / confidence | Current-source path and disposition |
| --- | --- | --- |
| `2e812341f6229e9df95464e3ed19445952f07d3bc13553e0e0b04030a97cb7d4` · `arbitrary-send-eth` | High / Medium | `BondingCurveV1._graduate`, `contracts/src/BondingCurveV1.sol:370-391`; suppressed. ETH is sent to snapshotted `_weth` through `deposit`, not to an attacker-selected user. |
| `42b0e1b871612543843ea44654c73d9476f2547022e39daf61ab45285587b8a5` · `arbitrary-send-eth` | High / Medium | `LaunchFactory._callDeveloperBuy`, `contracts/src/LaunchFactory.sol:280-315`; suppressed. The creator funds an exact-value launch; ETH goes to the factory-created curve clone, and creator identity is passed as trader/token/refund recipient. |
| `5b51b0993e49f396f8157cf8aebed0fd840fa508c3bd469257bf1a07422aede3` · `uninitialized-local` | Medium / Medium | `LaunchFactory.launch`, `contracts/src/LaunchFactory.sol:37-50,118-132`; suppressed. Every `LaunchEventData` member is assigned before `_emitTokenLaunched` consumes it. |
| `cdd33f0d96cdaa6959b5667bb27af51c7300aa57ffeee6c4e6ebb295ed26b07b` · `unused-return` | Medium / Medium | `BondingCurveV1._validateGraduationPair`, `contracts/src/BondingCurveV1.sol:394-420`; suppressed. The unused `blockTimestampLast` is unrelated to the zero launched-token reserve check; both reserve values are used in token-order-aware validation. |
| `f80749dca281fcbb9fc9a7aad6036b6a1d550de6a62b7d17bbacea91acc740e0` · `unused-return` | Medium / Medium | `LaunchFactory._validateDeveloperBuy`, `contracts/src/LaunchFactory.sol:264-301`; suppressed. Only `tokensOut` is needed for the cap; the executed buy then checks actual tokens and exact gross used. |

Closure ledger (Slither ids serve as the candidate row ids; the artifact contains no external advisory reference):

| Row id / instance | Seed anchor | Root control | Entry/source | Sink / closest control | Disposition | Counterevidence or proof gap | Survives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `2e812341…` / arbitrary ETH in graduation | `BondingCurveV1.sol:370-392` | `BondingCurveV1.sol:37-85,240-252` | Public buy reaching final-fill graduation; `_weth` comes from factory snapshot | `BondingCurveV1.sol:378`; configured WETH `deposit`, not user recipient | suppressed | Caller cannot select WETH; WETH/deployment authenticity remains P5-T2-002’s release proof gap | no |
| `42b0e1b8…` / developer-buy ETH | `LaunchFactory.sol:305-315` | `LaunchFactory.sol:76-110,240-252` | Creator-funded launch; factory-selected implementation | `LaunchFactory.sol:314`; factory-only `buyFor` on created clone, creator is all three recipient/actor arguments | suppressed | Exact `msg.value`, factory-only call, output/cap/gross checks; malicious registry entry requires timelock configuration | no |
| `5b51b099…` / event local | `LaunchFactory.sol:119` | `LaunchFactory.sol:120-131` | Creator launch request | `_emitTokenLaunched` consumes `eventData` after all 11 members are assigned | suppressed | All struct members assigned before encoding; no uninitialized read | no |
| `cdd33f0d…` / pair reserve tuple | `BondingCurveV1.sol:394-424` | `BondingCurveV1.sol:416-424` | Final-fill graduation reads pair state | `getReserves`; both reserves are used and only timestamp is ignored | suppressed | No oracle or elapsed-time calculation uses the timestamp | no |
| `f80749dc…` / developer-buy quote tuple | `LaunchFactory.sol:264-278` | `LaunchFactory.sol:271-301` | Creator-requested optional developer buy | `quoteBuy`; only token output feeds cap, actual buy checks quote/gross | suppressed | Source comment identifies required return; actual execution compares tokens and gross | no |

### Per-row validation evidence

**`2e812341…` — `arbitrary-send-eth` in graduation.** The alleged source is the final-fill/graduation transition. `BondingCurveV1.initialize` accepts configuration only from its recorded factory and snapshots the nonzero WETH address (`contracts/src/BondingCurveV1.sol:37-85`); `LaunchFactory.launch` supplies values from `_snapshot` (`contracts/src/LaunchFactory.sol:92-110,240-252`). At graduation, state changes first and `_graduationEth` is deposited into `_weth` as WETH (`BondingCurveV1.sol:370-384`), then tokens/WETH are transferred to the validated pair and LP is minted to the burn address (`:394-420,380-391`). The attacker-controlled recipient in Slither’s generic message does not exist on this call: an unprivileged creator/trader cannot select `_weth` for a launch. A malicious or wrong configured WETH remains a release/dependency trust concern covered by P5-T2-002, not an arbitrary-user ETH send. The exact source comment and fork gate reference this non-user-controlled snapshot (`BondingCurveV1.sol:376`; fork test `contracts/fork-test/RobinhoodMainnetFork.t.sol:111-116`). Disposition: **suppressed**; no public source-to-attacker sink.

**`42b0e1b8…` — `arbitrary-send-eth` in developer buy.** `launch` derives `creator` from `msg.sender` and requires `msg.value == launchFee + developerBuyGross` (`LaunchFactory.sol:76-88,99-110`). `_callDeveloperBuy` forwards only the creator-funded `gross` to `curve.buyFor` on the clone just created and initialized by that factory call, passing the same creator as trader, token recipient, and refund recipient (`LaunchFactory.sol:92-110,280-315`). `buyFor` rejects non-factory callers (`BondingCurveV1.sol:98-107`); the resolved engine is the timelock-configured registry entry and is snapshotted before launch (`LaunchFactory.sol:160-166,240-252`). The returned tokens/gross are checked against the quote, cap, and request (`LaunchFactory.sol:288-301`). A malicious timelock-selected implementation is a privileged governance configuration scenario, not an arbitrary public recipient; it is not evidenced in the baseline deployment. Disposition: **suppressed** as an attacker-recipient finding; privileged engine selection remains within P5-T2-002’s release-policy boundary.

**`5b51b099…` — `uninitialized-local` event data.** The declaration is followed by assignments to every member of `LaunchEventData`: the full `parameters` struct and each scalar/string field (`LaunchFactory.sol:37-50,118-131`). `_emitTokenLaunched` consumes the value only after those assignments. No member reaches event encoding from an unassigned local value. Disposition: **suppressed**; the detector identifies a declaration style, not an uninitialized-value path.

**`cdd33f0d…` — ignored `getReserves` timestamp.** Graduation verifies pair identity/factory/order and requires zero LP supply, then reads both reserves and selects the launched token’s reserve by token order (`BondingCurveV1.sol:394-420`). It deliberately ignores the third `blockTimestampLast` output; no oracle, elapsed-time, or price calculation is performed by this check. The token reserve is separately required to be zero, and token balance is separately checked (`:416-424`). Disposition: **suppressed**; the ignored value is not used by the security invariant.

**`f80749dc…` — unused `quoteBuy` outputs.** `_validateDeveloperBuy` destructures only the quote’s token output because that is the value needed for the 1% allocation cap (`LaunchFactory.sol:264-278`, with an explicit source comment at `:271`). The subsequent state-changing call checks the actual output against the quote and cap and verifies `actualGrossUsed == developerBuyGross` (`:280-301`). The other quote fields are not required by the caller’s invariant. Disposition: **suppressed**; ignored informational outputs do not bypass checks.

These are source-understood suppressions, not scanner-silence claims. The focused Foundry tests could not be executed because `forge` is unavailable; the source/control/sink assessment is complete and no runtime behavior is claimed. No separate PoC or validation artifact was needed for these deterministic source findings.

## Bytecode-size and gas-griefing review

The baseline `contracts/sizes/v1/sizes.json:1` blob matches the checked-out artifact (`c4456d6fcd66737bc82831b7486bf0cf1708c87b`). Its reported compiler outputs are:

| Contract | Runtime bytes | Headroom vs. 24,576-byte EIP-170 limit | Initcode bytes | Headroom vs. 49,152-byte EIP-3860 limit |
| --- | ---: | ---: | ---: | ---: |
| `BondingCurveV1` | 11,487 | 13,089 | 11,581 | 37,571 |
| `LaunchFactory` | 12,187 | 12,389 | 15,041 | 34,111 |
| `LaunchToken` | 2,502 | 22,074 | 3,953 | 45,199 |

The stored sizes are materially below those standard EVM limits. This is an artifact-level comparison only: `forge` was unavailable, so the exact baseline sources were not recompiled, and no Robinhood-specific code-size limit was independently established. **Fresh compiler size verification remains incomplete**; the committed sizes artifact is not represented as a newly reproduced build.

The source-backed gas-grief review found no `for`/`while` loop, unbounded storage scan, or attacker-sized collection traversal in `contracts/src/`; the trade/graduation path has a fixed number of external calls and state writes. Refund delivery to an arbitrary recipient is capped at 50,000 gas and failure is converted to a pull credit (`BondingCurveV1.sol:345-359`); claim calls that forward all gas target the authenticated claimant/treasury (`BondingCurveV1.sol:362-368`, `LaunchFactory.sol:135-146`), so a hostile receiver can at most make its own claim fail/revert. WETH/pair calls can revert or consume gas, but their addresses are factory-snapshotted configuration rather than per-trade user input; actual target dependency code/policy remains the explicit P5-T2-002 proof gap.

`LaunchRequest.name` and `.symbol` are unbounded dynamic strings (`contracts/src/types/LaunchTypes.sol:26-33`) copied into token constructor storage and the launch event (`LaunchFactory.sol:92-95,118-132,317-370`). Their storage/encoding cost scales with creator-supplied bytes and is not capped, but the creator selects and pays for that same launch; gas exhaustion reverts that transaction atomically and does not stall another user’s trade or shared loop. No source-backed cross-user gas-grief path was established. **Quantitative maximum-input gas profiling remains incomplete** because Foundry was unavailable and no maximum metadata length or gas budget is specified. This residual is an operational/product limit question, not a validated security finding under the stated actor model.

Task 2 acceptance status: all five Slither High/Medium entries have explicit current-source dispositions; stored bytecode sizes and public-path gas-grief behavior have source-backed review outcomes. Fresh Solidity compilation/size regeneration and quantitative maximum-input gas measurement are incomplete for the documented tool limitation above. No size, gas, or compiler gate is marked passed.

## Owned-path disposition inventory

Every baseline file in the Task 2 ownership rows is enumerated below. “Reviewed” means source/artifact inspection only; it does not imply the unavailable Foundry runtime gates passed.

### Solidity runtime — reviewed

- `contracts/src/BondingCurveV1.sol`
- `contracts/src/LaunchFactory.sol`
- `contracts/src/LaunchToken.sol`
- `contracts/src/interfaces/IBondingCurveV1.sol`
- `contracts/src/interfaces/ICurveClaims.sol`
- `contracts/src/interfaces/IFactoryClaims.sol`
- `contracts/src/interfaces/ILaunchErrors.sol`
- `contracts/src/interfaces/ILaunchEvents.sol`
- `contracts/src/interfaces/ILaunchFactory.sol`
- `contracts/src/interfaces/ILaunchPause.sol`
- `contracts/src/interfaces/ILaunchToken.sol`
- `contracts/src/interfaces/external/IUniswapV2Factory.sol`
- `contracts/src/interfaces/external/IUniswapV2Pair.sol`
- `contracts/src/interfaces/external/IWETH.sol`
- `contracts/src/libraries/CurveMath.sol`
- `contracts/src/storage/BondingCurveV1Storage.sol`
- `contracts/src/storage/LaunchFactoryStorage.sol`
- `contracts/src/storage/LaunchTokenStorage.sol`
- `contracts/src/types/LaunchTypes.sol`

### First-party tests and adversarial/fork fixtures — reviewed; execution deferred for Solidity/fork paths

- `contracts/test/BondingCurveV1.t.sol`
- `contracts/test/BondingCurveV1Graduation.t.sol`
- `contracts/test/BondingCurveV1Invariant.t.sol`
- `contracts/test/BondingCurveV1Trading.t.sol`
- `contracts/test/Deployment.t.sol`
- `contracts/test/InterfaceDeclarations.t.sol`
- `contracts/test/LaunchFactory.t.sol`
- `contracts/test/LaunchToken.t.sol`
- `contracts/test/harness/BondingCurveV1Harness.sol`
- `contracts/test/harness/BondingCurveV1StorageHarness.sol`
- `contracts/test/harness/CurveMathHarness.sol`
- `contracts/test/harness/LaunchFactoryStorageHarness.sol`
- `contracts/test/harness/LaunchTokenStorageHarness.sol`
- `contracts/fork-test/RobinhoodMainnetFork.t.sol`

### Deployment/evidence generation scripts — reviewed; Foundry execution deferred

- `contracts/script/DeployLaunchpad.s.sol`
- `contracts/script/DeployTestnetDependencies.s.sol`
- `contracts/script/GenerateCurveVectors.s.sol`
- `contracts/script/GenerateEventFixtures.s.sol`
- `contracts/script/deployment/DeploymentValidation.sol`

### Contract evidence artifacts — bytes/structure reviewed; Foundry regeneration and freshness deferred

- `contracts/abi/v1/ILaunchEvents.json`
- `contracts/abi/v1/IUniswapV2PairEvents.json`
- `contracts/abi/v1/LaunchFactory.json`
- `contracts/abi/v1/LaunchToken.json`
- `contracts/abi/v1/UniswapV2Router02.json`
- `contracts/fixtures/v1/event-logs-v1.json`
- `contracts/vectors/v1/curve-v1.json`
- `contracts/vectors/v1/curve.schema.json`
- `contracts/storage-layout/v1/BondingCurveV1.json`
- `contracts/storage-layout/v1/LaunchFactory.json`
- `contracts/storage-layout/v1/LaunchToken.json`
- `contracts/sizes/v1/sizes.json`

All 14 assigned JSON artifacts (including the backend vector/schema copies) parsed successfully as JSON. Solidity/Go curve-vector and schema copy hashes matched exactly. ABI, storage-layout, size, and event-fixture currentness could not be regenerated or compared with a fresh compiler run because Foundry was unavailable; they are not reported as freshly verified.

### Go curve mirror — reviewed; package tests passed

- `backend/internal/curve/doc.go`
- `backend/internal/curve/errors.go`
- `backend/internal/curve/math.go`
- `backend/internal/curve/math_test.go`
- `backend/internal/curve/properties_test.go`
- `backend/internal/curve/testdata/curve-v1.json`
- `backend/internal/curve/testdata/curve.schema.json`
- `backend/internal/curve/vectors.go`
- `backend/internal/curve/vectors_mirror_test.go`
- `backend/internal/curve/vectors_test.go`

## Tool and test limits

- `go test ./internal/curve` from `backend/` passed (`ok`, 0.345s). The command used `GOPROXY=off`, `GOTELEMETRY=off`, and a temporary cache path outside the repository because the default Go build cache was access-denied. Go still printed an access-denied telemetry upload-token warning; it did not prevent the package tests from passing. No dependency download or install occurred.
- `forge` was not present on `PATH` (`Get-Command forge -ErrorAction SilentlyContinue` resolved no executable). Consequently `forge test`, Foundry fuzz/invariant tests, `RobinhoodMainnetFork.t.sol`, deployment-script execution, and generated ABI/storage-layout/size/fixture regeneration were not run. This is a skipped gate, not a pass.
- No live chain/RPC verification was attempted. Production governance addresses and reviewed deployment manifests remain external prerequisites.
- Backlog status at audit completion: 2 Active items — “Robinhood testnet deployment manifest” and “Production release, governance, and audit inputs”. Other listed backlog entries are under Done and were not counted as active.
