# Plan 5 Task 3 — Indexer and Canonical Data Audit

## Scope and method

- Immutable product baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`.
- The current implementation paths reviewed below compare unchanged with that baseline; the
  post-baseline difference is the Plan 5 audit documentation, not product code.
- Scope follows Task 1 ownership rows for `backend/cmd/indexer/`, the Task 3 cross-review of
  `backend/cmd/migrate/`, non-generated `backend/internal/chain/*.go`,
  `backend/internal/indexer/`, `backend/internal/ledger/`, `backend/internal/holder/`, and
  `backend/internal/store/postgres/` including migrations, queries, and `postgrestest/`.
- Cross-review boundaries: configuration validation (Task 4 primary), deployment inputs and
  generated ABI/sqlc outputs/migration invocation (Task 7 primary), read/API notification
  consumers (Task 4 primary), and aggregation cost (Task 6 primary).
- Source evidence is line-numbered against the unchanged baseline paths. The exact conflict,
  projection, ownership, migration, and reorg integration tests were inspected; local unit tests
  and integration-test compilation were run as recorded below.
- Plan/spec citations are current audit context, not implementation evidence from immutable
  baseline `6184bc5`.
- No network, public/private RPC, endpoint credentials, production database, or local PostgreSQL
  service was used. No implementation or generated file was changed.

## Result

Two validated correctness findings are recorded. One notification-path candidate remains
unvalidated for material impact. Two items are deferred: documented recovery after a reorg deeper
than the bounded search, and production-cardinality query-plan measurement. No other reviewed
candidate met the Plan 5 reportability bar. The backlog was not modified; its two Active items
remain unchanged.

## Findings

## [P5-T3-001] Indexer does not bind the configured chain to the RPC network

- State: validated finding
- Severity: Medium
- Confidence: high
- Primary audit task: Task 3
- Affected asset/surface: `backend/cmd/indexer/` and `backend/internal/chain/` RPC ingestion,
  Task 3 ownership-ledger rows; `backend/internal/config/` is Task 4 primary.
- Baseline: 6184bc5febd43de99ab6cc2b6f71f7f90c878bb6
- Attacker/failure actor and prerequisites: Operator misconfiguration, stale/incorrect RPC URL,
  or RPC provider serving a different chain; the actor need not control PostgreSQL. This does not
  assume an attacker can change environment variables or that `eth_chainId` defeats a malicious
  provider that lies about its response.
- Source-to-sink or failure path: `config.Load` validates that `CHAIN_ID` is positive and
  `RPC_URL` is an HTTP(S) URL (`backend/internal/config/config.go:87-121`) but does not compare
  the endpoint's chain ID. `cmd/indexer.run` resolves a deployment from configured chain ID at
  `backend/cmd/indexer/main.go:36-43`, dials the configured URL at `:46-50`, then opens the
  database and acquires writer ownership at `:51-60`. `chain.Client` wraps JSON-RPC and exposes
  header/log/code calls but no `eth_chainId` validation (`backend/internal/chain/rpc.go:26-42,
  50-79, 115-142`). The engine labels returned headers/events with its configured chain ID
  (`backend/internal/indexer/engine.go:262-267`) and commits them under that chain ID
  (`:215-231`). A URL for another network can therefore feed headers and matching-address logs
  into the configured network's canonical rows; the existing hash/link checks only establish
  internal consistency of the endpoint's returned chain.
- Exact evidence: `backend/internal/config/config.go:87-121`; `backend/cmd/indexer/main.go:36-60`;
  `backend/internal/chain/rpc.go:26-42,50-79`; `backend/internal/indexer/engine.go:143-168,215-231,262-267`.
  The RPC fake tests cover heads, unsupported finality, retries, code/log/header calls and
  capacity classification, but not endpoint identity (`backend/internal/chain/rpc_test.go:26-145`).
- Impact: Canonical rows can be attributed to the wrong configured chain and then drive
  projections, holders, quotes, observations, and API finality. This is an integrity and
  operational correctness failure, not a demonstrated direct asset-loss path. A wrong network
  with no matching emitter addresses may yield no deployment events, but that does not establish
  endpoint identity.
- Counterevidence and assumptions: Runtime verifies block number/hash/link consistency, event
  emitter/topic routing through configured deployment addresses, and safe/finalized ordering;
  these do not attest the RPC endpoint's network or deployed runtime bytecode.
  `docs/runbooks/robinhood-testnet-deployment.md:35-38` instructs a human to run `cast chain-id`
  during testnet endpoint setup, but the indexer itself does not enforce this at startup. A
  hostile RPC can lie about `eth_chainId`; stronger trust against a Byzantine provider requires
  an independently reviewed chain checkpoint or equivalent trusted anchor, not only this check.
- Reproduction/proof method: Static source-to-sink proof at the cited callsites. The behavioral
  regression should use a local fake JSON-RPC server returning a chain ID different from the
  configured deployment and assert indexer startup fails before `OpenPool`, ownership acquisition,
  or writes. A matching chain ID should pass. No live endpoint is necessary.
- Proposed remediation: Add an explicit `eth_chainId` call during indexer startup and compare
  it to both configured `CHAIN_ID` and the resolved deployment's chain. Fail before acquiring
  writer ownership or persisting data. Separately decide whether a trusted block-hash anchor is
  required against malicious-provider risk.
- Required regression test: Fake-RPC mismatch is a fail-closed startup error before DB ownership
  or writes; exact match succeeds; zero/malformed/overflow chain IDs fail. Include a test where
  the URL and deployment are valid but the RPC returns a different chain ID.
- Disposition/owner: Validated; Task 3 implementation owner. Coordinate config/deployment
  contract changes with Task 4 and Task 7 before remediation.
- Related findings and cross-task references: Task 4 config validation and Task 7 deployment
  provenance. The operator `cast chain-id` procedure is compensating manual evidence, not runtime
  enforcement.

## [P5-T3-005] Indexer acquires writer ownership without validating deployed code or pair identity

- State: validated finding
- Severity: High
- Confidence: high
- Primary audit task: Task 3
- Affected asset/surface: `backend/cmd/indexer/` startup and `backend/internal/chain/` runtime
  deployment validation; Task 3 ownership-ledger rows.
- Baseline: 6184bc5febd43de99ab6cc2b6f71f7f90c878bb6
- Attacker/failure actor and prerequisites: Operator misconfiguration, stale or incorrect
  deployment manifest, replaced local-node state, or RPC serving code that differs from the
  reviewed deployment. The RPC endpoint need not be malicious if it is simply pointed at the
  wrong deployment state.
- Source-to-sink or failure path: `cmd/indexer.run` resolves the reviewed manifest deployment
  (`backend/cmd/indexer/main.go:36-43`), dials the RPC (`:46-50`), opens PostgreSQL (`:51-55`),
  then acquires the single-writer lock (`:56-60`) without calling either runtime verifier.
  Repository-wide Go call-site search found `VerifyDeploymentBytecode` and `VerifyPairAddress`
  only at their definitions and unit tests, not at an API/indexer startup or ingestion caller.
  The existing bytecode verifier reads code at Factory, CurveImplementation, WETH, and
  UniswapV2Factory addresses and checks the manifest hashes (`backend/internal/chain/verify.go:18-39`);
  the pair verifier calls factory `getPair` and compares it to the deterministic CREATE2 address
  (`:56-79`). Consequently, an RPC can return headers/logs for expected addresses even when the
  contracts at those addresses do not implement the reviewed system; the indexer can then persist
  their events under the selected deployment.
- Exact evidence: `backend/cmd/indexer/main.go:36-60` shows RPC dial followed directly by database
  open and writer-lock acquisition, with no code/pair verification; `backend/internal/chain/verify.go:18-39,56-79`
  contains the available verification methods. Reproduction/search command:
  `rg -n 'VerifyDeploymentBytecode|VerifyPairAddress' backend -g '*.go'`; baseline results are the
  definitions and tests (`backend/internal/chain/verify_test.go:20,43`), with no production call
  site. The current audit-context plan/spec (not immutable baseline evidence) call for deployment
  binding and explicitly record this scenario plus the release-only versus fail-closed decision
  at `docs/plans/2026-09-11-full-codebase-audit-hardening.md:110-112` and
  `docs/specs/2026-09-11-security-threat-model.md:157`.
- Impact: The indexer may persist a false canonical ledger for contracts that do not implement
  the reviewed Launchpad deployment, which can misstate balances, quotes, finality, or claims
  presentation. This is a durable integrity failure. Severity follows the threat model's High
  threshold for canonical corruption affecting decisions; no direct contract-held asset loss is
  demonstrated.
- Counterevidence and assumptions: Registry lookup validates the configured chain/deployment
  manifest and manifest metadata carries expected bytecode hashes; `VerifyDeploymentBytecode`
  and `VerifyPairAddress` have unit tests. Neither the manifest hashes nor those helper tests prove
  deployed code at runtime. This is distinct from P5-T3-001: matching `eth_chainId` alone does
  not attest contract code or factory pair identity.
- Reproduction/proof method: Static startup call-graph proof above. A safe behavioral regression
  uses a fake RPC returning empty/mismatched bytecode and asserts startup fails before
  `OpenPool`/`AcquireOwnership`; matching runtime code succeeds. A synthetic launch whose pair
  differs from factory `getPair` must not be accepted as a canonical launch or pair emitter.
- Proposed remediation: Call `VerifyDeploymentBytecode` immediately after dialing and before
  opening PostgreSQL or acquiring writer ownership. Verify each discovered token/pair against
  the factory's `getPair` result before persisting or routing its pair events; fail closed on
  absent code, mismatched hashes, malformed results, or pair disagreement.
- Required regression test: Fake-RPC code-hash mismatch and empty code abort before any DB
  connection/ownership; correct code passes. Per-launch fake `getPair` mismatch prevents the
  launch/pair from entering canonical storage; correct deterministic pair passes. Ensure both
  API and indexer startup boundaries are addressed or document why API runtime checks are not
  required.
- Disposition/owner: Validated; Task 3 implementation owner. Coordinate manifest/code-hash
  verification policy with Task 7 and the Task 4 API owner; do not treat release-artifact checks
  as runtime attestation.
- Related findings and cross-task references: Distinct from P5-T3-001 (RPC chain identity).
  Current audit-context threat-model item: `docs/specs/2026-09-11-security-threat-model.md:157`.

## [P5-T3-002] Idle indexer polls emit broad API and market-dirty notifications

- State: candidate
- Severity: MINOR
- Confidence: medium
- Primary audit task: Task 3
- Affected asset/surface: `backend/internal/indexer/` and `backend/internal/store/postgres/`
  notification path; API stream consumer is Task 4 primary.
- Baseline: 6184bc5febd43de99ab6cc2b6f71f7f90c878bb6
- Attacker/failure actor and prerequisites: No attacker required; a running indexer with no new
  blocks and a connected API listener is sufficient. The configured default poll interval is
  one second (`backend/internal/config/config.go:18-25,100-102`).
- Source-to-sink or failure path: Every `Engine.Step` starts with a store transaction to read
  state and token identities (`backend/internal/indexer/engine.go:44-54`). For an initialized,
  no-advance step, it still reaches the final transaction and writes the unchanged state
  (`:170-236`). Each successful `IndexerStore.Transaction` calls `notifyRefresh`, which attempts
  one `market_dirty` and one generic `api_refresh` notification (`backend/internal/store/postgres/indexer_store.go:28-57`).
  Therefore a normal idle poll attempts at least four `pg_notify` calls: two transactions times
  two channels, before any optional promotion reads; with the default one-second interval this
  is four attempts per second per idle indexer. The API listener republishes each generic event
  to the hub (`backend/cmd/api/main.go:109-127`), and SSE sends each to subscribers
  (`backend/internal/apiserver/event_routes.go:73-100`), so the API path can fan out two broad
  token invalidations per idle poll.
- Exact evidence: `backend/internal/indexer/engine.go:44-54,170-236,243-258`;
  `backend/internal/store/postgres/indexer_store.go:28-57`;
  `backend/internal/store/postgres/notify.go:10-33`; `backend/cmd/api/main.go:109-127`;
  `backend/internal/apiserver/event_routes.go:73-100`.
- Impact: At least four notification attempts and two broad downstream SSE refresh hints per
  ordinary idle one-second poll; consumers may refetch REST data despite no canonical change.
  No representative client population, API
  refetch behavior, database load, or slow-subscriber consequence was measured, so this is not
  promoted to a validated availability/performance finding.
- Counterevidence and assumptions: Dirty aggregation is durable in `aggregation_dirty` and
  worker polling is explicitly the backstop for lost notifications (`backend/internal/stats/worker.go:23-24`;
  `backend/internal/store/postgres/queries/projections.sql:102-130`). SSE is documented as
  refresh-only (`backend/internal/apiserver/event_routes.go:64`), and the hub bounds its buffer
  and evicts slow subscribers (`backend/internal/realtime/hub.go:79-90`). These limit the impact
  but do not make idle invalidations useful.
- Reproduction/proof method: Add an indexer-store notification spy or isolated PostgreSQL test;
  perform repeated successful initialized/no-advance `Step` calls and assert at least two
  `api_refresh` and two `market_dirty` attempts per call. Compare with a step that commits a new
  chunk. Measure downstream
  REST refetches only in a representative client/load setup before claiming material resource
  impact.
- Proposed remediation: Emit notifications only when a committed write changed canonical or
  derived state, or move event-specific notification responsibility to the successful write path.
  Preserve the durable dirty-table polling backstop.
- Required regression test: Repeated idle steps emit no API invalidation and do not spuriously
  wake aggregation; a newly committed block/event emits the intended refresh once; a missed dirty
  notification is still recovered by table polling.
- Disposition/owner: Candidate pending event-count and consumer-impact evidence; Task 3 owner,
  with Task 4 validating the SSE/REST consumer contract. Do not size as a production performance
  issue without a representative workload.
- Related findings and cross-task references: Task 4 API refresh semantics; Task 6 worker/query
  cost.

## [P5-T3-003] Recovery beyond 128 candidate blocks has no documented operator procedure

- State: deferred
- Severity: Low
- Confidence: high
- Primary audit task: Task 3
- Affected asset/surface: `backend/internal/indexer/reorg.go`; operational recovery runbook is
  Task 7 primary / operations owner.
- Baseline: 6184bc5febd43de99ab6cc2b6f71f7f90c878bb6
- Attacker/failure actor and prerequisites: Network or provider divergence whose common ancestor
  is more than 128 blocks below the observed tip, or a provider that cannot supply a common
  candidate inside the bounded window.
- Source-to-sink or failure path: `recoverReorg` reads at most 128 headers and asks the store for
  a common ancestor (`backend/internal/indexer/reorg.go:27-47`). If none is found, the transaction
  fails before recording or deleting canonical state (`:40-59`); `Step` returns the error and
  `Run` exits rather than advancing (`backend/internal/indexer/engine.go:243-250`). This is
  fail-closed and prevents invented ancestry, but no in-repository reindex/restore workflow is
  documented. The threat model itself says deeper divergence needs documented/tested manual
  recovery (`docs/specs/2026-09-11-security-threat-model.md:168`). The operator runbook covers
  generic release rollback and monitoring (`docs/runbooks/production-readiness.md:84-108`) but no
  deeper-reorg recovery procedure; a scoped search of `docs/runbooks/` for reorg recovery terms
  found no such procedure.
- Exact evidence: `backend/internal/indexer/reorg.go:27-59`;
  `backend/internal/indexer/engine.go:243-259`;
  `docs/specs/2026-09-11-security-threat-model.md:168`;
  `docs/runbooks/production-readiness.md:84-108`.
- Impact: The indexer halts on a deeper reorg until an operator restores/rebuilds it. The current
  code path fails closed, so this is an availability/recovery readiness gap, not evidence of
  canonical corruption.
- Counterevidence and assumptions: A shallow reorg has bounded automatic recovery, checks the
  configured safe floor, deletes event rows above the ancestor, rebuilds token projections and
  aggregates, and updates the watermark in one recovery transaction (`backend/internal/indexer/reorg.go:61-98`).
  A canonical mismatch at/below the saved safe head is terminal (`backend/internal/indexer/engine.go:76-96`).
  No supported manual reset/replay method was found, and no live deep-reorg runtime was run.
- Reproduction/proof method: Use an isolated fake source/store with a divergence deeper than
  128 blocks; assert no ancestor is invented, no canonical deletion occurs, the watermark is
  unchanged, and the process exits with an error. Then follow the approved operator recovery
  procedure on an isolated database and prove full replay/projection equality before production
  use.
- Proposed remediation: Task 7 and the operations owner should define a reviewed, backup-aware
  recovery/runbook procedure or an explicit supported rebuild command. Do not improvise live
  destructive SQL or lower the search bound without evidence.
- Required regression test: Deep divergence fails closed without writes; the documented recovery
  path restores/replays from a verified checkpoint and yields the same canonical ledger and
  projections as a clean rebuild.
- Disposition/owner: Deferred to Task 7 / operations. Prerequisite: owner-approved source of
  canonical checkpoint and database backup/restore policy. Resume by documenting an exact
  isolated-database rehearsal, expected safety checks, and operator approvals.
- Related findings and cross-task references: Current audit-context threat-model item
  `Low/Medium` at line 168 (not immutable baseline evidence); Task 7 runbook/production readiness.
  Shallow-reorg integration coverage is present but unavailable at runtime in this environment.

## [P5-T3-004] Reorg query-plan cost is unmeasured; event range predicates lack matching indexes

- State: deferred
- Severity: Low
- Confidence: low
- Primary audit task: Task 3
- Affected asset/surface: `backend/internal/store/postgres/migrations/00003_event_ledger.sql`,
  `backend/internal/store/postgres/queries/reorg.sql`; production workload/cardinality and
  query-cost acceptance are Task 6 / operations cross-boundaries.
- Baseline: 6184bc5febd43de99ab6cc2b6f71f7f90c878bb6
- Attacker/failure actor and prerequisites: No attacker required. The cost question arises during
  a reorg on a sufficiently large event ledger.
- Source-to-sink or failure path: `AffectedTokensAbove` filters 18 event tables by
  `(chain_id, block_number)` and `DeleteCanonicalAbove` issues one corresponding range delete per
  event table (`backend/internal/store/postgres/queries/reorg.sql:8-64`). Those event tables have
  primary-key identity `(chain_id, tx_hash, log_index)`; migration `00003` defines no general
  `(chain_id, block_number)` index, with only pool swap/sync reserve-lookup indexes
  (`backend/internal/store/postgres/migrations/00003_event_ledger.sql:32,79,116,147-539,399,428`).
  The predicate therefore has no obvious matching B-tree; a sequential scan is a plausible plan,
  but planner choice and latency depend on cardinality, selectivity, vacuum statistics, and how
  many rows are deleted.
- Exact evidence: `backend/internal/store/postgres/queries/reorg.sql:8-64`;
  `backend/internal/store/postgres/migrations/00003_event_ledger.sql:32-539`;
  indexes and query shapes also cross-checked against `backend/internal/store/postgres/migrations/00004_chain_projections.sql:86-131`.
- Impact: Reorg detection and cleanup may scan large portions of the ledger and delay recovery.
  There is no production-like cardinality or query-plan evidence here; no material runtime budget
  breach is asserted.
- Counterevidence and assumptions: The audit established schema/index shape only. A planner can
  reasonably select sequential scans for low-selectivity deletes, and added indexes impose write,
  storage, and vacuum cost. Production event counts, table sizes, statistics, and recovery-time
  objective are unavailable.
- Reproduction/proof method: The offline equivalent is the source-to-index predicate mapping
  above: the queried columns are not a leading index prefix for the affected event tables. It
  does not substitute for `EXPLAIN (ANALYZE, BUFFERS)` on an isolated production-like copy.
- Proposed remediation: None before measurement. Capture query plans and reorg timing at
  representative cardinalities, then add/select indexes only if the measured recovery budget
  requires them; include normal ingest overhead in the comparison.
- Required regression test: On an isolated, cardinality-controlled PostgreSQL database, record
  plans and median/tail reorg duration before and after any index change; prove event deletion,
  affected-token selection, and clean replay remain equivalent.
- Disposition/owner: Deferred measurement; Task 6 performance owner with Task 3 database owner.
  Prerequisite: isolated dataset or anonymized fixture with documented production-like counts,
  plus a recovery-time target. Resume with captured `EXPLAIN (ANALYZE, BUFFERS)` and ingest/reorg
  measurements.
- Related findings and cross-task references: Does not establish a missing-index defect. Task 6
  owns representative aggregation/query-cost measurement; Task 3 owns index/schema semantics.

## Control and acceptance evidence

| Plan 5 property | Evidence and disposition |
| --- | --- |
| RPC validation and chain binding | RPC URL syntax, positive timeout/backoff, bounded chunk/address/retry configuration, transient retry classification, and capacity-error classification are implemented. Finality-tag support errors are typed and fail closed; there is no RPC `eth_chainId` binding (validated finding P5-T3-001). `backend/internal/config/config.go:87-121,142-154`; `backend/internal/chain/rpc.go:32-42,64-103,145-209`. |
| Runtime deployment attestation | Manifest lookup is followed by RPC dial, database-pool open, and writer-lock acquisition, without invoking the available code-hash or pair-address verifiers. The helpers exist but have no production call sites (validated finding P5-T3-005; current audit-context threat-model item at `docs/specs/2026-09-11-security-threat-model.md:157`). |
| Finality and block/log validation | `Heads` reads latest/safe/finalized; engine rejects inconsistent ordering, checks saved safe/observed hashes, verifies block number and in-chunk parent linkage, rejects removed/out-of-chunk/hash-mismatched logs, rechecks the chunk end, and promotes only the locally processed intersection (`backend/internal/indexer/engine.go:57-96,106-168,180-231`). It has no silent confirmation-count fallback. |
| Staged discovery and partitioning | Factory logs discover launch addresses; fresh emitters are refetched from their launch block (including same-block logs), known emitters are queried separately, address batches are bounded, capacity errors recursively split ranges, and a single-block capacity error fails closed (`backend/internal/chain/discovery.go:36-122`). Out-of-scope emitter/topic logs, conflicting duplicates, and malformed routing fail closed (`:125-189` and `decoder.go`). |
| Event ABI routing | Decoder is engine-versioned and the router maps the 18 supported ledger event types to their domain insertors; all logs are ordered by block/transaction/log before routing. Unsupported engine/event versions and malformed address/data encodings are rejected. Unit fixtures cover all supported ABI event forms (`backend/internal/chain/decoder_test.go:70-170`; `backend/internal/indexer/router.go`). |
| Ownership loss and writer fencing | A dedicated PostgreSQL session holds a SHA-256-scoped advisory lock; every owned transaction is serialized on that same connection with a five-minute bound. Probe/connection/unknown-commit errors mark ownership terminal (`backend/internal/store/postgres/ownership.go:19-25,33-55,63-115`). Integration test kills the owning backend and asserts the second writer acquires ownership while the old writer fails (`backend/internal/store/postgres/postgrestest/ownership_integration_test.go:13`, runtime unavailable). |
| Transaction ambiguity and chunk atomicity | `WithinTx` uses READ COMMITTED, rolls back callback/context errors, and wraps commit errors as unknown outcomes (`backend/internal/store/postgres/tx.go:22-77`). `IndexerStore` routes writes through ownership and engine groups block rows, events, projections, finality, and sync-state update in a single transaction (`indexer_store.go:28-44`; `engine.go:215-236`). Main maps unknown outcome/ownership loss to terminal exit behavior (`shutdown.go`). |
| 18 event conflict/replay paths | Each event uses identity `(chain_id, tx_hash, log_index)`, `ON CONFLICT DO NOTHING`, then a full coordinate+payload match before accepting replay; mismatches return `InvariantConflictError` (`backend/internal/store/postgres/queries/events.sql:1-143`; `backend/internal/store/postgres/adapter.go:56-76,78-98` and generic `insertEvent`). The integration test constructs all 18 wrappers, asserts first insert, identical replay no-op, and a divergent payload conflict for each (`backend/internal/store/postgres/postgrestest/event_wrappers_integration_test.go:17`). It was compiled but not executed because no isolated DB was available. |
| Schema/FKs/locking/migrations | Sync-state checks enforce observed/safe/finalized completeness and order; indexed blocks bind identity and immutable block fields; canonical event rows reference blocks via deferrable composite FKs. Token event FKs and deferred graduation ordering preserve insertion-order tolerance (`backend/internal/store/postgres/migrations/00002_chain_control.sql:1-90`; `backend/internal/store/postgres/migrations/00003_event_ledger.sql:1-591`). Pool events intentionally lack token-launch FK because pair logs may precede launch discovery. Migrations 00001–00009 and explicit goose up/down/status runner were inspected; the intended up/down/up test exists but did not execute (`backend/internal/store/postgres/migrations/runner.go:18-105`; `backend/internal/store/postgres/postgrestest/migrations_integration_test.go:14`). |
| Reorg/replay | Reorg search is bounded at 128, rejects ancestors below safe, records the attempt, deletes all 18 event families/blocks above the common ancestor, rebuilds affected token projections and aggregate stats, then updates watermark and completes the reorg in one transaction (`indexer/reorg.go:27-98`; `queries/reorg.sql:1-76`). Shallow runtime E2E tests use Anvil + PostgreSQL; deep (>128) automatic recovery is intentionally unavailable and operational recovery is deferred (P5-T3-003). |
| Incremental/full projection equality | Integration differential tests compare token/reserve/holder/candle projections after chunk splits `[1,1,1,1]`, `[2,2]`, `[1,2,1]`, `[4]`, then after replay (`postgrestest/incremental_projections_integration_test.go:19-80`). Fixtures exercise pre-launch transfer order, same-transaction trades/transfers/graduation, same-transaction Sync/Swap ordering, unpaired swap, zero/self/burn/re-acquire balances, and negative-balance rollback. Rebuild uses canonical event tables ordered by block/tx/log in migration `00004_chain_projections.sql:373-563`. Tests were inspected, not run. |
| Candle/time boundaries | Incremental-vs-rebuild integration cases cover ±1 microsecond around 1m/5m/1h/1d edges (`incremental_projections_integration_test.go:193-237`). Block/event timestamps are UTC-normalized at encoding (`convert.go` `timestamptz`); `equalTimestamptz` compares after PostgreSQL microsecond precision truncation (`time.go:9-14`). Runtime database round-trip was unavailable. |
| NUMERIC/codec correctness | `numeric(78,0)` is used for unsigned on-chain quantities. `Uint256` enforces non-null, finite, non-negative, integral, ≤256-bit values on encode/decode; 20-byte addresses and 32-byte hashes reject other lengths (`backend/internal/store/postgres/sqlc/types.go:15-129`; unit tests in `backend/internal/store/postgres/sqlc/types_test.go:10-80`). PostgreSQL numeric exponent tests also cover exact and fractional cases (`backend/internal/store/postgres/profile_test.go:10`). |
| Notifications and dirty polling | Durable `aggregation_dirty` rows are generation-versioned and claimed via `FOR UPDATE SKIP LOCKED`; claim completion includes generation and worker identity (`queries/projections.sql:102-137`). Worker polls every five seconds even if notifications are lost (`stats/worker.go:8-9,23-55`). API refresh uses reconnecting LISTEN and best-effort hints. The idle broad NOTIFY behavior is the candidate P5-T3-002; API listener runtime was not exercised. |
| Query/index review | Static/offline predicate-to-index analysis was performed for canonical block lookup, event conflict keys, projection source ordering, dirty claims, API sort cursors, and reorg ranges. Reorg range access has no obvious matching leading `(chain_id, block_number)` index; no planner/cardinality claim is made. No live `EXPLAIN (ANALYZE, BUFFERS)` was possible; measurement is deferred in P5-T3-004. |

## Runtime evidence and limitations

- Passed, with `GOPROXY=off`, workspace-local `GOCACHE`, and local toolchain:
  `go test ./internal/chain ./internal/indexer ./internal/ledger ./internal/holder ./internal/store/postgres/... ./cmd/indexer ./cmd/migrate`
  from `backend/`. This exercises unit tests only; integration-tagged tests are excluded.
- Passed compile-only check:
  `go test -tags integration -run '^$' ./internal/indexer ./internal/store/postgres/postgrestest`
  from `backend/`. `-run '^$'` means no integration test body was executed.
- Docker daemon was unavailable; `anvil` was not installed. `DATABASE_URL` and
  `TEST_DATABASE_URL` were unset. Although a local PostgreSQL service was listening, no
  credentials or isolated test-database URL were supplied; it was deliberately not contacted.
- Consequently unavailable: migration up/down/up runtime, DDL/FK enforcement, event conflict
  transactions, ownership-session termination, SQL rollback/unknown-commit runtime, shallow/deep
  reorg end-to-end, projection differential execution, notification delivery, and PostgreSQL
  query plans. No `EXPLAIN` costs, table cardinalities, production latencies, or load measurements
  are claimed.
- A Go telemetry upload-token permission warning appeared because the global telemetry path was
  inaccessible; the local package tests nevertheless completed successfully. No telemetry or
  network upload was used as audit evidence.

## Complete Task 3 ownership disposition

All file names below are from baseline `6184bc5`; `reviewed` means static source/test review,
not successful runtime execution. Generated copies are explicitly excluded under Task 1's
most-specific-path rule and listed with their Task 7 ownership.

| Baseline path(s) | Disposition |
| --- | --- |
| `backend/cmd/indexer/main.go` | Reviewed; startup RPC chain-binding finding P5-T3-001 and missing runtime deployment-attestation finding P5-T3-005. |
| `backend/cmd/migrate/main.go`, `backend/cmd/migrate/main_test.go` | Reviewed for Task 3 migration cross-boundary; Task 7 remains primary owner. Unit command/config tests passed. |
| `backend/internal/chain/decoder.go`, `discovery.go`, `errors.go`, `rpc.go`, `types.go`, `verify.go`; `decoder_test.go`, `discovery_test.go`, `rpc_test.go`, `verify_test.go` | Reviewed; relevant unit tests passed. |
| `backend/internal/chain/abi/v1/ILaunchEvents.json`, `IUniswapV2PairEvents.json`, `LaunchFactory.json`, `LaunchToken.json`, `UniswapV2Router02.json`; `backend/internal/chain/testdata/event-logs-v1.json` | Generated/fixture inputs excluded from primary Task 3 ownership (Task 7); semantic consumption and fixture-test usage reviewed. |
| `backend/internal/indexer/engine.go`, `engine_test.go`, `health.go`, `health_http_test.go`, `ports.go`, `reorg.go`, `router.go`, `shutdown.go`, `api_e2e_integration_test.go`, `anvil_e2e_integration_test.go` | Reviewed. Unit tests passed; E2E tests inspected and compile-checked only, not run. Deferred deep-recovery procedure P5-T3-003. |
| `backend/internal/ledger/doc.go`, `events.go`; `backend/internal/holder/ports.go` | Reviewed as neutral event/holder contracts; packages compiled (`ledger`, `holder` contain no standalone unit tests). |
| `backend/internal/store/postgres/adapter.go`, `aggregation_source.go`, `api_notify.go`, `convert.go`, `doc.go`, `indexer_store.go`, `ledger_contract_test.go`, `metadata.go`, `model.go`, `notify.go`, `observation.go`, `open.go`, `open_test.go`, `operational_health.go`, `ownership.go`, `profile.go`, `profile_test.go`, `public_reads.go`, `read_adapter.go`, `read_snapshot.go`, `read_snapshot_test.go`, `time.go`, `tx.go` | Reviewed for canonical persistence/transaction/codec/notification behavior and Task 4 read-consumer boundaries. All applicable package/unit tests passed; database-dependent assertions unavailable. |
| `backend/internal/store/postgres/migrations/00001_initialize.sql` through `00009_token_images_reorg_survival.sql`, `runner.go`, `runner_test.go` | All nine migrations and runner reviewed. Runner unit tests passed; PostgreSQL up/down/up runtime unavailable. |
| `backend/internal/store/postgres/queries/blocks.sql`, `events.sql`, `indexer.sql`, `metadata.sql`, `observation.sql`, `profile.sql`, `projections.sql`, `read.sql`, `reorg.sql`, `sync.sql` | All ten query files reviewed. Canonical insert/projection/reorg semantics primary; read/profile/metadata queries cross-reviewed with Task 4. Query-plan cost deferred in P5-T3-004. |
| `backend/internal/store/postgres/postgrestest/chain_control_integration_test.go`, `chain_projections_integration_test.go`, `event_ledger_integration_test.go`, `event_wrappers_integration_test.go`, `incremental_projections_integration_test.go`, `metadata_integration_test.go`, `migrations_integration_test.go`, `observation_integration_test.go`, `ownership_integration_test.go`, `profile_integration_test.go`, `public_reads_integration_test.go`, `reorg_primitives_integration_test.go`, `sqlc_integration_test.go`, `testdatabase_integration.go`, `token_stats_integration_test.go`, `url.go`, `url_test.go`, `withintx_integration_test.go` | All 18 listed files reviewed for test intent/harness; integration test packages compile with tags but no test body ran. `url_test.go` runs in ordinary unit suite; DB harness defaults to Testcontainers or explicit `DATABASE_URL` and teardown drops its isolated database. |
| `backend/internal/store/postgres/sqlc/blocks.sql.go`, `config_test.go`, `db.go`, `dbtx_test.go`, `events.sql.go`, `indexer.sql.go`, `metadata.sql.go`, `models.go`, `observation.sql.go`, `profile.sql.go`, `projections.sql.go`, `querier.go`, `read.sql.go`, `reorg.sql.go`, `sync.sql.go`, `types.go`, `types_test.go` | Generated sqlc copies/tests excluded from primary Task 3 ownership (Task 7). Generated scalar codecs and relevant query consumers were reviewed; ordinary `sqlc` package tests passed. No sqlc regenerate/diff was run. |

## Required follow-up

1. Fix P5-T3-001 with fake-RPC chain-ID tests before any live indexer deployment; separately decide
   the required block-hash trust anchor for Byzantine-provider risk.
2. Fix P5-T3-005 with fake-RPC deployed-code and factory-pair tests before any live indexer
   deployment; reconcile runtime API verification with Task 4.
3. Measure or reject P5-T3-002 with a no-advance notification test and representative API-client
   behavior.
4. Assign Task 7/operations owner for P5-T3-003 and rehearse the approved deep-reorg recovery on
   an isolated database.
5. Close P5-T3-004 only after representative-cardinality plans and ingest/reorg recovery timing
   are recorded; do not add indexes based solely on the static audit.
