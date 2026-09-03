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

### Robinhood testnet deployment manifest
- **Date:** 2026-09-01
- **Reason:** external deployment prerequisite
- **Where it stopped:** Mainnet WETH/Uniswap addresses are verified. Live checks showed the
  same addresses have no code on testnet, so they cannot be reused.
- **Related files:** `docs/specs/2026-09-01-contract-core-design.md`,
  `docs/specs/2026-09-01-backend-core-design.md`
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
