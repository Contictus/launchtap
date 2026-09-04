# Backend Core — Design Spec

**Date:** 2026-09-01
**Status:** Design closed; implementation requires the normal high-risk pre-flight review
**Scope:** Go chain indexer, canonical ledger and projections, market aggregates, read API,
Privy authorization, and the Go curve mirror.
**Contract dependency:** `docs/specs/2026-09-01-contract-core-design.md` is authoritative
for economics, rounding, state transitions, and events.

## 1. Context and constraints

- Robinhood Chain mainnet `4663`, testnet `46630`; Anvil `31337` for local development.
- One Go 1.26 module at `backend/`, module path
  `github.com/Contictus/launchtap/backend`.
- Modular monolith with `cmd/api`, `cmd/indexer`, and `cmd/migrate`. API and indexer do
  not call each other; PostgreSQL is their shared source of truth.
- The backend never signs or submits user market transactions. Metadata/forum writes are
  authenticated off-chain; market state is read from chain.
- Solidity execution is authoritative. Go curve math is an informational mirror and must
  pass Solidity-generated differential vectors.
- One database instance is bound to one active chain deployment. `chain_id` is still stored
  in canonical keys so an accidental chain switch fails closed.

## 2. Architecture

### 2.1 Processes

- `cmd/api`: stateless REST/OpenAPI and best-effort SSE; horizontally scalable.
- `cmd/indexer`: singleton chain ingestion plus aggregation workers.
- `cmd/migrate`: embedded goose migrations.

`cmd/indexer` holds a session-level PostgreSQL advisory lock scoped by chain id and
deployment id on a dedicated connection. Failure to acquire or loss of that connection is
fatal; a second indexer must never continue as another writer.

### 2.2 Package layout

```text
backend/
  cmd/{api,indexer,migrate}/
  internal/
    launch/       launch and graduation projections
    trading/      canonical trades and informational quotes
    token/        explore, graduated, detail, and search reads
    holder/       transfer folding and holder definitions
    candle/       execution-price OHLCV
    stats/        token and protocol aggregates
    metadata/     off-chain metadata authorization
    curve/        pure big.Int mirror; stdlib only
    chain/        RPC, block/log fetch, ABI decoding; infrastructure only
    indexer/      watermarks, discovery, reorg, routing, and UoW ports
    store/postgres/
    config/
    privyauth/
    apiserver/
  deployments/   reviewed embedded chain manifests
  openapi/
```

### 2.3 Dependency rules

| Package | Allowed | Forbidden |
|---|---|---|
| `curve` | stdlib and `math/big` | all external packages |
| `config` | stdlib only; no `os` (environment via injected `func(string) string`) | everything else |
| `deployments` | stdlib, `encoding/json`, `embed`, go-ethereum `common` | pgx, sqlc, ethclient, chain, store, indexer, apiserver, feature modules |
| feature modules | feature ports, config values, go-ethereum value types | pgx, sqlc output, ethclient, chain, apiserver |
| `chain` | go-ethereum RPC/ABI packages | feature modules, store, indexer |
| `indexer` | chain ports, feature handlers, transaction port | apiserver, concrete pgx/sqlc types |
| `store/postgres` | pgx/v5, sqlc output, feature/indexer ports | chain, apiserver |
| `apiserver` | Huma, feature services, privyauth | chain, indexer, pgx/sqlc |

`common.Address`, `common.Hash`, and `*big.Int` are accepted domain value types. Infra
drivers and generated persistence types do not cross the application boundary.

### 2.4 Transaction boundary

One processed block chunk is one database transaction: block ledger rows, canonical event
rows, chain projections, aggregation-dirty markers, and the observed watermark commit or
roll back together.

The foundation exposes a store-internal `WithinTx` primitive backed by `pgx.Tx` and sqlc's
`DBTX`. The feature-level `IndexerUnitOfWork` and its narrow repository bundle are defined
with Plan 2 feature ports; Plan 1 must not freeze repository interfaces before their
consumers exist.

### 2.5 Migrations and test database provisioning

Migrations live at `internal/store/postgres/migrations/*.sql` — the single source,
embedded via `//go:embed migrations` and shared unmodified by `cmd/migrate` and the
PostgreSQL integration test helper. No second migrations directory and no copy.

**CLI contract.** `cmd/migrate` uses `config.LoadDatabase`, never `config.Load`. It has no
implicit default command; the operator names one explicitly:

```
cmd/migrate up
cmd/migrate down
cmd/migrate status
```

(Local invocation: `task migrate -- up`.) No production process runs migrations
implicitly. The shared migration runner is callable only from `cmd/migrate` and the
PostgreSQL integration test helper (which provisions throwaway per-test databases).
`cmd/api` and `cmd/indexer` (Plan 2/3) never run migrations at startup and never import
the runner for that purpose.

**Test database provisioning.** The integration test helper never migrates or otherwise
touches the database named in `DATABASE_URL`:

- If `DATABASE_URL` is set, the helper uses only its server coordinates (host, port,
  credentials), opens an administrative connection to the `postgres` maintenance database,
  and issues `CREATE DATABASE` for a uniquely named throwaway database per test.
  `DROP DATABASE` runs in the test's `t.Cleanup()`. If the supplied `DATABASE_URL` is
  unreachable, or the connecting role lacks `CREATE DATABASE`/`DROP DATABASE` privilege,
  the test **fails** — it does not skip, because an operator explicitly supplied
  `DATABASE_URL` and expected it to work.
- If `DATABASE_URL` is unset, the helper starts a `postgres:18.6-alpine` container via
  `testcontainers-go` (pinned to match `.github/workflows/backend.yml`'s service image),
  with a bounded startup timeout. If Docker is unavailable, the test skips with an explicit
  reason. Under `INTEGRATION_REQUIRED=true` that same condition is fatal, not a skip.
- Every test gets its own uniquely named database. No test runs against a database another
  test also uses; `t.Parallel()` and `go test -race` package-level parallelism must never
  race on shared schema state.

**Migration reversibility.** Every migration added by Tasks 5–7 ships a `Down` step that
actually restores the prior schema — not a no-op — so the required `up/down/up`
integration test is meaningful. This binds migration authors, not production operations:
production rollback stays forward-fix (a new forward migration); `Down` exists for the test
gate and local development, not a production revert procedure.

**Integration sentinel.** CI verifies more than "the test command exited zero." A named
test, `TestMigrationsUpDownUp`, run against a real database via the helper above, must be
observed to execute and pass. Concretely, a dedicated CI step runs:

```
go test -tags=integration -race -v -run '^TestMigrationsUpDownUp$' ./internal/store/postgres/...
```

and greps the `-v` output for a literal `--- PASS: TestMigrationsUpDownUp` line. A missing
test, a `--- SKIP:` line, or a `--- FAIL:` line fails the step regardless of the command's
own exit code — Go exits 0 when `-run` matches zero tests, so exit code alone cannot prove
the test ran.

## 3. Chain deployment registry

The backend defines no manifest schema of its own. `contracts/deployments/` is the single
source of truth, shared by contract deployment, backend, and frontend:

| Artifact | Schema | Selectable as a deployment? |
|---|---|---|
| Reviewed deployment manifest | `deployment.schema.json` | yes |
| Chain dependency record | `chain-dependencies.schema.json` | no |
| Chain disabled marker | `chain-disabled.schema.json` | no |

The backend consumes a byte-identical copy of `contracts/deployments/` and a CI check fails
if the copy drifts from the source (the curve-vector consumption pattern). No second schema,
no second generator, no RPC in this plan. `deployment.schema.json` pins `schemaVersion == 1`,
`engineVersion == 1`, `graduationEnabled == true`, and
`lpBurnAddress == 0x000000000000000000000000000000000000dEaD`; a manifest that violates any
of these is schema-invalid and rejected on load. There is no valid deployment manifest with
graduation disabled — that state is expressed only by a `chain-disabled` marker, which is
not a deployment.

### 3.1 Runtime Deployment model

The parsed runtime value carries only the fields the backend consumes:

```go
type Deployment struct {
    ChainID             uint64
    DeploymentID        string
    Name                string
    Environment         Environment // local | testnet | production
    Factory             common.Address
    StartBlock          uint64
    EngineVersion       uint16 // always 1 in V1
    CurveImplementation common.Address
    UniV2Factory        common.Address
    WETH                common.Address
    PairInitCodeHash    common.Hash
    LPBurnAddress       common.Address
    BytecodeHashes      BytecodeHashes // launchFactory, bondingCurveV1, uniV2Factory, weth
    DeployTransaction   common.Hash
    ExplorerBase        string
}
```

`uniswapV2Router02` is parsed and schema-validated but is **not** mapped into `Deployment`
and is never surfaced by the backend API; graduation uses Factory/Pair/WETH and routing is a
frontend concern. The `compiler`, `toolchain`, `governance`, and `verification` blocks are
schema-validated on load but are not part of the runtime model in this plan.

### 3.2 Lookup and fail-closed rules

- The lookup key is `(chain_id, deployment_id)`. An unknown key returns a typed
  `ErrDeploymentNotFound`; there is no default and no fallback to an Anvil manifest.
- A `chain-disabled` marker for the requested chain returns a typed `ErrDeploymentDisabled`
  carrying the recorded `reason`, distinct from `ErrDeploymentNotFound` so an operator can
  tell "explicitly disabled" from "unknown".
- A `chain-dependencies` record is never selectable as a deployment. Robinhood mainnet
  (`chain_id 4663`) currently has only a dependency record — no `LaunchFactory` or
  `BondingCurveV1` is deployed — so a production `(4663, …)` lookup fail-closes until a real
  reviewed and audited production manifest exists.
- Robinhood testnet (`chain_id 46630`) ships only its `chain-disabled` marker in this plan;
  producing the reviewed testnet manifest stays in `backlog.md`. A `46630` selection returns
  `ErrDeploymentDisabled` and cannot fall back to the mainnet dependency addresses.
- `deployment_id` is globally unique across every embedded manifest, and a repeated
  `(chain_id, deployment_id)` is rejected on load. `deployment_id` matches the canonical
  manifest pattern `^[a-z0-9][a-z0-9._-]{2,63}$`; `config.DEPLOYMENT_ID` uses the same
  expression so any selectable deployment is reachable from configuration.

### 3.3 Static validation (this plan) vs. chain verification (Plan 2)

Task 3 performs static validation only:

- schema validity against `deployment.schema.json`;
- every address parses via `common.IsHexAddress` and is compared byte-level as
  `common.Address` (embedded literals are stored EIP-55-checksummed for human review, but
  the comparison is checksum-agnostic);
- `Factory` and `CurveImplementation` are non-zero for every manifest;
- `LPBurnAddress == 0x…dEaD`;
- `EngineVersion` is in the supported set `{1}`;
- `PairInitCodeHash` and each `BytecodeHashes` entry are well-formed 32-byte non-zero hashes;
- `StartBlock` is the block of the factory deployment transaction and log discovery is
  inclusive of it; `StartBlock == 0` is accepted only for `Environment == local`.

`eth_getCode` bytecode verification and CREATE2 pair-address reproduction against
`UniV2Factory` are indexer-startup steps in Plan 2, not Task 3. Deployment generation
separately proves `StartBlock` equals the factory deployment receipt block.

### 3.4 Configuration reconciliation

`RPC_URL` and `DATABASE_URL` are environment-provided; contract addresses are not.
`config.Load` and `config.LoadDatabase` never resolve a manifest. API and indexer startup
each resolve the `(CHAIN_ID, DEPLOYMENT_ID)` manifest and then reconcile:

- `INDEXER_CONFIRMATIONS` (config, `*uint64`, nil when unset) is accepted only when the
  resolved manifest's `Environment == local`. For `testnet` or `production` a set
  `INDEXER_CONFIRMATIONS` is a fatal startup error. This is the enforcement Task 2 deferred.
- `CHAIN_ID` must equal the manifest `chainId`; a mismatch is fatal.

Known Robinhood mainnet dependency addresses (from
`contracts/deployments/config/robinhood-mainnet.json`, fork-verified at block `53240126`):

- WETH: `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73`
- Uniswap v2 Factory: `0x8bcEaA40B9AcdfAedF85AdF4FF01F5Ad6517937f`
- Router02: `0x89e5DB8B5aA49aA85AC63f691524311AEB649eba` (frontend routing only; not in the
  runtime `Deployment` model)

## 4. Finality and ingestion

### 4.1 Watermarks

The indexer reads `latest`, `safe`, and `finalized` headers. It does not treat an arbitrary
confirmation count as finality.

- `observed_head`: newest fully processed canonical-chain block; provisional and rollbackable.
- `safe_head`: newest node-reported safe block.
- `finalized_head`: newest node-reported finalized block.

Live UI reads observed projections and receives `finality=provisional|safe|finalized` plus
`as_of_block`. Settlement-oriented exports may request safe/finalized data. If a provider
does not support safe/finalized tags, startup fails unless the selected local-development
manifest explicitly enables a confirmations fallback; production Robinhood deployments do
not use that fallback.

Before the indexer runtime is implemented, an operational spike measures `latest`, `safe`,
and `finalized` tag support, tag monotonicity, the observed→safe→finalized lag distribution,
and block-hash consistency on the real Robinhood mainnet and chosen testnet providers. Its
result sets the runtime finality configuration and the health lag thresholds. It does not
block the backend module scaffold. See `backlog.md`.

### 4.2 Block ledger and reorg

`indexed_blocks` stores every processed block from `StartBlock`:

```text
(chain_id, block_number) PK
block_hash UNIQUE per chain
parent_hash, block_time, finality_status
```

Before extending the observed chain, the indexer verifies the new header's parent hash.
On mismatch it walks stored block hashes and RPC headers backward to the common ancestor,
then in one transaction:

1. Deletes canonical event rows above the ancestor.
2. Deletes block-ledger rows above the ancestor.
3. Rebuilds affected chain projections and derived rows from surviving canonical events.
4. Resets all affected watermarks.

Mutable `tokens.phase`, pair fields, holder balances, candles, and stats are projections;
deleting only event rows is never a complete rollback.

Reorgs wholly above the stored safe head are handled automatically. A hash mismatch at or
below the stored safe head stops ingestion and raises an operator-visible critical error;
a finalized block is never automatically deleted. Safe/finalized promotion first verifies
that the node-reported hashes match `indexed_blocks`. Watermarks exposed by the API are
bounded by the indexer's observed head even when the node is further ahead.

### 4.3 Staged address discovery

An `eth_getLogs` address filter is fixed for one request. Newly discovered addresses are
therefore processed in stages for every chunk:

1. Fetch factory logs and record `TokenLaunched` events.
2. Add discovered token/curve/pair addresses and refetch the affected block/receipt ranges.
3. Fetch known curve/token logs.
4. Fetch known pair logs.
5. Deduplicate and sort all logs by
   `(block_number, transaction_index, log_index)` before routing.

Same-transaction developer buys and graduation logs must be captured by the staged refetch.
The initial block chunk size and the address-filter partition size come from configuration,
not hard-coded provider numbers. Adaptive shrinking handles range and response-size errors
without changing event order. The measured `eth_getLogs` capacity of the active provider
(max block range, max response size, max addresses per filter) is recorded in the
deployment/operations notes and revisited when the provider plan changes; the architecture
does not embed a specific provider tier's limits.

Processing is two-pass inside the chunk transaction. The discovery pass inserts launch
ledger rows and token identity/projection skeletons idempotently. The event pass then applies
all standard and market logs in chain order. This supports the constructor's initial
`Transfer(0, curve, S)` appearing before `TokenLaunched`; any other pre-launch token log is
a fatal contract-invariant violation.

Under the locked V1 parameters the developer-buy cap (1% of `S`) is far below the curve
allocation `T_r`, so a launch transaction cannot also graduate. This is recorded as current
V1 deployment behavior, not a permanent indexer assumption: a future parameter snapshot or
engine version could change the ratio, so the indexer must not encode it as a fatal rule.

### 4.4 Canonicality and idempotency

Every event row contains:

```text
chain_id, block_number, block_hash, block_time,
transaction_index, tx_hash, log_index
```

Uniqueness is `(chain_id, tx_hash, log_index)`. Reprocessing is idempotent. Logs are decoded
using the ABI selected by factory deployment and `engine_version`; an unknown version is a
fatal indexing error, not a best-effort decode.

The V1 `Trade` decoder reads `ethGross` and `ethRefund` as adjacent fields (refund directly
after gross) and persists both. `ethGross + ethRefund` is the ETH supplied to the curve for
a buy and must reconcile from logs alone without transaction traces; `ethRefund` is `0` for
every sell. Executed-volume and candle inputs use `ethGross` only and never add `ethRefund`.

A curve `Trade` log dated after the same token's `Graduated` block is a fatal invariant
violation. The curve phase is one-way and post-graduation market activity is DEX-only.

## 5. Data model

### 5.1 Control and canonical event ledger

| Table | Purpose |
|---|---|
| `sync_state` | one row per chain/deployment; observed, safe, finalized watermarks and hashes |
| `indexed_blocks` | hash-linked processed block history and finality status |
| `token_launches` | exact `TokenLaunched` payload, including engine version and pair |
| `trades` | exact curve `Trade` payload, including `eth_gross` and the adjacent `eth_refund` |
| `graduations` | exact `Graduated` payload |
| `creator_fee_claims` | exact creator claim events |
| `protocol_fee_claims` | curve protocol-fee claim events |
| `launch_fee_claims` | factory launch-fee claim events |
| `refund_credits`, `refund_claims` | pull-refund lifecycle |
| `transfers` | ERC-20 Transfer logs |
| `pool_mints`, `pool_burns`, `pool_swaps`, `pool_syncs` | canonical Uniswap pair events |

`pool_syncs` is the authoritative reserve history. `pool_swaps` alone cannot reconstruct
liquidity changes, direct syncs, or the opening reserves.

### 5.2 Chain projections

| Table | Purpose |
|---|---|
| `tokens` | latest launch identity, parameter snapshot, phase, pair ordering, and launch coordinates |
| `token_reserves` | latest curve reserves or pair reserves with source block/log |
| `holder_balances` | folded Transfer balances and first acquisition |
| `aggregation_dirty` | transactional rebuild queue keyed by chain/token |

These tables are updated transactionally for reads but are rebuildable from the canonical
ledger. Off-chain metadata and images are not chain projections and survive a chain replay.

Curve graduation progress is derived, not stored as chain state:
`realCurveEth = virtualEthReserve - initialVirtualEth` and
`progress = realCurveEth / graduationEth`, where `initialVirtualEth` and `graduationEth`
come from the launch snapshot in `tokens`. The `Trade` event carries only the post-trade
virtual reserve, so the snapshot must be retained for the life of the token. An integration
test cross-checks the derived value against the curve's `realCurveEth()` view.

### 5.3 Market semantics

Do not overload one `price_wad` with different meanings:

- `execution_price_wad`: trade reserve delta divided by token amount; candles and trade
  history use this value.
- `spot_price_wad`: post-trade curve `x/y`, or post-update pair WETH/token reserves from
  `Sync`.
- `gross_eth_volume`: executed gross ETH for a curve trade — the `Trade.ethGross` value,
  which already excludes `Trade.ethRefund`; WETH leg for a DEX swap.
- `token_volume`: absolute token leg.

For DEX rows, `sender` and `to` are routing participants, not proven end-user identities;
the normalized `trader` is nullable.

`market_trades` is a SQL view over curve trades and DEX swaps with:

```text
chain_id, token_address, block_number, block_time, transaction_index,
tx_hash, log_index, source, side_buy, trader,
execution_price_wad, spot_price_wad, gross_eth_volume, token_volume,
finality
```

DEX `execution_price_wad` is derived from the Swap legs. Its `spot_price_wad` is resolved
from the `pool_syncs` row with the same `chain_id`, pair address, and `tx_hash` whose
`log_index` is the greatest value strictly less than this `Swap`'s `log_index`. Uniswap v2
emits `Sync` before each `Swap`, `Mint`, and `Burn`, so one transaction may carry several
`Sync`/`Swap` pairs on a pair; the strict-less-than-by-log-index rule selects the correct
post-state for each swap.

### 5.4 Supply and holder definitions

- `circulating_supply = total_supply - balance(curve) - balance(zero) - balance(dead)`.
- The canonical Uniswap pair balance counts as circulating supply.
- `market_cap = spot_price * circulating_supply`; `fdv = spot_price * total_supply`.
- Immediately before graduation circulating supply is `T_r`; after the reserved `L` enters
  the pair it becomes `S`, absent burns or forced transfers.
- Holder lists and `holder_count` exclude zero, dead, curve, and canonical pair addresses,
  while the pair balance still participates in circulating supply.
- `first_acquired` is the first block in the holder's current nonzero-balance period; it
  resets after the balance reaches zero.

ETH-denominated fields are canonical derivations. USD fields are nullable enrichment and
never determine list correctness or transaction behavior. USD columns are nullable
`NUMERIC(38,18)`; no float type is used even though the value is enrichment.

### 5.5 Derived market tables

| Table | Purpose |
|---|---|
| `candles` | execution-price OHLCV at `1m`, `5m`, `1h`, `1d`; `6h` and `all` aggregate on read |
| `token_stats` | ETH spot, market cap, FDV, liquidity, ATH, 24h volume/change, holder count, optional USD values |
| `protocol_daily` | daily ETH/USD volume, launches, trades, graduations |
| `protocol_stats` | current 24h/all-time protocol summary |

## 6. Aggregation and notifications

Canonical ingestion writes/upserts `aggregation_dirty` in the same transaction as events.
After commit it sends a small `NOTIFY market_dirty` wake-up containing only chain/deployment
and generation/checkpoint identifiers, never an affected-token list.

Worker startup order is: commit `LISTEN`, read the dirty snapshot, then enter the
notification loop. Notifications are hints; the dirty table is the durable work source.
A periodic reconciliation sweep rebuilds recent buckets and any projection affected by a
reorg. Aggregators never read chain RPC.

## 7. Curve mirror and quotes

`internal/curve` reproduces the contract's operation order and integer rounding exactly.
It returns domain errors for invalid public inputs; malformed static fixtures may panic only
inside tests. In particular, sells reject `tokensIn > tokensSold`, not `tokensIn >= Y`.

The package includes the exact-gross-for-net helper used by the final buy. Foundry generates
versioned JSON vectors from deployed Solidity behavior; Go consumes those files unchanged.
Hand-calculated or model-supplied values are not authoritative fixtures.

The backend quote endpoint is informational because its indexed reserves can be stale. It
returns `asOfBlock`, `finality`, `informational=true`, and no transaction-ready guarantee.
The frontend must call the curve contract's view quote against current RPC state before
building a transaction, and the transaction must enforce `minOut` and `deadline` on-chain.

## 8. Privy authentication and authorization

Privy session authentication and linked-wallet proof are separate:

- `Authorization: Bearer <access-token>` proves the Privy session.
- `X-Privy-Identity-Token: <identity-token>` supplies verified linked accounts.
- The verifier validates signature, issuer, audience/app id, expiry/not-before, and subject
  for both tokens, then requires matching subjects.
- Only linked wallet accounts from the verified identity token populate
  `AuthedUser.LinkedWallets`; merely connected client wallets are not accepted.

```go
type AuthedUser struct {
    PrivyDID      string
    LinkedWallets []common.Address
}
```

No custom SIWE endpoint or backend session table is added. Metadata authorization requires
the indexed launch creator to be in `LinkedWallets`. Token verification is behind a narrow
`Verifier` interface; its crypto/key-loading adapter follows the exact current Privy
verification-key format and is covered by valid, expired, wrong-audience, wrong-subject,
and unlinked-wallet tests. The design does not assume a generic JWKS URL.

## 9. API and realtime contract

- Huma over `net/http`, REST/JSON under `/v1`, generated OpenAPI committed and diffed in CI.
- Cursor pagination includes deterministic chain coordinates so equal timestamps cannot
  duplicate or skip rows.
- Errors use `application/problem+json`.
- Every market response includes `chainId`, `asOfBlock`, and `finality` at the response or
  collection level.
- SSE is best-effort. Clients fetch a REST snapshot first and treat SSE messages as refresh
  hints. PostgreSQL remains the source of truth; no replay/`Last-Event-ID` guarantee in v1.

Core endpoints remain Explore, Graduated, token detail/search, candles, trades, holders,
informational quote, protocol stats, metadata/image writes, health, and launch/token SSE.
Endpoint DTOs are finalized in the API plan after the underlying projections exist.

## 10. Configuration

Environment values:

```text
CHAIN_ID, DEPLOYMENT_ID, RPC_URL, DATABASE_URL,
PRIVY_APP_ID, PRIVY_VERIFICATION_KEY,
LOG_LEVEL, API_ADDR, INDEXER_CHUNK_SIZE, ETH_USD_SOURCE
```

`INDEXER_CHUNK_SIZE` is the initial block-range chunk; the staged-discovery address-filter
partition size is a further configuration value introduced with the indexer plan. Both are
starting points for adaptive shrinking, not hard limits.

`INDEXER_CONFIRMATIONS` exists only for manifests explicitly marked local-development
fallback. Contract addresses, start block, WETH, burn address, and engine version come from
the reviewed deployment manifest. Unknown or incomplete production manifests fail startup.

## 11. Testing and delivery gates

| Layer | Required verification |
|---|---|
| Curve | Solidity-generated vectors, Go fuzz/property tests, Anvil differential calls |
| Store | real PostgreSQL; migrations up/down/up; constraints, rollback, and replay tests |
| Indexer | staged discovery, duplicate logs, provider partitioning, same-tx events, shallow/deep reorg, mutable projection rollback, finality promotion |
| Auth | valid/expired/wrong-app/wrong-subject tokens and connected-but-unlinked wallet rejection |
| API | httptest contracts, cursor stability, finality fields, OpenAPI golden diff |
| CI | Go build/test-race/lint/sqlc diff, PostgreSQL service, Foundry gates, web gates when present |

Local integration tests may skip when Docker is unavailable. The CI integration job must
fail, not skip, if PostgreSQL is unavailable or no integration test ran.

## 12. Observability

Health reports deployment id; observed/safe/finalized blocks and timestamps; per-watermark
lag; advisory-lock ownership; last reorg depth/time; RPC status; dirty-work count; and token
phase counts. Structured logs include chain, deployment, block/hash, tx hash, and reorg id.

## 13. Deliberately deferred, non-blocking items

- ETH/USD provider: nullable enrichment adapter; ETH remains authoritative.
- Image storage migration from PostgreSQL to object storage.
- Materializing `market_trades` if measured query performance requires it.
- Post-graduation protocol fee capture; V1 remains vanilla Uniswap v2.
- Forum/moderation and market ticker data.

## 14. Invariants

- Contract events and block headers are the only source for market state.
- Solidity is the only authority for curve execution; Go never invents expected vectors.
- Observed data is explicitly provisional until safe/finalized; fixed confirmation counts
  are not called finality.
- Canonical events are append/idempotent for the current chain and rollback on reorg;
  projections and aggregates are always rebuildable.
- A pair `Sync`, not a swap amount, is the authority for reserves and spot price.
- The backend never supplies the final executable quote without an on-chain `eth_call` and
  transaction-level slippage/deadline protection.
- Curve buy input reconciles from logs alone: `Trade.ethGross + Trade.ethRefund` is the ETH
  supplied to the curve, and `ethRefund` is never part of executed volume.

## 15. Primary references checked for design closure

- Robinhood RPC and Nitro node model: https://docs.robinhood.com/chain/connecting/ and
  https://docs.robinhood.com/chain/run-a-full-node/
- Ethereum JSON-RPC block tags and log filtering:
  https://ethereum.org/en/developers/docs/apis/json-rpc/
- Privy access/identity tokens and linked wallets:
  https://docs.privy.io/authentication/user-authentication/tokens,
  https://docs.privy.io/user-management/users/identity-tokens, and
  https://docs.privy.io/wallets/wallets/get-a-wallet/get-connected-wallet
- PostgreSQL LISTEN/NOTIFY and advisory locks:
  https://www.postgresql.org/docs/17/sql-listen.html,
  https://www.postgresql.org/docs/17/sql-notify.html, and
  https://www.postgresql.org/docs/current/functions-admin.html
- Current Huma, sqlc, and golangci-lint configuration baselines:
  https://huma.rocks/tutorial/installation/,
  https://docs.sqlc.dev/en/latest/reference/config.html, and
  https://golangci-lint.run/docs/configuration/file/
