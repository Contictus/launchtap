# Backend Indexer — Task List

> **Workflow:** `AGENTS.md` governs pre-flight, implementation, verification, commit,
> and independent review. This is an implementation task list, not implementation code.

**Status:** Written, not started. No task may begin before its Claude pre-flight closes the
decisions listed under "Decisions to lock in pre-flight". Task 1 additionally gates the whole
plan: if the active provider cannot supply a usable `safe` tag, that is a launch blocker to
raise before Task 5's architecture, not a runtime patch (`backlog.md`, spec §4.1).

**Goal:** Turn the Backend Foundations substrate into a running chain ingestion service —
RPC access, staged log discovery, event decoding and routing, transactional canonical writes,
reorg replay, and aggregation workers — verified end to end against the real Robinhood
testnet.

**Specs:**

- `docs/specs/2026-09-01-backend-core-design.md`
- `docs/specs/2026-09-01-contract-core-design.md`

**Scope:** `internal/chain`, `internal/indexer`, the feature ingestion packages
(`internal/launch`, `internal/trading`, `internal/holder`, `internal/token`,
`internal/candle`, `internal/stats`), the remaining `internal/store/postgres` query surface,
and `cmd/indexer`. No HTTP delivery, no Privy auth, no OpenAPI — those are Plan 3.

**Toolchain:** unchanged from Backend Foundations (Go 1.26.x, pgx/v5, sqlc v1.31.1, goose/v3,
golangci-lint v2.13.2, testcontainers-go, `postgres:18.6-alpine`), plus go-ethereum's
`ethclient` and `accounts/abi` — already a direct dependency, so far used only for
`common.Address`/`common.Hash` value types — and Foundry 1.8.1 Anvil for the end-to-end
integration test.

## Global constraints

- Module path stays `github.com/Contictus/launchtap/backend`. The depguard rules in
  `backend/.golangci.yml` that already name `internal/chain` and `cmd/indexer` become live
  in this plan and must pass unmodified: `chain` may import go-ethereum RPC/ABI packages but
  never feature modules, store, or indexer; `indexer` imports chain ports, feature handlers,
  and the transaction port, but never `apiserver` or concrete pgx/sqlc types (spec §2.3).
- Every on-chain amount stays `*big.Int` in Go and `NUMERIC(78,0)` in PostgreSQL. No float
  type anywhere, including the nullable USD enrichment columns (spec §5.4, §5.5).
- One processed block chunk is one database transaction, through the existing
  `postgres.WithinTx`: block ledger rows, canonical event rows, chain projections,
  aggregation-dirty markers, and the observed watermark commit or roll back together
  (spec §2.4). No new transaction primitive is introduced.
- Canonical event uniqueness is `(chain_id, tx_hash, log_index)`. Every insert is
  `ON CONFLICT DO NOTHING` plus a full payload re-read and comparison — identical is
  idempotent success, different is a typed conflict error — never `DO UPDATE`, never a silent
  overwrite (spec §2.6). Reprocessing after an ambiguous commit outcome is safe by
  construction, not by retry logic.
- Observed data is provisional until safe/finalized. A fixed confirmation count is never
  called finality; `INDEXER_CONFIRMATIONS` remains accepted only for a `local` manifest
  (spec §14.3, §3.4).
- Projections and aggregates are always rebuildable from the canonical ledger. Reorg recovery
  is a full recompute of an affected token, never an incremental undo (spec §5.2).
- Aggregators never read chain RPC (spec §6).
- `Trade.ethGross + Trade.ethRefund` is the ETH supplied to the curve for a buy and must
  reconcile from logs alone; `ethRefund` is never part of executed volume or candle input
  (spec §14.7). A pair `Sync`, not a swap amount, is the authority for reserves and spot
  price (spec §14.5).
- Contract-side artifacts (deployment manifests, curve vectors, and — new in this plan —
  event ABIs) are single-sourced under `contracts/` and copied byte-identical into
  `backend/`; `task verify` fails on drift. No copy is ever hand-edited at the copy site.
- `cmd/indexer` never runs migrations at startup and never imports the migration runner for
  that purpose (spec §2.5).
- CI must fail, not skip, when PostgreSQL is unavailable or no integration test ran.

## Risk classes

- **low:** independent review optional.
- **high:** pre-flight and independent commit review required under `AGENTS.md`.

Every task in this plan is `high`. Each one lands squarely in `AGENTS.md`'s near-mandatory
list — indexer/reorg handling, transaction lifecycle, concurrency, critical infrastructure.

## Decisions to lock in pre-flight

Backend Foundations was written after its spec sections closed, so its acceptance criteria
were already locked. This plan is written before its pre-flights, and the spec deliberately
left the following open — each names the task that must not start until it is decided.

1. **Projection write path (Tasks 4-7, the load-bearing one).** Spec §5.2 says projections
   are updated transactionally alongside ingestion *and* are fully rebuildable. Read
   literally that is two implementations of one piece of logic — an incremental writer in Go
   and the existing `rebuild_token_projections()` in PL/pgSQL — which can drift, in precisely
   the code path that exists to recover from failure. **Recommendation:** ingestion calls
   `rebuild_token_projections()` once per token touched by the chunk, inside the chunk's own
   transaction. One implementation, no drift, and `candles` come free because the function
   already rebuilds them. The cost is a per-token full recompute per chunk; if that is ever
   measured to be too slow, an incremental fast path can be added later with the existing
   recompute as its test oracle. Rejecting this recommendation means Task 4 must instead
   specify how the two implementations are proven equivalent.
2. **Event ABI copy location and drift-gate name (Task 2).** Which directory under `backend/`
   holds the byte-identical `contracts/abi/v1/**` copy, and what the Taskfile target is
   called, following the `curve-vectors-diff` / `deployments-diff` precedents.
3. **Reorg identity (Task 6).** Spec §12 requires a "reorg id" in structured logs and "last
   reorg depth/time" in health, but defines no table or column. Decide: process-local
   identifier plus in-memory last-reorg summary, or a persisted reorg table. A persisted
   table is the only option that survives a restart, and health is read by an operator after
   exactly the kind of incident that restarts the process.
4. **Address-filter partition configuration (Task 3).** Spec §10 says this value is
   "introduced with the indexer plan" but does not name it. Its default comes from Task 1's
   measurement, not from a guess.
5. **`RPC_URL` scheme allowlist (Task 3).** `internal/config` accepts only `http`/`https`
   today, so a WebSocket subscription is currently unreachable. Decide whether this plan polls
   over HTTP only — in which case the allowlist stays as is and the poll interval becomes a
   new config value — or admits `ws`/`wss`.

## Task 1 — Chain operability prerequisites · Risk: high

**Delivers:** measured, recorded answers to the two `backlog.md` items that gate an indexer
runtime — a read-only capacity and finality probe of the Robinhood providers, and a reviewed
chain-46630 deployment manifest that replaces today's fail-closed disabled marker.

**Files:** a new operations note under `docs/`, `contracts/deployments/config/` (the
`robinhood-testnet.disabled.json` marker is replaced by a real manifest),
`backend/deployments/testdata/` (byte-identical copy), `backend/.env.example`.

**Acceptance criteria:**

- The probe is read-only and records, for Robinhood mainnet (`4663`) and the chosen testnet
  (`46630`): `latest`/`safe`/`finalized` tag support, tag monotonicity observed over time,
  the observed→safe→finalized lag distribution, block-hash consistency across repeated reads
  of the same height, and `eth_getLogs` capacity — max block range, max response size, and
  max addresses per filter. Measured numbers are committed to the operations note with the
  date and provider they were taken against; they are never embedded in code as provider
  constants (spec §4.3).
- Those measurements set the defaults for `INDEXER_CHUNK_SIZE`, the address-filter partition
  size, the runtime finality configuration, and the health lag thresholds — each default
  traceable to a specific measured number rather than chosen by feel.
- A provider that cannot supply a usable `safe` tag stops this plan and is escalated as a
  launch blocker before Task 5 is designed. Falling back to a fixed confirmation count on a
  non-`local` deployment is not an acceptable resolution (`backlog.md`, spec §4.1).
- The testnet manifest names a verified official WETH + Uniswap v2 stack on chain 46630,
  or a project-owned one deployed for this purpose; mainnet addresses are never substituted,
  which live checks already proved would be codeless on testnet (`backlog.md`).
- The manifest validates against `deployment.schema.json` with all 23 fields present,
  `startBlock` equal to the factory deployment receipt block and non-zero because the
  environment is not `local`, and `bytecodeHashes` taken from the deployed runtime code.
  `deployments.LoadEmbedded().Lookup(46630, …)` returns it instead of
  `ErrDeploymentDisabled`, and the backend copy passes `task deployments-diff`.
- Both `backlog.md` items are updated to name this task as their owner and are moved to
  `Done` only when the manifest is committed and the probe note is written — not before.
- Tasks 2-7 depend only on the probe half of this task. Only Task 8's testnet acceptance run
  depends on the manifest half, so a slow external deployment does not block backend work.

## Task 2 — Event ABI artifacts and log decoding · Risk: high

**Delivers:** a single-sourced event ABI artifact set covering every log the indexer must
read, and the pure decoding half of `internal/chain` — topic-to-typed-value decoders for all
18 event types, producing Go values that map one-to-one onto the canonical ledger tables'
payload columns.

**Depends on:** Task 1.

**Files:** `contracts/abi/v1/` (a new pair-event artifact),
`backend/internal/chain/` (new package: ABI registry and decoders, plus their testdata copy),
`backend/Taskfile.yml`, `.github/workflows/backend.yml` if the gate needs a path trigger.

**Acceptance criteria:**

- Uniswap v2 `Mint`, `Burn`, `Swap`, and `Sync` gain a committed event-ABI artifact on the
  contracts side — the repo has none today, and `IUniswapV2Pair.sol` is a function-only
  interface. It is generated or transcribed once, reviewed, and then treated exactly like
  `ILaunchEvents.json`: authoritative, and never re-derived at decode time.
- `contracts/abi/v1/**` is copied byte-identical into `backend/`, with a Taskfile target that
  fails on any difference, folded into `task verify` alongside the existing
  `curve-vectors-diff` and `deployments-diff` checks. The copy is never hand-edited.
- Decoders exist for the 13 `ILaunchEvents` events, ERC-20 `Transfer`, and the four pair
  events, and each one's output fields correspond exactly to its ledger table's payload
  columns as listed in spec §5.1 — a decoder that produces a field the table has no column
  for, or omits one it does, is a defect.
- `TokenLaunched` decodes against the frozen signature recorded in `LaunchFactory.sol`, and
  the test proves it against a golden log captured from a real Foundry run, not a
  hand-assembled fixture. The event is emitted by hand-written inline assembly `log4`, so the
  committed ABI artifact and a real emitted log — never the Solidity `event` declaration's
  field order read by eye — are the authority.
- `Trade` decodes `ethGross` and `ethRefund` as adjacent fields and persists both, so that
  buy input reconciles from logs alone (spec §4.4, §14.7).
- `ILaunchEvents` is inherited by both `LaunchFactory` and `BondingCurveV1`, so topic0 alone
  cannot say which contract emitted a log. Routing therefore keys on the emitting address as
  well as the topic, and a decoder never infers the emitter from the signature.
- The ABI set is selected by factory deployment and `engine_version`; an unknown version is a
  fatal indexing error, not a best-effort decode (spec §4.4).
- Malformed input is rejected rather than truncated: wrong topic count, short data, a
  non-zero-padded address word, and an unknown topic0 each produce a typed error naming the
  log's coordinates.
- Every decode test fixture originates from Foundry output. No human-, Claude-, or
  Codex-authored log payload is accepted as an authoritative fixture, matching the rule
  Backend Foundations Task 10 established for curve vectors.

## Task 3 — RPC client, head tracking, and staged log discovery · Risk: high

**Delivers:** the network half of `internal/chain` — a typed RPC client over go-ethereum's
`ethclient` covering headers, code, and logs; the three finality head reads; the five-stage
per-chunk log discovery sequence with adaptive shrinking and address-filter partitioning; and
the two startup verification helpers spec §3.3 explicitly deferred to indexer startup.

**Depends on:** Task 1.

**Files:** `backend/internal/chain/` (client, head reads, log discovery, startup
verification), `backend/internal/config/` (the new indexer runtime values).

**Acceptance criteria:**

- The client reads headers by number and by the `latest`, `safe`, and `finalized` tags, and
  reports a provider's lack of `safe`/`finalized` support as a typed error the runtime can
  fail startup on, rather than silently degrading (spec §4.1).
- Staged discovery runs the five stages spec §4.3 fixes — factory logs first, then the
  token/curve/pair addresses those `TokenLaunched` events reveal with the affected ranges
  refetched, then known curve/token logs, then known pair logs — and finishes by
  deduplicating and sorting every log by `(block_number, transaction_index, log_index)`
  before anything is routed. A same-transaction developer buy or graduation log is captured
  by the refetch, proven by a test rather than asserted.
- The address filter set is dynamic and grows by three addresses per launch. Neither the
  token nor the curve address is CREATE2-derivable — both use plain `CREATE` — so discovery
  is the only way they are learned, and no code path attempts to precompute them.
- Chunk size and address-filter partition size come from configuration seeded by Task 1's
  measurements, never from hard-coded provider numbers. Adaptive shrinking handles range and
  response-size errors, and a test proves the final routed log order is identical whether or
  not shrinking occurred — shrinking changes request shape, never event order (spec §4.3).
- A log returned twice by overlapping partitioned or refetched requests appears exactly once
  after deduplication, keyed on `(block_number, transaction_index, log_index)`.
- `eth_getCode` verification compares the runtime bytecode hash of `Factory`,
  `CurveImplementation`, `WETH`, and `UniV2Factory` against the manifest's `bytecodeHashes`,
  and a mismatch is a fatal startup error (spec §3.3). Task 3 of Backend Foundations
  validated only their shape and performed no RPC call; this is where that check becomes real.
- CREATE2 pair-address reproduction from `PairInitCodeHash`, `UniV2Factory`, and the sorted
  `(token, weth)` pair matches what the chain reports, and a mismatch is fatal (spec §3.3).
- The new configuration values — poll interval, RPC timeout and retry policy, address-filter
  partition size, and the indexer worker identifier — are validated in `internal/config` under
  its existing stdlib-only, no-`os` constraint, with `RequireIndexer()` mirroring the existing
  `RequireAPI()`.
- Tests run against a fake RPC server, not a live provider, so the suite stays hermetic; the
  live provider is exercised only in Task 8's acceptance run.

## Task 4 — Store completion for ingestion and rollback · Risk: high

**Delivers:** the persistence surface Backend Foundations deliberately left unbuilt because it
had no consumer — a `pgxpool` constructor, idempotent insert wrappers for the remaining 15
event tables, and the reorg SQL whose parameter shape was left for its Plan 2 consumer to fix.

**Depends on:** Task 1.

**Files:** `backend/internal/store/postgres/` (pool constructor, adapter methods,
`queries/*.sql`, regenerated `sqlc/`), `backend/internal/store/postgres/postgrestest/`.

**Acceptance criteria:**

- A pool constructor returns the `*pgxpool.Pool` that `WithinTx` requires. `Open` returning
  `*sql.DB` stays as it is and remains the migration runner's entry point — the two are not
  merged, and the pool is never used to run migrations.
- Insert queries and idempotent adapter wrappers exist for the 15 event tables that lack
  them, each one copying the proven `trades` / `launch_pause_events` pattern verbatim in
  shape: `ON CONFLICT (chain_id, tx_hash, log_index) DO NOTHING`, re-read on conflict,
  compare every payload column, identical is silent success, different is
  `*InvariantConflictError` (spec §2.6). No wrapper opens, commits, or rolls back a
  transaction; each accepts sqlc's `DBTX`.
- `sqlc diff` is clean, and every new query's generated params struct is field-identical to
  the hand-written adapter type it converts from, so a future column reordering breaks the
  build rather than silently mismapping.
- The reorg primitives exist as raw SQL designed with this plan's consumer, as spec §2.6
  said they would be: a common-ancestor walk over `indexed_blocks` driven by the candidate
  hashes the detector actually holds, deletion of canonical event rows above the ancestor,
  deletion of block-ledger rows above the ancestor, and discovery of the token set whose
  projections the deletion affects.
- Deletion order is exercised, not assumed: because every event table's block FK defines no
  `ON DELETE` action, deleting a block row before its event rows fails — a test asserts the
  database enforces this, so correctness does not rest on caller discipline alone (spec §5.1).
- Affected-token discovery covers tokens reachable through pair events as well as through
  the per-token FKs, since `pool_*` tables carry no `token_launches` FK and are linked only
  by a query-time join through `tokens.lp_pair` (spec §5.1).
- Integration tests drive these primitives with raw SQL against a real PostgreSQL database,
  the same pattern Backend Foundations Tasks 5-7 used, and assert both the rows removed and
  the rows deliberately left intact — `token_metadata` in particular is never touched by a
  rollback (spec §5.2).

## Task 5 — Indexer core: ownership, chunk loop, and event routing · Risk: high

**Delivers:** `internal/indexer` — singleton ownership, watermark management, the chunk loop
that turns one processed range into one transaction, two-pass processing, and routing of every
decoded event to a feature ingestion handler through ports defined where they are consumed.

**Depends on:** Tasks 2, 3, and 4.

**Files:** `backend/internal/indexer/` (new), `backend/internal/launch/`,
`backend/internal/trading/`, `backend/internal/holder/`, `backend/internal/token/` (ingestion
ports and handlers), `backend/internal/store/postgres/` (port implementations).

**Acceptance criteria:**

- Ownership is a session-level PostgreSQL advisory lock scoped by chain id and deployment id
  on a dedicated connection. Failure to acquire is fatal, and **loss of that connection is
  also fatal** — a second indexer never continues as another writer, and the process does not
  attempt to silently reacquire and carry on (spec §2.1).
- One chunk is one `WithinTx` call. Block ledger rows, canonical event rows, projections,
  aggregation-dirty markers, and the observed watermark are written inside it and commit or
  roll back together (spec §2.4).
- `sync_state` holds the indexer's **own locally-confirmed** heads. Safe and finalized are
  advanced only after the corresponding block has been processed and its hash verified
  against `indexed_blocks`; the node's raw reported tag is never persisted, and the watermarks
  the API will expose are bounded by the observed head even when the node is further ahead
  (spec §4.2, §5.1). Writes respect the table's bottom-up CHECKs — finalized requires safe,
  safe requires observed.
- Processing is two-pass within the chunk: a discovery pass inserts launch ledger rows and
  token identity skeletons idempotently, then an event pass applies all remaining logs in
  chain order. This is what makes the constructor's `Transfer(0, curve, S)` legal before its
  `TokenLaunched`; any *other* pre-launch token log is a fatal contract-invariant violation
  (spec §4.3).
- `token_stats.ath_price_eth_wad` and `ath_at` are initialized during the discovery pass from
  the launch snapshot's opening price and `launch_block_time`, as spec §5.5 requires, so the
  aggregator only ever moves them forward and never has to invent an initial value.
- Feature ingestion ports and the `IndexerUnitOfWork` bundle are declared in the packages that
  consume them and implemented in `store/postgres`. No pgx type, generated sqlc type, or
  `ethclient` type appears in any feature-package signature — enforced by the existing
  depguard rules, not by convention (spec §2.3, §2.4).
- A curve `Trade` dated after the same token's `Graduated` block is a fatal invariant
  violation surfaced by the indexer, not merely caught by the database's deferred constraint
  triggers at commit — although a test also proves the trigger fires, since it is the
  backstop (spec §4.4, §5.1).
- The indexer does **not** encode "a launch transaction cannot also graduate" as a rule. Under
  the locked V1 parameters the 1%-of-supply developer-buy cap is far below the curve
  allocation, but that is current deployment behaviour, not an invariant, and a future
  parameter snapshot could change it (spec §4.3).
- Startup with an `engine_version` the ABI registry does not know fails fatally rather than
  decoding on a best-effort basis (spec §4.4).

## Task 6 — Reorg detection and replay · Risk: high

**Delivers:** the running counterpart to Backend Foundations' rollback primitives — parent-hash
verification, the walk to the common ancestor, the single-transaction rollback and rebuild, and
the finality boundary at which the indexer stops instead of recovering.

**Depends on:** Task 5.

**Files:** `backend/internal/indexer/` (detector and replay), `backend/internal/chain/`
(header walk support), `backend/internal/store/postgres/postgrestest/`.

**Acceptance criteria:**

- Before extending the observed chain, the new header's parent hash is verified against the
  stored tip. On mismatch the indexer walks stored block hashes and RPC headers backward to
  the common ancestor; the walk terminates when no stored row matches a given hash, which is
  the correct "beyond the tracked range" signal, not a NULL sentinel (spec §4.2, §5.1).
- Rollback and rebuild happen in **one** transaction, in this order: canonical event rows
  above the ancestor are deleted, then block-ledger rows above it, then affected token
  projections are rebuilt from surviving canonical events, then every affected watermark is
  reset. A partial rollback is never committed (spec §4.2).
- Rebuild is a full recompute of an affected token's projections from its complete surviving
  event history, never an incremental undo — the failure path is the worst place to run the
  more failure-prone algorithm (spec §5.2).
- Mutable state is proven to roll back, not just event rows: a test drives a reorg that
  changes `tokens.phase`, `token_reserves`, `holder_balances`, and `candles`, and asserts each
  returns to the value implied by the surviving ledger. `token_metadata` is asserted unchanged
  (spec §4.2, §5.2).
- A hash mismatch at or below the stored safe head **stops ingestion** and raises an
  operator-visible critical error. A finalized block is never automatically deleted. Automatic
  recovery is confined to reorgs wholly above the safe head (spec §4.2).
- Safe and finalized promotion first verifies that the node-reported hashes match
  `indexed_blocks`, and a promotion whose hash disagrees is treated as a reorg signal rather
  than written through (spec §4.2).
- The reorg identity decided in pre-flight is emitted in structured logs and surfaced in
  health as last reorg depth and time (spec §12).
- Tests cover a shallow reorg above the safe head, a deep multi-block reorg, a reorg whose
  ancestor lies at the safe boundary, and finality promotion — four of the seven indexer
  dimensions spec §11 names, with the remaining three covered by Tasks 3 and 8.

## Task 7 — Aggregation workers and derived market state · Risk: high

**Delivers:** the aggregation half of `cmd/indexer` — the durable dirty-work loop, its
crashed-worker recovery, the computation of `token_stats`, `protocol_daily`, and
`protocol_stats`, and the periodic reconciliation sweep.

**Depends on:** Task 5.

**Files:** `backend/internal/candle/`, `backend/internal/stats/`, `backend/internal/indexer/`
(worker orchestration), `backend/internal/store/postgres/`.

**Acceptance criteria:**

- Ingestion writes `aggregation_dirty` inside the chunk transaction and sends
  `NOTIFY market_dirty` **after** the commit, carrying only chain/deployment and
  generation/checkpoint identifiers — never an affected-token list. There is no database
  trigger for this: a trigger would fire inside the transaction and announce work that may
  still roll back (spec §6).
- Worker startup order is commit `LISTEN`, read the dirty snapshot, then enter the
  notification loop. A missed notification costs latency and nothing else, because the dirty
  table is the durable work source and notifications are hints (spec §6).
- Claim and complete use the SQL already locked in spec §2.6 unchanged, including the
  `claimed_generation`-guarded delete that prevents a late completion from discarding work
  another worker has already claimed at a newer generation.
- Crashed-worker recovery reclaims rows whose `claimed_at` is older than a configured lease,
  using the `claimed_at`/`claimed_by` columns that already exist — no schema change. A test
  proves a row claimed by a worker that never completes becomes claimable again, and that a
  slow-but-alive worker's completion of a stale claim is correctly rejected rather than
  corrupting the newer claim.
- `token_stats` is computed with `ath_price_eth_wad` moving only forward from the value the
  discovery pass seeded, `price_change_24h_bps` as a signed integer because a price can fall,
  and `holder_count` excluding the zero, dead, curve, and canonical pair addresses while the
  pair balance still counts toward circulating supply (spec §5.4, §5.5).
- `protocol_daily` is keyed by a UTC-anchored `DATE` — one row per calendar day, never an
  intraday bucket — and `protocol_stats` holds one row per chain with `trades_all_time` as
  `BIGINT` (spec §5.5).
- Candles are read from the `market_trades` view using `execution_price_wad`, never
  `spot_price_wad`; `6h` and `all` are computed on read from the stored `1h`/`1d` rows and are
  never stored (spec §5.3, §5.5). Full candle recomputation already lives in
  `rebuild_token_projections()` and is reused rather than reimplemented.
- The periodic reconciliation sweep rebuilds recent buckets and any projection a reorg
  touched, so a lost notification or a crash mid-aggregation self-heals without operator
  action (spec §6).
- No aggregator code path opens an RPC client — enforced by a depguard rule, not by review
  (spec §6).
- Spot price, tokens sold, and real curve ETH reuse `internal/curve`'s existing functions
  rather than reimplementing the formulas in SQL or Go (spec §7.2). Circulating supply stays a
  projection-layer concern and is not added to the curve package's surface.
- USD columns remain NULL. The ETH/USD source is a separate, non-blocking backlog item, and
  its absence must not affect indexing, list correctness, or any ETH-denominated value
  (spec §5.4, `backlog.md`).

## Task 8 — Indexer runtime, observability, and verification gate · Risk: high

**Delivers:** `cmd/indexer` as a running process, the health and logging surface spec §12
mandates, an Anvil-backed end-to-end test covering every indexer dimension spec §11 names, and
the real Robinhood testnet acceptance run that closes this milestone.

**Depends on:** Tasks 1, 6, and 7.

**Acceptance criteria:**

- `cmd/indexer` starts by loading configuration, resolving the `(CHAIN_ID, DEPLOYMENT_ID)`
  manifest and reconciling it — a chain-id mismatch or an `INDEXER_CONFIRMATIONS` override on
  a non-`local` environment is fatal — then verifies bytecode hashes and reproduces the pair
  address, then acquires the advisory lock, then runs the sync loop with the aggregator as an
  in-process goroutine (spec §2.1, §3.3, §3.4).
- It never runs migrations and never imports the migration runner, enforced by the existing
  `migration-startup-boundary` depguard rule that already names `cmd/indexer` (spec §2.5).
- Shutdown is graceful: the in-flight chunk transaction either commits or rolls back, the
  advisory lock is released, and the process does not exit reporting success while a
  transaction outcome is unknown.
- Health reports every field spec §12 lists: deployment id; observed, safe, and finalized
  block numbers and timestamps; per-watermark lag; advisory-lock ownership; last reorg depth
  and time; RPC status; dirty-work count; and token phase counts. Structured logs carry chain,
  deployment, block number and hash, transaction hash, and reorg id.
- An Anvil-backed integration test indexes a real deployment end to end — launch, developer
  buy, ordinary trades, graduation, and post-graduation pair activity — and asserts the
  canonical ledger, projections, and aggregates that result. Together with Tasks 3 and 6 it
  covers all seven dimensions spec §11 names: staged discovery, duplicate logs, provider
  partitioning, same-transaction events, shallow and deep reorg, mutable projection rollback,
  and finality promotion.
- `task verify` gains the ABI drift gate and the new integration tests and remains the one
  reproducible command for the Go-side gates (spec §11). CI fails, rather than skips, when the
  indexer integration tests do not execute — matching the sentinel pattern that already guards
  `TestMigrationsUpDownUp`.
- A testnet acceptance run against Task 1's chain-46630 manifest indexes a real launch, trade,
  and graduation, and records the observed→safe→finalized progression actually seen. Its
  result is written up with the commit and CI run that produced it; a green local suite is not
  accepted as evidence of testnet operation.
- Codex's completion report states the exact verified tool versions and commands the new gate
  exercises; Claude records them into `AGENTS.md` in a separate commit — Codex does not edit
  `AGENTS.md` directly.

## Plan boundary

Plan 3 owns Huma endpoints, Privy access and identity verification, informational quote DTOs,
OpenAPI generation, and SSE. This plan supplies the canonical data and derived market state
those endpoints read, and the `asOfBlock`/`finality` values they must report, but it does not
define a single HTTP DTO. The ETH/USD enrichment adapter and any decision to materialize
`market_trades` stay deferred (spec §13).
