# Launchpad roadmap

This roadmap is a delivery view of the normative specifications and task plans. The plans
remain the acceptance authority; this file explains what is currently usable and what comes
next.

## Current milestone

### Contract Foundations — complete

The Solidity system, fixed-supply launch token, integer bonding curve, graduation flow,
Uniswap v2 pair creation, governance controls, deployment artifacts, curve vectors, invariant
tests, and release/fork gates are implemented.

### Backend Foundations — complete

The Go module, validated configuration, deployment registry, PostgreSQL migrations, canonical
event ledger, projections, sqlc adapters, transaction primitive, and pure Go curve mirror are
implemented and covered by the repository gates.

### Backend Indexer — code complete; live acceptance externally gated

RPC access, ABI decoding, staged discovery, canonical event persistence, incremental
projections, advisory ownership, chunk processing, reorg recovery, aggregate recomputation,
dirty-work polling, notifications, and the health endpoint are implemented and verified.

The deterministic implementation gate now includes the Anvil indexer path and live-state health
surface. The read-only public-RPC probe is recorded in
[`docs/runbooks/robinhood-rpc-probe.md`](runbooks/robinhood-rpc-probe.md). Public-network
operation still requires:

1. Reviewed chain-46630 dependency and Launchpad deployment manifest. The repository-owned
   bootstrap and review procedure is documented in
   [`docs/runbooks/robinhood-testnet-deployment.md`](runbooks/robinhood-testnet-deployment.md).
### API and identity (Plan 3) — code complete

Plan 3 consumes canonical and derived backend state. It owns Huma REST endpoints, finality
and `asOfBlock` response metadata, Privy access-token and linked-wallet verification, quote
DTOs, pagination, and SSE streams. It does not redefine ledger semantics or curve formulas.
Its seven completed tasks are defined in
[`docs/plans/2026-09-08-backend-api-identity.md`](plans/2026-09-08-backend-api-identity.md).

### Web delivery (Plan 4) — code complete; live release externally gated

All eight Plan 4 tasks are implemented and independently reviewed on `dev`. The deterministic
web, backend, contracts, drift, browser, and Anvil gates are wired into CI. The release and
handoff boundary is documented in [`docs/runbooks/production-readiness.md`](runbooks/production-readiness.md).

Forum/Memestock remains a later milestone because its persistence, authorization, moderation,
and API contracts do not exist yet; Plan 4 does not claim it with static fixtures.

## Deferred operational work

- ETH/USD adapter implementation and production CoinGecko account/configuration; the source
  selection and failure semantics are recorded in
  [`docs/runbooks/eth-usd-enrichment.md`](runbooks/eth-usd-enrichment.md). ETH-native values
  remain canonical and USD fields nullable.
- Production governance signer set, timelock policy, monitoring, and external audit.
- Production hosting and deployment topology after the local/testnet acceptance gate.
- Testnet bootstrap, manifest review, and first funded acceptance run; use
  [`docs/runbooks/robinhood-testnet-deployment.md`](runbooks/robinhood-testnet-deployment.md).

## Delivery rule

`dev` contains active implementation. `main` receives only a verified milestone merge. A
green unit test run is not sufficient evidence for live testnet operation or production launch.
