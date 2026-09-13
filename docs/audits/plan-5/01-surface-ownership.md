# Plan 5 Task 1 — Surface Ownership Ledger

The ledger assigns every first-party runtime or release directory in the immutable baseline one
primary audit task. Shared review is explicit in the final column; it never creates a second
primary owner. A path is assigned by its production or release role, not by file count.

| Baseline surface | Primary task | Shared boundary / review note |
| --- | --- | --- |
| `contracts/src/` | Task 2 | Task 2 owns contract behavior, external calls, authority, and economics. Task 3 consumes emitted events; Task 5 consumes ABI/write intent. |
| `contracts/test/` | Task 2 | Contract tests and adversarial/invariant gaps are Task 2 evidence. |
| `contracts/fork-test/` | Task 2 | Fork assumptions and release-facing contract behavior; Task 7 owns secret/fork configuration. |
| `contracts/script/deployment/` | Task 2 | Deployment validation semantics and pair/address assumptions; Task 7 reviews release invocation and operator exposure. |
| `contracts/script/local/` | Task 7 | Local deployment/bootstrap scripts are release and environment boundaries; Task 2 checks contract assumptions they encode. |
| Root files `contracts/script/*.s.sol` | Task 2 | Foundry deployment/vector/fixture scripts encode contract behavior and evidence generation; Task 7 cross-reviews invocation, provenance, and operator exposure. |
| `contracts/abi/v1/`, `contracts/fixtures/v1/`, `contracts/vectors/v1/`, `contracts/storage-layout/v1/`, `contracts/sizes/v1/` | Task 2 | These are contract evidence inputs; Task 7 verifies provenance and drift. |
| `contracts/deployments/` | Task 7 | Reviewed deployment manifests and generated copies are release trust inputs; Task 2 checks address/economic binding. |
| `contracts/coverage/`, `contracts/slither/` | Task 7 | Generated/scanner evidence provenance; Task 2 re-justifies contract findings and suppressions. |
| `contracts/lib/forge-std/`, `contracts/lib/openzeppelin-contracts/` | Task 7 | Vendored submodules are supply-chain inputs, not first-party code-quality scope. |
| `contracts/scripts/` | Task 7 | Toolchain/bootstrap/check/release execution, subprocesses, and fail-closed behavior. |
| Contract-root manifests and configs (`contracts/foundry.toml`, `contracts/foundry.lock`, `contracts/dependencies.lock`, `contracts/slither.config.json`) | Task 7 | Toolchain pins, lock/provenance, and scanner configuration; Task 2 consumes their behavioral settings. |
| `backend/cmd/api/` | Task 4 | API startup, configuration wiring, and shutdown. |
| `backend/cmd/indexer/` | Task 3 | Indexer startup, deployment loading, writer ownership, and shutdown. |
| `backend/cmd/migrate/` | Task 7 | Explicit migration operator path and release/rollback behavior; Task 3 reviews schema effects. |
| `backend/cmd/check-deployments/`, `backend/cmd/check-openapi/`, `backend/cmd/sync-curve-vectors/`, `backend/cmd/sync-event-abis/` | Task 7 | Generated-artifact provenance and drift gates; owning domain tasks consume their outputs. |
| `backend/internal/apiserver/`, `backend/internal/privyauth/` | Task 4 | HTTP, identity, authorization, limits, error mapping, and credential redaction. |
| `backend/internal/config/` | Task 4 | Precedence, secret/public boundary, URL validation, and fail-closed startup; Task 7 checks release injection. |
| `backend/internal/metadata/`, `backend/internal/profile/`, `backend/internal/token/`, `backend/internal/trading/`, `backend/internal/quote/`, `backend/internal/candle/`, `backend/internal/observation/`, `backend/internal/pagination/`, `backend/internal/realtime/` | Task 4 | API-facing domain ports, cursors, snapshots, and SSE behavior. Task 6 checks layer direction. |
| `backend/internal/chain/*.go` (excluding generated/testdata subdirectories) | Task 3 | RPC validation, finality, log partitioning, decoding, and ABI routing. |
| `backend/internal/indexer/`, `backend/internal/ledger/`, `backend/internal/holder/` | Task 3 | Canonical event ingestion, reorg/restart behavior, and domain event ownership. |
| `backend/internal/store/postgres/*.go` and `postgrestest/` | Task 3 | Transactions, ownership, canonical data, projections, and database behavior. |
| `backend/internal/store/postgres/migrations/`, `backend/internal/store/postgres/queries/` | Task 3 | Schema/query semantics, migration lifecycle, and canonical persistence rules. |
| `backend/deployments/*.go` | Task 7 | Deployment registry schemas are release trust inputs; runtime consumers remain cross-reviewed. |
| `backend/internal/curve/` | Task 2 | Go is a deterministic mirror of Solidity curve math; Task 2 owns differential/economic equivalence. |
| `backend/internal/stats/` | Task 6 | Aggregation architecture, measured rebuild cost, allocation, and query/resource efficiency; Task 3 checks canonical inputs. |
| `backend/openapi/`, `backend/deployments/testdata/`, `backend/internal/chain/abi/v1/`, `backend/internal/chain/testdata/`, `backend/internal/curve/testdata/`, `backend/internal/store/postgres/sqlc/` | Task 7 | Generated/copied artifacts are supply-chain/provenance surfaces; Tasks 2–4 own semantic consumers. |
| `backend/scripts/` | Task 7 | Anvil, subprocess, cleanup, environment, and cross-platform release helpers. |
| Backend-root manifests and configs (`backend/go.mod`, `backend/go.sum`, `backend/Taskfile.yml`, `backend/.golangci.yml`, `backend/sqlc.yaml`, `backend/.env.example`) | Task 7 | Dependency/tool pins, gate composition, and configuration examples; Tasks 3–4 review runtime semantics. |
| `web/app/`, `web/src/`, `web/e2e/`, `web/scripts/` | Task 5 | Wallet/transaction/browser/API/UI and browser-security flows. Task 7 owns package/install/build provenance. |
| Web-root manifests and configs (`web/package.json`, `web/package-lock.json`, `web/next.config.ts`, `web/tsconfig.json`, `web/playwright.config.ts`, `web/vitest.config.ts`, `web/performance-budgets.json`, `web/.env.example`) | Task 7 | Dependency, build, browser-runner, and bundle-policy provenance; Task 5 reviews runtime behavior. |
| `.github/workflows/` | Task 7 | CI permissions, path filters, skips, action pins, secrets, and artifact publication. |
| root `scripts/` | Task 7 | Cross-stack release orchestration and subprocess timeout/cleanup. |
| `docs/runbooks/` and release-facing root docs | Task 7 | Operational claims and deployment prerequisites are compared with executable behavior; not proof of external controls. |

## Non-runtime material

`docs/specs/`, `docs/plans/`, `AGENTS.md`, `CLAUDE.md`, `notes.md`, `PRODUCT.md`, `DESIGN.md`,
and `backlog.md` are governing or contextual documents, not first-party runtime directories.
Task 1 reconciles them; later tasks cite them as requirements or caveats. `.impeccable/` is
design/review evidence, not a deployed surface. None is silently treated as clean runtime code.

The new `docs/audits/plan-5/` directory is Task 1's evidence surface and is outside the
immutable implementation baseline.

## Ownership completeness rule

Before a later task closes, its report must enumerate every path in its ledger row, state whether
it was reviewed, and link any cross-boundary finding to the primary owner's report. A missing,
generated, vendored, or test-only path is an explicit disposition, never an implicit pass.

Rows use the most-specific-path rule: a nested row owns that nested directory, and a parent row
explicitly excludes it. Thus generated `sqlc`, ABI, fixture, vector, deployment, and testdata
directories have one primary owner even when their runtime parent has another owner.
