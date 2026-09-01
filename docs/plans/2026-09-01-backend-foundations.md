# Backend Foundations — Task List

> **Workflow:** see `AGENTS.md` → "Multi-agent workflow". Codex owns each task's
> implementation lifecycle (implementation plan, code, tests, verification, commit).
> Claude does pre-flight review on high-risk tasks and independent review of each commit.
> This document is the task breakdown + acceptance criteria — **not** an implementation
> guide. No code or test bodies here by design.

**Goal:** the substrate every later backend plan depends on — a tested pure-Go
bonding-curve math library, a migrated Postgres schema with typed access and a
Unit-of-Work, and config loading with a compiled-in chain registry.

**Scope:** shared packages `internal/curve`, `internal/config`, `internal/store/postgres`,
plus repo scaffolding. No `cmd/api` / `cmd/indexer` process is wired up here — Plans 2-3.

**Tech Stack:** Go 1.23, `jackc/pgx/v5`, `sqlc`, `pressly/goose/v3`, `shopspring/decimal`,
`ethereum/go-ethereum` (common value types only in this plan),
`testcontainers/testcontainers-go`, `golangci-lint`.

**Spec:** `docs/specs/2026-09-01-backend-core-design.md` (section refs below are into this doc)

## Global Constraints

- **Runtime:** Go 1.23. One module `backend/`, path `github.com/pons/launchpad/backend`
  (adjust the org segment once, everywhere, if it differs).
- **Zero-cost:** no paid services; dev Postgres via Docker / testcontainers only.
- **Precision:** all curve arithmetic in `*big.Int`. No `float64` / `big.Float` where a
  value must match on-chain state. `shopspring/decimal` only in API DTO code (not this plan).
- **DIP line:** application/domain code must not import `pgx`, sqlc-generated packages, or
  `ethclient`. It may use go-ethereum value types (`common.Address`, `common.Hash`,
  `*big.Int`).
- **Dependency rule (depguard):** `internal/curve` → stdlib + `math/big` only.
  `internal/config` → stdlib + `go-ethereum/common` only. Only `internal/store/**` may
  import `pgx` / sqlc output.
- **Canonical vs derived:** canonical tables are the chain projection, never recomputed
  from derived data; derived tables are always rebuildable from canonical.
- **Idempotency:** every event-derived table carries `block_number BIGINT`,
  `tx_hash BYTEA`, `log_index INT`, with UNIQUE `(tx_hash, log_index)`.
- **Curve rounding:** divisions that determine an amount *leaving the pool* round **up**
  (ceil), favouring the pool; fee splits round **down**. The differential test against the
  contract is the final authority; Go yields if they differ.

## Risk classes

- **low** — Codex proceeds solo; Claude review optional.
- **high** — Claude pre-flight before start + independent review of the commit
  (per `AGENTS.md`).

---

### Task 1 — Repo & Go module scaffold · Risk: low

**Delivers:** a buildable `backend/` Go module with linter (incl. depguard dependency
rules), a task runner, `.env.example`, and a path-filtered CI job.

**Files:** `.gitattributes`, `backend/go.mod`, `backend/.golangci.yml`,
`backend/Taskfile.yml`, `backend/.env.example`, `.github/workflows/backend.yml`

**Depends on:** —
**Spec:** §4.2 (package layout), §4.3 (dependency rules), §11 (CI)

**Acceptance criteria:**
- `cd backend && go build ./...` exits 0.
- `golangci-lint run` exits 0 and its depguard config enforces the Global Constraint
  dependency rule (verified by a deliberate probe import in a scratch branch, then removed).
- `task build`, `task test`, `task lint`, `task migrate`, `task sqlc` are defined.
- CI runs on `backend/**` changes: `go build ./...`, `go test ./... -race`, `golangci-lint`.
- `.gitattributes` enforces LF for `*.go` / `*.sql` / `*.md`.

---

### Task 2 — Config: `Config` + `Load()` · Risk: low

**Delivers:** env-driven config loading, pure and unit-testable.

**Files:** `backend/internal/config/config.go` (+ test)
**Depends on:** Task 1
**Spec:** §10

**Acceptance criteria:**
- `Load(getenv func(string) string) (Config, error)` — pure; no direct `os` access.
- Errors when `CHAIN_ID`, `RPC_URL`, or `DATABASE_URL` is missing/empty.
- Errors when `CHAIN_ID` does not parse as `uint64`.
- `LOG_LEVEL` defaults to `info` when unset.

---

### Task 3 — Config: chain registry · Risk: low

**Delivers:** compiled-in chain registry wired into `Load`.

**Files:** `backend/internal/config/chains.go` (+ modify `config.go`, tests)
**Depends on:** Task 2
**Spec:** §5.1; chain decision in `notes.md`

**Acceptance criteria:**
- `ChainByID(id uint64) (ChainConfig, bool)`.
- Registry has `31337` (anvil), `46630` (robinhood-testnet), `4663` (robinhood-mainnet)
  with `Name`, `Confirmations`, and — for the RH chains — the Uniswap v2 Factory/Router
  addresses from the spec, **verified against `notes.md`**.
- `Load` populates `Config.Chain` from the registry and errors on an unknown `CHAIN_ID`.
- `WETH` may be left zero (unverified in spec) — do not block on it.

---

### Task 4 — curve: `State` + integer math helpers · Risk: high

**Delivers:** `internal/curve` foundations — `State{X,Y,K}`, `NewState`, `Clone`,
`Invariant`, and `ceilDiv` / `mulDiv`.

**Files:** `backend/internal/curve/curve.go`, `backend/internal/curve/mathutil.go` (+ tests)
**Depends on:** Task 1
**Spec:** §6.2 (precision), §6.3 (surface); Global Constraint on rounding

**Acceptance criteria:**
- All arithmetic `*big.Int`; no `float64` / `big.Float`.
- `NewState(x0,y0)` sets `K = x0·y0` and does not alias caller inputs.
- `ceilDiv(a,b)` = ⌈a/b⌉ for non-negative `a`, positive `b`; panics on `b ≤ 0`.
- `mulDiv(a,b,denom)` = ⌊a·b/denom⌋; panics on `denom ≤ 0`.
- Package imports only stdlib + `math/big` (depguard passes).

---

### Task 5 — curve: price, tokens-sold, graduation check · Risk: high

**Delivers:** `SpotPriceWad`, `TokensSold`, `IsGraduated`.

**Files:** `backend/internal/curve/price.go` (+ tests)
**Depends on:** Task 4
**Spec:** §6.3; economy section in `notes.md`

**Acceptance criteria:**
- `SpotPriceWad(s)` = ⌊X·1e18/Y⌋ (wad fixed point, round down).
- `TokensSold(s, y0)` = `y0 − Y`.
- `IsGraduated(s, y0, curveTokens)` true iff tokens sold ≥ `curveTokens`.
- Tests use the spec's launch values (`x0 = 1.4e18`, `y0 = 1,066,666,667e18`) and assert
  exact expected outputs computed by hand under the documented rounding.

---

### Task 6 — curve: `QuoteBuy` · Risk: high

**Delivers:** buy quote with fee split and pool-favouring rounding.

**Files:** `backend/internal/curve/quote.go` (+ tests)
**Depends on:** Task 5
**Spec:** §2 (fee model), §6.3; Global Constraint on rounding

**Acceptance criteria:**
- Returns: amount out, protocol fee, creator fee, next `State`.
- `totalFee = ⌊ethGross·feeBps/10000⌋`; `protocolFee = ⌊totalFee·protoShareBps/10000⌋`;
  `creatorFee = totalFee − protocolFee`.
- `dxEff = ethGross − totalFee`; `newX = X + dxEff`; `newY = ⌈K/newX⌉`;
  `amountOut = Y − newY`.
- Panics on `ethGross ≤ 0`.
- Tests assert: exact fee split at 100 bps / 5000 bps; reserves move along the curve;
  spot price strictly increases after a buy.

---

### Task 7 — curve: `QuoteSell` · Risk: high

**Delivers:** sell quote with proceeds-side fees.

**Files:** `backend/internal/curve/quote.go` (+ tests)
**Depends on:** Task 6
**Spec:** §2, §6.3

**Acceptance criteria:**
- `newY = Y + tokensIn`; `newX = ⌈K/newY⌉`; `ethGross = X − newX`; fees taken from
  `ethGross`; `amountOut = ethGross − totalFee`.
- Panics on `tokensIn ≤ 0` or `tokensIn ≥ Y`.
- Tests assert: a buy-then-sell round trip loses value (fees + rounding); gross proceeds
  reconcile to the reserve delta.

---

### Task 8 — curve: differential vector table + fuzz · Risk: high

**Delivers:** a JSON vector-table test freezing exact `(state, input) → output` values,
plus a monotonicity fuzz test.

**Files:** `backend/internal/curve/vectors_test.go`,
`backend/internal/curve/testdata/curve_vectors.json`
**Depends on:** Task 7
**Spec:** §6.4

**Acceptance criteria:**
- `curve_vectors.json` has a versioned schema and ≥ 1 buy and ≥ 1 sell vector.
- **Vector expected values are the authority for the contract's behaviour.** For now they
  are Claude-supplied (from the documented math); the Solidity contract's generator
  replaces/extends the file later. No placeholder (`FILL_EXACT` etc.) survives in the
  committed file — the test fails if one does.
- The test asserts byte-identical `*big.Int` outputs.
- A fuzz test asserts `amountOut ≥ 0` and non-decreasing spot price after a buy, for
  random ETH inputs.

---

### Task 9 — store: migrations tooling + `sync_state` / `tokens` · Risk: high

**Delivers:** embedded goose tooling, `cmd/migrate`, a testcontainers Postgres helper, and
migration 00001.

**Files:** `backend/internal/store/postgres/db.go`,
`backend/internal/store/postgres/migrations/00001_*.sql`,
`backend/internal/store/postgres/migrations/embed.go`,
`backend/internal/store/postgres/testsupport.go`,
`backend/cmd/migrate/main.go` (+ tests)
**Depends on:** Task 1
**Spec:** §7.1, §7.4

**Acceptance criteria:**
- `RunMigrations(ctx, dsn)` applies all up migrations from an `embed.FS`.
- `StartTestPostgres(t)` starts a throwaway Postgres, runs migrations, returns a DSN;
  **SKIPs (not fails)** when Docker is unavailable.
- After 00001: `sync_state` (single row, `id = 1` CHECK) and `tokens` exist with the
  columns and the `tsvector` GIN index on `(name, symbol)` from the spec.

---

### Task 10 — store: canonical event tables · Risk: high

**Delivers:** migration 00002 — `trades`, `graduations`, `creator_fee_claims`,
`transfers`, `pool_swaps`.

**Files:** `backend/internal/store/postgres/migrations/00002_*.sql` (+ test)
**Depends on:** Task 9
**Spec:** §7.1; Global Constraint on idempotency

**Acceptance criteria:**
- Every table has `block_number`, `block_time`, `tx_hash`, `log_index` and UNIQUE
  `(tx_hash, log_index)`.
- `graduations` PK is `token_address`; the others use an identity PK.
- FK to `tokens(address)` on all.
- A test proves a duplicate `(tx_hash, log_index)` insert is rejected.

---

### Task 11 — store: derived tables, `market_trades` view, sqlc · Risk: high

**Delivers:** migration 00003 (derived tables + `market_trades` view), `sqlc.yaml`, first
query files, generated code, `DBTX` alias.

**Files:** `backend/internal/store/postgres/migrations/00003_*.sql`,
`backend/internal/store/postgres/queries/*.sql`,
`backend/internal/store/postgres/gen/*`, `backend/sqlc.yaml` (+ test)
**Depends on:** Task 10
**Spec:** §7.2, §7.3, §7.4

**Acceptance criteria:**
- Derived tables: `holder_balances`, `candles` (interval CHECK on `1m/5m/1h/1d`),
  `token_stats`, `protocol_daily`, `protocol_stats`.
- `market_trades` view unions `trades` and `pool_swaps` into
  `token_address, ts, price_wad, eth_volume, token_volume, side_buy, trader, tx_hash,
  log_index, source`; DEX rows resolve the WETH leg via `tokens.token_is_token0`.
- `sqlc generate` produces a `gen` package with typed queries for `sync_state`
  (get/upsert checkpoint) and `tokens` (upsert / get / set-graduated).
- `postgres.DBTX` aliases the sqlc `DBTX` interface.
- A test asserts the view's column set.

---

### Task 12 — store: Unit of Work · Risk: high

**Delivers:** `UnitOfWork` / `WithinTx` over a pgx transaction, with a `Repositories`
bundle.

**Files:** `backend/internal/store/postgres/uow.go` (+ test)
**Depends on:** Task 11
**Spec:** §4.5

**Acceptance criteria:**
- `WithinTx(ctx, fn func(Repositories) error) error` — opens a `pgx.Tx`, builds tx-bound
  repos, commits on nil, rolls back on error, rolls back + re-panics on panic.
- `pgx.Tx` appears in no signature outside `store/`.
- Tests prove: writes inside `WithinTx` commit on success; roll back fully on a returned
  error.

---

## Claude self-check (before handing to Codex)

- Spec coverage for foundations: §4.2/4.3 → T1 · §4.5 → T12 · §6 → T4-8 · §7 → T9-11 ·
  §10 → T2-3 · §11 → T1.
- Deferred to later plans (not gaps): `chain/`, `indexer/`, `apiserver/`, feature
  modules, aggregation, Privy auth, SSE, `ETH_USD` source, WETH address confirmation.
