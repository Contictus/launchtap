# Web Client Design

**Status:** Design prepared for Plan 4. Implementation has not started.

**Purpose:** Define the browser application that consumes the reviewed Launchpad contracts
and Backend Plan 3 API without introducing a second source of truth for chain state, pricing,
authorization, or transaction semantics.

## 1. Scope

Plan 4 delivers the core public launchpad experience:

- Explore and Graduated token discovery.
- Token detail, candles, recent trades, and holders.
- Curve-phase buy and sell transactions.
- Post-graduation routing to the reviewed Uniswap v2 router.
- Token creation with an optional developer buy.
- Privy login, embedded and external EVM wallets, and creator-authorized metadata/image edits.
- Protocol analytics summary, static product documentation, finality states, and SSE-driven
  refresh hints.
- Responsive, accessible, testable production web delivery.

The following are not part of Plan 4:

- Forum/Memestock posting, reactions, moderation, reputation, and ranked community feeds.
  There is no canonical schema or API for them. They require a separate product/backend plan.
- A market heatmap. Neither its product meaning nor its data contract is defined.
- Invented token counts, USD prices, social data, or historical protocol series.
- Governance/admin transaction screens.
- Server-side transaction signing, relaying, custody, or private-key handling.

## 2. Locked architecture

The web application lives in `web/` and uses:

- Next.js App Router with strict TypeScript.
- React Server Components for static shell and indexable read-only content; Client Components
  only where wallet state, browser APIs, charts, forms, or SSE require them.
- Tailwind CSS for tokens and layout. shadcn/ui may seed accessible primitives, but copied
  components become repository code and must follow the project design system.
- Privy React for authentication and embedded/external wallet discovery.
- Privy's wagmi adapter, wagmi, viem, and TanStack Query for EVM and server-state work.
- A generated TypeScript client from `backend/openapi/v1.json`; application components do not
  hand-maintain response DTOs.
- Lightweight Charts for area/candlestick and volume rendering. Its required TradingView
  attribution is part of the release acceptance criteria.
- Playwright for browser flows and accessibility checks; focused unit tests cover pure format,
  validation, transaction-state, and cursor/SSE logic.

Exact package versions, Node version, and browser targets are pinned together in Plan 4 Task 1.
The lockfile is committed. No floating `latest` dependency remains in CI or reproducible setup.

## 3. Authority and data boundaries

PostgreSQL is never called from the web application. Indexed reads use the backend API. Direct
RPC access is limited to contract reads, simulation, wallet transactions, transaction receipts,
and chain switching.

| Concern | Authority |
| --- | --- |
| Launch economics and executable quotes | Deployed Solidity contract |
| Canonical history, projections, aggregates | Backend API |
| Wallet session and linked-wallet proof | Privy |
| Transaction authorization | User-selected wallet |
| Deployment addresses and chain metadata | Reviewed deployment manifest |
| UI cache | Disposable browser state |

Every API amount remains a base-unit decimal string until parsed to `bigint`. Floating-point
numbers are forbidden for transaction amounts, slippage bounds, token balances, fees, reserves,
and price calculations. Decimal formatting is presentation-only.

Every collection response retains its snapshot, block number, block hash, and finality. Cursor
invalidation (`409`) clears only the affected pagination chain and refetches page one. The client
never combines pages from different snapshots.

## 4. Route map

| Route | Responsibility |
| --- | --- |
| `/` | Explore curve-phase tokens, search, sort, pagination, launch CTA |
| `/graduated` | Graduated token discovery with the same stable list behavior |
| `/token/[address]` | Token summary, phase, chart, trades, holders, trade panel, metadata |
| `/create` | Launch form, current factory configuration, optional developer buy |
| `/analytics` | Protocol summary and canonical daily history once Task 1 exposes it |
| `/profile` | Current Privy identity, linked wallets, pending claim/refund actions |
| `/docs` | Product, economics, risks, graduation, fees, and non-custodial explanation |

Unknown or malformed token addresses render a stable not-found state. The application does not
create a `/forum` route until the forum contract is designed.

## 5. API consumption and cache policy

The generated client covers the checked-in OpenAPI artifact. Generation and drift checks fail
CI when the backend contract and generated TypeScript differ.

TanStack Query keys include chain ID, deployment ID, resource identity, filters, pagination
cursor, and snapshot where applicable. Default behavior is:

- REST fetch on route entry.
- No optimistic mutation of canonical market data.
- Bounded stale times for list/detail reads.
- SSE messages are invalidation hints, never payload authority.
- Reconnect sequence: fetch a fresh REST snapshot, then resume SSE-driven invalidation.
- Visibility/focus refetch is allowed; unbounded polling is not.

API failures are mapped by problem type and status. The UI distinguishes validation, auth,
authorization, stale revision, invalidated cursor, rate limit, service not ready, and generic
failure. It never displays raw internal error strings.

## 6. Wallet and transaction rules

The selected deployment manifest defines the only supported chain. Before any write, the client
requires the exact chain ID and reviewed contract address. A wrong network blocks submission and
offers an explicit switch action; the application never silently targets another deployment.

Every contract write follows this state machine:

1. Validate form values as integer base units and enforce local bounds.
2. Read current wallet, chain, phase, balances, allowance, and relevant contract state.
3. Obtain the backend informational quote for UX, then call the authoritative contract quote or
   simulate the exact write against current RPC state.
4. Derive explicit slippage and deadline arguments from user-visible settings.
5. Show an exact confirmation summary: action, token, input, minimum output, fee, network, and
   contract.
6. Request the wallet signature and submit once.
7. Track the transaction hash through receipt success or revert.
8. After receipt success, show an indexing state until a fresh backend snapshot includes the
   event. Receipt success is not represented as indexed finality.

Curve buys call `BondingCurveV1.buy`; curve sells perform ERC-20 allowance handling followed by
`BondingCurveV1.sell`. Launches call `LaunchFactory.launch` with exactly
`launchFee + developerBuyGross`. Post-graduation swaps use only the router address in the reviewed
manifest and an exact V1-compatible ABI. Approval scope must be disclosed.

Revert decoding uses the versioned contract ABI. Known custom errors receive specific,
actionable copy; unknown errors remain generic and include the transaction hash when available.

## 7. Authentication and creator writes

Privy providers mount in one client boundary near the application root. The UI waits for Privy
and wallet readiness before making authorization decisions. A connected wallet is not assumed to
be a linked wallet.

Metadata and image writes send both backend-required credentials:

- `Authorization: Bearer <access token>`
- `privy-id-token: <identity token>`

Creator authorization remains server-side. The browser cannot enable a write merely because the
selected address matches the displayed creator. Metadata/image writes use the current `ETag` as
`If-Match`; a revision conflict refetches and asks the user to review before retrying.

Images are previewed locally but accepted only after the backend validates type, size, digest,
and creator authorization. Links are rendered only as HTTPS URLs with safe external-link
attributes.

## 8. Visual and interaction system

The visual direction is a distinctive trading product, not a generic dashboard template.
Implementation starts from reusable semantic tokens for color, typography, spacing, radius,
elevation, focus, and motion. The product supports dark mode first and maintains sufficient
contrast in every market state.

Required responsive states are 360 px mobile, tablet, small laptop, and wide desktop. The token
trade action remains reachable on mobile without hiding risk copy or finality. Tables collapse
into labelled rows rather than horizontal overflow where practical.

Motion communicates route changes, submission progress, refresh, and state transitions. It must
respect `prefers-reduced-motion`, remain interruptible, and never delay a wallet confirmation or
error message.

## 9. Finality and trust presentation

The UI exposes provisional, safe, and finalized states without implying confirmation-count
finality. Provisional data can disappear after a reorg. A stale or unready backend is visible;
the application does not replace it with cached values presented as current.

All transaction surfaces include the non-custodial statement, irreversibility/loss warning,
contract and explorer links, and a clear distinction between estimated, submitted, mined,
indexed, safe, and finalized.

## 10. Security baseline

- No secret is exposed through `NEXT_PUBLIC_*`; only public app IDs, chain metadata, and public
  endpoints are client configuration.
- No arbitrary HTML from token metadata is rendered. `dangerouslySetInnerHTML` is forbidden for
  user-controlled content.
- Content Security Policy, frame restrictions, MIME sniffing protection, referrer policy, and
  permissions policy are defined and verified in production build tests.
- External URLs are scheme-validated. Token names, symbols, descriptions, and URLs are always
  treated as untrusted data.
- Wallet and API errors are scrubbed before logging. Tokens, signatures, private keys, and full
  authorization headers are never logged or persisted.
- Dependency installation is lockfile-frozen in CI.

## 11. Known seams before implementation

Plan 4 Task 1 must close these seams before page implementation:

1. Generate a minimal browser ABI bundle for `LaunchFactory`, `BondingCurveV1`, LaunchToken
   allowance methods, and the reviewed Uniswap v2 router. It is derived from contract sources and
   guarded by a drift check.
2. Generate a TypeScript API client from `backend/openapi/v1.json` and add a drift gate.
3. Add a snapshot-bound read-only protocol-daily endpoint for historical analytics charts.
4. Define supported deployment selection without inventing the missing chain-46630 manifest.

Forum, heatmap semantics, ETH/USD enrichment, and production Privy/origin/hosting values remain
separate deferred inputs. Their absence produces explicit unavailable states, not production
fixtures.

## 12. Verification standard

The reproducible web gate runs format, lint, strict typecheck, unit/component tests, production
build, OpenAPI/ABI drift checks, and Playwright flows. Browser tests cover desktop and mobile,
keyboard navigation, automated accessibility scanning, reduced motion, empty/error/loading
states, cursor invalidation, SSE reconnect, wrong-chain blocking, rejected signatures, reverted
transactions, successful Anvil launch/buy/sell, and creator metadata revision conflicts.

No test requires a real Privy secret or funded public-network wallet. Live Robinhood and real
Privy acceptance are reported separately from deterministic local evidence.

## Primary references checked

- Next.js App Router: `https://nextjs.org/docs/app/getting-started/installation`
- Tailwind CSS with Next.js: `https://tailwindcss.com/docs/installation/framework-guides/nextjs`
- Privy React setup: `https://docs.privy.io/basics/react/setup`
- Privy wagmi integration: `https://docs.privy.io/wallets/connectors/ethereum/integrations/wagmi`
- wagmi: `https://wagmi.sh/`
- viem write simulation: `https://viem.sh/docs/contract/simulateContract`
- Lightweight Charts: `https://tradingview.github.io/lightweight-charts/docs`
- Playwright accessibility testing: `https://playwright.dev/docs/accessibility-testing`
