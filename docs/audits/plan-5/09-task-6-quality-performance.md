# Plan 5 Task 6 — Code Quality, Architecture, and Performance Audit

## Result

The implementation target is immutable commit `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`.
Two findings are validated: the aggregation worker can expose an empty `protocol_daily` table
during a refresh, and the aggregation worker interface/configuration contains dead or disconnected
elements. A price-change integer-overflow risk remains an unvalidated candidate because the
required 24-hour move was not established from representative chain activity. One static
performance opportunity remains unmeasured and is not a validated finding.
No product, test, generated, dependency, migration, workflow, or runtime-configuration file was
changed. `backlog.md` remains unchanged with exactly two Active items.

| Disposition | Count |
| --- | ---: |
| Validated findings | 2 |
| Rejected/suppressed hypotheses | 0 |
| Unvalidated correctness/availability candidates | 1 |
| Static optimization candidates not validated by measurement | 1 |
| Measured performance findings | 0 |

This is not a production-readiness assessment. The findings concern repository behavior at the
baseline; production traffic, topology, and service budgets remain unknown.

## Scope and method

The baseline resolves to the recorded merge commit. `git diff --name-only 6184bc5..HEAD` contains
only later policy/audit documentation and `SECURITY.md`; no implementation path differs from the
baseline. The working tree already contained later audit documentation changes and reports for
Tasks 2–4. They were left untouched. Scope was derived from the Plan 5 Task 6 requirements and
Task 1's ownership ledger, exclusions, harness, and reportability policy. The threat model and
prior Task 2, Task 3, and Task 4 reports were read first; their findings are cross-referenced below
where relevant.

Bounded checks performed on Windows:

| Check | Result |
| --- | --- |
| `git show -s --format=fuller 6184bc5...` and source-path comparison with `HEAD` | Baseline resolved; no product-code drift from the target. |
| `go list -f '{{.ImportPath}}|{{join .Imports ","}}' ./...` in `backend/` with `GOPROXY=off` and workspace-local `GOCACHE` | Passed; package imports enumerated, no import cycle reported. Go emitted the same telemetry upload-token `Access is denied` warning noted by earlier audit runs. |
| `go test -cover ./internal/stats` in `backend/` with `GOPROXY=off` and workspace-local `GOCACHE` | Passed; 61.6% statement coverage for the package. |
| Repository searches for `Benchmark`, `Poll`, `DefaultClaimLease`, `ComputeTokenStats`, aggregation refresh call sites, and relevant integration tests | Completed; results are described below. |
| Immutable-baseline review of the price-change SQL/cast, projection DDL, trade-to-candle path, Go mirror, worker error handling, and nearby tests | The `INTEGER` overflow path and absent schema bound are source-confirmed; no PostgreSQL execution or representative chain price trace was available, so it is reported as an unvalidated candidate. |
| Database, browser, full release, and cross-stack gates | Not run; no isolated database was used, and these broad gates are outside this bounded check. |

The Go test used the ignored `backend/.cache/go-build` path. No tracked file was produced by a
check. No network, production credential, private endpoint, or live database was used.

## Ownership and architecture map

Task 6's primary-owned implementation surface is `backend/internal/stats/`; other directories
remain with their ledger owner and were cross-reviewed only for dependency direction, duplication,
resource lifecycle, and aggregation cost.

The complete Task 6-owned file inventory is `backend/internal/stats/calculator.go`,
`calculator_test.go`, `public.go`, and `worker.go`. All four were reviewed: the calculator and
its tests for aliasing and rule parity, `public.go` for domain/read-port ownership, and `worker.go`
for claim, cancellation, retry, and lifecycle behavior. The two worker-contract findings below
refer to `worker.go` and its Postgres adapter.

| Surface | Observed dependency direction | Task 6 disposition |
| --- | --- | --- |
| `contracts/src/` | Solidity domain modules import their local interfaces, types, storage, libraries, and pinned OpenZeppelin types. The Go curve package is a deterministic mirror, with vectors as the shared evidence boundary. | Task 2 owns contract behavior and economics. No new cross-language mismatch was established; fresh Forge compilation/gas measurement remains unavailable as recorded in Task 2. |
| `backend/cmd/api/`, `cmd/indexer/`, `cmd/migrate/` | Composition roots assemble config, API/indexer services, and the Postgres adapter. Runtime modules are not assembled from generated SQLC models at the command layer. | Expected inward composition boundary; Task 3/4/7 retain their primary behavior and release ownership. |
| `backend/internal/{token,trading,candle,holder,metadata,profile,observation,pagination,realtime,stats,ledger}/` | Domain DTOs and ports do not import `internal/store/postgres` or `internal/store/postgres/sqlc`. `stats` imports `pagination`, `math/big`, time, and go-ethereum address types. | Clean application boundary. No persistence/generated type leakage found. `internal/curve` and `internal/config` remain standard-library-only, matching repository policy. |
| `backend/internal/apiserver/` and `internal/quote/` | API handlers depend on domain ports, auth, quote/curve services, and HTTP libraries. `quote` depends on `curve` and `token`, not persistence. | Task 4 owns API semantics. No API-to-Postgres or API-to-SQLC import was found. |
| `backend/internal/chain/` and `internal/indexer/` | `indexer` depends on chain and ledger representations; it does not import the Postgres implementation. | Task 3 owns ingestion and reorg semantics. The adapter direction remains one-way. |
| `backend/internal/store/postgres/` | The Postgres adapter depends on domain ports/events, selected indexer-owned transaction/reorg types, and generated SQLC types. SQLC types are contained inside this adapter package. | The adapter's dependency on domain-owned port/data types is the expected hexagonal implementation exception. The generated SQLC boundary is contained; no higher-level package imports SQLC directly. |
| `backend/internal/stats/` and `store/postgres/aggregation_source.go` | `stats.Worker` owns a storage-neutral queue contract; `AggregationSource` implements it and the command root wires it to the pool. | Primary Task 6 ownership. Findings P5-T6-001 and P5-T6-002 and candidate P5-T6-CAND-001 below. |
| `web/app/` and `web/src/` | App routes compose feature components. API clients consume generated OpenAPI types; wallet consumers use generated ABI/deployment artifacts. Browser-only components are marked as client modules. | Task 5 owns browser behavior. Chart cleanup was inspected for leaks; no performance claim was made without browser profiling. Generated artifacts remain Task 7's provenance responsibility. |
| Generated, vendored, and release surfaces | SQLC, OpenAPI, ABI/vector copies, `contracts/lib/`, npm/Go manifests, and release scripts have separate ownership in the ledger. | Not treated as first-party implementation for this code-quality pass. Dependency-advisory, lockfile, provenance, and release-script audits remain Task 7. |

The Go package graph has no reported cycles. The principal boundaries are consistent: command
packages compose services; application packages speak through ports; the Postgres adapter owns
storage-specific conversion and SQLC access; and generated web types remain at the API/wallet
edges. The Postgres adapter's large `adapter.go` file and the API route files were reviewed by
responsibility, not reported on line count alone; no concrete maintenance failure from file size
was established.

## Validated findings

### P5-T6-001 — Protocol aggregate refresh can expose an empty daily table

- State: validated finding
- Severity: Low
- Confidence: high for the reachable code path; visibility duration is unmeasured
- Primary audit task: Task 6, with Task 3 database and Task 4 read-boundary cross-review
- Affected asset/surface: indexer aggregation worker, Postgres protocol aggregate refresh, and
  `GET /v1/stats/protocol/daily`
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Actor and prerequisites: no attacker. A normal dirty-token claim and a concurrent protocol-
  daily API read are sufficient.
- Failure path: `backend/cmd/indexer/main.go:125` constructs `AggregationSource` with
  `storepostgres.NewAdapter(pool)`. `AggregationSource.Compute` first recomputes per-token stats,
  then calls `RecomputeProtocolAggregates` (`backend/internal/store/postgres/aggregation_source.go:32-37`).
  That method runs `ClearProtocolDaily`, `RecomputeProtocolDaily`, and
  `RecomputeProtocolStats` sequentially (`backend/internal/store/postgres/adapter.go:746-756`).
  On this worker path the adapter wraps a `pgxpool.Pool`, not a transaction, so each statement
  commits independently. The first SQL statement deletes the chain's daily rows
  (`backend/internal/store/postgres/queries/projections.sql:258-259`); the next statement only
  restores them after aggregating source events (`:261-274`). A reader starting after the delete
  commit and before the insert commit sees no daily rows. The public reader uses its own
  repeatable-read snapshot (`backend/internal/store/postgres/public_reads.go:245-278` and
  `read_adapter.go:331-352`); that snapshot makes an individual read consistent but does not
  make the background refresh atomic.
- Impact: users can briefly receive an empty daily analytics result while canonical events remain
  present. A failure after the delete also leaves the empty result until a later successful retry.
  No trade, reserve, or authorization state is changed.
- Counterevidence and assumptions: dirty claims are retried after their lease expires when
  computation fails; the indexer logs aggregation failures and continues. The reorg path can call
  `RecomputeProtocolAggregates` within its existing encompassing transaction, so this finding is
  specific to the background worker's pool-backed call path. The Task 3 report's reorg transaction
  review is therefore not duplicated. No production traffic or duration was measured.
- Proof method: source-backed call-chain and autocommit proof; no database was contacted. Existing
  `postgrestest` coverage contains no test for `RecomputeProtocolAggregates` atomic visibility or
  rollback after the delete.
- Proposed remediation: execute the three protocol aggregate statements within one explicit
  transaction on the worker path, retaining the old committed rows until the full refresh commits.
- Required regression test: use two database sessions to pause after the delete within a refresh
  and prove readers still see the prior committed daily rows; inject an error before commit and
  assert those rows remain. After commit, assert both daily and summary aggregates reflect the same
  rebuilt event set.
- Disposition/owner: validated; Task 8 must decide and verify a minimal fix with Task 3 and Task 4
  owners. No source change is authorized by this audit.
- Related findings: distinct from Task 3 P5-T3-004, which defers reorg range query-plan measurement,
  and Task 4's endpoint-contract findings.

### P5-T6-002 — Aggregation worker declares unused polling and lease controls

- State: validated finding
- Severity: MINOR
- Confidence: high
- Primary audit task: Task 6
- Affected asset/surface: `backend/internal/stats/worker.go`,
  `backend/internal/store/postgres/aggregation_source.go`, and the Task 3-owned claim query at
  `backend/internal/store/postgres/queries/projections.sql:111-129`
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Actor and prerequisites: maintainers changing the worker contract or expecting the declared
  lease value to control PostgreSQL claim expiry.
- Evidence and path: `DirtySource` requires both `Poll` and `Claim` (`worker.go:16-21`), but
  `Worker.Run`/`drain` use `Claim` only (`:34-74`). The only `Poll` implementation is a no-op that
  returns `(nil, nil)` (`aggregation_source.go:15`), and no call site invokes it. Similarly,
  `DefaultClaimLease` is declared as 30 seconds (`worker.go:9`) but has no consumer; the actual
  lease is independently hard-coded as `interval '30 seconds'` in the SQL claim query
  (`backend/internal/store/postgres/queries/projections.sql:111-129`). These declarations create
  an inaccurate worker API and a duplicate setting that can drift without changing runtime
  behavior.
- Impact: no current processing failure was established—the worker polls the durable SQL claim
  query on its ticker, and the constant currently matches the SQL literal. The concrete cost is
  dead interface/configuration surface and a silent mismatch risk for later changes or
  implementations.
- Counterevidence and assumptions: a global durable queue may be intentional; no chain-specific
  fairness or isolation defect is claimed. The configured `AggregationSource.ChainID` is also not
  read by the adapter, while claims carry their database chain ID; whether claims should be
  chain-filtered depends on the deployment/database topology and remains an unvalidated question.
- Proof method: repository-wide reference search plus direct control-flow inspection; the scoped
  `go test -cover ./internal/stats` passed, but there are no worker tests.
- Proposed remediation: remove the unused `Poll` contract and no-op implementation; either remove
  `DefaultClaimLease` or pass one lease value into SQL. Resolve whether `AggregationSource.ChainID`
  is intentional global-queue metadata before removing it or using it as a filter.
- Required regression test: add a fake `DirtySource` worker test for claim/drain/error/retry and
  cancellation behavior; if lease configurability is retained, integration-test that the configured
  lease is the SQL expiry value. Add a multi-chain queue test only if the operator model requires
  per-chain isolation.
- Disposition/owner: validated maintenance finding; Task 8 to triage the smallest safe cleanup.
- Related findings and cross-task references: Task 3 owns the SQL query's data/claim semantics;
  see the [Task 3 report](06-task-3-indexer-data.md), including its separate deferred query-plan
  measurement P5-T3-004. This finding concerns the unused Go lease declaration and no-op worker
  contract, not the query-plan question.

## Unvalidated correctness and availability candidates

### P5-T6-CAND-001 — 24-hour price-change conversion may overflow PostgreSQL INTEGER

- State: unvalidated correctness/availability candidate; not counted as a validated finding
- Severity/priority: unknown and not assigned; production reachability and affected-service budget
  are unestablished
- Confidence: high that an out-of-range computed result raises a PostgreSQL cast error; low that
  the required ratio occurs in representative chain activity
- Primary audit task: Task 6 for the derived-statistics failure path; Task 3 owns the primary SQL,
  schema, and database execution semantics
- Affected asset/surface: `backend/internal/store/postgres/queries/projections.sql:245`,
  `backend/internal/store/postgres/migrations/00004_chain_projections.sql:198-235`,
  `backend/internal/store/postgres/queries/read.sql:108`,
  `backend/internal/store/postgres/aggregation_source.go:32-37`,
  `backend/internal/stats/worker.go:57-69`, `backend/internal/stats/calculator.go:37-42,95-105`,
  `backend/internal/token/ports.go:66`, and `backend/internal/apiserver/public_routes.go:78`
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Actor, trigger, and prerequisites: no attacker is required. A normal indexed trade updates the
  latest candle; failure requires a positive baseline candle at or before the 24-hour cutoff and a
  latest close whose truncated basis-point change exceeds the signed 32-bit `INTEGER` maximum.
  Whether that ratio occurs in realistic Robinhood Chain activity is unknown.
- Source-to-sink and impact: `RecomputeTokenStats` selects `baseline_price` and `latest_price`,
  then computes `trunc((latest_price - baseline_price) * 10000 / baseline_price)::INTEGER`.
  For a positive baseline, the cast exceeds `INTEGER` when the truncated value is at least
  2,147,483,648, which corresponds to a relative increase of 214,748.3648× (a final
  latest/baseline ratio of 214,749.3648). The `candles` close-price columns are `NUMERIC(78,0)`
  and only have nonnegative checks; the destination `token_stats.price_change_24h_bps` is
  `INTEGER`. If this SQL path receives such values, PostgreSQL raises an out-of-range error and
  the per-token stats statement does not update. `AggregationSource.Compute` returns before
  protocol aggregates are rebuilt for that claim. `Worker.drain` reports the compute error,
  leaves the claim incomplete, and the lease makes it eligible for retry after 30 seconds;
  retries do not correct an out-of-range result. Existing stats can remain stale, or the row can
  remain absent.
- Nearest controls: numeric source fields have a wide 78-digit precision and candle prices have
  no magnitude or ratio bound. The Go mirror stores `PriceChange24hBPS` as `int64`, so it does
  not enforce the SQL `INTEGER` limit, while the Postgres read query, token port, and API DTO
  currently expose `int32`. The worker's lease allows retry but cannot resolve a deterministic
  cast overflow.
- Counterevidence and assumptions: the required approximately 214,749-fold final-price/baseline
  ratio is extreme, and fixed supply, pool reserves, trading costs, and actual available capital
  constrain market paths. No representative trade history or feasible maximum 24-hour ratio was
  established. A database-only fixture can demonstrate the type mismatch but would not prove
  realistic on-chain reachability, so this is not reported as a validated defect.
- Proof gaps: no isolated PostgreSQL instance was available to execute the failing cast; no
  canonical trade trace or contract/pool-bound analysis establishes the maximum reachable ratio;
  the existing SQL integration and Go unit cases exercise ordinary/small basis-point values, not
  this positive overflow boundary; no production distribution or API freshness target is available.
  These are unknown, not proof that overflow is unreachable.
- Remediation direction: choose and document a supported domain range before changing types.
  If values above `INTEGER` are valid, widen the database, read query, token port, API DTO, and
  API schema/client contract consistently to a bounded representation; if selecting
  `BIGINT`/`int64`, also check the calculator's `big.Int` conversion against that range. If larger
  values must be representable, use a compatible wider/decimal representation. If the product
  intends a narrower range, apply the same explicit checked or saturating rule in SQL and Go
  rather than relying on a narrowing cast.
- Required boundary test: in the Postgres integration suite, insert a positive 24-hour baseline
  close and latest close with a value just inside the `INTEGER` bps limit and one just outside;
  call `RecomputeTokenStats` and assert the selected domain policy plus parity with
  `ComputeTokenStats`. With baseline `1`, latest `214749` produces `2,147,480,000` bps and fits,
  while latest `214750` produces `2,147,490,000` and exceeds `INTEGER`. Add a worker-path check
  that verifies a rejected range cannot silently leave a claim permanently hot without an
  observable error/repair path.
- Disposition/owner: unvalidated candidate; Task 8 to triage the range policy, with Task 3
  reviewing the SQL/schema/API boundary. Do not count it as a validated finding until reachable
  event inputs and the database failure behavior are demonstrated.
- Related ownership and cross-task evidence: Task 3 owns the query/schema and database behavior;
  see the [Task 3 report](06-task-3-indexer-data.md) for the prior database-environment limitation.
  Task 4 owns the public API contract; its `int32` DTO surface is listed only to show the scope of
  any future range-policy change.

## Optimization evidence and candidates

No representative performance result meets the policy bar for a measured optimization finding.
The static queue path does expose one algorithmic opportunity:

### P5-T6-OPT-001 — Full protocol aggregates are recomputed once per dirty token

- State: candidate; unmeasured static optimization opportunity, not a validated performance
  finding
- Severity/priority: unknown and not assigned; material impact and target budget are unmeasured
- Confidence: medium (the repeated call path is source-certain; production impact is unknown)
- Primary audit task: Task 6; Task 3 owns the Postgres query semantics and plans
- Affected asset/surface: `backend/internal/stats/worker.go`,
  `backend/internal/store/postgres/aggregation_source.go`,
  `backend/internal/store/postgres/adapter.go`, and
  `backend/internal/store/postgres/queries/projections.sql:258-294`
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Actor/trigger/prerequisites: no attacker. A running indexer processing at least one dirty-token
  claim triggers the path; a full batch of 32 exposes the maximum repeated-query count per drain.
  Production token/event cardinality is unknown.
- Source-to-sink: `Worker.drain` processes claims sequentially
  (`backend/internal/stats/worker.go:57-74`), with batch size 32 configured in
  `backend/cmd/indexer/main.go:125`. For every claim, `AggregationSource.Compute` issues one
  token-scoped recomputation and then runs all three chain-scoped protocol statements
  (`backend/internal/store/postgres/aggregation_source.go:32-37`). One full batch can therefore
  issue 96 protocol-wide SQL statements (clear daily rows, rebuild daily groups, and rebuild
  protocol totals, repeated 32 times) in addition to 32 token-stat recomputations. The protocol
  rebuild queries do not depend on the token claim; they aggregate chain-wide event tables
  (`backend/internal/store/postgres/queries/projections.sql:261-294`). The sink is repeated database reads/writes and associated round
  trips for the same chain-wide aggregates.
- Impact: unknown. The source proves repeated work, but not material latency, lock contention,
  worker backlog, stale analytics, or resource exhaustion at production cardinality.
- Nearest controls: each drain is bounded to 32 claims and the durable dirty queue/lease permits
  retry. These controls bound a single batch but do not establish an execution-time or freshness
  budget. No query-cost control specific to the repeated chain-wide rebuild was found.
- Counterevidence: no dataset or plan shows that the repeated statements are expensive; small
  event tables, cached pages, or planner choices may make the work immaterial. The 32-claim batch
  bounds the repeated statement count per drain.
- Proof gaps: no representative event/token/candle/dirty-queue cardinality, isolated database,
  query plan, warm-up/sample method, median/tail/variance, aggregation freshness target, or
  semantic-equivalence execution is available. Those fields are unknown, not zero.
- Remediation direction: if representative measurements show material cost, evaluate moving the
  chain-wide rebuild out of the per-token method and running it once per drained batch or on a
  separately bounded refresh schedule. Preserve token freshness, generation/lease retry behavior,
  reorg consistency, and equivalence to the current full recomputation. Do not change the worker
  based on the static count alone.
- Required regression/equivalence test: compare protocol daily and summary rows from a
  once-per-batch rebuild against the current full recomputation for the same canonical event set;
  prove generation changes, failed claims, and reorg refreshes remain recoverable.
- Disposition/owner: unvalidated optimization candidate. Task 6 owns representative workload and
  before/after measurements; Task 3 owns query semantics and database-plan evidence. See the
  [Task 3 report](06-task-3-indexer-data.md) for the separate P5-T3-004 reorg query-plan deferral.

| Required performance evidence | Status |
| --- | --- |
| Workload and data cardinality | Unknown; no representative event, token, candle, or dirty-queue dataset was supplied. |
| Environment and warm-up/sample method | Not run; no isolated PostgreSQL instance or production-like fixture was used. |
| Baseline median/tail/variance | Not measured. The 96-command batch shape is source-derived, not a duration. |
| Target or budget | Unknown; no aggregation latency or freshness SLO was supplied. |
| Semantic-equivalence test | Not run. Any future batch-coalescing must compare daily/protocol aggregates against the existing full recomputation and preserve generation/lease retry behavior. |

Disposition: unvalidated static optimization candidate. Do not change the worker based on this
count alone. Measure a cardinality-controlled workload, including ingest overhead and freshness
targets, then compare per-token and once-per-batch protocol rollups with semantic equivalence.

## Test design, drift, and boundary notes

- The Task 6-owned stats package has two calculator tests in `calculator_test.go`; the 61.6%
  package statement coverage includes no `Worker.Run` or `Worker.drain` tests. No Go benchmark or
  profile for the stats worker/calculator was found.
- `TestRecomputeTokenStatsUsesCanonicalSupplyAndCandleHistory`
  (`backend/internal/store/postgres/postgrestest/token_stats_integration_test.go:16`) uses
  `stats.ComputeTokenStats` as a differential oracle for SQL `RecomputeTokenStats`. This
  duplication is deliberate and provides a useful cross-implementation check; one fixture is not
  exhaustive boundary coverage, but no currently reachable formula divergence was established.
  The integration test was inspected, not executed in this task.
- No Postgres test calls `RecomputeProtocolAggregates`; the observed non-atomic visibility path is
  therefore missing a direct database regression test. Task 3 previously reports no isolated
  database runtime for its integration suite, and that limitation applies here.
- `read_adapter.go:137-140` uses named-field reflection to normalize generated row structs for
  token-card orderings. It is a static coupling to generated field names, not a positional
  conversion. Current generated row types contain the names used by the adapter; no current
  runtime failure or material per-page cost was demonstrated. Do not replace it solely for style;
  keep its compatibility covered if SQLC output shape changes.
- `MarketChart` disconnects its `ResizeObserver` and calls `chart.remove()` during effect cleanup
  (`web/src/token/market-chart.tsx:86-99`), so no chart-resource leak was established. Its
  full-series initialization is keyed by mode and point count while later updates change only the
  last point (`:99-114`). A same-length historical candle correction may therefore need a Task 5
  canonical-UI review; it is not counted here as a Task 6 finding.
- Task 3 P5-T3-002 already owns the idle indexer notification/SSE amplification candidate, and
  P5-T3-004 owns unmeasured reorg range query plans. Task 4 P5-T4-002 owns API SSE shutdown
  cancellation. Those are not duplicated here.
- Dependency vulnerability, version/provenance, and lockfile reviews remain Task 7-owned; this
  task checked package-layer direction only. `internal/config` and `internal/curve` have no
  non-standard direct imports in the enumerated Go graph.

## Performance budgets and limits

`web/performance-budgets.json:15-23` sets synthetic navigation limits of 5.0 seconds for the
small-laptop profile and 5.5 seconds for mobile, plus 4,000,000 transferred bytes and 1,800,000
initial JavaScript bytes for each. Task 1 recorded a passing `verify:bundle` invocation with
43,708 initial bytes, 7,355,145 bytes across routes, and a 607-byte largest manifest
(`docs/audits/plan-5/00-baseline-provenance.md:121`). That is a single warm-cache artifact check,
not a user-latency distribution, route-render profile, or calibrated CI SLO. The limits are
therefore recorded but not accepted as validated product-performance targets.

Other required measurements are unavailable: no representative indexer throughput/allocation
profile, RPC round-trip distribution, PostgreSQL query plan/lock profile, projection or aggregation
rebuild duration, API concurrency/latency, SSE fan-out load, or client render profile was collected.
Task 3's prior report records the absent isolated PostgreSQL runtime and unmeasured production
cardinality. Task 2 records that fresh Forge compilation/gas results were unavailable on its host;
its committed bytecode-size artifact is not a new Task 6 measurement. Release-gate durations in
the Task 1 provenance are single-run host observations, not CI medians or a release-time budget.

## Limitations and backlog

This report is static source review plus one bounded Go package test and import-graph check. It does
not establish production topology, real traffic/cardinality, user-facing latency, PostgreSQL
plans, external dependency risk, production resource limits, or production readiness. No
production credentials, RPC, database, browser session, Forge compiler, or release target was used.

The repository backlog remains exactly two Active items, unchanged:

1. Robinhood testnet deployment manifest.
2. Production release, governance, and audit inputs.

No additional backlog item was added. No commit or push was made.
