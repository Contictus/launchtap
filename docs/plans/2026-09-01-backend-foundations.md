# Backend Foundations — Task List

> **Workflow:** `AGENTS.md` governs pre-flight, implementation, verification, commit,
> and independent review. This is an implementation task list, not implementation code.

**Status:** Design closed; do not start until the user authorizes implementation and the
high-risk pre-flight finds no blocker.

**Goal:** Build the backend substrate without prematurely implementing indexer feature
routing or API endpoints: Go tooling, fail-closed deployment config, PostgreSQL control and
canonical schemas, sqlc access, a store transaction primitive, and a Solidity-authoritative
curve mirror.

**Specs:**

- `docs/specs/2026-09-01-contract-core-design.md`
- `docs/specs/2026-09-01-backend-core-design.md`

**Scope:** `backend/` scaffold, `internal/config`, `internal/store/postgres`, and
`internal/curve`. No API or indexer runtime is wired in this plan.

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
  Tasks 10-12 cannot complete before the contract vector artifact exists.

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
- `LOG_LEVEL`, API address, and bounded chunk-size defaults are explicit.
- `INDEXER_CONFIRMATIONS` is rejected for a production manifest.
- Privy and USD settings may be absent for migration/indexer-only commands but API startup
  performs its own required-field validation.

## Task 3 — Reviewed deployment manifests · Risk: high

**Delivers:** embedded manifest schema, lookup, validation, and initial reviewed records.

**Depends on:** Task 2

**Acceptance criteria:**

- Lookup key is `(chain_id, deployment_id)`, not chain id alone.
- Robinhood mainnet dependency addresses match the backend spec exactly.
- Testnet does not reuse mainnet addresses and is explicitly marked graduation-disabled
  until its own deployment manifest is available.
- Anvil manifests can be loaded from generated contract deployment output without becoming
  production defaults.
- Validation rejects zero required addresses, wrong burn address, duplicate deployment id,
  unknown engine version, and chain mismatch. Deployment generation separately proves
  `StartBlock` equals the factory deployment receipt block.
- Unit tests prove a testnet configuration cannot silently select mainnet DEX contracts.

## Task 4 — Migration runner and PostgreSQL test support · Risk: high

**Delivers:** embedded goose migrations, `cmd/migrate`, testcontainers helper, and an
integration-test execution sentinel.

**Depends on:** Task 1

**Acceptance criteria:**

- Migrations run from `embed.FS` and support up/down/up verification in tests.
- Test helper creates a throwaway database and returns cleanup owned by the test.
- Local absence of Docker reports a clear skip reason.
- CI sets an explicit integration-required flag; under it, Docker/PostgreSQL failure or zero
  executed integration tests fails the job.
- No production process runs migrations implicitly unless a later plan adds an explicit
  operator flag.

## Task 5 — Chain control and block-ledger schema · Risk: high

**Delivers:** migration for `sync_state` and `indexed_blocks`.

**Depends on:** Task 4

**Acceptance criteria:**

- `sync_state` is keyed by `(chain_id, deployment_id)` and stores observed, safe, and
  finalized numbers/hashes plus timestamps.
- `indexed_blocks` is keyed by `(chain_id, block_number)` and stores block hash, parent hash,
  block time, and constrained finality status.
- Constraints forbid safe/finalized watermarks ahead of observed and finalized ahead of safe.
- Duplicate block number with a different hash cannot be silently upserted.
- Integration tests prove block-chain linkage queries can locate a common ancestor.

## Task 6 — Canonical event-ledger schema · Risk: high

**Delivers:** exact event tables for V1 contract and Uniswap events.

**Depends on:** Task 5

**Acceptance criteria:**

- Tables exist for token launches, trades, graduations, creator/protocol/launch fee claims,
  refund credits/claims, transfers, and pair Mint/Burn/Swap/Sync.
- Payload columns map one-to-one to the contract spec; `engine_version`, name, symbol, pair,
  and LP liquidity burned are not omitted.
- Every event table stores chain id, block number/hash/time, transaction index/hash, and log
  index, with unique `(chain_id, tx_hash, log_index)`.
- `NUMERIC(78,0)` plus nonnegative checks cover uint256 values without signed overflow.
- Foreign keys are deferrable/replay-safe: the token constructor's initial `Transfer` may
  precede `TokenLaunched` in the same transaction, while optional developer-buy events follow
  it. Rollback deletes dependent events before the launch.
- Duplicate-event, unknown-engine, negative-value, and rollback tests pass.

## Task 7 — Chain projections, aggregates, and market view · Risk: high

**Delivers:** migrations for projections, durable dirty work, market aggregates, metadata,
and `market_trades`.

**Depends on:** Task 6

**Acceptance criteria:**

- `tokens`, `token_reserves`, `holder_balances`, and `aggregation_dirty` are clearly marked
  rebuildable projections; metadata/images are separate off-chain state.
- `pool_syncs` supports exact post-state reserve lookup using the pair `Sync` emitted
  immediately before its `Swap` in the same transaction sequence.
- `market_trades` exposes execution and spot price separately, deterministic chain cursor
  fields, nullable DEX trader, gross ETH/WETH volume, token volume, source, and finality.
- DEX token/WETH leg resolution works for both token orderings.
- `candles`, `token_stats`, `protocol_daily`, and `protocol_stats` use ETH fields as required
  and USD fields as nullable.
- Circulating supply, holder exclusions, and first-acquired reset behavior match the spec.
- Tests cover both pair orderings, Mint/Sync without Swap, equal timestamps, graduation
  circulation transition, and excluded system addresses.

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

## Task 10 — Solidity curve-vector artifact gate · Risk: high

**Delivers:** versioned vector schema and checked-in V1 vectors produced by Foundry.

**Depends on:** reviewed contract implementation and its vector generator; Task 1

**Acceptance criteria:**

- The artifact records engine version, parameter snapshot, initial state, operation input,
  exact output, next state, fees, refund, graduation flag, and expected revert where relevant.
- Cases include normal/final buy, one-wei boundaries, refund, normal/max sell, invalid
  oversell, fee split dust, and zero-output reverts.
- The generator command is deterministic and CI proves regeneration has no diff.
- No human-, Claude-, or Codex-authored expected amount is accepted as an authoritative
  contract fixture.

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
  migrations up/down/up, sqlc generation/diff, and Solidity-vector regeneration/diff.
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
