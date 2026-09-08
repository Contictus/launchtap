# Backend API and Identity — Pre-flight and Task List

> **Workflow:** `AGENTS.md` governs implementation, verification, commit, and independent
> review. This document closes the planning boundary for Backend Plan 3. It is not
> implementation code.

**Status:** Pre-flight drafted. Seven tasks are proposed. Implementation must start with
Task 1 because the current aggregate and runtime surfaces are not yet safe to expose as a
public API. The external Robinhood RPC probe, chain-46630 deployment manifest, production
Privy credentials, production origins, ETH/USD source, and production governance inputs are
explicitly deferred; they do not block local implementation or deterministic tests.

**Goal:** Deliver a stateless REST/JSON API under `/v1` with a generated OpenAPI contract,
reorg-aware pagination, public market reads, informational curve quotes, Privy-authenticated
metadata writes, image delivery, and best-effort SSE refresh hints.

**Depends on:** Backend Foundations and the implemented parts of Backend Indexer Plan 2.
Task 1 below closes the API-facing correctness seams that remain in that implementation.

**Specs:**

- `docs/specs/2026-09-01-backend-core-design.md`
- `docs/specs/2026-09-01-contract-core-design.md`
- `docs/plans/2026-09-05-backend-indexer.md`
- `notes.md`

**Scope:** `cmd/api`, `internal/apiserver`, `internal/privyauth`, the read-side feature
packages (`internal/token`, `internal/trading`, `internal/holder`, `internal/candle`,
`internal/stats`, `internal/metadata`), their PostgreSQL adapters and sqlc queries, API-only
configuration, OpenAPI generation/diffing, and SSE delivery.

**Out of scope:** transaction construction or submission, backend-held signing keys,
custom SIWE, backend sessions, forum/moderation, ETH/USD provider selection, WebSocket RPC,
object-storage deployment, frontend code, and production hosting.

## Pre-flight findings

### BLOCKERS

#### B1 — Current aggregate values are not safe to publish

The implemented `internal/stats` and `RecomputeTokenStats` paths do not yet satisfy spec
§5.4/§5.5:

- market cap is assigned the same value as FDV instead of using circulating supply;
- holder count does not exclude zero, dead, curve, and canonical pair addresses;
- the 24-hour change selection does not establish the price at or immediately before the
  window boundary;
- `ath_at` is not tied to the candle that supplied the maximum high;
- the SQL and Go implementations are not protected by a differential test.

Task 1 must repair and cross-check these values before token list/detail or protocol endpoints
are registered. API handlers must not compensate for wrong stored aggregates.

#### B2 — `API_ADDR` currently has two owners

`cmd/indexer` currently binds its health server to `API_ADDR`, while Plan 3 assigns the same
setting to `cmd/api`. Running both processes on one host would produce an address conflict.
Task 1 introduces `INDEXER_HEALTH_ADDR` for the indexer and reserves `API_ADDR` for the API.
The indexer health tracker must also be populated continuously from runtime state; an initial
all-zero snapshot is not accepted as the Plan 2 observability gate.

#### B3 — Pagination is underspecified across provisional reorgs

A tuple cursor alone prevents timestamp ties from duplicating rows, but it does not protect a
multi-page read when the observed chain is replaced between requests. Every collection query
therefore needs a read snapshot identity. The cursor must bind to `(chain_id, as_of_block,
as_of_block_hash, sort, filters, version)`. A subsequent request verifies that block identity
is still canonical; mismatch returns a typed `409 cursor_invalidated` problem and the client
restarts from page one.

Each request reads its watermark and rows inside one read-only `REPEATABLE READ` transaction.
The API never claims a response is from a consistent block while reading the watermark and
payload from unrelated database snapshots.

#### B4 — The Privy wire contract in the existing spec has drifted

The current Privy documentation uses `Authorization: Bearer <access-token>` and
`privy-id-token: <identity-token>` for header-based clients. The backend spec currently names
`X-Privy-Identity-Token`. Plan 3 uses the documented `privy-id-token` name and does not enable
cookie authentication in v1, avoiding a second CSRF-bearing transport.

Both JWTs are independently signature-verified with an explicit ES256 algorithm allowlist,
issuer `privy.io`, audience equal to `PRIVY_APP_ID`, time claims, and non-empty subject. Their
subjects must match. Only EVM `wallet` and `smart_wallet` entries in the verified identity
token become linked addresses. Connected-only wallets are never authorization evidence.

The exact dashboard verification-key serialization must be captured as a format description
and reproduced with a synthetic fixture before the production adapter is declared complete.
Until the user supplies that format, local implementation uses generated P-256 test keys
behind the narrow `Verifier` interface. No
secret or token is committed, logged, placed in URLs, or returned in problem details.

#### B5 — “Image writes” have no persistence contract

The current schema stores only `token_metadata.image_url`; it has nowhere to store an uploaded
image even though the API scope includes image writes and the spec defers a later migration
from PostgreSQL to object storage. Task 6 adds a separate `token_images` table rather than
placing bytes in `token_metadata`:

```text
chain_id, token_address, content_type, content BYTEA, byte_size,
sha256 BYTEA, revision BIGINT, updated_at
```

V1 accepts PNG, JPEG, or WebP only, detects type from bytes, rejects active formats such as
SVG, caps decoded content at 5 MiB, and serves immutable-by-hash cache validators. The public
metadata `imageUrl` points to the API image resource. Object storage can later implement the
same storage port without changing endpoint DTOs.

### RISKS

- **R1 — Numeric precision:** every uint256/WAD value is a base-10 JSON string. JSON numbers
  and floating-point conversions are forbidden at the transport boundary.
- **R2 — Address ambiguity:** incoming EVM addresses must be exactly 20 bytes after hex
  decoding. Responses use EIP-55 checksum form. Address search is exact; name/symbol search
  is normalized prefix search, not an unindexed contains scan.
- **R3 — Read amplification:** Explore cards must come from one set-based query. Per-token
  metadata, stats, reserve, holder-count, or watermark queries are forbidden.
- **R4 — Mutable ordering:** metric-sorted pages include the metric value and token address
  in the cursor. The snapshot-bound cursor rule still applies because aggregate values can
  change while paging.
- **R5 — Quote staleness:** a quote is informational and curve-phase only. It reports the
  reserve source block and finality and never returns calldata, gas, slippage protection, or
  a transaction-ready guarantee.
- **R6 — Metadata races:** creator writes use an integer revision and conditional update.
  Blind last-write-wins updates are rejected with `409 revision_conflict`.
- **R7 — SSE pressure:** one slow subscriber must not block publishers or other clients.
  Buffers are bounded; slow subscribers are disconnected and reconnect through REST.
- **R8 — Horizontal scaling:** PostgreSQL `LISTEN/NOTIFY` is only a wake-up hint. Every API
  instance may listen independently; no instance-to-instance memory protocol is introduced.
- **R9 — Cross-origin auth:** allowed origins are explicit configuration. Wildcard origins
  are rejected when authorization headers are enabled.
- **R10 — Generated contract drift:** OpenAPI is derived from Go DTOs, committed, and checked
  byte-for-byte in `task verify`. No hand-maintained second schema is allowed.

## Decisions to lock before implementation

The following are the recommended decisions. Approval of this pre-flight locks them as a
single set.

1. **Seven tasks, sequential at high-risk seams.** Tasks 1–3 establish correctness, storage,
   and HTTP contracts; Tasks 4–6 implement features; Task 7 closes realtime and verification.
2. **External user work is deferred.** Robinhood testnet and production credentials are live
   acceptance gates only. Local development uses Anvil, PostgreSQL, and generated auth keys.
3. **Huma over `net/http`.** Pin one reviewed Huma v2 release in `go.mod`; do not add Chi or a
   second router unless the standard adapter proves insufficient.
4. **Stable wire primitives.** Amounts are decimal strings, addresses are checksummed hex,
   hashes are `0x`-prefixed 32-byte hex, timestamps are UTC RFC3339, and all durations exposed
   to clients are integer seconds.
5. **Response envelope.** Market resources carry `chainId`, `asOfBlock`, `asOfBlockHash`, and
   `finality` at collection or resource level. `finality` is only `provisional`, `safe`, or
   `finalized`.
6. **Opaque versioned cursors.** Base64url-encoded, strictly decoded cursor payloads contain
   snapshot identity, endpoint sort tuple, and filter fingerprint. Unknown fields, versions,
   sort modes, or filter mismatches are rejected.
7. **Public endpoint surface:**
   - `GET /v1/tokens`
   - `GET /v1/tokens/{token}`
   - `GET /v1/tokens/{token}/candles`
   - `GET /v1/tokens/{token}/trades`
   - `GET /v1/tokens/{token}/holders`
   - `POST /v1/tokens/{token}/quote`
   - `GET /v1/stats/protocol`
   - `GET /v1/events`
   - `GET /healthz` and `GET /readyz`
8. **Token listing owns Explore and Graduated.** `phase=curve|graduated` selects the list;
   supported sorts are `newest`, `oldest`, `market_cap`, and `volume_24h`. `q` is exact
   address or normalized name/symbol prefix. V1 does not expose an engine-version toggle.
9. **Candles:** stored intervals `1m`, `5m`, `1h`, `1d` are read directly. `6h` aggregates
   `1h` rows and `all` aggregates `1d` rows in SQL with correct first-open/last-close ordering.
10. **Quote input:** `{side, amount}` where `amount` is gross ETH wei for buy and token wei
    for sell. The handler constructs `curve.Parameters` and `curve.State` from one snapshot,
    calls the existing mirror, and maps typed curve errors to stable problem types.
11. **Auth transport:** bearer access token plus `privy-id-token`; no custom SIWE, backend
    session, refresh-token handling, or cookie mode.
12. **Metadata writes:** `PUT /v1/tokens/{token}/metadata` is a full replacement with an
    expected revision. Description is plain text with a 2,000-byte UTF-8 cap. X and Telegram
    URLs are optional HTTPS URLs with a 2,048-byte cap; HTML is never accepted or rendered.
13. **Image writes:** `PUT /v1/tokens/{token}/image` and `GET /v1/tokens/{token}/image` use the
    same creator authorization and revision discipline as metadata. PostgreSQL is the v1 blob
    store behind a replaceable port.
14. **CORS and abuse boundaries:** `API_ALLOWED_ORIGINS` is a comma-separated exact allowlist.
    Request headers, bodies, header-read time, idle time, and total handler time are bounded.
    Distributed rate limiting remains a deployment-edge responsibility until hosting is
    selected; authenticated writes still receive a conservative in-process per-subject limit.
15. **SSE is refresh-only:** event types are `launch`, `token`, and `reorg`; payloads contain
    only chain/deployment and affected identity/checkpoint data. There is no event replay and
    `Last-Event-ID` is ignored. A 15-second comment heartbeat keeps intermediaries from
    silently expiring an otherwise idle stream.
16. **Health split:** indexer operational health stays on `INDEXER_HEALTH_ADDR`; API
    liveness/readiness stays on `API_ADDR`. Product finality metadata is part of `/v1`
    resources, not inferred from HTTP readiness.

## Task 1 — Close API-facing indexer seams · Risk: high

**Delivers:** correct aggregate values, live indexer health, distinct process addresses, and
the local Plan 2 acceptance seam required by public reads.

**Acceptance criteria:**

- Go and SQL aggregate calculations implement spec §5.4/§5.5 identically for circulating
  supply, market cap, FDV, holder exclusions, ATH value/time, 24-hour volume, and signed
  24-hour change.
- A differential integration test runs the same fixture through incremental aggregation and
  an independent surviving-ledger recomputation and compares every stored field.
- Fixtures include burns, curve/pair balances, zero-balance resets, a candle immediately
  before the 24-hour boundary, falling price, equal highs at different times, and reorg
  removal of the former ATH.
- `INDEXER_HEALTH_ADDR` is independently parsed and validated. `cmd/indexer` no longer binds
  `API_ADDR`.
- Health is updated after known transaction outcomes and reports the spec §12 fields from
  real runtime/store state. It becomes not-ready on ownership loss, RPC failure, unknown
  transaction outcome, or watermark invariant failure.
- The Anvil end-to-end indexer test required by Plan 2 runs in the normal verification gate.
  The external Robinhood testnet run remains deferred and explicitly unclaimed.

## Task 2 — Read-store and snapshot primitives · Risk: high

**Depends on:** Task 1.

**Delivers:** sqlc queries and PostgreSQL adapters for every Plan 3 read, metadata/image
writes, snapshot-bound cursors, and no HTTP types in persistence.

**Acceptance criteria:**

- Feature packages define consumer-owned ports with neutral domain types. sqlc/generated
  types remain inside `internal/store/postgres`.
- One read-only `REPEATABLE READ` helper returns a watermark plus data from the same database
  snapshot and never commits after a handler cancellation.
- Collection queries use deterministic tuple ordering and keyset predicates. `OFFSET` is not
  used.
- Every cursor validates chain, block/hash, endpoint, sort, filters, direction, and version.
  Reorged snapshot identity returns a typed invalidation result.
- Token-list queries join metadata/stats in one statement and have `EXPLAIN`-verified indexes
  for every supported sort/filter path on a representative fixture.
- Candle aggregation for `6h` and `all` preserves open/close ordering and volume/count sums.
- Metadata/image writes authorize against the canonical launch creator inside the same
  transaction as the revision-guarded update.
- Integration tests cover empty/not-found results, maximum page size, tie-heavy pagination,
  forward progress, changed filters, tampered cursors, and snapshot invalidation after reorg.

## Task 3 — Huma API foundation and generated contract · Risk: high

**Depends on:** Task 2.

**Delivers:** `internal/apiserver`, standard middleware, problem mapping, configuration,
`cmd/api`, graceful shutdown, and committed OpenAPI.

**Acceptance criteria:**

- Huma runs over the standard-library router under `/v1`; framework types do not enter
  feature services or persistence.
- Middleware order is request ID, panic recovery, structured access log with secret
  redaction, CORS, body/timeout limits, authentication extraction, and operation handler.
- Validation and domain failures use stable `application/problem+json` types. Internal errors
  expose a request ID but no SQL, stack, token, key, or upstream response body.
- `cmd/api` loads config, resolves/reconciles the deployment, opens the database, registers
  routes, and shuts down with bounded drain. It never runs migrations and never acquires the
  indexer advisory lock.
- `/healthz` proves process liveness. `/readyz` requires database reachability, resolved
  deployment, and a non-broken indexed watermark; lag is reported but does not invent a
  chain-independent production threshold.
- Server read-header, read-body, write, idle, and shutdown timeouts are explicit and tested.
- Generated `backend/openapi/v1.json` is deterministic, committed, and checked by an
  `openapi-diff` task included in `task verify` and CI path filters.

## Task 4 — Public token and market reads · Risk: high

**Depends on:** Task 3.

**Delivers:** token lists/search/detail, candles, trades, holders, and protocol statistics.

**Acceptance criteria:**

- All routes and DTOs match decisions 4–9 exactly and include snapshot/finality metadata.
- List limits default to 20 and are bounded to 1–100. Invalid cursors and unsupported
  sort/filter combinations fail rather than silently falling back.
- Token detail reports immutable launch parameters, current phase/reserves, graduation
  progress, metadata, and aggregate statistics without recomputing chain facts in handlers.
- Trades expose curve or DEX source, nullable trader, side, execution price, spot price,
  volumes, transaction coordinates, time, and row finality.
- Holders exclude system addresses according to spec §5.4 and order by balance then address.
- Empty histories return empty collections, while unknown tokens return a typed 404.
- `httptest` contract tests assert status, content type, validation failures, decimal-string
  amounts, checksummed addresses, pagination links/cursors, and finality fields.

## Task 5 — Informational curve quote endpoint · Risk: high

**Depends on:** Tasks 2 and 3. May proceed in parallel with Task 4 after Task 3.

**Delivers:** curve-phase buy/sell quotes backed exclusively by the existing pure-Go mirror.

**Acceptance criteria:**

- The handler reads token parameters, reserves, phase, and watermark in one snapshot and
  invokes `internal/curve`; it contains no duplicate fee or curve arithmetic.
- Every request and response amount is a canonical base-10 uint256 string. Leading signs,
  decimals, exponent notation, overflow, and non-canonical leading zeros are rejected.
- Responses include input/output, protocol/creator fee, refund where applicable, next state,
  graduation flag, reserve source block/hash, `asOfBlock`, `finality`, and
  `informational: true`.
- Graduated tokens return the mirror's phase error. The endpoint does not quote Uniswap,
  build calldata, estimate gas, or claim executable freshness.
- Tests replay all Solidity vector cases through the HTTP boundary and assert typed problem
  mappings for every mirror error.

## Task 6 — Privy authorization, metadata, and images · Risk: high

**Depends on:** Task 3. Metadata/image persistence from Task 2 must be present.

**Delivers:** local Privy verification adapter, authenticated creator writes, revisioned
metadata, safe image storage/serving, and audit-safe logs.

**Acceptance criteria:**

- Access and identity tokens follow B4 and decision 11. Malformed bearer syntax, wrong
  algorithm, invalid signature, expired/not-yet-valid token, wrong issuer/audience, missing
  subject, subject mismatch, malformed linked account, non-EVM account, duplicate wallet,
  and connected-but-unlinked wallet are tested.
- Token parsers cap header/token/claim size and reject duplicate or ambiguous claims.
- Public keys are parsed once at startup; private keys and Privy app secrets are neither
  required nor accepted for local JWT verification.
- Metadata and image writes require the token's canonical creator in verified linked wallets.
  Authentication failure is 401; authenticated but unlinked is 403; revision conflict is 409.
- Metadata validation follows decision 12 and strips no content silently.
- Image validation follows B5 and decision 13. Hash/ETag, content type, content length,
  `X-Content-Type-Options: nosniff`, conditional GET, replacement, and oversize rejection are
  covered by tests.
- A synthetic fixture matching the real dashboard key serialization is required only for
  live Privy acceptance. Its absence remains a named deferred item and does not weaken
  generated-key unit coverage.

## Task 7 — SSE, runtime hardening, and verification gate · Risk: high

**Depends on:** Tasks 4–6.

**Delivers:** refresh-hint SSE, multi-instance-safe notification consumption, complete API
verification, documentation, and milestone readiness evidence.

**Acceptance criteria:**

- `/v1/events` follows decision 15, sends the initial retry recommendation and heartbeat,
  flushes each event, terminates on client cancellation, and never holds a database
  transaction for the stream lifetime.
- The subscriber registry is race-tested. Publish is non-blocking, buffers and connection
  counts are bounded, and slow-client eviction is observable.
- PostgreSQL notification loss is explicitly tolerated because every SSE payload is only a
  refresh hint and REST remains authoritative.
- CORS preflight permits only the configured origins, methods, and headers, including
  `Authorization`, `Content-Type`, `privy-id-token`, and conditional revision headers.
- `go build ./...`, `go vet ./...`, `go test ./... -race`, integration tests, pinned lint,
  sqlc diff, OpenAPI diff, migrations up/down/up, and all existing artifact gates pass through
  `task verify`.
- CI proves that API integration and OpenAPI sentinel tests actually executed; zero matched
  tests fail the job.
- A local end-to-end flow starts PostgreSQL, Anvil indexer, and API; reads a launched token,
  pages trades, requests a quote, writes metadata/image with generated Privy tokens, observes
  an SSE refresh hint, simulates a shallow reorg, rejects the old cursor, and reads the
  surviving state.
- The completion report separates local deterministic evidence from deferred live Robinhood,
  production Privy, origin, hosting, ETH/USD, governance, and audit acceptance.

## Dependency graph

```text
Task 1 -> Task 2 -> Task 3 -> Task 4 --+
                         \-> Task 5 --+-> Task 7
                         \-> Task 6 --+
```

## Deferred user/external inputs

These inputs are deliberately scheduled after local Plan 3 implementation:

1. Robinhood provider probe and chain-46630 reviewed deployment manifest.
2. A real Privy application ID and the dashboard verification-key format; tokens and keys
   themselves are never committed. A generated public key reproduces the observed format in
   tests.
3. Production web origins for `API_ALLOWED_ORIGINS`.
4. Production edge rate-limit/hosting configuration.
5. ETH/USD enrichment source.
6. Production governance signers, timelock policy, monitoring, and external audit.

None of these may be replaced with invented values. Their absence blocks the corresponding
live acceptance or release claim, not Tasks 1–7's local implementation.

## Pre-flight verdict

Plan 3 is implementable as seven tasks, but it is not correct to begin at HTTP handlers.
B1–B5 must be accepted as binding decisions, and Task 1 must land first. No external account
work is required to start Tasks 1–5 or the generated-key portion of Task 6.

## Primary references checked during pre-flight

- Privy access and identity token model:
  `https://docs.privy.io/authentication/user-authentication/tokens`
- Privy access-token transport and verification:
  `https://docs.privy.io/authentication/user-authentication/access-tokens`
- Privy identity-token claims and `privy-id-token` transport:
  `https://docs.privy.io/user-management/users/identity-tokens`
- Privy linked-versus-connected wallet distinction:
  `https://docs.privy.io/wallets/wallets/get-a-wallet/get-connected-wallet`
- Huma v2 standard-library adapter and OpenAPI baseline:
  `https://github.com/danielgtaylor/huma`
