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

### Production release, governance, and audit inputs
- **Date:** 2026-09-01
- **Reason:** production-only external coordination
- **Where it stopped:** Contract roles and permitted actions are designed, but signer set,
  timelock delay, legal/geo policy, monitoring provider, and audit vendor are not selected.
  Plan 4 additionally needs a real Privy application, verified production API/RPC endpoints
  and web origins, hosting/domain/CSP and edge-rate-limit ownership, monitoring, rollback
  ownership, and named incident contacts. The repository contains the deterministic release
  gate and runbook, but it must not invent these live values.
- **Related files:** `docs/specs/2026-09-01-contract-core-design.md`,
  `docs/plans/2026-09-09-web-client.md`, `docs/runbooks/web-release.md`,
  `web/.env.example`, `scripts/verify-release.mjs`
- **Resume (next step):** Resolve the Privy, public API/RPC/origin, hosting and operator
  inputs; then resolve governance signers/timelock/legal policy, monitoring, and external
  audit before approving a production deployment checklist or accepting mainnet funds.
- **Pitfalls / notes:** These do not authorize changing existing launch economics or adding
  a reserve rescue path. Do not commit credentials, private RPC URLs, wallet keys, or guessed
  deployment addresses.

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

### ETH/USD enrichment source selection

- **Completed:** 2026-09-11
- **Evidence:** `docs/runbooks/eth-usd-enrichment.md` records the official Robinhood and
  Chainlink review and selects CoinGecko’s commercial `/simple/price` API as the optional
  cached source. The runbook defines authentication, commercial attribution, numeric
  handling, freshness, outage, and rate-limit semantics.
- **Boundary:** This closes source selection only. The provider adapter, source/retrieval
  timestamps, attribution UI, and production API key remain a future implementation and
  operations step; ETH-native indexing, quotes, and transactions remain independent.

### Robinhood RPC finality and getLogs capacity probe

- **Completed:** 2026-09-11
- **Evidence:** `docs/runbooks/robinhood-rpc-probe.md` records read-only measurements against
  the official mainnet (`4663`) and testnet (`46630`) endpoints. Both endpoints returned
  `latest`, `safe`, and `finalized`; fixed-height block hashes were stable across repeated
  reads; bounded `eth_getLogs` range, response-size, and address-array observations are
  recorded.
- **Limitation:** the finality sample is short (two samples over about 14.5 seconds), so it
  is not a long-run provider SLA or a statistically derived alert percentile.

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
