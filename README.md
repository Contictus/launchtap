# Launchpad

Launchpad is a non-custodial fixed-supply token launchpad for Robinhood Chain. Tokens start
on an integer bonding curve, graduate at a configured threshold, and move to a Uniswap v2
pair whose initial LP position is burned. Users sign their own transactions; the backend
indexes canonical chain data and never holds trading funds.

## Project status

| Area | Status |
| --- | --- |
| Contract Foundations (Tasks 1–12) | Complete |
| Backend Foundations (Tasks 1–12) | Complete |
| Backend Indexer Task 2 | Complete |
| Backend Indexer Task 3 | Complete |
| Backend Indexer Tasks 4–5 | Implemented; acceptance pending |
| API and identity (Plan 3) | Not started |
| Web client | Not started |

Plan 2 still needs the external Robinhood probe and reviewed chain-46630 deployment
manifest. The Anvil end-to-end indexer scenario and full observability gate must pass before
this milestone is merged to `main`.

## Repository layout

- `contracts/` — Solidity, Foundry tests, deployment scripts and artifacts.
- `backend/` — Go module and PostgreSQL-backed indexer.
- `docs/specs/` — normative specifications.
- `docs/plans/` — implementation plans and acceptance criteria.
- `notes.md` — product and architecture decisions.
- `backlog.md` — externally blocked or deliberately deferred work.

Backend packages include `internal/chain` (RPC/ABI/discovery), `internal/curve` (stdlib-only
curve mirror), `internal/indexer` (chunk loop and reorg recovery), `internal/ledger` (domain
events), `internal/stats` (aggregation), and `internal/store/postgres` (pgx/sqlc/migrations).

## Toolchain and quick start

- Go 1.26.x; PostgreSQL 18.6
- Foundry 1.8.1; Solidity 0.8.36
- pgx/v5, sqlc 1.31.1, goose/v3, golangci-lint 2.13.2

```powershell
cd contracts
forge install
forge test

cd ../backend
go run github.com/go-task/task/v3/cmd/task@v3.53.1 setup
go run github.com/go-task/task/v3/cmd/task@v3.53.1 verify
```

The indexer requires `CHAIN_ID`, `DEPLOYMENT_ID`, `RPC_URL`, `DATABASE_URL`, and
`INDEXER_WORKER_ID`. Run migrations explicitly with `task migrate -- up`; `cmd/indexer`
never runs migrations during startup. Docker is required for PostgreSQL integration tests.

## Architecture invariants

- Solidity and the canonical event ledger are authoritative; projections and aggregates are
  rebuildable from surviving canonical events.
- Amounts use `*big.Int` in Go and `NUMERIC(78,0)` in PostgreSQL. Monetary floats are not used.
- One indexed chunk is one transaction. Advisory ownership uses a dedicated PostgreSQL
  session; automatic reorg recovery is limited to data above the locally confirmed safe head.
- `latest`, `safe`, and `finalized` are tracked independently. Confirmation counts are not
  finality on non-local deployments.
- Contract artifacts, ABIs, vectors, manifests, migrations and sqlc output are single-sourced
  and protected by drift checks.

## Reading order

1. [`AGENTS.md`](AGENTS.md)
2. [`notes.md`](notes.md)
3. [`docs/specs/2026-09-01-contract-core-design.md`](docs/specs/2026-09-01-contract-core-design.md)
4. [`docs/specs/2026-09-01-backend-core-design.md`](docs/specs/2026-09-01-backend-core-design.md)
5. [`docs/plans/2026-09-01-contract-foundations.md`](docs/plans/2026-09-01-contract-foundations.md)
6. [`docs/plans/2026-09-01-backend-foundations.md`](docs/plans/2026-09-01-backend-foundations.md)
7. [`docs/plans/2026-09-05-backend-indexer.md`](docs/plans/2026-09-05-backend-indexer.md)

`dev` is the active implementation branch. `main` contains verified milestones only.
