# Backend Foundations — Task List

> **Workflow:** `AGENTS.md` governs pre-flight, implementation, verification, commit,
> and independent review. This is an implementation task list, not implementation code.

**Status:** Design closed. The contracts milestone (Plan 1) is complete and the curve vector
artifact exists at `contracts/vectors/v1/`. Tasks 1-5 are implemented and on `dev`. Task 6's
high-risk pre-flight is complete and its acceptance criteria are locked (see the task and
spec §5.1, "Canonical event-ledger schema"). Tasks 7-12 still require their high-risk
pre-flight before implementation.

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

**Delivers:** migrations for projections, durable dirty work, market aggregates, metadata,
and `market_trades`.

**Depends on:** Task 6

**Acceptance criteria:**

- `tokens`, `token_reserves`, `holder_balances`, and `aggregation_dirty` are clearly marked
  rebuildable projections; metadata/images are separate off-chain state.
- `tokens`/`token_reserves` retain the launch snapshot's `initial_virtual_eth` and
  `graduation_eth`. Curve progress is derived, not stored as chain state:
  `real_curve_eth = new_eth_reserve - initial_virtual_eth` and
  `progress = real_curve_eth / graduation_eth`. An integration test cross-checks the derived
  `real_curve_eth` against `IBondingCurveV1.realCurveEth()` at a sampled block.
- `market_trades` resolves a DEX swap's spot price from the `pool_syncs` row with the same
  `chain_id`, pair address, and `tx_hash` whose `log_index` is the greatest value strictly
  less than the swap's `log_index`. Tests cover multi-hop transactions with interleaved
  `Sync`/`Swap` pairs and `Sync` emitted by `Mint`/`Burn`.
- `market_trades` exposes execution and spot price separately, deterministic chain cursor
  fields, nullable DEX trader, gross ETH/WETH volume, token volume, source, and finality.
- Curve `gross_eth_volume` in `market_trades` is `trades.eth_gross`; `eth_refund` is stored
  but never included in volume, candles, or 24h aggregates.
- DEX token/WETH leg resolution works for both token orderings.
- `candles`, `token_stats`, `protocol_daily`, and `protocol_stats` use ETH fields as required
  and USD fields as nullable `NUMERIC(38,18)` columns; no float type is introduced for USD.
- Circulating supply, holder exclusions, and first-acquired reset behavior match the spec.
- A reorg that unwinds a graduation transaction is a named test: the rebuild from surviving
  canonical events flips `tokens.phase` back to the curve phase, deletes the pair projection
  rows above the common ancestor, restores the pre-graduation circulating-supply definition
  (canonical pair balance no longer counts; reserved `L` is curve inventory again), and
  rebuilds candles whose execution-price source reverted from DEX swaps to curve trades.
- Tests cover both pair orderings, Mint/Sync without Swap, equal timestamps, the forward
  graduation circulation transition, and excluded system addresses.

## Task 8 — sqlc queries and persistence adapters · Risk: high

**Delivers:** sqlc v2 configuration, generated package, and foundation query adapters.

**Depends on:** Task 7

**Acceptance criteria:**

- `sqlc generate` and `sqlc diff` are reproducible and leave no diff in CI.
- Generated `DBTX` accepts pgx pool and transaction implementations.
- Queries cover block insertion/link lookup, watermarks, idempotent event insertion,
  projection rebuild primitives, and dirty-work claim/complete.
- No generated type escapes `internal/store/postgres`.
- Byte/address and uint256 numeric conversion helpers reject wrong lengths, negative values,
  and values above 256 bits.

## Task 9 — Store transaction primitive · Risk: high

**Delivers:** store-internal `WithinTx` using sqlc bound to pgx transactions.

**Depends on:** Task 8

**Acceptance criteria:**

- Success commits; returned error rolls back; panic rolls back and re-panics.
- Context cancellation does not report success and leaves no partial event/checkpoint writes.
- A test commits block, event, projection, dirty marker, and watermark atomically.
- A failure at each stage proves all five categories roll back.
- pgx and generated query types appear in no public domain/application signature.
- The feature-level repository bundle is explicitly deferred to Plan 2, where consumer
  interfaces exist.

## Task 10 — Solidity curve-vector artifact consumption · Risk: high

**Delivers:** the backend consumes the existing contract vector artifact
(`contracts/vectors/v1/curve-v1.json` plus `curve.schema.json`, produced and
regeneration-gated by the completed contracts milestone) and proves its local copy stays
byte-identical to that source. The backend adds no second generator.

**Depends on:** Task 1. The contract vector artifact and its Foundry generator already exist.

**Acceptance criteria:**

- A task step copies `contracts/vectors/v1/` into `backend/internal/curve/testdata/`; CI
  fails if the copy is not byte-identical to the source artifact.
- The copied artifact is schema-validated on load against `curve.schema.json`.
- The consumed cases already cover normal/final buy, the one-wei buy boundary, final-buy
  refund with graduation, normal/max sell, invalid zero-input buy and sell, invalid
  oversell, sell one-wei zero-output, and fee-split dust.
- Two additional buy vectors — a mid-curve buy from a non-genesis `tokensSold` state and a
  buy that lands just below the graduation boundary without graduating — are added by a
  small contracts-side follow-up commit before Task 11.
- A buy-side zero-output revert vector is added only if it is first proven reachable under
  the locked V1 parameters. An unreachable defensive branch is not given a synthetic
  fixture presented as a production vector.
- No human-, Claude-, or Codex-authored expected amount is accepted as an authoritative
  contract fixture; Foundry regeneration stays the only source and is gated in contracts CI.

## Task 11 — Pure Go curve mirror · Risk: high

**Delivers:** state, checked arithmetic helpers, buy/sell/final-buy quotes, prices, supply,
and domain errors.

**Depends on:** Tasks 1 and 10

**Acceptance criteria:**

- Package uses `*big.Int`, does not alias caller values, and imports only stdlib.
- Operation order and rounding match the contract spec and every Foundry vector byte-for-byte.
- Sell validation uses `tokensIn <= tokensSold`; it never exposes virtual ETH.
- Final buy consumes the exact gross amount, reports refund, lands on `yFinal`, and does not
  silently cross `G`.
- The exact-gross helper implements the contract spec's closed formula and proves the
  resulting net amount equals the requested net amount over the supported fee range.
- Invalid public input returns a typed error rather than panicking.
- Property tests cover monotonic price, `x*y >= K`, bounded inventory, fee conservation,
  round-trip loss, and graduation at most once.

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
