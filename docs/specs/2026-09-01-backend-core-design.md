# Backend Core — Design Spec

**Date:** 2026-09-01
**Status:** Draft for review
**Scope:** Sub-project A backend (Go): chain indexer + read API + curve math mirror.
**Out of scope:** Solidity contracts (own spec), web frontend, forum, analytics beyond
protocol tiles, Limit/Orders, v1/v2 UI, tokenized-stock pairing.

---

## 1. Context & constraints

- **Product:** pons-style fixed-supply token launchpad. Bonding curve → graduation →
  Uniswap v2 pool with LP burned. Non-custodial: all state-changing actions are
  submitted by the user's wallet; the backend is read-only except off-chain metadata.
- **Chain:** EVM-agnostic contracts; target Robinhood Chain (testnet 46630 / mainnet
  4663), an Arbitrum-Orbit EVM L2. Dev on Anvil; Base Sepolia optional portability check.
- **Language:** Go. No tRPC, no Ponder. Custom Go indexer (`go-ethereum` + `abigen`).
- **Budget:** zero-cost. Free tiers only; Docker Postgres for dev. Hosting deferred.
- **Wallet/auth:** Privy (embedded + external wallets + email/social). Backend verifies
  Privy JWTs; no custom auth system.

## 2. Locked economic model (backend depends on these)

| Parameter | Value |
|---|---|
| Total supply `S` | 1,000,000,000 × 10¹⁸ (fixed, no mint) |
| Curve allocation `T_r` | 800,000,000 (provisional 80/20) |
| LP allocation `L` | 200,000,000 |
| Curve type | virtual-reserve constant-product, `x·y = k` |
| `x0` (initial virtual ETH) | `G·L/(T_r−L)` = 1.4 ETH at defaults |
| `y0` (initial virtual token) | `T_r²/(T_r−L)` = 1,066,666,667 at defaults |
| Graduation threshold `G` | 4.2 ETH default; configurable per future launch; snapshot at launch |
| Launch fee | 0.0005 ETH → protocol treasury |
| Trade fee | 1% (100 bps), split 50% protocol / 50% creator — **curve phase only** |
| Snipe tax | none (v1) |
| Developer buy | allowed, max 1% of supply at launch |
| Graduation fee | 0 (all `G` to pool) |
| Creator fees | accrue on-chain, creator claims |
| Post-graduation fees | none (vanilla Uniswap); future via V4 hook |

**Parameter management principle:** every launch parameter (`x0, y0, T_r, L, G`, fees) is
snapshotted into the clone's immutable storage at launch. The factory holds mutable
defaults for *future* launches only. A started launch's rules never change.

**Derived quantities:**
- launch→graduation FDV multiple = `(T_r/L)²` (16× at 80/20), independent of `G`
- initial FDV = `G·L·S/T_r²` ; graduation FDV = `G·S/L`
- pool ETH depth = `G`, independent of the split

## 3. Contract interface (event schema)

The backend consumes these events. Contract implementation is a separate spec; this is
the agreed interface.

```solidity
// Factory
event TokenLaunched(
    address indexed token, address indexed curve, address indexed creator,
    uint256 totalSupply,      // 1e27
    uint256 virtualEth,       // x0 snapshot
    uint256 virtualToken,     // y0 snapshot
    uint256 curveTokens,      // T_r
    uint256 lpTokens,         // L
    uint256 graduationEth,    // G
    uint16  tradeFeeBps,      // 100
    uint16  protocolShareBps  // 5000
);

// Curve clone — every buy/sell, curve phase only
event Trade(
    address indexed token, address indexed trader, bool isBuy,
    uint256 ethAmount,        // GROSS, before fees
    uint256 tokenAmount,
    uint256 protocolFee, uint256 creatorFee,           // ETH
    uint256 newEthReserve, uint256 newTokenReserve     // x, y after
);

// Curve clone — once
event Graduated(
    address indexed token, uint256 ethToPool, uint256 tokensToPool,
    address lpPair, uint256 graduationFee              // graduationFee = 0 in v1
);

// Curve clone
event CreatorFeesClaimed(address indexed token, address indexed creator, uint256 amount);
```

The backend is **parametric**: it reads `x0, y0, T_r, L, G`, and fee bps from
`TokenLaunched` and stores them per token. It hard-codes no economic value, so the
provisional 80/20 split (or any later retune) does not affect backend code.

Plus standard external events indexed per token:
- ERC-20 `Transfer(from, to, value)` — for holder balances (all phases)
- Uniswap v2 pair `Swap(...)` and `Sync(reserve0, reserve1)` — post-graduation price/volume

Notes: no `ts` field (logs carry block/time). Protocol fee is transferred immediately to
treasury (visible as `protocolFee` in `Trade`, no separate event). Creator fees accrue and
are claimed (`CreatorFeesClaimed`).

## 4. Architecture

### 4.1 Shape

Modular monolith, one Go module (`backend/`). Two runtime processes + a migration runner,
all from the same codebase:

- `cmd/api` — HTTP API. Stateless, horizontally scalable (N replicas).
- `cmd/indexer` — chain ingestion loop + aggregation goroutine. **Singleton.**
- `cmd/migrate` — runs embedded migrations.

`api` and `indexer` never call each other over the network. They communicate through
Postgres (+ `LISTEN/NOTIFY` for live hints). Deployed together on one box for v1.

### 4.2 Package layout

```
backend/
  cmd/{api, indexer, migrate}/main.go
  internal/
    # --- feature modules (vertical slices): entity + service + repo interface ---
    launch/      TokenLaunched ingestion, param snapshot, graduation phase transition
    trading/     Trade ingestion → canonical trades; quotes (consumes curve/)
    token/       read model: explore/graduated lists, detail, search
    holder/      Transfer ingestion → balances, holder lists
    candle/      OHLC / price series builder (price aggregator)
    stats/       protocol analytics: 24h + daily rollups
    metadata/    off-chain token metadata + Privy-auth authorization
    # --- shared technical ---
    curve/       pure bonding-curve math (big.Int); zero dependencies
    chain/       RPC client, log fetch, block headers, ABI decoding — infra ONLY
    indexer/     sync loop, checkpoint, reorg rollback, event routing → module handlers
    store/
      postgres/  pgx pool, sqlc output, UoW impl; one file per feature + uow.go + db.go
      migrations/ goose SQL files (embedded)
    config/      env parsing + chain registry
    privyauth/   Privy JWT verification middleware (JWKS cache)
    apiserver/   huma app, SSE hub, mounts module routers, problem+json errors
  openapi/       generated openapi.json → consumed by web for TS types
```

### 4.3 Dependency rules (enforced via `depguard` lint)

| Package | May import | May NOT import |
|---|---|---|
| `curve/` | stdlib, `math/big` | everything else |
| feature modules | `curve/`, `config/`, stdlib, go-ethereum **value types** | `pgx`, `sqlc`, `ethclient`, `chain/`, `store/` |
| `chain/` | `ethclient`, go-ethereum | feature modules, `store/`, `indexer/` |
| `indexer/` | `chain/`, feature module handlers, `store/` | `apiserver/` |
| `store/postgres` | `pgx`, sqlc, feature module **interfaces** | `chain/`, `apiserver/` |
| `apiserver/` | `huma`, feature module services, `privyauth/` | `chain/`, `indexer/` |

**DIP line:** domain/application code must not touch infra drivers/clients (`pgx`, `sqlc`,
`ethclient`). It *may* use go-ethereum value types (`common.Address`, `common.Hash`,
`*big.Int`) as domain primitives — the product is EVM-native and wrapping them buys no
portability, only ceremony.

### 4.4 Ports & adapters

Each feature module defines the repository interface it consumes, next to the consumer,
kept narrow (ISP). Example:

```go
// internal/token/repository.go
type Repository interface {
    Get(ctx context.Context, addr common.Address) (Token, error)
    List(ctx context.Context, q ListQuery) ([]Token, Cursor, error)
    Search(ctx context.Context, term string, limit int) ([]Token, error)
}
```

`internal/store/postgres` implements every module's `Repository` against sqlc queries.

### 4.5 Unit of Work

One block chunk is processed in one DB transaction spanning multiple modules, without
leaking `pgx.Tx` into the domain:

```go
type Repositories struct {
    Launch  launch.Repository
    Trading trading.Repository
    Holder  holder.Repository
    Sync    SyncRepository
    // ...
}
type UnitOfWork interface {
    WithinTx(ctx context.Context, fn func(r Repositories) error) error
}
```

Implementation: `WithinTx` opens a `pgx.Tx`, constructs each repo bound to that tx (sqlc's
`DBTX` interface is satisfied by both `*pgxpool.Pool` and `pgx.Tx`, so binding is trivial),
calls `fn`, commits on `nil` / rolls back otherwise. Feature-module services are stateless
and accept repos as parameters so they compose inside a UoW.

Indexer per-chunk flow:

```
uow.WithinTx(ctx, func(r Repositories) error {
    for _, ev := range sortedEvents {   // see 5.3
        route(ctx, ev, r)               // r.Launch.Record(...), r.Trading.Insert(...), ...
    }
    return r.Sync.SetCheckpoint(ctx, chunkEndBlock, chunkEndHash)
})   // BEGIN … all events … checkpoint … COMMIT   (atomic)
```

## 5. Chain ingestion

### 5.1 RPC & chain registry

- `go-ethereum/ethclient` over HTTP. WebSocket optional later.
- Providers: Anvil (local), Alchemy Robinhood endpoints (testnet/mainnet).
- `config.ChainConfig` keyed by chain id; one active via `CHAIN_ID` env:

```go
type ChainConfig struct {
    ChainID       uint64
    Name          string
    RPCURL        string  // env-injected secret
    FactoryAddr   common.Address  // our launchpad factory (per deployment)
    StartBlock    uint64          // factory deploy block; backfill origin
    Confirmations uint64          // reorg safety depth (default 5; verify for RH Chain)
    UniV2Factory  common.Address
    UniV2Router   common.Address
    WETH          common.Address
    ExplorerBase  string
}
```

### 5.2 Watched sets

A single `eth_getLogs` per block range with a growing address set and a fixed topic set:

- Static: `FactoryAddr` → `TokenLaunched`
- Dynamic (added as `TokenLaunched` is seen): each `curve` clone → `Trade`, `Graduated`,
  `CreatorFeesClaimed`; each `token` → ERC-20 `Transfer`
- Dynamic (added as `Graduated` is seen): each `lpPair` → `Swap`, `Sync`

`FilterQuery{FromBlock, ToBlock, Addresses: [...all known...], Topics: [[sig union]]}`.
The known-address set is loaded from `tokens` + `graduations` on indexer boot.

### 5.3 Deterministic ordering

Before processing a batch, sort logs by `(block_number, transaction_index, log_index)`.
RPC return order is not guaranteed, especially across paginated calls or multi-address
filters. Ordering matters: within one tx a final `Trade` must be recorded before the
`Graduated` in the same tx flips the phase.

### 5.4 Backfill + live (one code path)

- **Backfill:** from `max(StartBlock, checkpoint+1)` to `head − Confirmations`, in chunks
  (default 2000 blocks; halve on provider range/response-size error, restore gradually).
  Each chunk = one UoW transaction (events + checkpoint).
- **Live:** poll `eth_blockNumber` every ~1.5s; when `head − Confirmations > checkpoint`,
  process the delta through the same chunked path.

### 5.5 Checkpoint & idempotency

- `sync_state(id, chain_id, last_block, last_block_hash, updated_at)` — single row.
- Every canonical row carries `(block_number, tx_hash, log_index)` with a unique constraint
  on `(tx_hash, log_index)`. Writes use `ON CONFLICT DO NOTHING`, so re-processing a range
  is idempotent. A crash mid-run resumes from the last committed checkpoint; the API keeps
  serving the last committed state.

### 5.6 Reorg handling

- Only blocks up to `head − Confirmations` are ever processed.
- On each live poll, verify the parent-hash chain from `last_block_hash` forward. On
  mismatch, find the fork point, delete all canonical rows with `block_number > fork` (every
  table carries `block_number`), reset the checkpoint to the fork, and re-process. Derived
  data (candles, rollups, balances) is rebuilt from canonical rows by the aggregators.

### 5.7 Phase transition is a domain concern

`chain/` decodes a `Graduated` log into a typed struct and nothing more. The indexer routes
it to `launch.Service.RecordGraduation(...)`, which sets `tokens.phase = graduated`, stores
`lp_pair`, records the `graduations` row, and computes/stores `token_is_token0` (WETH
ordering in the pair, needed to derive DEX price). The indexer then adds `lp_pair` to the
watched set. A stray `Trade` after graduation (contract should prevent it) is logged and
ignored.

## 6. Curve math (`internal/curve`)

### 6.1 Purpose

Off-chain mirror of the Solidity curve for: (a) pre-trade quotes in the UI, (b) any derived
value not carried by events. Events carry post-trade reserves, so price/MC/FDV are direct;
quotes need the full formula.

### 6.2 Precision rules

- All arithmetic in `*big.Int`, mirroring the contract's integer operations **exactly** —
  same operation order, same rounding direction (round toward zero as Solidity does).
- No `float64`, no `big.Float` for anything that must match chain state.
- `shopspring/decimal` is allowed only at the API DTO layer for human-readable USD/percent.

### 6.3 Surface

```go
type State struct{ X, Y, K *big.Int } // X = ETH reserve, Y = token reserve, K = X*Y

func QuoteBuy(s State, ethGross *big.Int, feeBps, protoShareBps uint16)
    (tokensOut, protocolFee, creatorFee *big.Int, next State)
func QuoteSell(s State, tokensIn *big.Int, feeBps, protoShareBps uint16)
    (ethOut, protocolFee, creatorFee *big.Int, next State)
func SpotPriceWad(s State) *big.Int                    // X * 1e18 / Y
func TokensSold(s State, y0 *big.Int) *big.Int         // y0 - Y
func IsGraduated(s State, y0, curveTokens *big.Int) bool
```

### 6.4 Parity / differential testing

Solidity is authoritative execution; Go is quote/simulation only. To guarantee they never
drift:

- Foundry emits a table of `(state, input) → output` vectors (via `forge script` / test
  fixtures checked into the repo).
- A Go test feeds the identical vectors through `internal/curve` and asserts **byte-identical**
  `big.Int` results.
- Fuzz layer: random states/inputs, cross-checked against a curve deployed on a local Anvil
  via `cast call`.
- All of the above runs in CI.

## 7. Data model

### 7.1 Canonical (indexer writes; rebuildable target = never)

| Table | Key columns |
|---|---|
| `sync_state` | single row |
| `tokens` | `address` PK; `curve_address, creator, name, symbol, total_supply, x0, y0, k, curve_tokens, lp_tokens, graduation_eth, trade_fee_bps, protocol_share_bps, phase, lp_pair, token_is_token0, launched_at, launch_block, launch_tx` |
| `trades` | `token_address, trader, is_buy, eth_amount, token_amount, protocol_fee, creator_fee, new_eth_reserve, new_token_reserve, price_wad, block_number, block_time, tx_hash, log_index` |
| `graduations` | `token_address` PK; `eth_to_pool, tokens_to_pool, lp_pair, graduation_fee, block_*` |
| `creator_fee_claims` | `token_address, creator, amount, block_*` |
| `transfers` | `token_address, from_addr, to_addr, value, block_*` (high volume) |
| `pool_swaps` | `token_address, pair, amount0_in, amount1_in, amount0_out, amount1_out, price_wad, block_*` (post-graduation) |

`price_wad` on `trades` is computed at insert from the post-trade reserves. On `pool_swaps`
it is computed from the swap amounts + `token_is_token0`.

Unique `(tx_hash, log_index)` on every event-derived table.

### 7.2 Unified market-trade projection

Canonical storage stays split. Everything market-facing (candles, volume, ATH, realtime
feed, trade history endpoint) reads a single normalized view:

```sql
CREATE VIEW market_trades AS
  SELECT token_address, block_time AS ts, price_wad,
         eth_amount AS eth_volume, token_amount AS token_volume,
         is_buy AS side_buy, trader, tx_hash, log_index, 'curve' AS source
  FROM trades
  UNION ALL
  SELECT token_address, block_time, price_wad,
         (amount0_in + amount0_out) /* WETH leg, resolved via token_is_token0 */ AS eth_volume,
         (amount1_in + amount1_out) AS token_volume,
         (amount1_out > 0) AS side_buy, NULL, tx_hash, log_index, 'dex'
  FROM pool_swaps;
```

(Exact WETH-leg resolution handled in the view via `token_is_token0`; simplified above.)
Promote to a materialized view or a real `market_trades` table if read perf demands.

### 7.3 Derived (aggregators write; fully rebuildable from canonical)

| Table | Purpose |
|---|---|
| `holder_balances` | PK `(token_address, holder)`; `balance, first_acquired_block, updated_block` — folded from `transfers` |
| `candles` | PK `(token_address, interval, bucket_start)`; `open, high, low, close, volume_eth, volume_token, trade_count`. Intervals stored: `1m, 5m, 1h, 1d`. `6h` / `all` derived on read. |
| `token_stats` | `token_address` PK; hot denormalized row: `price_wad, price_usd, fdv_usd, circ_mc_usd, liquidity_usd, ath_price_wad, vol_24h_usd, price_change_24h, holder_count, updated_at`. Lists and detail read from here. |
| `protocol_daily` | `day` PK; `volume_eth, volume_usd, launches, trades, graduations` — analytics bars |
| `protocol_stats` | single hot row: `vol_24h_usd, launches_24h, trades_24h, updated_at` |

### 7.4 Tooling

- `pgx/v5` pool; `sqlc` for typed queries (`internal/store/postgres/queries/*.sql`);
  `goose` migrations embedded and run by `cmd/migrate` (or `cmd/api` on boot behind a flag).
- Search: `tsvector` GIN index on `tokens(name, symbol)` + exact-match on `address`.
- TimescaleDB deferred; plain Postgres + `candles` table is sufficient for v1.

## 8. Aggregation

Conceptually separate from ingestion. Indexer answers "what happened on chain?" and writes
canonical rows. Aggregators answer "what market data can I derive?" and write derived rows.

- Packages: `candle/`, `stats/`, and holder-balance folding (in `holder/`).
- Trigger: after each indexer chunk commits, it emits a Postgres `NOTIFY market_dirty` with
  the affected token set. Aggregators (running as goroutines in `cmd/indexer` for v1)
  `LISTEN` and incrementally update: the current candle bucket, `token_stats`,
  `protocol_stats`.
- Periodic reconcile sweep (e.g. every 60s) re-derives recent buckets / rollups from
  canonical rows — covers reorg rollbacks and missed notifications.
- Aggregators never read the chain and never run inside the sync loop. They can later move
  to `cmd/aggregator` unchanged.

## 9. API (`internal/apiserver` + module services)

### 9.1 Shape

- `huma` over `net/http`; REST/JSON; base path `/v1`; OpenAPI generated to `openapi/openapi.json`,
  consumed by `web` to generate a typed TS client (one-way codegen, no runtime coupling).
- Cursor-based pagination everywhere lists are returned.
- Errors as `application/problem+json`; domain errors mapped (`NotFound`, `Validation`,
  `Conflict`).

### 9.2 Auth (Privy only)

- `privyauth` middleware: extract Privy JWT from `Authorization: Bearer`, verify signature
  against Privy's JWKS (cached, refreshed on `kid` miss), yield
  `AuthedUser{PrivyDID string, Wallets []common.Address}` (verified linked wallets).
- No nonce endpoint, no session table, no SIWE library. Privy owns the challenge/response.
- Only metadata writes require auth. Authorization for
  `PUT /v1/tokens/{addr}/metadata`: `tokens.creator ∈ AuthedUser.Wallets`.

### 9.3 Endpoints

**Read (public):**

| Method | Path | Notes |
|---|---|---|
| GET | `/v1/tokens` | Explore list. `filter=recent_buys\|newest\|oldest\|market_cap\|volume`, `window=all\|24h\|7d`, `cursor`, `limit`. Reads `token_stats ⨝ tokens` where `phase='curve'`. |
| GET | `/v1/tokens/graduated` | Graduated list. `sort`, `cursor`, `limit`. |
| GET | `/v1/tokens/search` | `q` = name / ticker / address. |
| GET | `/v1/tokens/{addr}` | Detail: params, phase, `token_stats`, socials, contract/pool links. |
| GET | `/v1/tokens/{addr}/candles` | `interval=5m\|1h\|6h\|1d\|all`, `from`, `to`. Feeds Lightweight Charts. Reads `candles` (or aggregates on read for `6h`/`all`). |
| GET | `/v1/tokens/{addr}/trades` | Merged curve + DEX via `market_trades`, newest first, cursor. |
| GET | `/v1/tokens/{addr}/holders` | `balance` desc; each: address, balance, `%supply`, `first_acquired`. |
| POST | `/v1/tokens/{addr}/quote` | Body `{side, amountIn, slippageBps}` → `{amountOut, priceImpactBps, protocolFee, creatorFee, minReceived}`. Pure `curve/` math vs current reserves. Post-graduation → returns a "route via Uniswap" hint. |
| GET | `/v1/stats/protocol` | `window=24h\|all` → analytics tiles. |
| GET | `/v1/stats/protocol/daily` | `metric=volume\|launches\|trades`, `from`, `to` → chart bars. |
| GET | `/v1/health` | `last_block`, `lag_seconds`, phase counts, RPC ok. |

**Metadata (auth):**

| Method | Path | Notes |
|---|---|---|
| PUT | `/v1/tokens/{addr}/metadata` | `tokens.creator ∈ user.Wallets`. Body: `description, x_handle, telegram`, image ref. |
| POST | `/v1/uploads/image` | auth'd; returns URL. v1 storage: `bytea` in a small `images` table, served by `GET /v1/images/{id}`. Escape hatch: swap for object storage if it grows. |

### 9.4 SSE (best-effort)

- `GET /v1/tokens/{addr}/stream` — event types `trade`, `price`, `graduated`.
- `GET /v1/stream/launches` — new `TokenLaunched` for a live Explore feed.
- Backed by an in-process hub in `cmd/api`, fed by Postgres `LISTEN market_dirty` (the API
  process then reads the fresh row and pushes). Since `api` and `indexer` are separate
  processes, the bridge is Postgres NOTIFY, not an in-memory channel.
- **Reliability contract:** Postgres is the source of truth; SSE is a live hint. If a
  process dies after commit but before publish, the event is missed — this is **not** data
  loss. A reconnecting client MUST first re-fetch canonical state via REST, then apply SSE
  deltas as refresh hints / appends. `Last-Event-ID` and replay are future work.

## 10. Configuration

Env vars: `CHAIN_ID`, `RPC_URL`, `DATABASE_URL`, `PRIVY_APP_ID`, `PRIVY_JWKS_URL`,
`TREASURY_ADDR` (display only), `ETH_USD_SOURCE`, `LOG_LEVEL`, `API_ADDR`,
`INDEXER_CONFIRMATIONS` (override), `INDEXER_CHUNK_SIZE` (override).
Chain registry (factory address, start block, Uniswap addresses, WETH, explorer) is
compiled-in per chain id, secrets injected via env.

## 11. Testing strategy

| Layer | Approach |
|---|---|
| `curve/` | Foundry differential vectors (byte-identical) + fuzz vs Anvil `cast call` |
| `store/postgres` | Real Postgres via testcontainers (or CI service container). No SQL mocks. |
| feature services | Fake in-memory repos for logic-level tests |
| `indexer/` | Against Anvil: deploy contracts, drive events, assert canonical + derived rows; reorg simulation (snapshot/revert) |
| `apiserver/` | `httptest` contract tests; golden `openapi.json` diff in CI |
| CI | GitHub Actions, path-filtered: `contracts` (forge fmt/build/test), `backend` (golangci-lint, `go test -race`, Postgres service, `sqlc diff`, build all `cmd/`), `web` (lint/typecheck/build) |

## 12. Observability

- `GET /v1/health`: `last_block`, `lag_seconds` (wall clock − last block time), counts by
  phase, RPC reachability.
- Structured logs (slog) with `chain_id`, `block`, `tx_hash` fields.
- Metrics (Prometheus) deferred; health endpoint is enough for v1.

## 13. Open questions (do not block backend start)

1. **ETH/USD source** — on-chain Chainlink `ETH/USD` if deployed on Robinhood Chain; else a
   cached external API (Coingecko) refreshed every ~60s. Affects only USD display columns.
2. **Confirmations depth for Robinhood Chain** — L2 sequencer reorg behavior; default 5,
   verify against docs/observation.
3. **Image storage** — v1 `bytea` in Postgres; revisit if metadata volume grows.
4. **`market_trades`** — start as a SQL view; materialize or table-ize if read perf demands.
5. **Post-graduation fee capture** — out of scope for v1; would require a Uniswap V4 hook
   and couples graduation to V4.

## 14. Strongest design decisions (keep these invariant)

- `curve/` has zero dependencies and is verified against Solidity by differential tests.
  Solidity is authoritative; Go is a mirror.
- Canonical data (chain projection) is strictly separated from derived data (market
  aggregates); derived data is always rebuildable from canonical.
- `chain/` is pure infrastructure; domain state transitions live in feature modules.
- `api` and `indexer` are separate processes over one database — modular monolith, no
  microservices, no gRPC.
