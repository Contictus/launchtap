# Plan 5 — Full Codebase Audit and Hardening

> **Workflow:** `AGENTS.md` governs implementation, verification, commits, and independent
> review. This plan audits the immutable completed implementation before authorizing changes.
> Audit hypotheses are not findings, and green tests are not proof of production safety.

**Status:** Tasks 1–7 complete. Task 8 remediation is next, but is not authorized and has not
started.

**Audit baseline:** `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6` (`main` milestone merge)

**Threat model:** `docs/specs/2026-09-11-security-threat-model.md`

**Goal:** Establish whether the completed contract, backend, indexer, API, web, database, CI,
and release system is secure, correct, maintainable, and efficient enough for live acceptance;
then remediate only independently validated issues with measurable regression protection.

## Scope and completion boundary

Plan 5 has eight tasks. Tasks 1–7 are read-only audits of the immutable baseline. They may add
audit reports under `docs/audits/plan-5/`, but they do not change product code, generated
artifacts, migrations, dependencies, workflows, or runtime configuration. Task 8 is the only
remediation task.

This plan does not replace the external deployment, governance, production configuration, or
external-audit inputs in `backlog.md`. It can complete repository-side review while reporting
those inputs as unresolved prerequisites. It cannot declare production readiness without them.

## Locked decisions

1. The implementation audit target is immutable commit `6184bc5`. Documentation written after
   that commit does not silently widen or move the target.
2. Tasks 1–7 discover and validate; they do not opportunistically fix code. A suspected issue is
   recorded with evidence and survives independent validation before Task 8 may change source.
3. Every candidate finding records severity, confidence, affected asset, attacker prerequisites,
   source-to-sink or failure path, exact `path:line` evidence, impact, counterevidence, reproduction
   or proof method, proposed remediation, and required regression test.
4. Scanner output is evidence input, not a finding. Dependency advisories require production
   reachability and exploitability triage. Complexity metrics require a concrete maintenance or
   defect risk. Performance work requires a representative baseline and before/after measurement.
5. Contract economics, canonical-ledger semantics, public API/OpenAPI behavior, migrations, and
   generated artifacts do not change under a cleanup label. Any necessary semantic change receives
   an explicit finding, compatibility analysis, and focused commit.
6. Plan 5 implementation/remediation code is delegated to `gpt-5.6-luna` agents at high reasoning
   effort. The root agent orchestrates scope, validates evidence, assigns non-overlapping fixes,
   verifies integration, and does not author remediation code.
7. Remediation uses small topic commits. Security, correctness, dependency, performance, and
   refactor changes are not squashed into one opaque commit.
8. The agent that writes a fix does not independently approve it. A fresh-context reviewer or
   Claude reviews the named commit/range against the validated finding and regression test.
9. No real secret, private key, seed phrase, Privy verification key, database credential, private
   RPC URL, or production token is copied into prompts, reports, tests, logs, or commits. Synthetic
   canaries are used for leak-path testing.
10. Task 8 closes only when the complete contract, backend, web, browser, Anvil, generated-drift,
    and release gates pass and all findings have an explicit disposition. Deferred external items
    remain visible in `backlog.md`.

## Finding states

```text
hypothesis -> candidate -> validated finding -> assigned fix -> verified fix -> closed
                         \-> rejected/suppressed with evidence
                         \-> deferred with owner, prerequisite, and resume step
```

`Critical`, `High`, `Medium`, and `Low` follow the repository threat model. Code-quality-only
items use `IMPORTANT` or `MINOR` and must still identify a concrete defect, maintenance cost, or
measured resource waste. Pure style preferences are not reportable.

## Task 1 — Baseline, architecture, policy, and audit harness · Risk: high

- Verify the baseline commit, repository cleanliness, submodule revisions, generated-artifact
  provenance, toolchain pins, and the exact commands that form the current release gate.
- Reconcile the source-backed threat model with actual entrypoints, supported deployments,
  configuration precedence, trust boundaries, sensitive resources, and `backlog.md` prerequisites.
- Define repository-wide security policy and reportability rules without weakening existing
  `AGENTS.md` constraints.
- Inventory first-party, generated, vendored, test-only, local-development, CI, release, and
  production-conditional surfaces so later task coverage is auditable.
- Create a coverage ledger and canonical finding template. Record exclusions and unknowns rather
  than treating unreviewed paths as clean.
- Capture reproducible baseline gate durations, binary/bundle sizes, test counts, and dependency
  inventory. Do not optimize from a single noisy measurement.

Acceptance criteria:

- The target remains `6184bc5`, with its submodule commits and generated inputs recorded.
- Every first-party runtime/release directory is assigned to exactly one primary audit task; shared
  boundaries may be cross-reviewed without becoming unowned.
- The threat model contains verified `path:line` evidence and clearly labels hypotheses,
  deployment assumptions, and external unknowns.
- Baseline commands, host requirements, skip conditions, and expected artifacts are sufficient for
  a clean machine to reproduce the audit harness.
- No product source or dependency is changed.

## Task 2 — Smart-contract and economic-security audit · Risk: high

**Depends on:** Task 1.

- Review factory initialization, clone initialization, engine versioning, immutable launch
  snapshots, pause/timelock/treasury authority, and claim permissions.
- Re-derive buy/sell fee arithmetic, rounding, virtual reserves, graduation threshold, refunds,
  developer buy, fixed supply, pair ordering, liquidity minting, LP burn, and post-graduation phase
  transitions from Solidity rather than documentation.
- Trace checks-effects-interactions and every external call, callback/reentrancy surface,
  fee/refund failure path, malicious ERC-20/pair/factory behavior assumption, forced ETH, and
  accounting invariant.
- Extend review beyond existing happy-path vectors with stateful fuzzing/invariants, boundary
  sequences, differential math, fork assumptions, storage/layout checks, bytecode size, and gas
  griefing analysis. Existing Slither suppressions are re-justified from source.
- Review deployment/bootstrap scripts and manifests for deterministic address/configuration
  binding, chain-ID checks, receipt/code-hash evidence, unsafe operator defaults, and whether the
  pair-init-code fallback can call `createPair` during a live/broadcast validation.

Acceptance criteria:

- Every external/public function and privileged state transition has a coverage disposition.
- Curve and graduation properties are expressed as executable invariants or a documented proof;
  equivalent Solidity/Go/vector outputs are checked at adversarial boundaries.
- Each Slither triage entry is still applicable to current source; scanner silence is not treated
  as manual-review coverage.
- Findings distinguish a public attacker, creator, governance signer, dependency contract, and
  operator misconfiguration; assumed signer compromise alone is not a new exploit.
- The task produces no contract or deployment change.

## Task 3 — Chain, indexer, PostgreSQL, and reorg-correctness audit · Risk: high

**Depends on:** Task 1.

- Review RPC response validation, block/finality ordering, `eth_getLogs` partitioning and shrink
  behavior, staged emitter discovery, ABI/version routing, and hostile/malformed log handling.
- Prove one-writer advisory ownership, connection-loss detection, shutdown/ambiguous transaction
  behavior, chunk atomicity, idempotent conflict comparison, and restart recovery.
- Exercise shallow/deep reorgs, mismatches at/below safe, common-ancestor search, event/block delete
  order, projection rebuilds, aggregate invalidation, notifications, periodic dirty-table polling,
  and cursor/snapshot invalidation.
- Differentially compare incremental projections and aggregates with full rebuild oracles across
  adversarial event ordering, zero-balance transitions, same-transaction Sync/Swap selection,
  candle eligibility, day boundaries, and multiple chunk splits.
- Validate fail-closed and documented operator recovery when the correct common ancestor lies
  beyond the current 128-candidate automatic search window.
- Inspect schema constraints, indexes, query plans, locks, isolation levels, pool sizing, numeric
  codecs, time precision, and migration up/down/up behavior.

Acceptance criteria:

- Canonical state after every tested reorg/restart equals a clean replay from surviving events.
- No second writer can make progress after ownership loss without the first process entering a
  terminal unhealthy state inside the documented detection window.
- All 18 event-table conflict paths reject non-identical duplicate identities and accept identical
  replay without double-applying projections.
- Representative production-shape queries have captured `EXPLAIN (ANALYZE, BUFFERS)` evidence or
  an offline equivalent when live data is unavailable; missing production cardinality is explicit.
- The task produces no Go, SQL, migration, or configuration change.

## Task 4 — API, identity, authorization, and content-security audit · Risk: high

**Depends on:** Task 1.

- Review route inventory, method/path contracts, snapshot/finality semantics, pagination and
  cursor integrity, error disclosure, content negotiation, CORS, cache behavior, SSE lifecycle,
  timeouts, body/header limits, cancellation, and graceful shutdown.
- Trace Privy access and identity tokens through syntax parsing, signature and claim validation,
  app/audience/issuer binding, linked-account parsing, duplicate/case handling, key formats,
  clock boundaries, and failure mapping.
- Prove creator-only metadata/image authorization at the transaction boundary, including
  token-to-creator binding, linked-wallet changes, rate limits, ETag/`If-Match`, concurrent writes,
  image signatures/types/sizes, URL policy, and reorg survival.
- Test malformed and adversarial addresses, big integers, dates, cursors, JSON, headers, images,
  disconnects, slow clients, and high-cardinality subscriptions without using real credentials.
- Compare OpenAPI, generated client behavior, runtime routes, and status/problem schemas for drift.

Acceptance criteria:

- Every public and authenticated endpoint has authentication/authorization, input, output,
  resource-limit, data-consistency, and error-path dispositions.
- No creator credential or linked wallet can mutate another token or bypass optimistic concurrency.
- Parser and verifier tests cover missing, duplicate, oversized, ambiguous, expired, not-yet-valid,
  wrong-key, wrong-app/audience/issuer, and malformed credential cases as applicable to the actual
  Privy contract.
- Public errors/logs never contain credentials, raw database/RPC URLs, SQL details, or sensitive
  upstream payloads.
- The task produces no API, identity, SQL, or OpenAPI change.

## Task 5 — Web, wallet, transaction, and browser-security audit · Risk: high

**Depends on:** Task 1.

- Trace launch, approve, buy, sell, claim, metadata, and network-switch flows from untrusted UI/API
  state through simulation, wallet request, receipt, indexing, reorg, safe, and finalized states.
- Verify exact account/chain/target/value/arguments/deadline/minimum-output binding and behavior when
  any dependency changes between render, simulation, signature, receipt, and canonical observation.
- Review generated ABI/API boundaries, reviewed deployment lookup, test-fixture isolation,
  `NEXT_PUBLIC_*` exposure, hydration boundaries, query keys/cache invalidation, SSE reconnection,
  duplicate submissions, and stale approvals.
- Audit all metadata rendering, links, images, error text, CSP/header construction, redirects,
  logging/telemetry redaction, source maps, and production bundles for injection and data leakage.
- Prove the E2E RPC forwarding route cannot be enabled in a production artifact or used to relay
  unbounded attacker-selected RPC traffic to an operator-selected upstream.
- Re-run keyboard, focus, semantics, reduced motion, responsive, failure-state, and automated
  accessibility coverage because inaccessible transaction disclosure is a safety failure.

Acceptance criteria:

- A write cannot proceed unless reviewed deployment, supported chain, selected account, current
  simulation intent, and displayed confirmation agree byte-for-byte on security-relevant fields.
- Mined, reverted, indexing, indexed, reorged, safe, and finalized states remain distinct under
  reload, disconnect, duplicate click, stale query, and reorg.
- Untrusted metadata remains inert under server rendering, hydration, image fallback, external-link,
  clipboard, and error paths.
- Production builds contain no test wallet, Anvil fixture escape, secret canary, mock market value,
  or unreviewed address.
- The task produces no TypeScript, CSS, generated client, ABI, or public configuration change.

## Task 6 — Code quality, architecture fitness, and measured optimization audit · Risk: high

**Depends on:** Task 1.

This is the dedicated code-cleanliness and optimization step. It is separate from security so
maintainability and performance evidence cannot disappear behind vulnerability severity.

- Identify dead code, unused configuration, obsolete compatibility paths, duplicate business
  rules, oversized modules/functions, unclear ownership, inconsistent error semantics, hidden
  mutation/aliasing, missing cancellation, resource leaks, brittle positional conversions, and
  generated or vendored code accidentally treated as first-party source.
- Verify package/layer direction and domain ownership across Solidity, `internal/chain`,
  `internal/ledger`, feature ports, `internal/store/postgres`, API DTOs, generated sqlc/OpenAPI
  types, web domain helpers, React components, and release scripts. Runtime layers must not import
  persistence/generated representations across established boundaries.
- Measure representative indexer throughput, allocation pressure, RPC/database round trips,
  projection/aggregation rebuild cost, lock contention, query plans, API latency/concurrency, SSE
  fan-out, Next.js route payloads, client JavaScript, chart lifecycle, render churn, contract gas,
  bytecode size, and release-gate duration.
- Audit `big.Int` copy discipline, integer conversions, address/hash codecs, goroutine/channel and
  connection ownership, React effect cleanup, cache-key stability, subprocess termination, and
  error wrapping/observability.
- Classify each proposal as correctness, maintainability, performance, or style. Style-only churn,
  speculative abstractions, blanket rewrites, dependency swaps without evidence, and micro-
  optimizations outside measured hot paths are rejected.

Acceptance criteria:

- The report contains a module ownership/dependency map and identifies every boundary exception
  with rationale; no circular or persistence-type leakage is silently accepted.
- Every cleanup candidate demonstrates concrete dead code, duplication/drift risk, defect pattern,
  or maintenance cost. Line count and cyclomatic complexity alone are not findings.
- Every optimization candidate records workload, dataset/cardinality, environment, warm-up/sample
  method, median plus tail or variance where meaningful, baseline result, target/budget, and a
  semantic-equivalence test. No unmeasured performance refactor reaches Task 8.
- SQL optimization includes query-plan and lock evidence; Go optimization includes benchmark or
  profile evidence; web optimization includes route/bundle/render evidence; Solidity optimization
  includes gas/bytecode evidence without changing economics or security invariants.
- Existing budgets in `web/performance-budgets.json` and release timeouts are evaluated against
  measured user/CI goals rather than automatically accepted as correct.
- The task produces no refactor, cleanup, dependency, or optimization change.

## Task 7 — Supply chain, CI, release, and operational-security audit · Risk: high

**Depends on:** Task 1.

- Inventory direct/transitive Go, npm, Foundry, Python/Slither, GitHub Action, Docker image, browser,
  and system-tool dependencies with version, provenance, license, maintenance, and runtime/release
  reachability.
- Run ecosystem-native vulnerability checks and manually triage each advisory. In particular,
  reconcile the known `npm ci` advisory count with the production dependency graph; do not report
  raw audit totals as vulnerabilities.
- Review lockfiles, Git submodules, install/build scripts, lifecycle scripts, generated artifacts,
  caches, action SHA pins, workflow permissions, secret exposure, untrusted PR behavior,
  environment protection, artifact provenance, branch protection, path filters, and skip logic.
- Trace `DEPLOYMENT_MANIFEST_PATH` and deployment code-hash verification through every API/indexer,
  E2E, release, and production startup path. Prove the local manifest overlay cannot become a
  mutable production trust root, and determine whether runtime bytecode verification is required.
- Verify release target selection, fail-closed production validation, subprocess timeouts/cleanup,
  cross-platform behavior, Anvil isolation, database lifecycle, rollback, health checks, backup/
  restore assumptions, alert ownership, and evidence retention.
- Compare pinned Node/npm/Go/Foundry/solc/Slither/PostgreSQL versions across manifests, CI, scripts,
  and documentation. Record toolchain drift even when the current gate happens to pass.

Acceptance criteria:

- Every advisory has reachability, affected version, exploit prerequisite, compensating control,
  disposition, and upgrade/regression impact; counts alone are not accepted.
- CI jobs use least privilege and untrusted pull requests cannot receive production secrets or
  publish artifacts without an independently enforced approval boundary.
- Required gates cannot pass through path-filter gaps, missing tools, conditional skips, stale
  generated copies, or production/test fixture confusion.
- Recovery and operational claims distinguish repository-tested behavior from production controls
  that remain external or unknown.
- The task produces no lockfile, workflow, script, dependency, or runbook change.

## Task 8 — Finding validation, remediation, independent review, and closeout · Risk: high

**Depends on:** Tasks 2–7.

- Reconcile duplicate/cross-layer candidates and independently validate each one against the
  immutable baseline. Reject scanner noise and speculative cleanup with written counterevidence.
- Order fixes by exploitability and blast radius: Critical/High security and correctness first,
  then Medium/Low hardening, then evidence-backed quality/performance work.
- Assign non-overlapping remediation packets to Luna/high implementation agents. Each packet names
  the finding, allowed files, prohibited semantic changes, required tests, and expected commit.
- Keep schema/contract/public-API changes isolated and subject to their normal high-risk pre-flight;
  a Plan 5 finding does not waive compatibility or migration review.
- Independently review each fix commit, run focused negative/regression tests, then run the complete
  cross-stack release gate from a clean checkout.
- Publish the final findings/coverage report with `fixed`, `rejected`, `accepted`, or `deferred`
  disposition and update `backlog.md` for every unfinished item.

Acceptance criteria:

- No source change exists without a validated finding or measured quality/performance case.
- Every fixed security finding has a regression test that fails on `6184bc5` or a source-backed
  proof when safe runtime reproduction is inappropriate, and passes after the fix.
- Every optimization preserves output and invariant behavior and includes reproducible before/
  after evidence; regressions outside the measured hot path fail the normal gates.
- Contract checks, Slither, backend build/vet/race/integration/lint/migration/sqlc/artifact checks,
  web format/lint/typecheck/unit/build/bundle/browser checks, and the Anvil cross-stack gate pass.
- GitHub CI passes on the reviewed head. Conditional live/fork/production checks are reported as
  conditional and are never converted into deterministic local evidence.
- The final report states the two existing external backlog items plus any newly deferred item.

## Dependency graph

```text
                       -> Task 2 --\
                       -> Task 3 ---\
Task 1 (baseline) -----+-> Task 4 ----+-> Task 8 (validate, remediate, re-review, close)
                       -> Task 5 ---/
                       -> Task 6 --/
                       -> Task 7 -/
```

Tasks 2–7 may run in parallel only when their path ownership is non-overlapping and all agents
remain read-only. Task 8 fixes run in small, coordinated batches because all agents share one
working tree.

## Deferred external boundary

Plan 5 can audit repository controls but cannot supply or approve:

1. The funded and independently reviewed Robinhood chain-46630 deployment manifest and first live
   acceptance evidence.
2. Production Privy, RPC/API/origin, database/hosting/domain/CDN/WAF, secret-manager, monitoring,
   and rollback values and owners.
3. Production pause multisig, timelock, treasury, legal/geo policy, and external audit evidence.
4. Production CoinGecko commercial credentials and attribution implementation.

These remain human/external inputs. Their absence is an explicit confidence boundary, not a reason
to invent test values or declare the system production-ready.
