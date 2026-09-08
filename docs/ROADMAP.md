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

### Backend Indexer — implementation delivered; acceptance in progress

RPC access, ABI decoding, staged discovery, canonical event persistence, incremental
projections, advisory ownership, chunk processing, reorg recovery, aggregate recomputation,
dirty-work polling, notifications, and the initial health endpoint are present on `dev`.

The milestone is not closed until the following evidence exists:

1. Robinhood mainnet/testnet RPC probe note with finality and `eth_getLogs` measurements.
2. Reviewed chain-46630 dependency and Launchpad deployment manifest.
3. Anvil-backed indexer end-to-end test covering launch, trades, graduation, pair activity,
   reorg, and finality promotion.
4. Runtime health values populated from live indexer state, not only startup defaults.

## Next milestone — API and identity (Plan 3)

Plan 3 consumes canonical and derived backend state. It owns Huma REST endpoints, finality
and `asOfBlock` response metadata, Privy access-token and linked-wallet verification, quote
DTOs, pagination, and SSE streams. It does not redefine ledger semantics or curve formulas.

## Later milestone — web delivery

The web client will provide Explore, graduated-token lists, token detail and trading views,
charts, forum/memestock features, analytics, wallet connection, and user-facing error and
finality states. It will consume Plan 3 contracts rather than query PostgreSQL directly.

## Deferred operational work

- ETH/USD enrichment source; ETH-native values remain canonical and USD fields nullable.
- Production governance signer set, timelock policy, monitoring, and external audit.
- Production hosting and deployment topology after the local/testnet acceptance gate.

## Delivery rule

`dev` contains active implementation. `main` receives only a verified milestone merge. A
green unit test run is not sufficient evidence for live testnet operation.
