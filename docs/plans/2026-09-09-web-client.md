# Web Client — Pre-flight and Task List

> **Workflow:** `AGENTS.md` governs implementation, verification, commit, and independent
> review. This document defines Plan 4. It is planning only; no Plan 4 implementation is
> included in this commit.

**Status:** Design and task decomposition prepared. Implementation is deliberately not started.
Every task is high risk because it touches wallet transactions, public API contracts, or the
production user interface. Independent pre-flight review is required before Task 1.

**Goal:** Deliver the core non-custodial Launchpad web client against the reviewed contract and
Backend Plan 3 boundaries, with deterministic transaction construction, reorg-aware reads,
Privy creator authorization, production-grade UX, and reproducible browser verification.

**Spec:** `docs/specs/2026-09-09-web-client-design.md`

**Depends on:** Contract Foundations, Backend Foundations, Backend Indexer Plan 2 code, and
Backend API and Identity Plan 3 code. Live release also depends on the external items listed at
the end of this plan.

## Pre-flight findings

### BLOCKERS

#### B1 — The browser contract artifact boundary does not exist

The repository has event ABIs for indexing but no minimal, versioned browser ABI bundle for
launch, buy, sell, allowance, claims, and post-graduation routing. Importing arbitrary Foundry
output would expose unstable artifact shape and excessive bytecode. Task 1 generates a minimal
bundle from authoritative contracts and fails CI on drift.

#### B2 — Historical protocol analytics has storage but no public endpoint

`protocol_daily` exists, while Plan 3 exposes only `/v1/stats/protocol`. Plan 4 adds a
snapshot-bound daily read endpoint because daily volume, launch, trade, and graduation charts are
part of product scope.

#### B3 — Forum has no implementable contract

There is no forum schema, authorization policy, moderation model, media policy, or API. A static
mock would be false completion. Forum/Memestock is excluded from Plan 4 and requires its own
pre-flight and backend plan.

#### B4 — Live configuration is intentionally incomplete

The chain-46630 deployment, production Privy configuration, allowed origins, hosting, and edge
policy do not exist. They do not block deterministic implementation, but they block any claim of
live testnet or production acceptance.

### RISKS

- Informational backend quotes can be stale between render and signature. Every write uses a
  current contract quote or exact simulation immediately before submission.
- A successful receipt can precede indexing. UI state must not present mined as indexed or
  finalized.
- Cursor pages can become invalid after a reorg. Mixed-snapshot lists are prohibited.
- Embedded and connected wallets can differ. Creator authorization remains based on
  server-verified linked wallets.
- Token strings, images, and social URLs are attacker-controlled content.
- Client-only wallet/chart libraries can accidentally move whole routes out of Server Components
  and inflate the initial bundle.
- Mobile transaction layouts can hide minimum output, fees, deadlines, and warnings unless they
  are explicit acceptance criteria.

## Locked decisions

1. `web/` is a standalone Next.js App Router workspace with strict TypeScript and a committed
   npm lockfile.
2. Tailwind CSS owns styling tokens; shadcn/ui is source-owned primitive code, not a runtime UI
   abstraction boundary.
3. Privy React + Privy's wagmi adapter + wagmi + viem is the only wallet stack. A second wallet
   modal is not layered on top.
4. TanStack Query owns remote server state. Global client state remains local/contextual until a
   measured need justifies another store.
5. The checked-in OpenAPI document generates the browser client. Handwritten duplicate DTOs are
   rejected by the drift gate.
6. Contract writes use generated minimal ABIs and the reviewed deployment manifest. Addresses
   are never duplicated in page code.
7. Backend REST is authoritative for indexed reads; RPC is authoritative for live contract
   simulation and wallet writes.
8. Monetary and token quantities remain strings/`bigint`; JavaScript `number` is display-only.
9. SSE carries invalidation hints only. REST snapshots replace cached canonical state.
10. Lightweight Charts owns area/candlestick/volume views and ships required attribution.
11. Forum/Memestock and heatmap are out of Plan 4 until their data/product contracts exist.
12. Task 1 pins exact Node and package versions after checking supported releases; planning prose
    does not freeze a floating `latest` command.

## Task 1 — Reproducible web and contract boundaries · Risk: high

**Delivery:** One infrastructure commit before page work.

- Scaffold `web/` with Next.js App Router, strict TypeScript, Tailwind, lint/format, unit tests,
  and Playwright.
- Pin Node and dependencies; commit `package-lock.json` and engine metadata.
- Add web commands for setup, format check, lint, typecheck, unit test, production build, and
  browser tests.
- Generate a typed API client from `backend/openapi/v1.json`; add `web-api-sync` and
  `web-api-diff` commands.
- Generate minimal browser ABIs and deployment types from authoritative contract artifacts; add
  `web-contracts-sync` and `web-contracts-diff` commands.
- Add `GET /v1/stats/protocol/daily` as a snapshot-bound, range-bounded read contract, update
  OpenAPI, and regenerate the client.
- Configure Robinhood chain data only from reviewed manifests. Missing testnet data stays
  fail-closed.
- Extend CI path filters and verification without weakening backend or contract gates.

Acceptance criteria:

- A clean checkout reproduces generated API and ABI files byte-for-byte.
- Unknown deployment, missing public configuration, wrong chain, stale OpenAPI, or stale ABI
  fails before a transaction-capable build is deployable.
- Generated artifacts contain no bytecode, private configuration, or unrelated contract surface.
- Protocol-daily reads cannot mix snapshots and have deterministic date ordering and bounds.
- No product page beyond a minimal diagnostic shell is implemented in this task.

## Task 2 — Application shell and design system · Risk: high

**Depends on:** Task 1.

- Root layout, providers, navigation, footer, theme, fonts, metadata, icons, and route transition
  boundary.
- Semantic tokens and reusable button, input, dialog, sheet, tab, badge, skeleton, empty, error,
  toast, and transaction-status primitives.
- Desktop/mobile navigation for Explore, Graduated, Create, Analytics, Docs, and Profile.
- Shared non-custodial and risk language.
- CSP/security headers and safe external-link/image primitives.

Acceptance criteria:

- 360 px, tablet, small-laptop, and wide-desktop layouts have no clipped primary action.
- Full keyboard navigation, visible focus, semantic landmarks, reduced motion, and automated
  accessibility checks are present.
- Loading, empty, unavailable, stale, and failure states are first-class components.
- No mocked market values appear in production routes.

## Task 3 — Data, identity, wallet, and transaction foundations · Risk: high

**Depends on:** Tasks 1–2.

- Privy, QueryClient, and Privy wagmi provider nesting per the supported integration contract.
- API base URL, public chain/deployment configuration, generated-client wrapper, problem mapping,
  snapshot/cursor types, and query-key factory.
- Wallet readiness, selected account, supported-chain guard, balance/allowance reads, explicit
  switch-network flow, explorer links, and transaction state machine.
- Decimal-string/`bigint` parsing and deterministic display/parse helpers.
- SSE reconnect and targeted query invalidation.

Acceptance criteria:

- Wallet-dependent controls do not render an authorized state before provider readiness.
- Wrong-chain, disconnected, rejected-signature, RPC failure, revert, mined, indexed, safe, and
  finalized states are distinct and tested.
- SSE loss never loses data; reconnect starts with REST refetch.
- Tokens and authorization headers never enter logs, URLs, analytics, or persistent storage.

## Task 4 — Explore and Graduated discovery · Risk: high

**Depends on:** Task 3.

- `/` and `/graduated` routes using generated token-list APIs.
- Search, phase, supported sorts, stable cursor pagination, URL-backed filters, token cards,
  snapshot/finality indicators, and resilient image fallbacks.
- Responsive list density and accessible loading/empty/error/cursor-invalidated states.

Acceptance criteria:

- URL state is shareable and back/forward navigation restores the same query.
- Cursor invalidation discards the affected page chain and refetches page one.
- No fabricated total count is shown because the API does not expose one.
- Malicious metadata cannot inject markup or script.

## Task 5 — Token detail and market visualization · Risk: high

**Depends on:** Tasks 3–4.

- `/token/[address]` identity, creator, phase, reserves, graduation progress, market metrics,
  links, finality, and explorer navigation.
- Candle timeframe selector, area/candlestick toggle, volume pane, resize lifecycle, empty ranges,
  and incremental last-bar refresh.
- Recent-trades and holders tabs with stable cursor pagination.
- SSE invalidation scoped to the displayed token.

Acceptance criteria:

- Chart values derive only from candle DTOs; execution and spot prices are not conflated.
- Chart instances and observers are disposed on route/token changes.
- TradingView attribution is visible where required.
- Large integers format without precision loss; malformed quantities fail closed.
- The unsupported heatmap control is not displayed.

## Task 6 — Launch and trading transactions · Risk: high

**Depends on:** Tasks 1, 3, and 5.

- `/create` name, symbol, image preview, links, optional developer buy, live factory state, exact
  launch value, validation, confirmation, and receipt flow.
- Curve buy/sell with exact quote, slippage, deadline, balance/allowance, approval, write, receipt,
  and indexing state.
- Post-graduation swap handoff or router flow using only the reviewed router deployment.
- Creator/refund claim actions when the selected wallet is eligible.
- Typed custom-revert mapping from generated ABIs.

Acceptance criteria:

- Every write is simulated with exact account, value, and arguments immediately before submission.
- Launch ETH equals launch fee plus developer buy; ambiguous overpayment is impossible.
- Sell approval and transaction are separate, resumable states. Duplicate clicks cannot submit
  the same action twice.
- Deadlines and minimum outputs are visible before signature and boundary-tested.
- Receipt success does not mutate canonical API data optimistically; indexing clears only after a
  fresh snapshot observes the transaction.
- Anvil browser tests cover launch, buy, sell, rejection, revert, wrong chain, and reorg refresh.

## Task 7 — Creator metadata, analytics, profile, and docs · Risk: high

**Depends on:** Tasks 3–6 and Task 1's daily stats endpoint.

- Creator-only metadata/image editor with Privy tokens, linked-wallet authorization, validation,
  preview, ETag/If-Match concurrency, and conflict recovery.
- `/analytics` summary tiles and canonical daily volume/launch/trade/graduation history.
- `/profile` identity, linked wallets, claim/refund availability, and disconnected states.
- `/docs` content for launch flow, curve/graduation, fees, risks, non-custody, finality, contracts,
  and explorer links.

Acceptance criteria:

- The client never decides creator authorization; server denial remains authoritative.
- Revision conflicts refetch and require review before resubmission.
- Invalid images and unsafe URLs fail before upload and remain handled if the server rejects them.
- Analytics labels ETH-native values honestly and omits USD while unavailable.
- Documentation matches deployed V1 values and never promises liquidity or returns.

## Task 8 — Runtime hardening and web release gate · Risk: high

**Depends on:** Tasks 1–7.

- Production headers, caching, error boundaries, not-found behavior, telemetry scrubbing, bundle
  analysis, route performance budgets, and deployment validation.
- Complete Playwright desktop/mobile/reduced-motion/accessibility suite.
- Anvil web → API → indexer → PostgreSQL → contract loop for representative reads and writes.
- CI `web` gate and a root verification entrypoint composing contract, backend, and web gates
  without silently skipping required services.
- Operational runbook for public variables, CSP origins, Privy setup, deployment selection,
  rollback, and health checks.

Acceptance criteria:

- Format, lint, strict typecheck, unit/component tests, production build, drift gates, and required
  Playwright paths pass from a clean checkout.
- No production bundle contains secrets, private RPC credentials, unreviewed addresses, mock
  market values, or test wallet keys.
- Core routes meet performance budgets on small-laptop and mobile profiles.
- Live Robinhood and real Privy evidence is separate from deterministic Anvil evidence.

## Dependency graph

```text
Task 1 -> Task 2 -> Task 3 -> Task 4 -> Task 5 -> Task 6 -> Task 7 -> Task 8
```

## Deferred user/external inputs

1. Reviewed Robinhood chain-46630 deployment manifest and funded test wallets.
2. Real Privy app ID/client ID and verified dashboard behavior.
3. Production API/RPC URLs and allowed web origins.
4. Production hosting, domain, CSP/edge rate limits, monitoring, and rollback ownership.
5. ETH/USD enrichment source.
6. Governance signers, timelock, legal/geo policy, and external audit.
7. Forum/Memestock product model, moderation, persistence, and API plan.

These inputs are not replaced with guessed values. Tasks 1–8 can use deterministic local
configuration and generated keys; missing external inputs block only corresponding live
acceptance and release claims.
