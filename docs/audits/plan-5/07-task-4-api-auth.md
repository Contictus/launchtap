# Plan 5 Task 4 — API, Identity, Authorization, and Content-Security Audit

## Result

Reviewed immutable baseline `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`. The current owned product paths were confirmed unchanged from that baseline. This report records four validated findings (one Medium, three Low), one rejected hypothesis, and one deferred Task 7 boundary. No product, generated, migration, or test file was changed.

The scoped offline Go tests passed:

```text
go test ./internal/apiserver ./internal/privyauth ./internal/config ./internal/pagination ./internal/realtime ./internal/quote
ok   internal/apiserver
ok   internal/privyauth
ok   internal/config
ok   internal/pagination
ok   internal/realtime
?    internal/quote [no test files]
```

The first test attempt used the inaccessible default Go build cache. Re-running with `GOCACHE` under the system temp directory succeeded; Go still printed an Access Denied telemetry-upload warning. `go run ./cmd/check-openapi` completed with exit code 0 in default read-only mode using `GOPROXY=off`. Database-backed Postgres integration tests were not run. No network, real credentials, private endpoints, or production systems were used.

The integration test `TestMetadataAndImagesAuthorizeAndUseRevisionsAtomically` is present at `backend/internal/store/postgres/postgrestest/metadata_integration_test.go:18` (including orphan-survival assertions at `:65-78`), and the separate concurrent-write test `TestMetadataAndImageFirstWritesRejectConcurrentExpectedZero` is present beginning at `:82`; neither was executed because Postgres was unavailable.

## Owned-path coverage

Every Task 4 implementation and test file in the ledger paths was inspected. `backend/openapi/v1.json` received semantic contract review only; provenance and generated-artifact ownership remain Task 7.

| Ledger path | Files reviewed | Disposition |
|---|---|---|
| `backend/cmd/api/` | `main.go` | Startup wiring, signal handling, readiness, listener, DB pool lifetime, manifest override; see findings 002 and 006. |
| `backend/internal/apiserver/` | `candle_routes.go`, `event_routes.go`, `event_routes_test.go`, `metadata_routes.go`, `metadata_routes_test.go`, `observation_routes.go`, `observation_routes_test.go`, `openapi.go`, `profile_routes.go`, `profile_routes_test.go`, `public_routes.go`, `public_routes_test.go`, `quote_routes.go`, `quote_vectors_test.go`, `server.go`, `server_test.go`, `token_routes.go`, `token_routes_test.go` | All registered handlers, middleware, DTOs, limits, validators, error mapping, logging, and route tests reviewed. See validated findings 002–004 and rejected CORS hypothesis 005. |
| `backend/internal/privyauth/` | `verifier.go`, `verifier_test.go` | JWT parsing, ES256 verification, issuer/audience/subject/time checks, linked-account parsing, wallet filtering, size/duplicate-key handling, and tests reviewed; no validated auth bypass found. |
| `backend/internal/config/` | `config.go`, `config_test.go`, `doc.go` | Environment parsing, required API settings, URL/origin checks, secret-safe errors, and tests reviewed; no validated defect found. |
| API-facing domain ports | `candle/ports.go`, `metadata/ports.go`, `observation/ports.go`, `pagination/cursor.go`, `pagination/cursor_test.go`, `profile/ports.go`, `quote/service.go`, `realtime/hub.go`, `realtime/hub_test.go`, `token/ports.go`, `trading/ports.go` | Snapshot/DTO, cursor, quote, metadata, observation, and bounded SSE behavior reviewed; no additional validated finding. `quote` has no package-local tests. |
| `backend/openapi/v1.json` | `v1.json` | Semantic drift cross-checked against `web/src/api/generated.ts` and the manual client in `web/src/api/client.ts`; generation/provenance remains Task 7-owned. Findings 003 and 004. |

API-facing persistence and deployment boundaries were cross-reviewed, not reassigned from their primary owners: `backend/internal/store/postgres/metadata.go:29-104`, `backend/internal/store/postgres/queries/metadata.sql:1-43`, `backend/internal/store/postgres/queries/read.sql:81-115`, `backend/internal/store/postgres/postgrestest/metadata_integration_test.go:18-88`, migrations `00005_token_metadata_launch_fk.sql`, `00008_api_metadata_images.sql`, `00009_token_images_reorg_survival.sql`, and `contracts/src/LaunchFactory.sol:92-95`. The pinned vendored `Clones.clone` implementation uses `CREATE` (`contracts/lib/openzeppelin-contracts/contracts/proxy/Clones.sol:57`); Task 7 owns vendored provenance.

## Endpoint and boundary disposition

| Runtime endpoints | Review disposition |
|---|---|
| `GET /healthz`, `/readyz`, `/v1/healthz`, `/v1/readyz` | Root/versioned behavior and readiness errors reviewed. |
| `GET /v1/tokens`, `/v1/tokens/{token}`, `/v1/tokens/{token}/trades`, `/v1/tokens/{token}/holders`, `/v1/stats/protocol`, `/v1/stats/protocol/daily` | Address/date/phase/sort parsing, snapshots, cursor use, page/range bounds, DTOs, and error paths reviewed. Token list page size is bounded 1–100; daily range is capped at 366 days. |
| `POST /v1/tokens/{token}/quote` | Read-only informational quote path reviewed; canonical uint256 decimal parsing rejects noncanonical, negative, fractional, exponent, and over-width inputs. |
| `GET /v1/tokens/{token}/candles` | Interval/time/page validation and bounded result size reviewed; limit is capped at 100. |
| `GET /v1/transactions/{tx_hash}` | Exact 32-byte transaction hash and canonical observation lookup reviewed. |
| `GET /v1/profile` | Both Privy tokens verified; returned profile data is scoped to verified linked EVM wallets. |
| `GET, PUT /v1/tokens/{token}/metadata` | Public read and creator-authorized write, URL/description constraints, DID rate limit, `If-Match` revision CAS, and errors reviewed. |
| `GET, PUT /v1/tokens/{token}/image` | Public image read/ETag/304/nosniff and creator-authorized write, 5 MiB cap, PNG/JPEG/WebP signature and declared-type match reviewed. SVG is rejected. |
| `GET /v1/events` | Refresh-only SSE, chain/deployment filtering, 15-second heartbeat, 1000-subscriber/16-event bounds, disconnect cleanup and write-timeout handling reviewed. Shutdown behavior is finding 002. |

Shared HTTP controls reviewed: 5s header, 15s read/write, 60s idle, 5s shutdown, 6 MiB request-body and 32 KiB header limits; ordinary handlers have a 15s context timeout. SSE clears the absolute write deadline. CORS uses exact non-wildcard configured origins and a preflight allowlist. Request logs omit authorization values; API errors do not echo credentials. The verifier enforces ES256 and configured app/audience, `privy.io` issuer, nonempty same-subject access/identity tokens, `iat`/`exp`/`nbf`, strict duplicate/trailing JSON rejection, and bounded JWT/header/claim sizes; linked wallet addresses are normalized/deduplicated and only EVM wallet/smart-wallet accounts are used. The actual production Privy key, app configuration, host/proxy behavior, DB role, and traffic profile remain unverified.

## Validated findings

### P5-T4-001 — Orphaned creator content can be attributed to a different launch after address reuse

- State: validated finding
- Severity: Medium
- Confidence: high
- Primary audit task: Task 4
- Affected asset/surface: creator metadata/image reads and writes; API-facing Postgres boundary; Task 4 API/identity row, cross-referencing Task 2 contract and Task 3 canonical persistence owners
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Attacker/failure actor and prerequisites: a valid creator A writes public metadata or an image for a canonical launch; a reorg removes that launch; a different creator B is the next factory launch on the replacement branch and reuses the same CREATE-derived token address.
- Source-to-sink or failure path: migrations deliberately remove metadata/image launch foreign keys (`00005...:1-6`, `00009...:1-6`) and the integration test confirms image content survives deleting the launch (`metadata_integration_test.go:65-78`). Rows are read by `(chain_id, token_address)` (`metadata.go:63-88`); `GetTokenDetail` joins metadata on those same fields without a launch identity or creator predicate (`queries/read.sql:100-115`). The factory deploys a clone and then `LaunchToken` using sequential CREATE operations (`LaunchFactory.sol:92-95`; pinned vendored `Clones.clone` executes CREATE at `contracts/lib/openzeppelin-contracts/contracts/proxy/Clones.sol:57`). If the replacement launch has the same factory nonce sequence, its token address is reused and the old creator-controlled links/image appear under B's token.
- Exact evidence: `backend/internal/store/postgres/migrations/00005_token_metadata_launch_fk.sql:1-6`; `backend/internal/store/postgres/migrations/00009_token_images_reorg_survival.sql:1-6`; `backend/internal/store/postgres/postgrestest/metadata_integration_test.go:65-78`; `backend/internal/store/postgres/metadata.go:63-88`; `backend/internal/store/postgres/queries/read.sql:100-115`; `contracts/src/LaunchFactory.sol:92-95`.
- Impact: cross-launch content integrity and attribution failure; stale links or image can mislead users about a different token. No direct fund-loss path was demonstrated.
- Counterevidence and assumptions: writes correctly verify the current creator against `token_launches` (`metadata.go:91-104`; `queries/metadata.sql:1-5`) and use revision compare-and-swap; an orphan cannot be newly edited until a current matching launch exists. Address reuse requires a replacement canonical history with no intervening factory CREATE that changes the nonce sequence. Same-launch reorg replay is the intended preservation case.
- Reproduction/proof method: source proof above plus the existing integration test's orphan-preservation invariant. `TestMetadataAndImagesAuthorizeAndUseRevisionsAtomically` at `backend/internal/store/postgres/postgrestest/metadata_integration_test.go:18` and `TestMetadataAndImageFirstWritesRejectConcurrentExpectedZero` at `:82` are present but unexecuted because Postgres was unavailable; a DB-backed alternate-launch fixture was not run.
- Proposed remediation: bind persisted creator content to a canonical launch identity (at minimum creator plus immutable launch identity); expose it only when it matches the current canonical launch, while preserving data for replay of that same launch.
- Required regression test: write content for creator A, remove the launch, create creator B's token at the same chain/address, and assert all public metadata/detail/image reads do not return A's content; separately assert same-launch replay retains it and A cannot write after B's launch.
- Disposition/owner: validated; Task 8 remediation decision, coordinated with Task 3 persistence owner.
- Related findings and cross-task references: Task 2 must confirm launch-address reuse assumptions; Task 3 owns reorg/persistence semantics.

### P5-T4-002 — SIGTERM does not cancel active SSE handlers before shutdown deadline

- State: validated finding
- Severity: Low
- Confidence: high
- Primary audit task: Task 4
- Affected asset/surface: API SSE request lifecycle and process shutdown; Task 4 `cmd/api` and `apiserver` rows
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Attacker/failure actor and prerequisites: operational SIGTERM while one or more public SSE streams are active; no attacker privilege required.
- Source-to-sink or failure path: `main` creates a signal context but does not attach it as the HTTP server `BaseContext`; on cancellation it calls `Shutdown` with a 5s deadline (`cmd/api/main.go:49-50, 89-98`). The server directly delegates to `http.Server.Shutdown` (`server.go:103,115`); middleware explicitly exempts `/v1/events` from request timeout and clears its write deadline (`server.go:168-176`). SSE handlers exit only when request context is done, a send fails, or their subscription closes (`event_routes.go:54-103`). `Shutdown` stops new accepts but does not cancel active handler contexts; it waits for them, so a live stream can hold shutdown until the 5s context expires and produce a shutdown error before process exit.
- Exact evidence: `backend/cmd/api/main.go:49-50,89-98`; `backend/internal/apiserver/server.go:103,115,168-176`; `backend/internal/apiserver/event_routes.go:54-103`.
- Impact: graceful shutdown is not clean for active SSE; process termination waits for the deadline and reports an error, and stream cleanup relies on connection/process closure instead of lifecycle cancellation.
- Counterevidence and assumptions: SSE has a bounded hub (1000 subscribers, 16 buffered events each), heartbeat, and client-disconnect cleanup; existing tests cover request-context cancellation and survival beyond the ordinary write timeout, but not server shutdown.
- Reproduction/proof method: static lifecycle proof above; existing `TestSSEInitialRetryEventHeartbeatAndCancellation` exercises only client cancellation. No new product test was added.
- Proposed remediation: explicitly cancel long-lived SSE request contexts when shutdown begins, or provide a dedicated stream-drain signal; preserve normal request drain semantics and handle the shutdown result deliberately.
- Required regression test: start an active SSE request on an `http.Server`, trigger the same shutdown lifecycle as SIGTERM, and assert the stream exits, `Hub.Active()` returns to zero, and `Shutdown` returns nil before its configured deadline.
- Disposition/owner: validated; Task 8 remediation decision.
- Related findings and cross-task references: none.

### P5-T4-003 — OpenAPI underdeclares required write headers and image response/request semantics

- State: validated finding
- Severity: Low
- Confidence: high
- Primary audit task: Task 4
- Affected asset/surface: semantic OpenAPI/runtime contract for profile, metadata, and image endpoints; Task 4 API row, generated provenance Task 7
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Attacker/failure actor and prerequisites: API consumer or generated client relies on the published OpenAPI document; no attacker privilege required.
- Source-to-sink or failure path: OpenAPI declares `Authorization`, `privy-id-token`, and `If-Match` as optional on profile and metadata/image writes (`backend/openapi/v1.json:1359,1872,1886,2026,2040`), but runtime handlers reject absent auth and revision headers (`profile_routes.go:44-54`; `metadata_routes.go:134-145,160-171`). Image PUT's generated request body includes `application/octet-stream` (`v1.json:1902`) although runtime requires declared Content-Type to equal detected PNG/JPEG/WebP (`metadata_routes.go:173-180`). Conditional image GET can return 304 (`metadata_routes.go:200-204`) but its OpenAPI response lists only 200/default (`v1.json:1788-1850`).
- Exact evidence: `backend/openapi/v1.json:1359,1788-1850,1872-1902,2026-2040`; generated client `web/src/api/generated.ts:750-759,1022-1048,1050-1070,1126-1152` repeats optional auth/If-Match and lacks image 304; runtime handlers `backend/internal/apiserver/profile_routes.go:44-54` and `backend/internal/apiserver/metadata_routes.go:134-145,160-180,200-204`; manual client `web/src/api/client.ts:112-128,131-146,156-167` reads revision/ETag and supplies If-Match/auth.
- Impact: generated TypeScript types permit omission of auth and `If-Match` that runtime rejects, allow an image media type runtime rejects, and omit the 304 case; manual client code supplies auth and revision headers and reads response validators. Generated and handwritten consumers therefore describe different usable contracts. No authorization bypass was found.
- Counterevidence and assumptions: runtime checks fail closed; this is contract drift, not a runtime authorization weakness. `go run ./cmd/check-openapi` passes byte-level generated-file checking but does not test these semantic requirements.
- Reproduction/proof method: inspect OpenAPI parameter `required` fields, request media types, and response map alongside generated TypeScript and runtime/manual client code; read-only OpenAPI check command exited 0. The check compares generated bytes, not these semantic obligations.
- Proposed remediation: express required headers and supported image media types in the Huma/OpenAPI source; document 304, regenerate only through the Task 7-owned workflow, then verify semantic assertions.
- Required regression test: semantic OpenAPI test asserting required profile/write auth and `If-Match` headers, image PUT content types exactly match runtime, and GET image documents 304; retain runtime tests proving omitted headers/unsupported media are rejected.
- Disposition/owner: validated; Task 7 owns generated artifact/provenance and must coordinate source-of-truth correction with Task 4.
- Related findings and cross-task references: Task 7 generated OpenAPI provenance.

### P5-T4-004 — Allowed cross-origin clients cannot read the image revision header

- State: validated finding
- Severity: Low
- Confidence: high
- Primary audit task: Task 4
- Affected asset/surface: allowed-origin image GET and creator image PUT concurrency contract; Task 4 HTTP/API boundary
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Attacker/failure actor and prerequisites: an ordinary authenticated user uses the web client from a separately hosted origin that is present in the API CORS allowlist; no attacker privilege is required.
- Source-to-sink or failure path: for allowed origins, CORS sets `Access-Control-Allow-Origin` and allowed request headers but never `Access-Control-Expose-Headers` (`server.go:201-207`). Image GET returns the numeric `X-Revision` response header (`metadata_routes.go:83-89,200-204`). Browser Fetch therefore does not expose that non-safelisted response header to cross-origin JavaScript. The manual client treats a missing header as revision `0` (`web/src/api/client.ts:112-128`) and later sends that value in `If-Match` for image replacement (`:156-167`). When the stored image revision is nonzero, the SQL compare-and-swap rejects expected revision `0` (`queries/metadata.sql:35-51`) and the API reports a revision conflict (`metadata_routes.go:226-233`).
- Exact evidence: `backend/internal/apiserver/server.go:201-207`; `backend/internal/apiserver/metadata_routes.go:83-89,200-204,226-233`; `backend/internal/store/postgres/queries/metadata.sql:35-51`; `web/src/api/client.ts:112-128,156-167`; existing CORS test only asserts allow headers at `backend/internal/apiserver/server_test.go:40-49`.
- Impact: image editing from an allowed separate origin can repeatedly submit stale revision zero and fail with a precondition conflict after an image already exists. Same-origin deployments are unaffected; this is a bounded usability/concurrency failure, not an authorization bypass.
- Counterevidence and assumptions: same-origin clients can read `X-Revision`; the API correctly enforces compare-and-swap and does not accept stale writes. Cross-origin browser clients need a configured allowed origin, and this finding assumes the production UI and API are on distinct origins.
- Reproduction/proof method: source-backed CORS and fetch-header visibility proof; have a cross-origin browser GET an image at revision greater than zero, observe `response.headers.get("X-Revision") === null`, then observe the manual client send `If-Match: "0"` and receive a revision conflict.
- Proposed remediation: expose `X-Revision` (and `ETag` if the client needs it) on allowed-origin responses using `Access-Control-Expose-Headers`; preserve the current exact origin allowlist.
- Required regression test: assert an allowed-origin image response includes `Access-Control-Expose-Headers` naming `X-Revision`; add a browser/client-level regression that reads a nonzero revision cross-origin and successfully updates with that value. Keep denied-origin behavior unchanged.
- Disposition/owner: validated; Task 8 remediation decision.
- Related findings and cross-task references: related contract drift in P5-T4-003; no authorization bypass.

## Rejected hypothesis

### P5-T4-005 — Ignoring the non-preflight CORS return permits cross-origin writes

- State: rejected/suppressed
- Severity: Low
- Confidence: high
- Primary audit task: Task 4
- Affected asset/surface: HTTP CORS middleware; Task 4 API row
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Attacker/failure actor and prerequisites: hostile-origin browser page attempting a cross-origin state change.
- Source-to-sink or failure path: middleware ignores `cors`'s false return for non-OPTIONS requests (`server.go:164`), suggesting a rejected origin might still reach a handler.
- Exact evidence: `backend/internal/apiserver/server.go:152-166,196-212`; protected writes require Authorization, `privy-id-token`, and `If-Match` (`metadata_routes.go:134-145,160-171`).
- Impact: none established; no CORS authorization bypass.
- Counterevidence and assumptions: rejected origins receive no `Access-Control-Allow-Origin`; browser fetches with the required non-simple headers trigger OPTIONS, which is explicitly denied with 403 (`server.go:152-162`). No state-changing endpoint accepts a simple cross-origin form request. CORS is not relied on as server authorization.
- Reproduction/proof method: inspect preflight branch, exact origin allowlist, required write headers, and endpoint methods.
- Proposed remediation: no security change required for this hypothesis; keep creator authentication authoritative. Any change to reject non-preflight requests is optional hardening, not a validated fix.
- Required regression test: retain denied-origin preflight coverage and assert protected writes still reject missing/invalid Privy credentials.
- Disposition/owner: rejected; current controls prevent the proposed browser path.
- Related findings and cross-task references: none.

## Deferred boundary

### P5-T4-006 — API startup accepts an external deployment-manifest path; production trust is unverified

- State: deferred
- Severity: Low
- Confidence: low
- Primary audit task: Task 4
- Affected asset/surface: API startup deployment registry input; Task 4 `cmd/api` row, primary runtime trust owner Task 7
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Attacker/failure actor and prerequisites: an operator or environment-injection actor able to set `DEPLOYMENT_MANIFEST_PATH`; whether that authority is available in production is unknown.
- Source-to-sink or failure path: a nonempty environment value is passed to `deployments.LoadEmbeddedWithManifest` instead of `LoadEmbedded` (`cmd/api/main.go:102-106`), and the resolved registry is used at startup. Task 4 evidence does not establish release-environment ownership, manifest immutability, or runtime code-hash verification.
- Exact evidence: `backend/cmd/api/main.go:102-106`; Task 7 owns `backend/deployments/` and deployment/release injection paths per `01-surface-ownership.md:24,32`.
- Impact: unknown; a trusted local overlay may be intentional, but a writable production path could affect runtime deployment selection.
- Counterevidence and assumptions: no production env values or host filesystem permissions were available; the path may be restricted to trusted operator configuration. No exploit is claimed.
- Reproduction/proof method: not reproducible without production release configuration and runtime trust evidence.
- Proposed remediation: none until Task 7 establishes the actual release path and validates digest/signature/code-hash checks and file permissions; do not remove a legitimate local override based on this audit alone.
- Required regression test: Task 7 should test that production startup cannot select an unapproved manifest and that local test overlays remain scoped to explicitly trusted environments.
- Disposition/owner: deferred to Task 7; prerequisite is tracing manifest configuration from release workflow/environment through registry loading and bytecode verification; resume with that end-to-end trust review.
- Related findings and cross-task references: Task 7 deployment and release provenance.

## Limitations and handoff

No live Privy issuer/key/app or production audience, proxy/header behavior, hosting/CDN policy, database credentials, real traffic/cardinality, or production shutdown supervisor was available. No network or Postgres integration environment was used, so the alternate-launch reorg scenario remains source-proven but not executed against Postgres; both named metadata authorization/revision and concurrent-write integration tests were inspected but not run. Findings concern the repository baseline only; they do not establish production exploitability or external control posture.

The repository backlog remains at two pre-existing active items: Robinhood testnet deployment manifest; production release, governance, and audit inputs. This audit did not modify `backlog.md`.
