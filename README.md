# launchpad

A pons-style **fixed-supply token launchpad** on Robinhood Chain (EVM L2). Bonding curve
→ graduation at a threshold → liquidity moved to a Uniswap v2 pool with the LP burned.
Non-custodial: every state change is submitted by the user's own wallet.

## Status

Contract and backend design closure is complete. There is **no application code yet** — the
next gate is the normal independent pre-flight review, followed by explicit user approval
to start implementation.

## Repository layout

```
AGENTS.md          Agent instructions + workflows (single source of truth;
                   CLAUDE.md just imports it). READ THIS FIRST.
README.md          This file.
notes.md           Project brain: reference-product analysis, every decision
                   (chain, economics, curve simulation, auth), open questions.
backlog.md         Unfinished-work log.
docs/specs/        Normative contract core and backend core design specs.
docs/plans/        Contract and backend implementation task lists with acceptance criteria.
backend/           Go module — created by Backend Foundations. Modular monolith:
  internal/curve/      pure bonding-curve math (big.Int), zero deps
  internal/config/     env + compiled-in chain registry
  internal/store/      Postgres: pgx + sqlc + goose + Unit of Work
  internal/chain/      RPC / logs / decoding                     (Plan 2)
  internal/indexer/    sync loop, reorg, event routing            (Plan 2)
  internal/<feature>/  launch / trading / token / holder / candle / stats / metadata
  internal/apiserver/  huma REST + SSE                            (Plan 3)
  cmd/api  cmd/indexer  cmd/migrate
contracts/         Solidity + Foundry — created by Contract Foundations.
web/               Next.js frontend (later).
```

## Where to start

1. `AGENTS.md` — roles, multi-agent workflow, git workflow.
2. `notes.md` — the decisions and the reasoning behind them.
3. `docs/specs/2026-09-01-contract-core-design.md` — authoritative economics,
   contract state machine, graduation, security, and events.
4. `docs/specs/2026-09-01-backend-core-design.md` — indexer, finality, storage,
   market semantics, auth, and API boundaries.
5. `docs/plans/2026-09-01-contract-foundations.md` — first implementation task list;
   produces the authoritative contracts and curve vectors.
6. `docs/plans/2026-09-01-backend-foundations.md` — backend foundation task list;
   its Go curve tasks consume those vectors.

## Key facts

- **Chain:** Robinhood Chain (testnet chainId 46630, mainnet 4663), an EVM-equivalent
  Arbitrum Orbit L2. Contracts are written EVM-agnostic. Dev on Anvil.
- **Backend:** Go 1.26. Modular monolith, two processes (`api` + `indexer`) over one Postgres.
  REST/JSON via `huma`. Custom Go indexer (`go-ethereum` + `abigen`), not Ponder.
- **Wallet / auth:** Privy — access token proves the session; identity token proves linked
  wallets. No custom auth/session system.
- **Curve:** virtual-reserve constant-product. Solidity is authoritative; the Go `curve`
  package is a mirror verified by differential vectors.
- **Finality:** latest data is provisional; the indexer separately tracks Robinhood RPC
  `safe` and `finalized` heads and rolls provisional data back on reorg.
- **Budget:** zero-cost — free tiers only; dev Postgres via Docker / testcontainers.
- **Working model:** Codex builds and commits implementation; Claude is the independent
  reviewer / architect and commits only docs. Branches: `main` (verified) / `dev` (active).
