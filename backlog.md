# Backlog — Unfinished Work

> Unfinished work is noted here. Reason: ran out of time, scope decision, or
> usage limit about to run out. Goal: later, resume quickly from where we
> stopped **without rebuilding context from scratch**.

## How to use

- Every unfinished piece of work becomes an item under "Active".
- The **Resume** field is written clearly enough to include file paths,
  commands, last working state, and the next concrete step.
- When work is done, delete the item or move it to "Done".

---

## Active

### Robinhood RPC finality and getLogs capacity probe
- **Date:** 2026-09-04
- **Reason:** scope decision — operational prerequisite for the indexer runtime (Backend
  Plan 2); explicitly does not block Backend Foundations Task 1 (Go module/tooling scaffold).
- **Where it stopped:** Backend Foundations design assumes usable `safe`/`finalized` block
  tags and unspecified `eth_getLogs` limits on Robinhood Chain (Arbitrum Nitro/Orbit).
  Neither has been measured against the real providers.
- **Owner:** Backend Plan 2 Task 1 (`docs/plans/2026-09-05-backend-indexer.md`). Tasks 2-7 of
  that plan depend on this probe; it is no longer unowned.
- **Related files:** `docs/specs/2026-09-01-backend-core-design.md` (§4.1, §4.3, §10),
  `docs/plans/2026-09-05-backend-indexer.md`
- **Resume (next step):** Before implementing the indexer runtime, run a read-only probe
  against the Robinhood mainnet provider and the chosen testnet provider and record:
  `latest`/`safe`/`finalized` tag support, tag monotonicity over time,
  observed→safe→finalized lag distribution, block-hash consistency across repeated reads,
  and `eth_getLogs` capacity (max block range, max response size, max addresses per filter).
  Feed the result into the runtime finality config, health lag thresholds, and the
  `INDEXER_CHUNK_SIZE` / address-filter partition defaults.
- **Pitfalls / notes:** Production Robinhood deployments must not fall back to a fixed
  confirmation count. If a provider cannot supply a usable `safe` tag, that is a launch
  blocker to raise before Plan 2 architecture, not a runtime patch.

### Robinhood testnet deployment manifest
- **Date:** 2026-09-01
- **Reason:** external deployment prerequisite
- **Where it stopped:** Mainnet WETH/Uniswap addresses are verified. Live checks showed the
  same addresses have no code on testnet, so they cannot be reused.
- **Owner:** Backend Plan 2 Task 1 (`docs/plans/2026-09-05-backend-indexer.md`). Only that
  plan's Task 8 testnet acceptance depends on it, so it does not block backend Tasks 2-7.
- **Related files:** `docs/specs/2026-09-01-contract-core-design.md`,
  `docs/specs/2026-09-01-backend-core-design.md`,
  `docs/plans/2026-09-05-backend-indexer.md`
- **Resume (next step):** Before testnet graduation integration, identify a verified
  official testnet deployment or deploy a project-owned WETH + Uniswap v2 test stack, then
  produce and review the chain-46630 deployment manifest.
- **Pitfalls / notes:** Testnet startup must remain graduation-disabled until the manifest
  is complete; never substitute mainnet addresses.

### ETH/USD enrichment source
- **Date:** 2026-09-01
- **Reason:** non-blocking product enrichment
- **Where it stopped:** No verified Robinhood Chain ETH/USD feed was selected. ETH-native
  values are canonical; USD columns are nullable by design.
- **Related files:** `docs/specs/2026-09-01-backend-core-design.md`
- **Resume (next step):** Before USD UI work, verify an on-chain feed deployment or select
  one cached external adapter with freshness and outage semantics.
- **Pitfalls / notes:** USD availability must not affect indexing, list correctness, quotes,
  or transaction construction.

### Production governance and audit inputs
- **Date:** 2026-09-01
- **Reason:** production-only external coordination
- **Where it stopped:** Contract roles and permitted actions are designed, but signer set,
  timelock delay, legal/geo policy, monitoring provider, and audit vendor are not selected.
- **Related files:** `docs/specs/2026-09-01-contract-core-design.md`
- **Resume (next step):** Resolve these inputs before a production deployment checklist is
  approved; transfer deployer authority and complete an external audit before accepting
  mainnet funds.
- **Pitfalls / notes:** These do not authorize changing existing launch economics or adding
  a reserve rescue path.

<!-- Template:
### <short title>
- **Date:** YYYY-MM-DD
- **Reason:** time | limit (~__%) | scope decision
- **Where it stopped:** <what was done and the exact stopping point>
- **Related files:** <paths>
- **Resume (next step):** <concrete first step + command>
- **Pitfalls / notes:** <things to watch out for>
-->

---

## Done

### Task 11 pinned Robinhood mainnet fork acceptance

- **Completed:** 2026-09-03
- **Evidence:** GitHub Actions run `33733283872` passed both the normal Foundry gate and the
  explicit QuickNode-backed fork job at pinned block `53,240,126` on commit `d09ba9a`.

### Task 12 contract release gate

- **Completed:** 2026-09-04
- **Evidence:** GitHub Actions `workflow_dispatch` run `33811377759` passed the `Foundry`,
  `Release gate`, and `Robinhood mainnet fork` jobs on commit `e663eb0`. Closes Contract
  Foundations (Tasks 1-12); external audit stays out of scope under "Production governance
  and audit inputs".
