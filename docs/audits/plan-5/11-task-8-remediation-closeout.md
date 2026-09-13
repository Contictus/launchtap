# Plan 5 Task 8 — Finding Validation, Remediation, and Closeout

## Result and boundary

Task 8 reconciled the immutable audit baseline `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
against the Task 2–7 reports, implemented narrowly scoped fixes for validated repository
findings, reviewed the remediation independently, and reran the available verification gates.
The reviewed repository head is `995e5c9f8660578529bd2e649ebc3d8749506b80`.

This closes repository-side Plan 5 remediation, not live acceptance or production readiness.
Two backlog items remain. The archive-RPC fork check and fresh Slither detector output were not
available in the final environment, and this report does not claim either passed. Task 2–7
baseline reports remain unchanged; this report is their remediation/status overlay.

## Remediation map

| Validated finding(s) | Disposition and remediation | Focused regression evidence |
| --- | --- | --- |
| `P5-T2-001` | **Fixed** in `ffce836`: deployment generation now uses and asserts the specified launch-fee default rather than silently selecting zero. No launch economics were changed. | `contracts/test/Deployment.t.sol::testDeploymentScriptUsesAndAssertsSpecifiedLaunchFee`; final local Foundry suite 97/97. |
| `P5-T3-001`, `P5-T3-005` | **Fixed** in `106ecfe`: before opening the database or taking writer ownership, indexer startup binds the RPC-reported chain ID to configuration/deployment, verifies expected runtime code, and checks factory/pair identity before accepting discovered canonical events. | `backend/cmd/indexer/main_test.go::TestInitializeIndexerResourcesFailsBeforeDatabaseOrOwnership`, `TestInitializeIndexerResourcesVerifiesBeforeOpeningAndAcquiring`; `backend/internal/chain/discovery_test.go::TestDiscovererRejectsLaunchPairBeforeReturningCanonicalEvents`; unit and integration gates in backend verification. |
| `P5-T3-003` | **Fixed, repository-side** in `ffbf631`: recovery beyond the former 128-block search is available only through explicit bounded deep-reorg configuration/acknowledgement, up to 100,000 candidates, still respecting the safe/start floor and revalidating the chain around the atomic rollback/replay. The runbook was added. **Live operator rehearsal remains deferred.** | `TestLoadRequiresExplicitModeForExpandedReorgSearch`, `TestNewRequiresAcknowledgementForExpandedReorgSearch`, `TestDeepReorgDefaultWindowFailsClosedWithoutWrites`, `TestAcknowledgedDeepReorgUsesAtomicRecoveryAboveSafe`, and the mismatch, discontinuity, safe-boundary, and atomic-failure tests in `backend/internal/indexer/engine_test.go`. |
| `P5-T4-001`–`P5-T4-004` | **Fixed** in `4abe30e`: metadata/image identity is tied to the canonical launch rather than reusable token address; SSE handlers are cancelled at shutdown; OpenAPI documents write headers and image request/response/304 semantics; allowed clients can read revision headers. Migration down/up behavior is guarded. | `TestServerShutdownCancelsActiveSSEHandler`, `TestMetadataHTTPContracts`, `TestMetadataLaunchIdentityMigrationQuarantinesLegacyRowsAndProtectsDown`, `TestMetadataAndImagesAuthorizeAndUseRevisionsAtomically`, and `TestMetadataAndImageFirstWritesRejectConcurrentExpectedZero`; API/OpenAPI and Postgres integration gates. |
| `P5-T5-001`–`P5-T5-006` | **Fixed** in `7462bb3`: wallet writes require an immutable, freshly reviewed intent; canonical transaction state/hash survive reload; transient API failure no longer masquerades as reorg; full candle snapshots replace corrected history; SSE retries back off under REST-only success; trade-side tabs implement keyboard navigation. | `web/src/transactions-task6.test.ts` review-intent and API-failure cases; `web/src/transaction-storage.test.ts`; `web/src/api/sse.test.ts`; `web/src/token/chart-data.test.ts`, `market-chart.test.ts`; `web/src/components/primitives.test.ts`; Anvil browser assertions in `web/e2e/task6-anvil.spec.ts`. |
| `P5-T6-001`, `P5-T6-002` | **Fixed** in `5396229`: protocol aggregate refresh is atomic for readers/failures, and unused worker poll/lease surface was removed; worker retry/cancellation behavior is tested. | `TestRecomputeProtocolAggregatesKeepsCommittedRowsVisibleUntilRefreshCompletes`, `TestRecomputeProtocolAggregatesRollsBackOnSummaryFailure`, `TestWorkerRetriesFailedClaimAndHonorsCancellation`; PostgreSQL integration gate. |
| `P5-T6-CAND-001` | **Accepted and fixed as defensive type-consistency hardening**, not retrospectively claimed as a reachable baseline exploit. `b029bb9` widened signed 24-hour change through PostgreSQL `BIGINT`, Go `int64`, OpenAPI/client, with a JavaScript-safe API bound and a downgrade guard against lossy narrowing. | `TestComputeTokenStatsKeepsPriceChangeBeyondPostgresIntegerRange`, `TestComputeTokenStatsRejectsPriceChangeOutsideSafeIntegerRange`, `TestCheckedPriceChange24hBPSAcceptsSafeIntegerBoundaries`, `TestCheckedPriceChange24hBPSRejectsValuesOutsideSafeIntegerBoundaries`, `TestRecomputeTokenStatsPriceChangeBigintBoundary`, `TestPriceChangeBigintDownMigrationRejectsLossyNarrowing`; generated OpenAPI/client and migration checks. |
| `P5-T6-OPT-001` | **Measured and fixed** in `b8c02ee`: protocol-wide aggregates are coalesced once per drained chain batch instead of once per dirty token. Output parity and stale-claim protections are checked. | `TestAggregationSourceBatchMatchesPerClaimRefresh`, `TestAggregationDirtyLeaseGuardsStaleCompletion`, `TestProtocolAggregationBatchPerf`; bounded PostgreSQL integration fixture described below. |

## Candidate and residual disposition register

| Candidate / hypothesis | Final disposition |
| --- | --- |
| `P5-T2-002` — production timelock/dependency source and code-hash evidence | **Deferred** to reviewed target manifest and governance inputs; no target transaction or credentials were fabricated. |
| `P5-T2-003` — pair-hash fallback broadcasts `createPair` | **Rejected** in the Task 2 report: first-party validation call sites are outside broadcast scopes. |
| `P5-T2-004` — same-version engine configuration upgrades existing clones | **Rejected** in the Task 2 report: launch configuration is snapshotted; source/tests show existing clones are unchanged. |
| Slither `2e812341…` (`arbitrary-send-eth` in graduation) | **Suppressed/rejustified**: WETH is factory-snapshotted and the transfer is to configured WETH/pair, not an attacker-selected recipient. |
| Slither `42b0e1b8…` (`arbitrary-send-eth` in developer buy) | **Suppressed/rejustified**: creator-funded exact launch value reaches the new clone; creator is trader/token/refund recipient and `buyFor` is factory-only. |
| Slither `5b51b099…` (`uninitialized-local`) | **Suppressed/rejustified**: every launch-event struct field is assigned before use. |
| Slither `cdd33f0d…` (`unused-return` for pair reserves) | **Suppressed/rejustified**: both reserve outputs participate in pair validation; only the unused timestamp is irrelevant to the invariant. |
| Slither `f80749dc…` (`unused-return` for quote) | **Suppressed/rejustified**: only token output is needed for the cap; actual execution checks tokens and exact gross. |
| Fresh Slither detector run | **Unavailable**, not a pass: build-info was unavailable in the closeout environment. The five stored rows above were source-rejustified in Task 2 and no new scan is claimed. |
| `P5-T3-002` — idle indexer notification attempts | **Accepted without code change** as a low-risk/unoptimized behavior. Source shows four notification attempts per idle step, but the impact harness was invalid and no live listener/resource impact was established. |
| `P5-T3-004` — reorg range index/query-plan cost | **Accepted without adding an index**: the synthetic 200,000-row test exercised the existing index/skip-scan path and did not justify a new index. Production cardinality and a reorg SLO remain unknown; no production-plan claim is made. |
| `P5-T3-003` live deep-reorg operator rehearsal | **Deferred** despite the repository recovery mode and runbook: a funded/reviewed target, trusted live source and named operator rehearsal remain external. |
| `P5-T4-005` — non-preflight CORS path permits browser writes | **Rejected** in the Task 4 report based on the actual CORS control flow. |
| `P5-T4-006` — external deployment-manifest path as production trust root | **Deferred** pending production filesystem/configuration ownership and digest/immutability evidence. The local E2E overlay remains intentional. |
| `P5-T5-007` — wallet chain changes after simulation | **Rejected**: pinned viem checks current chain before the provider transaction request; existing wrong-chain E2E remains. |
| `P5-T5-008` — token metadata executes markup/script | **Rejected** as an executable injection finding: React text rendering and URL/image scheme checks provide no source-to-DOM execution path. Production artifact/browser evidence remains separately deferred. |
| `P5-T5-009` — metadata plus image save is unrecoverable partial commit | **Rejected** as reportable integrity defect: the API versions the two resources independently and the editor retains the unsaved image/retry state. |
| `P5-T5-010` — repeated clicks create concurrent writes | **Rejected**: per-action in-flight refs are set before awaiting and block re-entry in the mounted panel. |
| `P5-T5-011` — public reachability of E2E RPC relay | **Deferred** to deployment/preview inventory. Production configuration rejects the fixture flag; no external preview exposure inventory was available. |
| Task 5 production-configured bundle/acceptance gate | **Deferred** until real reviewed deployment, Privy, API/RPC, origin, and hosting inputs exist. Deterministic Playwright and Anvil gates now ran successfully; they are not live acceptance. |
| Task 6 product-performance hypotheses outside `P5-T6-OPT-001` | **Deferred/not established** where the reports lack production-shaped traffic, query plans, SLOs, or user-latency samples. No code was changed on static counts alone. |
| Task 7 PR access to the archive-RPC secret | **Rejected** in the Task 7 report: the secret-bearing jobs require `workflow_dispatch`; PR paths do not run them. |
| Task 7 stale checked-in Slither JSON suppresses release scan | **Rejected**: the release gate invokes a version-checked fresh source scan and does not consume the stored triage JSON. Task 8's separate fresh-scan limitation is recorded above. |
| `P5-T7-001` — wallet SDK production license scope | **Deferred** pending integrity-verified package bytes, production bundle/deployment reachability, actual use/configuration and written legal determination; no violation is asserted. |
| Task 7 online dependency/advisory, upstream provenance, action/tool license and hosted GitHub policy unknowns | **Deferred evidence gaps**: offline registry/module access and unavailable external organization settings prevented current advisory/provenance/branch-protection claims. |

The closeout does not silently convert static/source evidence into runtime proof. Task 3's periodic
dirty-table polling and existing fail-closed boundaries remain; no notification-performance
optimization was made without validated impact.

## Performance evidence

`TestProtocolAggregationBatchPerf` is an opt-in integration measurement in
`backend/internal/store/postgres/postgrestest/protocol_aggregation_batch_perf_integration_test.go`.
It seeds PostgreSQL 18 with 200,000 canonical market rows distributed over 32 dirty tokens,
alternates old/new execution order (`AB`, `BA`, `AB`, `BA`), resets outputs for each timing, and
compares aggregate snapshots after each pair. Four samples per path were collected:

| Path | Samples (ms) | Median | Relevant statements / transactions |
| --- | --- | ---: | --- |
| Previous per-token protocol refresh | 41,928; 42,838; 41,383; 41,636 | 41,782 ms | 96 protocol statements; 128 total compute statements; 32 transactions |
| Batched refresh | 1,338; 1,277; 1,172; 1,232 | 1,254 ms | 3 protocol statements; 35 total compute statements; 1 transaction |

All four output comparisons matched; the maximum batched sample remained below the 30-second
dirty-claim lease. This fixture measures a controlled workload and validates semantic parity, not
production event cardinality or a user-facing freshness SLO. The run's teardown command timed out
while dropping its disposable database after the test assertions had passed; the fixture/test
reported successful assertions, but automatic database cleanup was not confirmed by that command.

The `P5-T3-004` index decision is separate: synthetic 200,000-row evidence showed the existing
index/skip-scan path and did not justify adding an index. Exact runtime/`EXPLAIN` numbers were not
retained in the available evidence, so this is not a quantified production query-plan result.

## Commit and independent-review trail

The implementation sequence from audit-doc completion through the final backend test fix is:

| Commit | Scope |
| --- | --- |
| `482ff4a` | Complete read-only Tasks 2–7 audit reports. |
| `ffce836` | Enforce specified launch-fee deployment default. |
| `106ecfe` | Verify RPC chain identity and deployment/pair before ingestion. |
| `5396229` | Make protocol aggregate refresh atomic; remove unused aggregation worker controls. |
| `7462bb3` | Fix web transaction intent, persistence, reorg refresh, SSE retry, chart history, and tabs. |
| `4abe30e` | Bind metadata to canonical launches; correct API/OpenAPI, SSE shutdown, and CORS contracts. |
| `b029bb9` | Safely widen signed price-change handling across DB/API/client. |
| `b8c02ee` | Batch protocol aggregate refresh with equivalence and perf tests. |
| `ffbf631` | Add acknowledged bounded deep-reorg recovery and operator runbook. |
| `8e79b8f`, `14aaa64`, `74eb046`, `fdf2dce`, `2949c66`, `995e5c9` | Follow-up fixes/tests for SQL join ambiguity, E2E fixture correctness, migration rollback verification, observation-state semantics, web formatting, and snapshot precedence discovered during integration/release verification. |

Each remediation packet and follow-up was independently reviewed; all findings were reported
**CLEAN after fixes**. Reviewer identities and per-finding review hashes are not asserted here
because they are not part of the retained evidence. The final gate failures in API joins,
observation state and integration fixtures were corrected in the listed follow-ups and rerun.

## Final verification evidence

| Evidence | Result and exact boundary |
| --- | --- |
| GitHub backend CI | Success, run `34757931951`, exact head `995e5c9`. Runs backend `task verify`, including build, vet/race/unit and required integration/migration/sqlc/artifact checks plus Anvil indexer E2E. |
| GitHub web CI | Success, run `34757527184`, commit `2949c66`. No web-owned path changed between that commit and `995e5c9`; the final backend-only observation test is covered by the backend run. |
| Local web unit tests | 108/108 passed. |
| Local Playwright | 52 passed; 26 expected skips for the separately gated Anvil project. |
| Local web Anvil gate | 14/14 passed. |
| Contracts | 97/97 Foundry tests passed; build, lint, size, vector/golden, event/deployment drift, simulation and reviewed source checks passed in the recorded run. |
| Windows Foundry format check | The only observed formatter discrepancy was checkout line endings: 28 files / 5,927 line-pairs normalize identically. This is reported as CRLF-only, not as a source-format fix or semantic diff. |
| Archive-RPC fork gate | Not run: `ROBINHOOD_MAINNET_ARCHIVE_RPC_URL` was unavailable. Do not interpret as passed. |
| Fresh Slither detector output | Not produced: current build-info was unavailable. The five stored Task 2 High/Medium rows were re-justified/suppressed from source as documented; that does not replace a fresh detector run. |

The local and hosted evidence is deterministic repository evidence. It does not prove a live
Robinhood testnet deployment, real Privy configuration, external preview isolation, production
configuration, governance custody, backup/restore, monitoring/rollback rehearsal, or external
audit.

## Backlog and remaining external inputs

`backlog.md` remains exactly **2 Active items**, unchanged:

1. **Robinhood testnet deployment manifest.** Human operator must fund the named Foundry account,
   execute and review the dependency bootstrap receipts/code hashes, then deploy and review the
   Launchpad chain-46630 manifest. Live chain acceptance and deep-reorg rehearsal depend on
   approved operators and target inputs.
2. **Production release, governance, and audit inputs.** Product/infrastructure/security owners
   must fill the pending production readiness sheet: real Privy app/dashboard settings, public
   API/RPC/origin configuration, database/hosting/domain/CDN/WAF and secret-manager owners,
   monitoring/rollback/incident ownership, pause multisig/timelock/treasury/legal policy, external
   audit, and CoinGecko commercial credentials/attribution implementation.

The ETH/USD source selection is already recorded as complete; its adapter/credentials/UI attribution
remain under production release inputs. Forum/Memestock remains a separate future product plan.
No production or live-testnet transaction was authorized or broadcast during Task 8.
