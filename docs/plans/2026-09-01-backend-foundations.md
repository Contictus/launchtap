# Backend Foundations — Task List

> **Workflow:** `AGENTS.md` governs pre-flight, implementation, verification, commit,
> and independent review. This is an implementation task list, not implementation code.

**Status:** Design closed. The contracts milestone (Plan 1) is complete and the curve vector
artifact exists at `contracts/vectors/v1/` (now 13 cases). Tasks 1-11 are implemented and on
`dev`. Task 12 still requires its high-risk pre-flight before implementation.

**Goal:** Build the backend substrate without prematurely implementing indexer feature
routing or API endpoints: Go tooling, fail-closed deployment config, PostgreSQL control and
canonical schemas, sqlc access, a store transaction primitive, and a Solidity-authoritative
curve mirror.

**Specs:**

- `docs/specs/2026-09-01-contract-core-design.md`
- `docs/specs/2026-09-01-backend-core-design.md`

**Scope:** `backend/` scaffold, `internal/config`, `deployments`, `internal/store/postgres`,
and `internal/curve`. No API or indexer runtime is wired in this plan.

**Toolchain:** Go 1.26.x, Huma-compatible module baseline, pgx/v5, sqlc, goose/v3,
go-ethereum value types, testcontainers-go, golangci-lint v2. `shopspring/decimal` is not
added until an API DTO actually needs it.

## Global constraints

- Module path: `github.com/Contictus/launchtap/backend`.
- All exact on-chain amounts use `*big.Int` or database `NUMERIC(78,0)`. No float type is
  used for contract-equivalent values.
- `curve` imports only the standard library. Domain/application packages do not import
  pgx, sqlc output, or ethclient.
- Canonical event keys include `(chain_id, tx_hash, log_index)` and every event row stores
  block hash plus transaction index.
- Addresses in production deployments come only from reviewed embedded manifests. Unknown,
  incomplete, or cross-chain manifests fail closed.
- Local integration tests may skip without Docker. CI must fail if PostgreSQL is unavailable
  or no integration test executes.
- Solidity-generated vectors are the only expected-value authority for the Go curve mirror.
  The contract vector artifact already exists at `contracts/vectors/v1/` (schema-validated,
  regeneration-gated by the contracts milestone CI); Tasks 10-12 consume it and never
  regenerate it in the backend module.
- Deployment manifests are owned by `contracts/deployments/` (the shared
  `deployment.schema.json` plus `chain-dependencies` and `chain-disabled` records). Task 3
  consumes a byte-identical copy and validates against those schemas; the backend authors no
  manifest schema and no generator.

## Risk classes

- **low:** independent review optional.
- **high:** pre-flight and independent commit review required under `AGENTS.md`.

## Task 1 — Repository and Go module scaffold · Risk: low

**Delivers:** buildable Go 1.26 module, task runner, golangci-lint v2 config with depguard,
environment example, and path-filtered backend CI.

**Files:** `.gitattributes`, `backend/go.mod`, `backend/.golangci.yml`,
`backend/Taskfile.yml`, `backend/.env.example`, `.github/workflows/backend.yml`

**Acceptance criteria:**

- `go.mod` declares the exact module path and supported Go version.
- `go build ./...`, `go test ./... -race`, and `golangci-lint run` pass.
- Linter config uses v2 schema and a temporary probe proves depguard rejects pgx from a
  domain package and all external imports from `curve`; the probe is removed before commit.
- Task commands exist for build, unit test, integration test, lint, migration, sqlc, and
  verification.
- CI provides PostgreSQL for integration tests and fails if the integration suite skips.
- `*.go`, `*.sql`, and `*.md` use LF in Git.

## Task 2 — Pure environment configuration · Risk: low

**Delivers:** pure config parsing independent of direct `os` calls.

**Depends on:** Task 1

**Acceptance criteria:**

- `Load(getenv func(string) string) (Config, error)` is deterministic and unit tested.
- Missing/invalid `CHAIN_ID`, `DEPLOYMENT_ID`, `RPC_URL`, or `DATABASE_URL` fails.
- `LOG_LEVEL`, `API_ADDR`, and `INDEXER_CHUNK_SIZE` have explicit bounded defaults, and the
  parsed struct field names match the backend spec's environment list exactly.
- `INDEXER_CONFIRMATIONS` is rejected for a production manifest.
- Privy and USD settings may be absent for migration/indexer-only commands but API startup
  performs its own required-field validation.

## Task 3 — Reviewed deployment manifests · Risk: high

**Pre-flight:** complete. Acceptance criteria below are locked (spec §3). Two Codex
follow-ups must land and pass CI **before** implementation starts:

1. Align `config.DEPLOYMENT_ID` validation to the canonical manifest pattern
   `^[a-z0-9][a-z0-9._-]{2,63}$`, with updated tests (one regex, not two).
2. Add contracts-side `chain-dependencies.schema.json` and `chain-disabled.schema.json`, and
   validate `config/robinhood-mainnet.json` and `config/robinhood-testnet.disabled.json`
   against them in the contracts gate.

**Delivers:** consumption of the shared `contracts/deployments/` artifacts — a byte-identical
copy with a CI drift gate, load-time schema validation, static manifest validation, the
`(chain_id, deployment_id)` lookup with typed fail-closed errors, and the config×manifest
reconciliation that closes the Task 2 `INDEXER_CONFIRMATIONS` deferral. No backend-authored
schema, no second generator, no RPC.

**Depends on:** Task 2 and the two follow-ups above.

**Files:** `backend/deployments/` (runtime model, `embed.FS`, schema validation, static
validation, lookup, reconciliation), `backend/deployments/*_test.go`,
`backend/deployments/testdata/` (byte-identical copy of `contracts/deployments/`),
`.github/workflows/backend.yml` (drift-check step).

**Acceptance criteria:**

- `contracts/deployments/` is copied into `testdata/` and CI fails if the copy is not
  byte-identical to the source. The backend adds no second schema and no second generator.
- Every embedded manifest is schema-validated against `deployment.schema.json` on load;
  `schemaVersion == 1`, `engineVersion == 1`, `graduationEnabled == true`, and
  `lpBurnAddress == 0x…dEaD` are enforced and a violation is rejected.
- The lookup key is `(chain_id, deployment_id)`. An unknown key returns a typed
  `ErrDeploymentNotFound`; a `chain-disabled` marker returns a typed `ErrDeploymentDisabled`
  with the recorded `reason`; the two are distinguishable. No default, no Anvil fallback.
- A `chain-dependencies` record (Robinhood mainnet, `chain_id 4663`) is never selectable as
  a deployment. A production `(4663, …)` lookup fail-closes because no `LaunchFactory` /
  `BondingCurveV1` is deployed yet.
- Robinhood testnet (`chain_id 46630`) ships only its `chain-disabled` marker. A unit test
  proves a `46630` selection returns `ErrDeploymentDisabled` and cannot fall back to the
  mainnet dependency addresses or any other manifest.
- Anvil manifests load from `contracts/deployments/.generated/` output, are
  `environment == local`, and never become a default for any other `(chain_id,
  deployment_id)`.
- Static validation rejects: a zero `Factory` or `CurveImplementation`, `lpBurnAddress`
  other than `0x…dEaD`, an `engineVersion` outside `{1}`, a malformed or zero
  `pairInitCodeHash` or `bytecodeHashes` entry, a `deployment_id` that is not globally
  unique or repeats a `(chain_id, deployment_id)`, a `deployment_id` outside
  `^[a-z0-9][a-z0-9._-]{2,63}$`, and `startBlock == 0` for a non-`local` environment.
  Addresses are checked with `common.IsHexAddress` then compared byte-level. Deployment
  generation separately proves `StartBlock` equals the factory deployment receipt block.
- `uniswapV2Router02` is parsed and schema-validated but is not mapped into the runtime
  `Deployment` and is not surfaced by the backend API. `compiler`, `toolchain`,
  `governance`, and `verification` are schema-validated but not in the runtime model.
- `eth_getCode` bytecode verification and CREATE2 pair-address reproduction are explicitly
  deferred to indexer startup (Plan 2).
- API and indexer startup resolve the `(CHAIN_ID, DEPLOYMENT_ID)` manifest and reconcile:
  `INDEXER_CONFIRMATIONS` set is fatal unless `environment == local`; `CHAIN_ID` must equal
  the manifest `chainId`. `config.Load` / `config.LoadDatabase` do not resolve manifests.
  Unit tests cover local-set-ok, testnet-set-fatal, production-set-fatal, and
  chain-id-mismatch-fatal.

## Task 4 — Migration runner and PostgreSQL test support · Risk: high

**Pre-flight:** complete. Acceptance criteria below are locked (spec §2.5).

**Delivers:** embedded goose migrations (single source at
`internal/store/postgres/migrations/`), `cmd/migrate` with an explicit `up`/`down`/`status`
CLI, a reusable PostgreSQL test-database helper (`DATABASE_URL`-aware with a
testcontainers-go fallback), and a CI sentinel that proves the up/down/up integration test
itself executed and passed.

**Depends on:** Task 1.

**Files:** `backend/internal/store/postgres/migrations/` (embedded `.sql`, goose format),
`backend/cmd/migrate/` (CLI), `backend/internal/store/postgres/*.go` (migration runner and
test-database helper), `backend/internal/store/postgres/*_test.go`
(`TestMigrationsUpDownUp` and helper tests), `backend/go.mod`/`go.sum`
(`testcontainers-go` and its postgres module), `.github/workflows/backend.yml` (sentinel
step).

**Acceptance criteria:**

- Migrations live at `internal/store/postgres/migrations/*.sql`, embedded via
  `//go:embed migrations`; one source shared unmodified by `cmd/migrate` and the test
  helper.
- `cmd/migrate` uses `config.LoadDatabase`. It has no implicit default command; the
  operator names one of `up`, `down`, `status` explicitly (`task migrate -- up`).
- The shared migration runner is callable only from `cmd/migrate` and the PostgreSQL
  integration test helper. `cmd/api` and `cmd/indexer` never run migrations at startup and
  never import the runner for that purpose.
- The test helper never migrates or otherwise touches the database named in
  `DATABASE_URL`. When `DATABASE_URL` is set, it uses only the server coordinates, opens an
  administrative connection to the `postgres` maintenance database, and issues `CREATE
  DATABASE`/`DROP DATABASE` for a uniquely named throwaway database per test (`t.Cleanup()`
  owns the drop). An unreachable `DATABASE_URL` or a role lacking `CREATE`/`DROP DATABASE`
  privilege **fails** the test — it does not skip.
- When `DATABASE_URL` is unset, the helper starts a pinned `postgres:18.6-alpine` via
  `testcontainers-go` with a bounded startup timeout. Docker unavailable → local skip with
  an explicit reason; under `INTEGRATION_REQUIRED=true` that same condition is fatal, not a
  skip.
- Every test gets its own uniquely named database; no two tests — including
  `t.Parallel()` and `go test -race` package-level parallelism — ever share one.
- Migrations run from `embed.FS`, and `TestMigrationsUpDownUp` proves up/down/up
  round-trips cleanly against a real, helper-provisioned database.
- CI runs a dedicated step asserting `TestMigrationsUpDownUp` itself executed and passed —
  not merely that the overall test command exited zero:
  `go test -tags=integration -race -v -run '^TestMigrationsUpDownUp$'
  ./internal/store/postgres/...`, grepping the `-v` output for a literal
  `--- PASS: TestMigrationsUpDownUp` line. A missing test, a `--- SKIP:`, or a `--- FAIL:`
  line fails the step regardless of the command's own exit code.
- No production process runs migrations implicitly.

## Task 5 — Chain control and block-ledger schema · Risk: high

**Pre-flight:** complete. Acceptance criteria below are locked (spec §5.1).

**Delivers:** migration for `sync_state` and `indexed_blocks`, including the
immutable-identity trigger on `indexed_blocks`.

**Depends on:** Task 4.

**Files:** `backend/internal/store/postgres/migrations/` (new up/down `.sql`),
`backend/internal/store/postgres/postgrestest/*_test.go` (or equivalent) proving the
constraints, the trigger, and the common-ancestor query.

**Acceptance criteria:**

- `sync_state` is keyed by `(chain_id, deployment_id)`; `deployment_id` carries
  `CHECK (deployment_id ~ '^[a-z0-9][a-z0-9._-]{2,63}$')`. Each of the three watermark
  levels (`observed`, `safe`, `finalized`) is a `(number BIGINT, hash BYTEA, at
  TIMESTAMPTZ)` triple, NULL together or filled together.
- `CHECK (safe_number IS NULL OR (observed_number IS NOT NULL AND safe_number <=
  observed_number))` and `CHECK (finalized_number IS NULL OR (safe_number IS NOT NULL AND
  finalized_number <= safe_number))`. `safe`/`finalized` are the indexer's own
  hash-verified local watermarks, never the node's raw reported tag.
- `indexed_blocks` is keyed by `(chain_id, block_number)`; `block_hash` unique per
  `chain_id`; `parent_hash` is `NOT NULL` (always the real on-chain value, including at
  `StartBlock`); `finality_status` is `TEXT NOT NULL CHECK (... IN ('observed', 'safe',
  'finalized'))`, not a native `ENUM`.
- All hash columns are `BYTEA` with `CHECK (octet_length(...) = 32)`; future address
  columns (Task 6+) are `BYTEA` with `CHECK (octet_length(...) = 20)`. `chain_id`/
  `block_number` are `BIGINT` with nonnegative `CHECK`s — not `NUMERIC(78,0)`, which stays
  reserved for on-chain token/monetary amounts. No foreign key to a chains table; none
  exists (`deployments` is an embedded Go artifact, spec §3).
- `indexed_blocks` carries a `BEFORE UPDATE` trigger rejecting any change to `block_hash`,
  `parent_hash`, or `block_time`; `finality_status` remains updatable in place. Integration
  tests prove: a plain duplicate-key `INSERT` fails; an `ON CONFLICT ... DO UPDATE`
  changing `block_hash` is rejected by the trigger; an `UPDATE` changing only
  `finality_status` succeeds.
- Integration tests prove a common-ancestor query (inline raw SQL — `sqlc` doesn't exist
  until Task 8) can walk `parent_hash` back to find where two diverging chains meet.

## Task 6 — Canonical event-ledger schema · Risk: high

**Pre-flight:** complete. Acceptance criteria below are locked (spec §5.1, "Canonical
event-ledger schema").

**Delivers:** 18 exact event tables — 13 for V1 contract and Uniswap pair events, plus 5
control-plane/governance tables (captured for auditability per spec §4.4, out of Task 7's
market aggregation) — the block-ledger linkage FK (added to `indexed_blocks` by this
task's migration), the `token_launches` linkage FK, and the two order-independent
graduation-ordering constraint triggers.

**Depends on:** Task 5.

**Files:** `backend/internal/store/postgres/migrations/` (new up/down `.sql`),
`backend/internal/store/postgres/postgrestest/*_test.go` (or equivalent) proving the
constraints, FKs, and triggers.

**Acceptance criteria:**

- Tables exist for `token_launches`, `trades`, `graduations`, `creator_fee_claims`,
  `protocol_fee_claims`, `launch_fee_claims`, `refund_credits`, `refund_claims`,
  `transfers`, `pool_mints`, `pool_burns`, `pool_swaps`, `pool_syncs`,
  `launch_pause_events`, `trading_pause_events`, `engine_configurations`,
  `future_defaults_configurations`, and `future_treasury_configurations`. Payload columns
  map one-to-one to the contract spec per the locked table in spec §5.1; `engine_version`,
  `name`, `symbol`, `lp_pair`, `lp_liquidity_burned`, and the `Trade` `eth_gross`/
  `eth_refund` pair are not omitted; `launch_fee_claims` correctly has no `token_address`
  (the event is per-treasury, not per-launch).
- Every event table stores `chain_id`, `block_number`, `block_hash`, `block_time`,
  `transaction_index`, `tx_hash`, and `log_index`, each with its own explicit `CHECK`
  (`chain_id > 0`, `block_number >= 0`, `transaction_index >= 0`, `log_index >= 0`), with
  primary key `(chain_id, tx_hash, log_index)` — no surrogate `id` column, uniqueness
  enforced independently per table.
- `NUMERIC(78,0)` plus nonnegative `CHECK`s cover every `uint256` value (including `Sync`'s
  `uint112` reserves, for consistency) without signed overflow. `uint16` fields use
  `INTEGER CHECK (... BETWEEN 0 AND 65535)`, not `SMALLINT` (which cannot hold the full
  `uint16` range).
- This task's migration adds `UNIQUE (chain_id, block_number, block_hash, block_time)` to
  `indexed_blocks`. Every event table carries a `DEFERRABLE INITIALLY DEFERRED` foreign key
  on that exact tuple to `indexed_blocks`, with no `ON DELETE` action — an event can never
  claim a block coordinate the block ledger doesn't recognize, and reorg rollback's
  event-before-block deletion order (spec §4.2) is DB-enforced.
- `token_launches` carries `UNIQUE (chain_id, token_address)`. `trades`, `graduations`,
  `creator_fee_claims`, `protocol_fee_claims`, `refund_credits`, `refund_claims`, and
  `transfers` each carry a `DEFERRABLE INITIALLY DEFERRED` foreign key on
  `(chain_id, token_address)` to `token_launches` — this is what lets the constructor's
  initial `Transfer` legally precede `TokenLaunched` within one transaction.
  `launch_fee_claims`, the five control-plane tables, and `pool_mints`/`pool_burns`/
  `pool_swaps`/`pool_syncs` carry **no** such FK (factory-level events, and pair events
  that can be indexed before any launch claims that pair — spec §6).
- A curve `Trade` log whose block number is strictly greater than the same token's
  `Graduated` block is rejected as a fatal invariant violation and not stored, enforced by
  **two** order-independent `DEFERRABLE INITIALLY DEFERRED` `CONSTRAINT TRIGGER`s — one on
  `trades` rejecting a trade after an existing graduation, one on `graduations` rejecting a
  graduation before an existing later trade — so the check does not depend on which row is
  inserted first within a transaction. A `Trade` sharing the exact same block as its
  `Graduated` row (the graduating trade itself) is always accepted. Tests cover both
  insertion orders, a trade after an already-committed graduation (rejected), and same-block
  trade+graduation (accepted).
- `pool_syncs` rows carry the coordinates needed to resolve a `pool_swaps` row's reserve
  state by the Task 7 rule (same `chain_id`, pair address, and `tx_hash`; greatest
  `log_index` strictly less than the swap's `log_index`); `pool_syncs` and `pool_swaps`
  are indexed on `(chain_id, pair_address, tx_hash, log_index)` for that lookup.
- Duplicate-event, unknown-engine, negative-value, and rollback tests pass.

## Task 7 — Chain projections, aggregates, and market view · Risk: high

**Pre-flight:** complete. Acceptance criteria below are locked (spec §5.2, §5.3, §5.5).

**Delivers:** migrations for `tokens`, `token_reserves`, `holder_balances`,
`aggregation_dirty`, `token_metadata` (chain projections + off-chain metadata, spec §5.2),
the `market_trades` SQL view (spec §5.3), and `candles`/`token_stats`/`protocol_daily`/
`protocol_stats` (spec §5.5). Rebuild SQL primitives that recompute a token's projections
from its surviving canonical events, proven by a raw-SQL-driven integration test — not a
live indexer or reorg orchestrator (Plan 2 scope; spec §5.2 "Scope boundary").

**Depends on:** Task 6.

**Files:** `backend/internal/store/postgres/migrations/` (new up/down `.sql`),
`backend/internal/store/postgres/postgrestest/*_test.go` (or equivalent) proving the
schema, the rebuild primitives, and the market view.

**Acceptance criteria:**

- `tokens`, `token_reserves`, `holder_balances`, `aggregation_dirty`, and `token_metadata`
  match spec §5.2 exactly — see the locked column lists there, including: `tokens`'
  immutable launch snapshot, `phase`, nullable-together graduation coordinates (with FKs to
  `indexed_blocks` and `graduations`), and generated `token_is_token0`; `token_reserves`'
  `reserve_source` discriminated union instead of parallel nullable curve/pair columns,
  with no duplicated `initial_virtual_eth`/`graduation_eth`; `holder_balances`'
  `first_acquired_block_number` NULL-exactly-when-`balance = 0` invariant;
  `aggregation_dirty`'s `aggregation_dirty_generation_seq`-backed `generation`/
  `claimed_generation`/`claimed_at`/`claimed_by` shape (the claim/complete queries
  themselves are Task 8's); `token_metadata`'s FK to `token_launches`, not `tokens`, so it
  survives a realistic reorg untouched.
- `candles`, `token_stats`, `protocol_daily`, and `protocol_stats` match spec §5.5 exactly
  — every column, type, and unit locked there (ETH `NUMERIC(78,0)` WAD vs. nullable USD
  `NUMERIC(38,18)`; `candles`' four-interval `CHECK` with `6h`/`all` aggregated on read
  only; `token_stats`' unconstrained signed `price_change_24h_bps`; `protocol_daily`'s
  `DATE` key; `protocol_stats`' `BIGINT trades_all_time`). No float type anywhere.
- Curve graduation progress (`realCurveEth = virtualEthReserve - initialVirtualEth`,
  `progress = realCurveEth / graduationEth`) is proven at the SQL-formula level against
  fixture reserve values, not a live `IBondingCurveV1.realCurveEth()` RPC call (spec §5.2
  — that cross-check moves to Plan 2, which has RPC access).
- `market_trades` is a plain, non-materialized `CREATE VIEW` (spec §5.3) exposing
  `chain_id, token_address, block_number, block_time, transaction_index, tx_hash,
  log_index, source, side_buy, trader, execution_price_wad, spot_price_wad,
  gross_eth_volume, token_volume, finality`. DEX `spot_price_wad` resolves from the
  `pool_syncs` row with the same `chain_id`/pair address/`tx_hash` and the greatest
  `log_index` strictly less than the swap's. DEX token/WETH leg resolution uses
  `tokens.token_is_token0` for both orderings — never RPC, never a second stored column.
  Curve `gross_eth_volume` is exactly `trades.eth_gross`; `eth_refund` is stored but never
  included in volume, candles, or 24h aggregates. `sender`/`to` on DEX rows are routing
  participants, not proven identities; `trader` is nullable.
- Tests cover multi-hop transactions with interleaved `Sync`/`Swap` pairs, `Sync` emitted
  by `Mint`/`Burn` without an adjoining `Swap`, and equal-timestamp blocks.
- Rebuild SQL primitives recompute an affected token's `tokens`/`token_reserves`/
  `holder_balances`/`candles` rows as a full recompute from that token's complete
  surviving canonical events — never an incremental undo (spec §5.2 "Scope boundary").
  A named integration test drives this with raw SQL, standing in for the indexer's own
  ancestor walk (no live indexer exists yet): insert canonical events including a
  `Graduated` row, delete the losing branch's rows above a chosen ancestor, invoke the
  rebuild primitives, and assert `tokens.phase` flips back to `curve`, pair-sourced
  `token_reserves`/DEX-sourced `candles` rows above the ancestor are gone, circulating
  supply reflects the pre-graduation definition again (§5.4 — reserved `L` is curve
  inventory again, canonical pair balance no longer counts), and candles rebuilt from
  surviving curve `trades` replace the DEX-sourced ones. `token_metadata` is untouched.
  The test also covers the forward direction: the graduation circulation transition
  (`T_r` circulating pre-graduation → `S` after, absent burns/forced transfers).
- `holder_balances`/holder-list/`holder_count` queries exclude zero, dead, curve, and
  canonical pair addresses; the canonical pair balance still counts toward circulating
  supply (§5.4). Excluded-address tests pass.
- Duplicate-token-launch, negative-value, and unknown-address rejection tests pass for
  every new table, matching the Task 6 pattern (`CHECK`/`FOREIGN KEY` violations asserted
  by exact constraint name).

## Task 8 — sqlc queries and persistence adapters · Risk: high

**Pre-flight:** complete. Acceptance criteria below are locked (spec §2.6).

**Delivers:** `sqlc.yaml` (config schema v2, pinned CLI `v1.31.1`), the generated
`internal/store/postgres/sqlc` package with per-column `Address`/`Hash`/`Uint256` type
overrides, and a representative set of hand-wrapped query adapters (spec §2.6).

**Depends on:** Task 7.

**Files:** `backend/sqlc.yaml` (or `backend/internal/store/postgres/sqlc.yaml`),
`backend/internal/store/postgres/sqlc/` (generated `Queries` + hand-written
`Address`/`Hash`/`Uint256` types and their `.sql` sources), `backend/internal/store/postgres/*.go`
(insert-with-conflict-comparison wrapper, claim/complete adapter), `backend/.golangci.yml`
(depguard extension), `backend/Taskfile.yml` and `.github/workflows/backend.yml` (`sqlc
diff` step), `backend/internal/store/postgres/postgrestest/*_test.go` (or equivalent).

**Acceptance criteria:**

- `sqlc generate` and `sqlc diff` are reproducible and leave no diff in CI (spec §2.6
  "CI"); `sqlc diff` runs as a dedicated `Taskfile.yml` target and CI step alongside the
  existing drift checks (§3, §2.5).
- Generated code lives in `internal/store/postgres/sqlc`, never `sqlcgen` or any other
  name. `depguard` is extended so every package other than `internal/store/postgres/**`
  is forbidden from importing it — proven by a temporary probe removed before commit
  (Task 1's own pattern). "No generated type escapes `internal/store/postgres`" is this
  depguard rule, not a documentation claim.
- Every `BYTEA CHECK (octet_length(...) = 20)` column has a per-column `sqlc.yaml`
  override to `Address [20]byte`; every `= 32` column overrides to `Hash [32]byte`; every
  `NUMERIC(78,0)` column overrides to `Uint256`, which rejects a negative value, a
  fractional value, and any value with `BitLen() > 256` on scan. `NUMERIC(38,18)` USD
  columns (§5.4) are explicitly excluded from the `Uint256` override.
- Representative query scope only (spec §2.6): idempotent insert queries for `trades`,
  `launch_pause_events`, and `indexed_blocks` (plus `GetIndexedBlockByNumber`/
  `GetIndexedBlockByHash` link lookups), `sync_state` watermark upsert, a wrapper for
  `rebuild_token_projections`, and the dirty-work claim/complete queries. The other 15
  event tables' insert queries are explicitly deferred to Plan 2, added on demand by
  copying this proven pattern.
- Every event insert query is `INSERT ... ON CONFLICT (chain_id, tx_hash, log_index) DO
  NOTHING` — never `DO UPDATE`. The Go adapter wrapping it re-reads the existing row on
  conflict and compares every payload column: identical payload is an idempotent success;
  a different payload is a typed conflict/invariant error, never silently swallowed or
  silently overwritten. A test proves both paths for at least one representative table.
- The dirty-work claim query is the atomic CTE from spec §2.6 (`FOR UPDATE SKIP LOCKED`,
  ordered by `generation, chain_id, token_address`), selecting rows where
  `claimed_generation IS NULL OR claimed_generation < generation`. The completion query
  compares **all of** `generation = $claimed_generation`, `claimed_generation =
  $claimed_generation`, and `claimed_by = $worker_id` before deleting — not the bare
  `claimed_generation = generation` shape. A test proves the exact race from spec §2.6
  (worker A claims generation 1, the row is re-dirtied to generation 2, worker B claims
  generation 2, A's stale completion call is a no-op and does not delete B's live claim).
- The common-ancestor recursive walk is **not** given a permanent named query in this
  task; only the two link-lookup queries above are delivered. Task 5's inline raw-SQL test
  query is unaffected.
- No generated or hand-wrapped query opens, commits, or rolls back a transaction — every
  one runs against sqlc's `DBTX`, unmodified, whether given a pool connection or an
  already-open `pgx.Tx`. `WithinTx` composition stays Task 9's job.

## Task 9 — Store transaction primitive · Risk: high

**Delivers:** store-internal `WithinTx(ctx, pool, fn func(ctx, *Adapter) error) error`,
backed by a `pgx.Tx` opened with explicit `pgx.ReadCommitted` isolation, whose callback
receives an `*Adapter` (Task 8) over that same transaction — never a raw `pgx.Tx` or
generated `sqlc.Queries`.

**Depends on:** Task 8

**Files:** `backend/internal/store/postgres/tx.go` (new),
`backend/internal/store/postgres/postgrestest/withintx_integration_test.go` (new).

**Acceptance criteria:**

- Success commits; a returned error rolls back; a panic rolls back and re-panics with the
  original recovered value unchanged, even if the rollback call itself also errors.
- After `fn` returns `nil`, `ctx.Err()` is re-checked before COMMIT is issued — cancellation
  is never reported as success. Rollback runs on a cleanup context independent of the
  caller's (possibly already-canceled) context, bounded by its own timeout.
- On the error path, a rollback failure is attached as additional context but never
  displaces the original error — the original error remains reachable via
  `errors.Is`/`errors.As`.
- A single atomicity test commits block, event, projection (via
  `rebuild_token_projections`), aggregation-dirty marker, and watermark together, then
  proves rollback by injecting a genuine constraint-violation failure at five points: the
  block insert, the event insert, the `rebuild_token_projections` call, the watermark
  upsert, and COMMIT itself (a deferred constraint violation that only fires at commit,
  after every callback statement already succeeded — proving a `nil`-returning callback is
  not sufficient for reported success). Each induced failure asserts all five row
  categories are unchanged from their pre-attempt state (fixture rows may legitimately
  exist beforehand); `ON CONFLICT DO NOTHING` duplicate inserts do not error and are not a
  valid injection mechanism.
- No nested-transaction/savepoint support: calling `WithinTx` again inside a callback opens
  an independent transaction against the pool, explicitly outside the outer transaction's
  atomicity guarantee.
- pgx and generated query types appear in no public domain/application signature.
- The feature-level repository bundle is explicitly deferred to Plan 2, where consumer
  interfaces exist.

## Task 10 — Solidity curve-vector artifact consumption · Risk: high

**Delivers:** the backend consumes the existing contract vector artifact
(`contracts/vectors/v1/curve-v1.json` plus `curve.schema.json`, produced and
regeneration-gated by the completed contracts milestone) and proves its local copy stays
byte-identical to that source. The backend adds no second generator.

**Depends on:** Task 1. The contract vector artifact and its Foundry generator already exist.

**Files:** `backend/internal/curve/testdata/curve-v1.json` (copy, new),
`backend/internal/curve/testdata/curve.schema.json` (copy, new), a stdlib-only vector loader
and validator under `internal/curve` (new), `.github/workflows/backend.yml` (path filters).

**Acceptance criteria:**

- A task step copies `contracts/vectors/v1/` into `backend/internal/curve/testdata/`; CI
  fails if the copy is not byte-identical to the source artifact. `backend.yml`'s `push` and
  `pull_request` path filters include `contracts/vectors/**`, alongside the existing
  `contracts/deployments/**` entry, so a contracts-only vector commit still triggers the
  check.
- The copied artifact is schema-validated on load against the locked `curve.schema.json`,
  entirely with stdlib (`encoding/json` with `DisallowUnknownFields` plus a manual
  validator) — no JSON-schema engine dependency and no depguard exception for
  `internal/curve`, matching this task's own "imports only stdlib" requirement (below) and
  spec §7.1. The manual validator covers required-field presence (tracked independently of
  Go zero values), the schema's `const` fields, `cases` length `>= 11` (never `== 11`), the
  amount and case-id regex patterns, the `operation`/`phase` enums, the bps bounds, the
  revert `data` hex pattern, and the nullable `output`/`expectedRevert` fields. Amount
  fields stay raw strings at this layer; `*big.Int` conversion is Task 11's concern.
- Negative-path tests cover at minimum: an unknown field, a missing required field, a
  malformed amount/id/enum/hex value, an out-of-range bps value, and a `cases` array with
  fewer than 11 entries.
- The consumed cases already cover normal/final buy, the one-wei buy boundary, final-buy
  refund with graduation, normal/max sell, invalid zero-input buy and sell, invalid
  oversell, sell one-wei zero-output, and fee-split dust.
- Two additional buy vectors — a mid-curve buy from a non-genesis `tokensSold` state and a
  buy that lands just below the graduation boundary without graduating — are added by a
  small contracts-side follow-up commit before Task 11, not as part of this task.
- A buy-side zero-output revert vector is added only if it is first proven reachable under
  the locked V1 parameters. An unreachable defensive branch is not given a synthetic
  fixture presented as a production vector.
- `expectedRevert.data` is validated only structurally (the hex pattern); decoding it
  against a real Solidity custom-error ABI signature is out of scope for this task.
- No human-, Claude-, or Codex-authored expected amount is accepted as an authoritative
  contract fixture; Foundry regeneration stays the only source and is gated in contracts CI.

## Task 11 — Pure Go curve mirror · Risk: high

**Delivers:** state, checked arithmetic helpers, buy/sell/final-buy quotes, prices, supply,
and domain errors, transcribed directly from `contracts/src/libraries/CurveMath.sol` and
`contracts/src/interfaces/ILaunchErrors.sol` (spec §7.2 is the authoritative order of
operations, resolved against the real Solidity source, not the prose in spec §4).

**Depends on:** Tasks 1 and 10

**Prerequisite (before implementation starts):** a small contracts-side Foundry commit adds
the two additional buy vectors (a mid-curve buy from a non-genesis `tokensSold` state, and a
buy landing just below the graduation boundary without graduating) and resyncs the backend
copy (`task curve-vectors-sync`) in the same commit, reviewed independently before this
task's real implementation begins.

**Acceptance criteria:**

- Task 10's JSON-fidelity vector types are renamed to `VectorParameters`, `VectorState`,
  `VectorInput`, `VectorOutput`, `VectorCase`, `VectorRevert` (`VectorArtifact` unchanged),
  freeing `Parameters` and `State` for this task's runtime types.
- `Parameters` and `State` hold unexported `*big.Int` fields; every constructor copies every
  `*big.Int` input via `new(big.Int).Set`, and every accessor/quote/next-state result returns
  a freshly-allocated value — never an internal pointer. `Buy`/`Sell` are pure functions that
  do not mutate their receiver. The package imports only stdlib.
- `Buy`'s control flow matches spec §7.2 exactly: fees are split from the full supplied
  amount first; the closed-form branch triggers on `candidateVirtualEth > finalVirtualEth`
  (ETH-space, strict) — not a token-space comparison — and re-splits fees from
  `ethGrossUsed`, discarding the first split; the boundary-equal case
  (`candidateVirtualEth == finalVirtualEth`) takes the ordinary branch, with
  `graduates := (newVirtualToken == finalVirtualToken)`, exactly reproducing the existing
  `buy_final_exact` vector.
- `Sell` validation uses `tokensIn <= tokensSold`; it never exposes virtual ETH.
- Both `Buy` and `Sell` check `State.Phase == Curve` before any other step, returning
  `ErrWrongPhase{Expected, Actual}` immediately on a `Graduated` state (mirroring
  `_requireCurvePhase`) — not a no-argument "already graduated" sentinel.
- `ErrZeroInput`, `ErrOversell{Attempted, Sold}`, `ErrZeroOutput`, and `ErrWrongPhase` are
  matched via `errors.Is`/`errors.As` in the vector-consumption test, keyed off each vector
  case's `expectedRevert.name` — a semantic match, not a byte-for-byte match against
  `expectedRevert.data`'s ABI encoding (still out of scope).
- `NewParameters` validates every `CurveMath.validateParameters` condition (supply
  allocation, curve/LP allocation, graduation ETH, virtual reserves, fee bounds, and the
  `ceilDiv` round-trip boundary check) and fails closed with a typed error — never a panic.
  `K`, `yFinal`, and `xFinal` are always derived inside the constructor, never accepted as
  caller-supplied fields.
- The exact-gross helper (`exactGrossForNet`) is tested over the full supported fee range
  `feeBps ∈ [0, 9999]`, proving `gross - floor(gross*feeBps/10_000) == net` for every tested
  pair.
- `SpotPriceWad`, `TokensSold`, and `RealCurveETH` implement the exact formulas in spec §7.2
  (full-precision `mulDiv` for price, no separate overflowing intermediate step). Circulating
  supply is not part of this package.
- A computed `netNeeded <= 0` inside the closed-form path returns a typed internal-invariant
  error rather than computing a nonsensical result.
- Property tests cover monotonic price, `x*y >= K`, bounded inventory, fee conservation,
  round-trip loss, and graduation at most once — written with stdlib only (`math/rand` with a
  deterministic seed, or `testing/quick`), since the existing strict `internal/curve`
  depguard rule covers every file under the package regardless of test-package clause.

## Task 12 — Foundation verification gate · Risk: high

**Delivers:** one reproducible verification command and a clean foundation handoff.

**Depends on:** Tasks 1-11

**Acceptance criteria:**

- Runs formatting, build, unit/race tests, required PostgreSQL integration tests, lint,
  migrations up/down/up, sqlc generation/diff, and the curve-vector byte-identical check
  against `contracts/vectors/v1/` (regeneration itself stays in the contracts gate).
- Runs on Windows developer setup with a workspace-local `GOCACHE` when the global cache is
  inaccessible, without weakening CI.
- Reviews `git diff` for generated noise, placeholder addresses, skipped integration gates,
  float use, stale module path, and unreviewed dependency additions.
- Records exact tool versions and commands in `AGENTS.md` only after they work.

## Plan boundary

Plan 2 owns RPC clients, safe/finalized polling, advisory-lock lifecycle, staged log
discovery, event decoding/routing, feature repository ports, reorg replay, and aggregators.
Plan 3 owns Huma endpoints, Privy access+identity verification, informational quote DTOs,
OpenAPI generation, and SSE. This plan supplies their tested storage and math substrate but
does not invent their interfaces early.
