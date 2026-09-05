# Backend Indexer — Task List

> **Workflow:** `AGENTS.md` governs pre-flight, implementation, verification, commit,
> and independent review. This is an implementation task list, not implementation code.

**Status:** Written, not started. The five cross-cutting decisions under "Locked decisions"
are closed and binding; each task still takes its own pre-flight for the criteria below it.
Task 1 gates the whole plan: if the active provider cannot supply a usable `safe` tag, that is
a launch blocker to raise before Task 4's architecture, not a runtime patch (`backlog.md`,
spec §4.1).

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

**Granularity:** five deliberately coarse tasks. Tasks 4 and 5 each carry enough change that
`AGENTS.md`'s `task/<slug>` short-lived branch — reserved for a high-risk task whose change is
large or uncertain — is the expected path for them rather than the exception. Coarse tasks do
not mean coarse review: each still takes a full pre-flight and a full independent commit
review, and a task may be split during its pre-flight if the review surface turns out larger
than the criteria below suggest.

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

## Locked decisions

Backend Foundations was written after its spec sections closed, so its acceptance criteria
were already locked. This plan was written before its pre-flights; the five decisions the
spec deliberately left open were resolved in the Claude↔Codex pre-flight round and are now
binding on the tasks named beside them.

1. **Projection write path — transactional incremental writer (Tasks 3-5).** Ingestion writes
   projections incrementally inside the chunk transaction. `rebuild_token_projections()` is
   *not* the ingestion path; it stays the reorg-recovery primitive, the reconciliation sweep's
   worker, and the differential-test oracle that keeps the incremental writer honest.
   Claude's initial recommendation — call the rebuild per touched token per chunk, buying
   single-implementation safety — was **rejected on the merits by Codex and the rejection is
   correct**: the function deletes and rebuilds a token's entire `holder_balances` from its
   full transfer history and its entire `candles` set from its full `market_trades` history
   (a four-interval `CROSS JOIN` over a view that itself laterally joins `pool_syncs`). A hot
   token touched in every chunk therefore costs H₁ + H₂ + … + Hₙ — quadratic in its own
   history — and, because the rebuild sits inside the chunk transaction, the observed
   watermark cannot advance until it finishes, so ingestion lag grows independently of RPC
   speed. The repeated DELETE/INSERT churn also costs WAL volume, dead tuples, and autovacuum
   pressure. This is a structural property of the function as written, not a hypothetical
   that "measure it first" can defer. Equivalence is therefore bought by test rather than by
   construction — see Task 3.
2. **Event ABI copy location and drift gate (Task 2).** The byte-identical copy of
   `contracts/abi/v1/**` lives at `backend/internal/chain/abi/v1/`, with Taskfile targets
   `event-abis-sync` and `event-abis-diff`, matching the `curve-vectors-sync` /
   `curve-vectors-diff` pair.
3. **Reorg identity — persisted (Task 4).** A durable `indexer_reorgs` table, not a
   process-local identifier. The detection record is persisted **before** the recovery
   transaction opens, so a rollback or rebuild that itself fails does not also lose its own
   audit record — which is exactly the incident an operator reads health after. This is the
   one piece of new schema Plan 2 adds (migration `00005`).
4. **Address-filter partition configuration (Task 2).** `INDEXER_LOG_ADDRESS_BATCH_SIZE`. Its
   default comes from Task 1's measurement, not from a guess.
5. **`RPC_URL` scheme allowlist — unchanged (Task 2).** `http`/`https` only. Head tracking
   polls; WebSocket reconnect and subscription lifecycle are error surface this plan does not
   need. A subscription may be added later as a *latency hint only* — never as a finality
   source, which stays the `safe`/`finalized` tag reads.
6. **Chain↔store type bridge — a neutral `internal/ledger` package (Tasks 3-4).** Canonical
   event input models live in a new `internal/ledger`, in persistence-independent types
   (`common.Address`, `common.Hash`, `*big.Int`, `time.Time`). The flow is
   `chain.DecodedLog` → Task 4's handler conversion → `ledger.*` → feature port → PostgreSQL
   adapter → `sqlc.Address` / `Hash` / `Uint256` / `pgtype`. Neither `chain` nor
   `store/postgres` imports the other, and no feature port carries a generated or
   persistence type. The `Uint256` conversion exists only inside the adapter — already
   CI-enforced, since `generated-sqlc-boundary` in `.golangci.yml` denies the `sqlc` package
   everywhere outside `internal/store/postgres`. The direction is also already enforced the
   other way: `chain-boundary` is `list-mode: strict`, so `internal/chain` cannot import
   `internal/ledger`, which is why the conversion is Task 4's handler and not a method on a
   `chain` type.
7. **Event insert results are typed (Task 3).** Event wrappers return
   `(ledger.InsertResult, error)` where `InsertResult` carries `Inserted bool` — including
   the two that exist today, `InsertTrade` and `InsertLaunchPauseEvent`, which are converted
   rather than left on a bare `error`. `UpsertIndexedBlock` is deliberately *not* forced onto
   the same type: it cannot separate a first insert from a finality promotion, and calling
   that `Inserted` would be a lie. It returns `UpsertResult{Changed bool}` instead.
8. **Incremental projection writes are SQL-side deltas (Task 3).** Each projection update is
   a single-statement `INSERT … ON CONFLICT … DO UPDATE`. There is no Go-side
   read-modify-write, which would be a lost-update race under any concurrency and would also
   be unable to satisfy `holder_balances_first_acquired_with_balance` — a plain
   non-deferrable CHECK that couples `balance` and `first_acquired_block_number`, and so
   requires both to move in one statement. The adapter orchestrates: it inspects the event
   insert result first and runs the projection statement only when `Inserted` is true. No
   wrapper opens a transaction; all of it runs inside the `WithinTx` boundary Task 4 owns.

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
- Those measurements set the defaults for `INDEXER_CHUNK_SIZE`,
  `INDEXER_LOG_ADDRESS_BATCH_SIZE`, the runtime finality configuration, and the health lag
  thresholds — each default traceable to a specific measured number rather than chosen by feel.
- A provider that cannot supply a usable `safe` tag stops this plan and is escalated as a
  launch blocker before Task 4 is designed. Falling back to a fixed confirmation count on a
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
- Only the probe half gates other work: Task 2 needs its measured defaults, and Task 3 needs
  nothing from this task at all. Only Task 5's testnet acceptance run depends on the manifest
  half, so a slow external deployment never blocks backend implementation.

## Task 2 — Chain access: event ABIs, decoding, and staged log discovery · Risk: high

**Delivers:** the whole of `internal/chain` — a single-sourced event ABI artifact set,
topic-to-typed-value decoders for all 18 event types, a typed RPC client over go-ethereum's
`ethclient` covering headers, code, and logs, the three finality head reads, the five-stage
per-chunk log discovery sequence with adaptive shrinking and address-filter partitioning, and
the two startup verification helpers spec §3.3 explicitly deferred to indexer startup.

**Depends on:** Task 1's probe half.

**Files:** `contracts/abi/v1/` (a new pair-event artifact), `backend/internal/chain/` (new
package: ABI registry, decoders, RPC client, head reads, log discovery, startup verification,
plus the byte-identical ABI copy), `backend/internal/config/` (the new indexer runtime
values), `backend/Taskfile.yml`, `.github/workflows/backend.yml` if the gate needs a path
trigger.

**Acceptance criteria:**

- Uniswap v2 `Mint`, `Burn`, `Swap`, and `Sync` gain a committed event-ABI artifact on the
  contracts side — the repo has none today, and `IUniswapV2Pair.sol` is a function-only
  interface. It is generated or transcribed once, reviewed, and then treated exactly like
  `ILaunchEvents.json`: authoritative, and never re-derived at decode time.
- `contracts/abi/v1/**` is copied byte-identical into `backend/internal/chain/abi/v1/` by
  `task event-abis-sync`, and `task event-abis-diff` fails on any difference, folded into
  `task verify` alongside the existing `curve-vectors-diff` and `deployments-diff` checks.
  The copy is never hand-edited.
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
- Chunk size (`INDEXER_CHUNK_SIZE`) and address-filter partition size
  (`INDEXER_LOG_ADDRESS_BATCH_SIZE`, new) come from configuration seeded by Task 1's
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
- The new configuration values — poll interval, RPC timeout and retry policy,
  `INDEXER_LOG_ADDRESS_BATCH_SIZE`, and the indexer worker identifier — are validated in
  `internal/config` under its existing stdlib-only, no-`os` constraint, with
  `RequireIndexer()` mirroring the existing `RequireAPI()`. `RPC_URL`'s scheme allowlist stays
  `http`/`https`: head tracking polls, and a WebSocket subscription is deliberately out of
  scope for this plan.
- Tests run against a fake RPC server, not a live provider, so the suite stays hermetic; the
  live provider is exercised only in Task 5's acceptance run.

## Task 3 — Store completion, incremental projections, and rollback SQL · Risk: high

**Delivers:** the persistence surface Backend Foundations deliberately left unbuilt because it
had no consumer — a `pgxpool` constructor, idempotent insert wrappers for the remaining 16
event tables, the transactional incremental projection writer that decision 1 locks as the
ingestion path, the differential test that proves it equivalent to
`rebuild_token_projections()`, and the reorg SQL whose parameter shape was left for its Plan 2
consumer to fix.

**Files:** `backend/internal/ledger/` (new), `backend/internal/store/postgres/` (pool
constructor, adapter methods, `queries/*.sql`, regenerated `sqlc/`),
`backend/internal/store/postgres/postgrestest/`, `backend/.golangci.yml`.

**Acceptance criteria:**

- A pool constructor returns the `*pgxpool.Pool` that `WithinTx` requires. `Open` returning
  `*sql.DB` stays as it is and remains the migration runner's entry point — the two are not
  merged, and the pool is never used to run migrations.
- Insert queries and idempotent adapter wrappers exist for the 16 event tables that lack
  them — §5.1 defines 18 event tables and only `trades` and `launch_pause_events` are
  covered today, `indexed_blocks` being the block ledger rather than an event table — each
  one copying the proven `trades` / `launch_pause_events` pattern verbatim in
  shape: `ON CONFLICT (chain_id, tx_hash, log_index) DO NOTHING`, re-read on conflict,
  compare every payload column, identical is silent success, different is
  `*InvariantConflictError` (spec §2.6). No wrapper opens, commits, or rolls back a
  transaction; each accepts sqlc's `DBTX`.
- `sqlc diff` is clean, and every new query's generated params struct is field-identical to
  the hand-written adapter type it converts from, so a future column reordering breaks the
  build rather than silently mismapping.
- Every idempotent insert wrapper **reports whether it actually inserted a row**, not just
  whether it errored: `(ledger.InsertResult, error)` per decision 7. Today's wrappers have
  the `:execrows` count in hand and discard it, returning bare `error` (`adapter.go`,
  `InsertTrade`). The incremental writer's correctness depends on that distinction, so it
  becomes part of the wrapper's signature rather than something a caller re-derives.
  `InsertTrade` and `InsertLaunchPauseEvent` are converted to the new signature in this task,
  not left inconsistent with the 16 new ones. `UpsertIndexedBlock` returns
  `ledger.UpsertResult{Changed bool}`.
- The incremental projection writer applies a change **only when the event insert genuinely
  added a row**. An idempotent conflict — the identical-payload replay path — must never
  apply a projection delta a second time. This is the single most likely way a replay after
  an ambiguous commit outcome (spec §2.4) silently corrupts a balance, and it is tested
  directly, not left to inspection.
- `holder_balances.first_acquired_block_number` follows spec §5.2 under incremental
  application: set on a `0 → nonzero` transition, left unchanged across nonzero-to-nonzero
  transfers, and reset to `NULL` when the balance returns to `0`. It is the field most likely
  to diverge from the SQL rebuild's windowed fold, so the differential test's coverage of it
  is explicit rather than incidental.
- `token_reserves` stays one latest-only row per token, and the incremental writer resolves
  "latest" by the same `(block_number, transaction_index, log_index)` ordering the rebuild
  uses, across both `reserve_source` legs — a `Trade`'s reserves for `'curve'`, a
  `pool_syncs` row's mapped through `tokens.token_is_token0` for `'pair'` (spec §5.2).
- A differential test proves the incremental writer and `rebuild_token_projections()` agree:
  the same canonical event sequence is driven through the incremental path; after each chunk,
  `tokens`, `token_reserves`, `holder_balances`, and `candles` are snapshotted; the rebuild is
  then run for the same token; and the two snapshots must be identical row-for-row in a
  deterministic order, nullable columns included. `aggregation_dirty.generation` is excluded
  from the comparison and asserted separately — it is drawn from a global sequence, so the
  two paths can never produce equal values, only equal dirtiness.
- That differential test covers, at minimum: different chunk boundary splits over the same
  event sequence; duplicate replay and ambiguous-commit repetition; graduation; post-graduation
  pair activity; and the ledger history that survives a reorg. Passing on one tidy sequence is
  not sufficient — the writer must agree with the oracle under the splits and repeats
  production will actually produce.
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
- `internal/ledger` exists and is **governed**, not merely created. `.golangci.yml` gains a
  strict `ledger-boundary` rule allowing `$gostd` and `github.com/ethereum/go-ethereum/common`
  and nothing else, so the package cannot quietly acquire `pgx`, `sqlc`, `internal/chain`,
  `ethclient`, or `internal/store/postgres`. Without this the one package whose entire purpose
  is to be neutral is the only package in the tree with no boundary enforcing it.
- Each `ledger.*` input model is cross-checked against **both** its `00003_event_ledger.sql`
  payload columns and the corresponding struct in `internal/chain/types.go` (Task 2, commit
  `fd5806c`), and any field present in one and absent from the other is justified in the
  package doc comment. Task 3 defines these types before Task 4 writes the conversion that
  consumes them; this check is what keeps that ordering from producing a rework, and it is
  cheap now that `internal/chain` already exists.
- The incremental writer applies transfers **one event at a time in canonical order**. No
  chunk-level netting of holder deltas: the aggregate is not equivalent, because
  `first_acquired_block_number` depends on the intermediate `0 → nonzero` crossings a netted
  delta erases.
- A projection delta that would drive `holder_balances.balance` below zero must surface as a
  typed invariant error naming the token, holder, and log coordinates — not as a raw
  `holder_balances_balance_nonnegative` CHECK violation. The abort is correct; an opaque
  constraint name at three in the morning is not.
- The incremental candle writer reproduces the rebuild's row-eligibility filter exactly. The
  oracle bounds its bucketing with `WHERE market.execution_price_wad IS NOT NULL`, and
  `execution_price_wad` is `trunc(eth_gross * 1e18 / NULLIF(token_amount, 0))` — so a fill
  with `token_amount = 0` contributes **no** candle row and **no** volume or `trade_count`.
  An incremental writer that skips this filter diverges from the oracle on exactly the input
  the oracle discards silently.
- Within a bucket the incremental writer sets `open_price_wad` **only on insert**, overwrites
  `close_price_wad` on every application, and takes `greatest`/`least` for high and low —
  correct only because events arrive in canonical `(block_number, transaction_index,
  log_index)` order, which the criterion states rather than assumes.
- The `bucket_start_time` expression has **one source of truth** shared by the incremental
  writer and `rebuild_token_projections()`. The `'5m'` case in particular is
  `date_trunc('hour', t) + floor(extract(minute FROM t) / 5) * interval '5 minutes'`, not
  anything that merely looks equivalent. Either both paths call one `IMMUTABLE` SQL helper, or
  the duplication is backed by an equivalence test over timestamps that sit exactly on and
  either side of `1m`/`5m`/`1h`/`1d` bucket edges. Codex picks the mechanism; an unproven
  second copy of the expression is not an option.
- For the `dex` leg, the incremental writer selects the pairing `Sync` the way
  `market_trades` does: the nearest **preceding** `pool_syncs` row *in the same transaction*
  with a lower `log_index` (`ORDER BY sync.log_index DESC LIMIT 1`), not the pair's latest
  sync. A multi-hop transaction containing two swaps, each with its own preceding sync, must
  therefore price each swap against its own sync — and that transaction is part of the
  differential test's pair-activity scenario. Note also that the lateral join is inner: a swap
  with no preceding same-transaction sync vanishes from `market_trades` entirely, so the
  incremental path must drop it too rather than write a candle the rebuild will delete.
- Chunk boundaries are **block** boundaries, so every log of a block — and therefore every log
  of a transaction — is applied inside one `WithinTx`. The writer may rely on this for the
  same-transaction sync lookup above, and on the `DEFERRABLE INITIALLY DEFERRED` FK from
  `holder_balances` to `tokens` for the constructor's `Transfer(0x0, curve, S)`, which legally
  precedes the `TokenLaunched` that creates the `tokens` row. A test covers that pair landing
  in a single transaction.
- The differential test's four chunk-split arrangements are not free choices: at least one
  must place a boundary **inside** a `1m` candle bucket (two trades in one bucket, split
  across two chunks), and at least one must split a token's transfer history across chunks
  while a holder balance is mid-flight between zero crossings. Four splits that all fall on
  quiet boundaries prove nothing about the incremental path.
- Test budget: a single differential scenario runs at most 24 events, four chunk-split
  arrangements, and at most 32 oracle rebuild calls. The cap bounds one scenario, **not** the
  scenario list — if a named scenario above cannot be expressed within it, the scenario is
  split into a second fixture and the cap holds per fixture. Coverage does not yield to the
  budget.
- Snapshot comparison reads the values actually stored in PostgreSQL and compares those. No
  test-side truncation or rounding is applied, `block_time` included — a comparison that
  normalises before comparing cannot detect the precision loss it normalises away.
- The conflict-path test covers **all 18** event wrappers, not only the 16 added here. The two
  that exist today change signature in this task, which re-exposes their column mapping to
  exactly the mistake the conflict path is meant to catch.
- The pool constructor defaults to 8 connections with an accepted minimum of 4, and its doc
  comment states plainly that the indexer's session advisory lock holds one connection for the
  process's entire lifetime — so the usable pool is one smaller than its configured size, and
  a minimum of 4 means 3 in practice.

## Task 4 — Indexer core: ownership, chunk loop, routing, and reorg replay · Risk: high

**Delivers:** `internal/indexer` — singleton ownership, watermark management, the chunk loop
that turns one processed range into one transaction, two-pass processing, the
`chain.DecodedLog` → `ledger.*` conversion decision 6 places here (Task 3 defines the target
types; `chain-boundary`'s strict allowlist forbids `internal/chain` from doing it itself),
routing of every decoded event to a feature ingestion handler through ports defined where
they are consumed,
and the reorg path: parent-hash verification, the walk to the common ancestor, the
single-transaction rollback and rebuild, and the finality boundary at which the indexer stops
instead of recovering.

**Depends on:** Tasks 2 and 3.

**Files:** `backend/internal/indexer/` (new), `backend/internal/launch/`,
`backend/internal/trading/`, `backend/internal/holder/`, `backend/internal/token/` (ingestion
ports and handlers), `backend/internal/store/postgres/` (port implementations),
`backend/internal/store/postgres/migrations/00005_indexer_reorgs.sql` (new),
`backend/internal/store/postgres/postgrestest/`.

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
- Before extending the observed chain, the new header's parent hash is verified against the
  stored tip. On mismatch the indexer walks stored block hashes and RPC headers backward to
  the common ancestor; the walk terminates when no stored row matches a given hash, which is
  the correct "beyond the tracked range" signal, not a NULL sentinel (spec §4.2, §5.1).
- Rollback and rebuild happen in **one** transaction, in this order: canonical event rows
  above the ancestor are deleted, then block-ledger rows above it, then affected token
  projections are rebuilt from surviving canonical events, then every affected watermark is
  reset. A partial rollback is never committed (spec §4.2).
- Rebuild is a full recompute of an affected token's projections from its complete surviving
  event history via `rebuild_token_projections()`, never an incremental undo — the failure
  path is the worst place to run the more failure-prone algorithm (spec §5.2). This is the
  primitive's purpose; it is deliberately not the ingestion path (decision 1).
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
- Migration `00005` adds a durable `indexer_reorgs` table — the only new schema in this plan.
  The detection record is written and **committed before the recovery transaction opens**, so
  a rollback or rebuild that itself fails cannot also erase its own audit record. Each row
  carries enough to reconstruct the incident without the logs: chain and deployment, the
  detected tip and the common ancestor, the resulting depth, detection time, and an outcome
  that distinguishes recovered from still-open. A row left un-outcomed after a restart is a
  signal an operator must see, not a bug in the writer.
- Migrations still run up/down/up cleanly with the new file, and `sqlc diff` stays clean.
- Tests cover a shallow reorg above the safe head, a deep multi-block reorg, a reorg whose
  ancestor lies at the safe boundary, and finality promotion — four of the seven indexer
  dimensions spec §11 names, with the remaining three covered by Tasks 2 and 5.

## Task 5 — Aggregation, runtime, observability, and verification gate · Risk: high

**Delivers:** the rest of the running process — the durable dirty-work loop with its
crashed-worker recovery, the computation of `token_stats`, `protocol_daily`, and
`protocol_stats`, the periodic reconciliation sweep, `cmd/indexer` itself, the health and
logging surface spec §12 mandates, an Anvil-backed end-to-end test covering every indexer
dimension spec §11 names, and the real Robinhood testnet acceptance run that closes this
milestone.

**Depends on:** Tasks 1 and 4.

**Files:** `backend/internal/candle/`, `backend/internal/stats/`, `backend/internal/indexer/`
(worker orchestration), `backend/internal/store/postgres/`, `backend/cmd/indexer/` (new),
`backend/Taskfile.yml`, `.github/workflows/backend.yml`.

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
- Candles use `execution_price_wad`, never `spot_price_wad`; `6h` and `all` are computed on
  read from the stored `1h`/`1d` rows and are never stored (spec §5.3, §5.5). Live candle
  rows are written by Task 3's incremental writer during ingestion; this task's reconciliation
  sweep repairs them through `rebuild_token_projections()` rather than reimplementing the
  recomputation.
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
  canonical ledger, projections, and aggregates that result. Together with Tasks 2 and 4 it
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
