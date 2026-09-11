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
- **Where it stopped:** Mainnet WETH/Uniswap addresses are verified. Official Uniswap v2
  deployment records list Robinhood Chain mainnet, not chain 46630 testnet. The repository
  now has a deterministic project-owned dependency bootstrap, candidate evidence capture,
  Launchpad candidate-manifest flow, and operator runbook; no testnet transaction has been
  authorized or broadcast by the repository workflow.
- **Owner:** Backend Plan 2 Task 1 (`docs/plans/2026-09-05-backend-indexer.md`). Only that
  plan's Task 8 testnet acceptance depends on it, so it does not block backend Tasks 2-7.
- **Related files:** `docs/runbooks/robinhood-testnet-deployment.md`,
  `contracts/scripts/bootstrap-testnet-dependencies.ps1`, `contracts/scripts/deploy.ps1`,
  `contracts/deployments/config/robinhood-testnet.disabled.json`
- **Resume (next step):** A human operator must fund a named Foundry account, run the dry-run
  and broadcast commands in the runbook, independently review receipts/code hashes/source
  evidence, commit the reviewed dependency record, then run the Launchpad deployment and
  commit its reviewed chain-46630 manifest. The exact first command is:
  `pwsh ./contracts/scripts/bootstrap-testnet-dependencies.ps1 -RpcUrl <RPC> -Sender <address>`.
- **Pitfalls / notes:** Testnet startup must remain graduation-disabled until the manifest
  is complete; never substitute mainnet addresses.

### Production release, governance, and audit inputs
- **Date:** 2026-09-01
- **Reason:** production-only external coordination
- **Where it stopped:** The repository now contains the production input sheet, Privy
  dashboard checklist, governance handoff, health/rollback procedure, monitoring ownership
  checklist, and audit evidence checklist. No live organization, signer, policy, endpoint,
  hosting, monitoring, or auditor values have been invented.
- **Related files:** `docs/runbooks/production-readiness.md`,
  `docs/runbooks/web-release.md`, `web/.env.example`, `backend/.env.example`,
  `scripts/verify-release.mjs`
- **Resume (next step):** Product/infrastructure/security owners must fill every `<pending>`
  row in `docs/runbooks/production-readiness.md`, provision values through the approved
  secret/variable manager, and run `node scripts/verify-release.mjs --target=production`.
  Production approval still requires signed governance and external-audit evidence.
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
