# Plan 5 Task 5 — Web, Wallet, Transaction, and Browser-Security Audit

**Audit target:** `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`

**Result:** 6 validated findings; 11 candidates considered, 4 rejected and 1 deferred; 2 additional runtime-verification gates deferred.

**Change boundary:** this report only; no product, generated, plan, backlog, README, or configuration files changed.

## Scope and baseline

The ownership ledger assigns `web/app/`, `web/src/`, `web/e2e/`, and `web/scripts/` to Task 5 (`docs/audits/plan-5/01-surface-ownership.md:38`); package/build provenance stays with Task 7 (`:39`). The audited web implementation is unchanged between the required baseline and the starting `HEAD` (`git diff --name-status 6184bc5..HEAD -- web/app web/src web/e2e web/scripts` produced no paths). Findings below therefore cite the immutable baseline source.

Reviewed the wallet readiness/configuration and release boundaries, generated ABI/API consumers, launch/approval/curve/router/claim transaction flows, receipt and canonical observation, metadata/image/link handling, token/chart/SSE refresh, app/error states, accessible controls, E2E and unit-test coverage, bundle/release scripts, and CSP/cache/logging code. The threat-model and Task 5 plan objectives, reportability policy, ownership ledger, audit harness, exclusions, and backlog were also checked.

Candidate count is 11: six validated findings, four rejected hypotheses, and one deferred candidate whose reportability depends on an external deployment fact. Separately, two prescribed runtime checks are deferred because their required production/browser/Anvil inputs are unavailable; these are test limitations, not extra findings.

## Complete Task 5 owned-path inventory

The inventory below was enumerated from the immutable baseline with `git ls-tree -r --name-only 6184bc5febd43de99ab6cc2b6f71f7f90c878bb6 -- web/app web/src web/e2e web/scripts`: **83 tracked paths**. Every path is explicitly marked reviewed and classified. “Runtime” means shipped application behavior; “test-only” means test/fixture code not shipped as application behavior; “script” means a development or release helper; “generated” means checked-in generated client output. Cross-owner links identify the report responsible for the adjacent contract, generation, release, or test-system boundary; they do not transfer Task 5 browser/runtime ownership.

| Baseline path | Reviewed | Classification | Disposition / cross-owner reference |
| --- | --- | --- | --- |
| `web/app/analytics/page.tsx` | Yes | Runtime | Reviewed; no independent candidate. |
| `web/app/create/page.tsx` | Yes | Runtime | Reviewed; no independent candidate. |
| `web/app/docs/page.tsx` | Yes | Runtime | Reviewed; no independent candidate. |
| `web/app/e2e/rpc/route.ts` | Yes | Runtime, test-only, cross-owner | Reviewed; deferred candidate P5-T5-011 covers flag-gated relay exposure. Release/preview trust boundary: [Task 7 report](10-task-7-supply-chain-release.md). |
| `web/app/error.tsx` | Yes | Runtime | Reviewed; no independent candidate. |
| `web/app/global-error.tsx` | Yes | Runtime | Reviewed; no independent candidate. |
| `web/app/globals.css` | Yes | Runtime | Reviewed; focus-visible and reduced-motion behavior checked; keyboard-semantic finding P5-T5-006 is in the tab controls, not these styles. |
| `web/app/graduated/page.tsx` | Yes | Runtime | Reviewed; no independent candidate. |
| `web/app/layout.tsx` | Yes | Runtime | Reviewed; no independent candidate. |
| `web/app/not-found.tsx` | Yes | Runtime | Reviewed; no independent candidate. |
| `web/app/page.tsx` | Yes | Runtime | Reviewed; no independent candidate. |
| `web/app/profile/page.tsx` | Yes | Runtime | Reviewed; no independent candidate. |
| `web/app/providers.tsx` | Yes | Runtime | Reviewed; wallet/provider lifecycle inspected; no independent candidate. |
| `web/app/token/[address]/page.tsx` | Yes | Runtime | Reviewed; route-to-detail/chart flow supports P5-T5-004. |
| `web/e2e/accessibility.spec.ts` | Yes | Test-only | Reviewed; axe route coverage excludes token/trade, recorded under P5-T5-006. |
| `web/e2e/diagnostic.spec.ts` | Yes | Test-only | Reviewed; no independent candidate. |
| `web/e2e/release-hardening.spec.ts` | Yes | Test-only, cross-owner | Reviewed; release-fixture assertions checked against [Task 7 release evidence](10-task-7-supply-chain-release.md). |
| `web/e2e/task6-anvil.spec.ts` | Yes | Test-only, cross-owner | Reviewed; transaction-path coverage supports P5-T5-001; Task 6 test-system and implementation context: [Task 6 report](09-task-6-quality-performance.md). |
| `web/e2e/task6-transactions.spec.ts` | Yes | Test-only, cross-owner | Reviewed; wallet/transaction browser assertions checked; Task 6 cross-review: [Task 6 report](09-task-6-quality-performance.md). |
| `web/e2e/token-detail.spec.ts` | Yes | Test-only | Reviewed; no same-length historical-replacement assertion, relevant to P5-T5-004. |
| `web/scripts/anvil-task6-gate.ps1` | Yes | Script, test-only, cross-owner | Reviewed; Anvil gate orchestration is test infrastructure; [Task 6 report](09-task-6-quality-performance.md) and [Task 7 release-gate review](10-task-7-supply-chain-release.md). |
| `web/scripts/anvil-task6-platform.test.mjs` | Yes | Script, test-only, cross-owner | Reviewed; script platform test; Task 7 process/release boundary: [Task 7 report](10-task-7-supply-chain-release.md). |
| `web/scripts/check-budgets.mjs` | Yes | Script, cross-owner | Reviewed; budget checker behavior is separate from its build/dependency provenance; [Task 7 report](10-task-7-supply-chain-release.md). |
| `web/scripts/check-budgets.test.mjs` | Yes | Script, test-only, cross-owner | Reviewed; checker tests inspected; [Task 7 report](10-task-7-supply-chain-release.md). |
| `web/scripts/generate-api.mjs` | Yes | Script, cross-owner | Reviewed; generation provenance belongs to Task 7 and OpenAPI/API semantics to Task 4: [Task 7 report](10-task-7-supply-chain-release.md), [Task 4 report](07-task-4-api-auth.md). |
| `web/scripts/generate-contracts.mjs` | Yes | Script, cross-owner | Reviewed; generation provenance belongs to Task 7 and ABI semantics to Task 2: [Task 7 report](10-task-7-supply-chain-release.md), [Task 2 report](05-task-2-contracts.md). |
| `web/scripts/run-anvil-task6-gate.mjs` | Yes | Script, test-only, cross-owner | Reviewed; Anvil runner lifecycle is test/release infrastructure; [Task 6 report](09-task-6-quality-performance.md), [Task 7 report](10-task-7-supply-chain-release.md). |
| `web/scripts/validate-release.mjs` | Yes | Script, cross-owner | Reviewed; production fixture rejection supports P5-T5-011 disposition; release policy belongs to [Task 7](10-task-7-supply-chain-release.md). |
| `web/scripts/validate-release.test.mjs` | Yes | Script, test-only, cross-owner | Reviewed; release validator assertions inspected; [Task 7 report](10-task-7-supply-chain-release.md). |
| `web/scripts/verify-release-command.test.mjs` | Yes | Script, test-only, cross-owner | Reviewed; release-command test inspected; [Task 7 report](10-task-7-supply-chain-release.md). |
| `web/src/amounts.test.ts` | Yes | Test-only | Reviewed; no independent candidate. |
| `web/src/amounts.ts` | Yes | Runtime | Reviewed; exact amount/rounding helpers inspected; no independent candidate. |
| `web/src/api/client.test.ts` | Yes | Test-only, cross-owner | Reviewed; client failure/contract assertions inspected; API semantics cross-reference [Task 4 report](07-task-4-api-auth.md). |
| `web/src/api/client.ts` | Yes | Runtime, cross-owner | Reviewed; request/error handling and generated type consumption checked; server API contract cross-reference [Task 4 report](07-task-4-api-auth.md). |
| `web/src/api/generated.ts` | Yes | Runtime, generated, cross-owner | Reviewed as a consumed contract artifact; drift check passed. Generator/provenance: [Task 7 report](10-task-7-supply-chain-release.md); OpenAPI contract ownership: [Task 4 report](07-task-4-api-auth.md). |
| `web/src/api/problems.ts` | Yes | Runtime, cross-owner | Reviewed; problem payload mapping checked; API error contract cross-reference [Task 4 report](07-task-4-api-auth.md). |
| `web/src/api/sse.test.ts` | Yes | Test-only, cross-owner | Reviewed; current tests exercise retry cases but omit repeated SSE-only errors, supporting P5-T5-005. Upstream event amplification is separately owned by [Task 3](06-task-3-indexer-data.md). |
| `web/src/api/sse.ts` | Yes | Runtime, cross-owner | Reviewed; reconnect state path validates P5-T5-005. Upstream notification behavior is in [Task 3 report](06-task-3-indexer-data.md). |
| `web/src/api/types.test.ts` | Yes | Test-only, cross-owner | Reviewed; API DTO validation coverage inspected; contract ownership [Task 4 report](07-task-4-api-auth.md). |
| `web/src/api/types.ts` | Yes | Runtime, cross-owner | Reviewed; API DTO bounds/shape checks inspected; backend contract ownership [Task 4 report](07-task-4-api-auth.md). |
| `web/src/components/app-shell.tsx` | Yes | Runtime | Reviewed; no independent candidate. |
| `web/src/components/icons.tsx` | Yes | Runtime | Reviewed; no independent candidate. |
| `web/src/components/primitives.test.ts` | Yes | Test-only | Reviewed; shared tabs primitive keyboard semantics provide counterevidence for route-local P5-T5-006. |
| `web/src/components/primitives.tsx` | Yes | Runtime | Reviewed; shared tab implementation compared with route-local trade tabs in P5-T5-006. |
| `web/src/components/route-placeholder.tsx` | Yes | Runtime | Reviewed; no independent candidate. |
| `web/src/components/route-transition.tsx` | Yes | Runtime | Reviewed; no independent candidate. |
| `web/src/config/public.test.ts` | Yes | Test-only, cross-owner | Reviewed; public config assertions inspected; build/config provenance is [Task 7-owned](10-task-7-supply-chain-release.md). |
| `web/src/config/public.ts` | Yes | Runtime, cross-owner | Reviewed; browser-visible env/config behavior checked; deployment/config provenance cross-reference [Task 7 report](10-task-7-supply-chain-release.md). |
| `web/src/config/release.test.ts` | Yes | Test-only, cross-owner | Reviewed; release configuration assertions inspected; [Task 7 report](10-task-7-supply-chain-release.md). |
| `web/src/config/release.ts` | Yes | Runtime, cross-owner | Reviewed; release-target and fixture gating supports P5-T5-011; manifest/release boundary belongs to [Task 7](10-task-7-supply-chain-release.md). |
| `web/src/contracts/generated.ts` | Yes | Runtime, generated, cross-owner | Reviewed as a consumed ABI/deployment artifact; drift check passed. Generator/provenance: [Task 7 report](10-task-7-supply-chain-release.md); contract behavior: [Task 2 report](05-task-2-contracts.md). |
| `web/src/discovery/controller.test.ts` | Yes | Test-only | Reviewed; no independent candidate. |
| `web/src/discovery/controller.ts` | Yes | Runtime | Reviewed; request concurrency/cancellation path inspected; no independent candidate. |
| `web/src/discovery/query-state.test.ts` | Yes | Test-only | Reviewed; no independent candidate. |
| `web/src/discovery/query-state.ts` | Yes | Runtime | Reviewed; route/query state behavior inspected; no independent candidate. |
| `web/src/discovery/token-discovery.tsx` | Yes | Runtime | Reviewed; API-driven list and failure behavior inspected; no independent candidate. |
| `web/src/profile/profile-view.tsx` | Yes | Runtime | Reviewed; profile rendering and API-driven failure behavior inspected; no independent candidate. |
| `web/src/security/headers.test.ts` | Yes | Test-only, cross-owner | Reviewed; header assertions inspected; deployment CSP/header configuration cross-reference [Task 7 report](10-task-7-supply-chain-release.md). |
| `web/src/security/headers.ts` | Yes | Runtime, cross-owner | Reviewed; security header policy inspected; framework/deployment configuration boundary [Task 7 report](10-task-7-supply-chain-release.md). |
| `web/src/security/logging.test.ts` | Yes | Test-only | Reviewed; redaction assertions inspected; no independent candidate. |
| `web/src/security/logging.ts` | Yes | Runtime | Reviewed; client-side logging/redaction path inspected; no independent candidate. |
| `web/src/token/address.test.ts` | Yes | Test-only | Reviewed; address input coverage inspected; no independent candidate. |
| `web/src/token/address.ts` | Yes | Runtime | Reviewed; token address parsing/normalization inspected; no independent candidate. |
| `web/src/token/chart-data.test.ts` | Yes | Test-only | Reviewed; normalization coverage does not cover same-length historical replacement in rendered chart (P5-T5-004). |
| `web/src/token/chart-data.ts` | Yes | Runtime | Reviewed; API candle bounds and transformation path checked; P5-T5-004 is in full-series refresh lifecycle. |
| `web/src/token/market-chart.tsx` | Yes | Runtime, cross-owner | Reviewed; stale historical series is P5-T5-004. Task 6 independently noted this UI boundary in [its report](09-task-6-quality-performance.md). |
| `web/src/token/metadata-editor.test.ts` | Yes | Test-only | Reviewed; metadata validation coverage inspected; partial-save candidate rejected as P5-T5-009. |
| `web/src/token/metadata-editor.tsx` | Yes | Runtime | Reviewed; metadata/image save, text/link/image rendering and retry behavior support rejected P5-T5-008/009. |
| `web/src/token/pagination.test.ts` | Yes | Test-only | Reviewed; pagination boundary tests inspected; no independent candidate. |
| `web/src/token/pagination.ts` | Yes | Runtime | Reviewed; cursor bounds and response handling inspected; no independent candidate. |
| `web/src/token/sse-scope.test.ts` | Yes | Test-only | Reviewed; event-to-token scoping coverage inspected; no independent candidate. |
| `web/src/token/sse-scope.ts` | Yes | Runtime | Reviewed; scoped invalidation path inspected; no independent candidate. |
| `web/src/token/token-detail.tsx` | Yes | Runtime, cross-owner | Reviewed; refresh/reorg path supports P5-T5-003/004. Canonical event/data production is cross-reviewed under [Task 3](06-task-3-indexer-data.md) and API contract under [Task 4](07-task-4-api-auth.md). |
| `web/src/transactions-panel.tsx` | Yes | Runtime, cross-owner | Reviewed; primary path for P5-T5-001/002/006 and rejected P5-T5-010; contract behavior cross-reference [Task 2 report](05-task-2-contracts.md), browser/test boundary [Task 6 report](09-task-6-quality-performance.md). |
| `web/src/transactions-task6.test.ts` | Yes | Test-only, cross-owner | Reviewed; helper-level intent equality does not bind UI confirmation, supporting P5-T5-001; Task 6 implementation/test review: [Task 6 report](09-task-6-quality-performance.md). |
| `web/src/transactions.test.ts` | Yes | Test-only | Reviewed; observer transition/reorg coverage supports P5-T5-003; no transient canonical-fetch failure assertion. |
| `web/src/transactions.ts` | Yes | Runtime | Reviewed; canonical transaction observation supports P5-T5-002/003. |
| `web/src/wallet/config.test.ts` | Yes | Test-only, cross-owner | Reviewed; wallet config assertions inspected; provider/dependency provenance cross-reference [Task 7 report](10-task-7-supply-chain-release.md). |
| `web/src/wallet/config.ts` | Yes | Runtime, cross-owner | Reviewed; wallet chain/RPC setup inspected; dependency/build provenance belongs to [Task 7](10-task-7-supply-chain-release.md). |
| `web/src/wallet/explorer.ts` | Yes | Runtime | Reviewed; explorer URL construction/scheme behavior inspected; no independent candidate. |
| `web/src/wallet/readiness.test.ts` | Yes | Test-only | Reviewed; no independent candidate. |
| `web/src/wallet/readiness.ts` | Yes | Runtime | Reviewed; wallet readiness gating inspected; no independent candidate. |
| `web/src/wallet/reads.ts` | Yes | Runtime, cross-owner | Reviewed; chain-pinned reads and quote path inspected for P5-T5-001/007; wallet contract boundary cross-reference [Task 2 report](05-task-2-contracts.md). |

Inventory reconciliation: **83/83** baseline paths are listed and reviewed. Test-only and generated files are explicit dispositions, not implicit passes. The cross-owner references above route API/OpenAPI semantics to Task 4, indexer/reorg event production to Task 3, ABI behavior to Task 2, transaction/performance test boundaries to Task 6, and generation/release/config provenance to Task 7. The ledger-external `web/` manifests and build configuration remain Task 7-owned and are linked in the scope statement above.

## Validated findings

### P5-T5-001 — Wallet write intent can differ from the displayed confirmation

- State: validated finding
- Severity: High
- Confidence: high
- Primary audit task: Task 5
- Affected asset/surface: curve and graduated buy/sell confirmation and wallet-signing paths in `web/src/transactions-panel.tsx` (Task 5 ownership row `docs/audits/plan-5/01-surface-ownership.md:38`)
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Attacker/failure actor and prerequisites: trader; the API quote is stale, the on-chain price changes before review/sign, or the user leaves the review panel open. No elevated privilege is required.
- Source-to-sink or failure path: the API effect stores a quote without storing the input/side identity that produced it (`web/src/transactions-panel.tsx:266-300`); `activeQuote` and the displayed minimum use that state (`:346-348`, `:811-819`, `:836-856`). On Sign, `execute` hides the reviewed values (`:375`), computes a new deadline (`:379`), reads a fresh contract quote and stores an intent (`:410-444`), then compares only that new intent to a second on-chain read (`:498-546`) before simulating and writing (`:548-571`). The user-visible confirmation is not part of `sameWriteIntent`. The router path has the same shape: it creates a deadline and hides confirmation on Sign (`:1040-1058`), re-quotes after that (`:1137-1164`), while the displayed minimum/deadline are current state and a render-time calculation (`:1296-1333`).
- Exact evidence: `web/src/transactions-panel.tsx:284`, `:346-348`, `:375`, `:379`, `:428-444`, `:523-546`, `:548-571`, `:849-856`, `:1038-1058`, `:1137-1164`, `:1322-1333`. `web/src/transactions-task6.test.ts:74-87` tests helper-level intent equality, not equality to the review UI. `web/e2e/task6-anvil.spec.ts:156-219` exercises a normal buy/sell/approval path without changing the quote between review and sign.
- Impact: a user can approve one minimum output and sign a different, lower threshold based on the current on-chain quote. A displayed backend minimum can be stale while the wallet call uses a fresh one; the 5% slippage limit is then applied to the fresh quote rather than the reviewed value. The displayed deadline can also slide while the review is open because it is recomputed on render and again at Sign. This is material wallet-intent substitution; the contract enforces the signed minimum but cannot enforce what the user saw.
- Counterevidence and assumptions: the UI labels the backend quote informational and says the contract quote is authoritative before signing; the code checks the wallet account/chain and compares two fresh on-chain intents before simulation. Those controls do not display or require consent to the changed intent. Contract slippage/deadline checks protect only the values actually signed.
- Reproduction/proof method: source trace above is deterministic. A regression test should give the UI quote for amount A, change the API/on-chain quote before Sign (and separately leave Review open long enough to move the deadline), then assert no wallet request occurs until the changed minimum/deadline is visibly reviewed and confirmed. Assert target, account, chain, value, args, minimum, and deadline against the displayed review.
- Proposed remediation: capture a review-time immutable intent from a fresh on-chain quote; display its exact wallet/account, chain, target, value, arguments, minimum, and deadline. Revalidate immediately before wallet invocation. If any security-relevant field changes, keep signing disabled, update the visible review, and require a second explicit confirmation.
- Required regression test: browser test changes quote and wallet/account/chain state at each review-to-sign boundary; it must prove that the wallet request is absent until the rendered confirmation equals the exact simulated and signed intent.
- Disposition/owner: validated; Task 8 remediation owner.
- Related findings and cross-task references: the contract-side minimum-output check remains effective for the signed value; this is a browser consent-binding defect, not a contract bypass.

### P5-T5-002 — Transaction status and hash are not recoverable after reload

- State: validated finding
- Severity: Medium
- Confidence: high
- Primary audit task: Task 5
- Affected asset/surface: client transaction state and canonical observation in `web/src/transactions-panel.tsx`
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Attacker/failure actor and prerequisites: user reloads/navigates away while a submitted transaction is mined, indexing, or under canonical observation; no attacker privilege is required.
- Source-to-sink or failure path: each transaction panel initializes state in component-local `useState` as `disconnected` (`web/src/transactions-panel.tsx:227`, `:1002`, `:1402`). `getCanonicalTransaction` is called only by `observeFreshSnapshot` (`:68-116`, `web/src/api/client.ts:266`), which is started after a successful receipt (`transactions-panel.tsx:579-584`, `:673-678`, `:1190-1195`, `:1619-1624`). No mount-time restore of a submitted hash/status exists. The observer removes its listeners and stops polling after 60 seconds (`:77-98`, `:110`).
- Exact evidence: `web/src/transactions-panel.tsx:68-98`, `:110-116`, `:160-162`, `:227`, `:579-584`; `web/src/api/client.ts:266`; `web/e2e/task6-anvil.spec.ts:156-219` covers a reload after an observed trade but does not assert that its status/hash is restored. `rg -n 'localStorage|sessionStorage' web/src web/app` found no transaction persistence path.
- Impact: after reload, the UI cannot distinguish a prior submitted/indexing/reorged write from no write. A user deciding whether to retry loses the app’s exact hash and lifecycle state, creating avoidable duplicate-action risk and breaking the Task 5 requirement to preserve lifecycle distinctions across reloads.
- Counterevidence and assumptions: wallet/explorer history and indexed trade rows can provide independent evidence; a reload does not itself resend a transaction. This does not restore the app’s pending/reverted/canonical state or connect it to the submitted hash.
- Reproduction/proof method: submit a write, reload while the indexer is delayed, and inspect the panel. The new component starts `disconnected`; there is no API call to recover the previous transaction hash. The 60-second observer also stops listening for later reorg/finality updates.
- Proposed remediation: persist only the public submitted hash and non-secret action/chain/token context, then query the canonical transaction endpoint on mount and reattach lifecycle observation. Keep wallet signatures/tokens out of storage. Continue observation until a documented terminal policy rather than a fixed short window.
- Required regression test: reload while the transaction is indexing and after it becomes safe; restore the same hash/state, then simulate canonical disappearance and verify regression without a second wallet request.
- Disposition/owner: validated; Task 8 remediation owner.
- Related findings and cross-task references: P5-T5-003 covers false regression when canonical API reads fail.

### P5-T5-003 — Transient canonical API failures are treated as reorgs

- State: validated finding
- Severity: Low
- Confidence: high
- Primary audit task: Task 5
- Affected asset/surface: canonical status refresh in `web/src/transactions-panel.tsx`
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Attacker/failure actor and prerequisites: temporary API/network failure during canonical transaction polling; no attacker privilege is required.
- Source-to-sink or failure path: `observeFreshSnapshot` catches all exceptions from `getCanonicalTransaction` (`:136`) and supplies `records: []` (`:138-143`). `observeCanonicalTransaction` treats an absent previously canonical hash as a reorg and regresses `safe`/`finalized`/`indexed` to `indexing` (`web/src/transactions.ts:47-53`); caller then emits `launchpad:canonical-reorg` (`transactions-panel.tsx:145-149`). A network error, 5xx, or an authoritative not-found response is not distinguished.
- Exact evidence: `web/src/transactions-panel.tsx:116`, `:136-149`; `web/src/transactions.ts:47-53`; `web/src/transactions-task6.test.ts:138-179` tests record absence/reorg but not API transport failure.
- Impact: a temporary API outage produces a false “canonical record disappeared”/indexing state and triggers token/candle/collection refresh as if a reorg had occurred. This misstates canonicality but does not change chain state or wallet execution.
- Counterevidence and assumptions: subsequent successful polling can restore the canonical state; current polling is bounded by the observer window. No false transaction is submitted.
- Reproduction/proof method: first return an event at `safe`, then make the next canonical endpoint request fail with a timeout/503; the catch passes no records and the pure observer regresses state.
- Proposed remediation: only treat an authoritative canonical absence/reorg response as disappearance. Preserve last known state on transport/server failure and expose a separate refresh-unavailable condition.
- Required regression test: inject a timeout/503 after `safe` and assert state remains safe with an API-error indicator; keep the existing missing-record test as the distinct reorg case.
- Disposition/owner: validated; Task 8 remediation owner.
- Related findings and cross-task references: P5-T5-002 covers persistence/observer lifetime.

### P5-T5-004 — Same-length candle refresh leaves stale chart history

- State: validated finding
- Severity: Low
- Confidence: high
- Primary audit task: Task 5
- Affected asset/surface: token chart refresh in `web/src/token/market-chart.tsx` and `web/src/token/token-detail.tsx`
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Attacker/failure actor and prerequisites: reorg or corrected API candle snapshot changes historical values while preserving point count; no attacker privilege is required.
- Source-to-sink or failure path: token detail replaces the full `chartPoints` array on each candle response (`web/src/token/token-detail.tsx:158-183`) and refreshes on canonical-reorg (`:367-380`). `MarketChart` calls full-series `setData` only in chart creation (`web/src/token/market-chart.tsx:63-79`), but its lifecycle effect is keyed by `[mode, points.length]` (`:97-99`). For equal-length replacements the later effect updates only the last price/volume point (`:101-115`); earlier corrected candles remain in the chart. If a reorg moves the last timestamp backwards, the incremental update can also be rejected by the chart series while stale data remains.
- Exact evidence: `web/src/token/market-chart.tsx:63-79`, `:97-115`; `web/src/token/token-detail.tsx:158-183`, `:367-380`; `web/src/token/chart-data.test.ts:16-32` tests transforms and pure last-bar update, not full-series replacement; `web/e2e/token-detail.spec.ts:159-194` tests initial render/timeframe selection, not same-length reorg refresh.
- Impact: the visible indexed-history chart can disagree with the refreshed token snapshot after a reorg/correction. Trading quotes are sourced separately from the backend/on-chain quote paths, so the chart does not directly set wallet arguments; stale visualization can nevertheless mislead market assessment.
- Counterevidence and assumptions: chart values are explicitly derived from indexed candle DTOs and validated for bounds; current finality banners remain separate. The defect is specific to replacing historical points without changing array length.
- Reproduction/proof method: mount with candles at times T1/T2/T3; refresh equal-length data changing T1 while T3 stays the same; the chart series receives only an update at T3. Then refresh with a removed latest bar and observe update of an earlier time against the old latest series.
- Proposed remediation: call `setData` when the complete snapshot/series changes (including reorg corrections), reserving `update` for a proven same-series newest-bar append/update path.
- Required regression test: component-level test for same-length historical correction and shorter/reorged series; assert exact series data and no chart update exception.
- Disposition/owner: validated; Task 8 remediation owner.
- Related findings and cross-task references: Task 3 owns canonical candle correctness; this finding is the browser consumer refresh defect.

### P5-T5-005 — Successful REST recovery resets SSE backoff, permitting a tight reconnect loop

- State: validated finding
- Severity: Low
- Confidence: medium
- Primary audit task: Task 5
- Affected asset/surface: `web/src/api/sse.ts`, used by discovery and token detail
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Attacker/failure actor and prerequisites: the SSE route or proxy repeatedly errors while REST endpoints remain available; a user keeps discovery or token detail open.
- Source-to-sink or failure path: an EventSource error closes the source and schedules recovery (`web/src/api/sse.ts:55-77`). With `retryAttempt === 0`, recovery delay is zero (`:84-92`). A successful REST snapshot resets `retryAttempt` to zero and reconnects (`:98-106`); the next SSE-only error therefore repeats immediately and never reaches `maxAttempts`. Token detail recovery reloads token, candles, and collection (`web/src/token/token-detail.tsx:347-355`); discovery recovery reloads its page (`web/src/discovery/token-discovery.tsx:237-242`).
- Exact evidence: `web/src/api/sse.ts:71-109`; `web/src/api/sse.test.ts:77-100` covers REST failures followed by success but not repeated SSE errors with successful REST recovery.
- Impact: an SSE-only incompatibility can cause repeated EventSource connections and REST refreshes without backoff, increasing per-user traffic and API/browser resource consumption. This is conditional on the SSE path failing independently of REST.
- Counterevidence and assumptions: when REST itself fails, retries back off and are capped; stream events are invalidation hints and REST remains canonical. No server-side outage amplification was measured in this environment.
- Reproduction/proof method: make each created EventSource emit `error` after connection, while each `refetchSnapshot` resolves; advance fake timers. Every cycle schedules at zero and resets the retry counter, so the number of cycles is unbounded.
- Proposed remediation: maintain a separate consecutive EventSource reconnect/backoff counter, resetting only after a stable connection window or valid event, and cap retry traffic while preserving REST refresh on recovery.
- Required regression test: repeated source errors with successful REST snapshots must show exponential/bounded retry timing and stop/cap policy; retain existing transient-REST tests.
- Disposition/owner: validated; Task 8 remediation owner.
- Related findings and cross-task references: none.

### P5-T5-006 — Trade-side controls declare tabs without tab keyboard behavior

- State: validated finding
- Severity: MINOR
- Confidence: high
- Primary audit task: Task 5
- Affected asset/surface: curve and graduated trade-side switchers in `web/src/transactions-panel.tsx`
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Attacker/failure actor and prerequisites: keyboard or assistive-technology user selecting Buy versus Sell; no attacker privilege is required.
- Source-to-sink or failure path: both switchers use `role="tablist"` and `role="tab"` with `aria-selected` (`web/src/transactions-panel.tsx:747-766`, `:1242-1262`) but provide no roving `tabIndex`, `aria-controls`/tab-panel relationship, or arrow/Home/End handler. The shared primitive does implement these behaviors (`web/src/components/primitives.tsx:178-221`), but the transaction selectors bypass it.
- Exact evidence: the source lines above; `web/e2e/accessibility.spec.ts:4-6` runs axe only on shell routes and excludes populated token detail/trade; no keyboard test covers these selectors.
- Impact: keyboard users can still Tab to and activate each native button, but expected tab-list arrow-key navigation does not switch transaction side. This is a bounded accessibility/usability defect in a safety-relevant transaction choice, not a bypass.
- Counterevidence and assumptions: buttons retain visible labels, native focus, and Enter/Space activation; the selected side is announced through `aria-selected`. The issue is the declared tab interaction model and missing keyboard behavior.
- Reproduction/proof method: focus Buy and press ArrowRight/Home; source has no handler, so selection does not move. Tab/Enter remains available.
- Proposed remediation: use the tested `Tabs` primitive or implement roving focus, arrow/Home/End navigation, and associated panel semantics.
- Required regression test: Playwright keyboard test on populated token detail switches Buy/Sell and preserves visible selected state, focus, and confirmation side.
- Disposition/owner: validated; Task 8 remediation owner.
- Related findings and cross-task references: none.

## Rejected candidates

### P5-T5-007 — Wallet chain could change during simulation and sign on another chain

- State: rejected/suppressed
- Severity: High (candidate severity)
- Confidence: high
- Primary audit task: Task 5
- Affected asset/surface: `walletClient.writeContract` paths in `web/src/transactions-panel.tsx`
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Actor/prerequisites: user/provider switches chain between app preflight and wallet request.
- Source-to-sink or failure path: app checks the wallet before simulation and some paths do not repeat app-level checks afterward; hypothesis was a write to the reviewed address on the newly selected chain.
- Exact evidence: `web/src/transactions-panel.tsx:548-571`, `:1157-1179`; pinned `viem` 2.31.0 (`web/package.json:45`, `web/package-lock.json:23`) `sendTransaction` reads current chain and calls `assertCurrentChain` for JSON-RPC accounts before `eth_sendTransaction` (`web/node_modules/viem/actions/wallet/sendTransaction.ts:210-215`; assertion at `web/node_modules/viem/utils/chain/assertCurrentChain.ts:20-26`). The application passes the explicit account string to `writeContract`.
- Impact: no wrong-chain transaction path was established for the pinned wallet client; mismatch is rejected before the provider transaction request.
- Counterevidence and assumptions: the client has its reviewed chain configured. This rejection is limited to the app’s pinned viem path; changing wallet libraries or chain configuration requires re-audit.
- Reproduction/proof method: inspect pinned installed viem implementation and lock version; it checks `eth_chainId` immediately before request and throws on mismatch.
- Proposed remediation: none for this candidate. Keep the chain pin and preserve a regression test if wallet transport changes.
- Required regression test: existing wrong-chain E2E remains, plus a simulated chain flip before `writeContract` must reject without a transaction request.
- Disposition/owner: rejected with pinned-library counterevidence.
- Related findings and cross-task references: P5-T5-001 is a separate UI-intent binding defect.

### P5-T5-008 — Untrusted token metadata can execute markup or script through the web renderer

- State: rejected/suppressed
- Severity: High (candidate severity)
- Confidence: high
- Primary audit task: Task 5
- Affected asset/surface: metadata, token labels, image URLs, external links, CSP
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Actor/prerequisites: malicious token creator supplies markup, `javascript:` URL, or hostile image URL.
- Source-to-sink or failure path: candidate path was API/on-chain metadata into token detail/list rendering and then HTML, script, link, or image sinks.
- Exact evidence: metadata is rendered as React text in `web/src/token/token-detail.tsx` and discovery components; no `dangerouslySetInnerHTML`/`innerHTML` sink exists in owned paths. `web/src/components/primitives.tsx:400-415` restricts external links to HTTPS and sets `noopener noreferrer`; `:423-461` restricts image schemes, validates fallback, and sets `referrerPolicy="no-referrer"`. Editor URLs also reject credentials (`web/src/token/metadata-editor.tsx:33`).
- Impact: no executable metadata-to-DOM path was established. `unsafe-inline` in the CSP (`web/src/security/headers.ts:52-63`) is weaker defense-in-depth, but by itself is not a reachable injection finding under the reviewed sinks.
- Counterevidence and assumptions: browser CSP/runtime behavior still needs the production artifact check; server-side API URL policy is Task 4. No claim is made about an unreviewed third-party dependency’s own DOM sinks.
- Reproduction/proof method: source-to-sink search across owned renderers; unsafe URL test fixture in `web/e2e/token-detail.spec.ts` is intended to prove fallback, but browser execution was unavailable.
- Proposed remediation: none from this candidate. Preserve React text rendering, scheme validation, and output encoding; consider a nonce CSP only through a separately validated Next.js deployment design.
- Required regression test: keep the malicious image URL fixture and assert no request/script execution when browser tests can run.
- Disposition/owner: rejected as an executable injection finding; production bundle/browser proof deferred separately.
- Related findings and cross-task references: production bundle gate appears under deferred runtime verification.

### P5-T5-009 — Metadata plus image save is a partially committing, unrecoverable write

- State: rejected/suppressed
- Severity: MINOR (candidate severity)
- Confidence: high
- Primary audit task: Task 5
- Affected asset/surface: creator metadata editor and API client
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Actor/prerequisites: creator updates metadata and an image in one UI submission; the second request fails.
- Source-to-sink or failure path: metadata PUT commits first; image PUT is separate, so a failed image upload can leave metadata saved while the UI reports an error (`web/src/token/metadata-editor.tsx:211-244`).
- Exact evidence: `web/src/token/metadata-editor.tsx:211-224` advances metadata revision/ETag before image PUT; `web/src/api/client.ts:131-164` uses separate endpoints and independent revision validators.
- Impact: partial success can be confusing, but the committed metadata revision is retained, the selected file remains pending, and a retry uses the current metadata revision. No lost update, stale-validator loop, unauthorized write, or irreversible financial action was established.
- Counterevidence and assumptions: the API exposes independently versioned metadata/image resources; no atomic cross-resource contract is promised. Revision conflict recovery explicitly refreshes and requires review (`metadata-editor.tsx:226-242`).
- Reproduction/proof method: cause image PUT to fail after successful metadata PUT and inspect revision/file state; metadata persists, retry remains possible.
- Proposed remediation: no security/correctness change authorized. If product requires atomic save semantics, define that API contract separately and report partial success explicitly.
- Required regression test: if the UI copy changes, assert the saved metadata revision is retained and the unsaved file remains available for retry.
- Disposition/owner: rejected as a reportable data-integrity finding; user-facing partial-success copy may be considered in normal product work.
- Related findings and cross-task references: API endpoint authorization/version semantics remain Task 4.

### P5-T5-010 — Repeated clicks can submit concurrent writes in one mounted panel

- State: rejected/suppressed
- Severity: Medium (candidate severity)
- Confidence: high
- Primary audit task: Task 5
- Affected asset/surface: launch, curve/router trade, claim write handlers
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Actor/prerequisites: user double-clicks Sign/Claim or fires repeated click events before React rerenders.
- Source-to-sink or failure path: hypothesis was two overlapping calls reaching `writeContract`.
- Exact evidence: `web/src/transactions-panel.tsx:353-356`, `:375-376` gates curve execution with `executionLockRef`; claim uses `claimLockRef`/`claimBusy` (`:603-609`, `:678-687`); router and launch use independent lock refs (`:1041-1054`, `:1483-1485`).
- Impact: source guards prevent the same mounted handler from entering twice. Duplicate behavior after reload is a separate state-restoration finding (P5-T5-002).
- Counterevidence and assumptions: this does not prove persistence across reload, but no same-instance concurrent write path was found.
- Reproduction/proof method: inspect lock set before the first awaited operation and cleared only in `finally`; E2E test currently exercises normal single clicks.
- Proposed remediation: none for the same-instance candidate; preserve the lock ordering in any refactor.
- Required regression test: fire two Sign events synchronously and assert exactly one `writeContract` call.
- Disposition/owner: rejected with source-backed in-flight lock evidence.
- Related findings and cross-task references: P5-T5-002 addresses reload behavior.

## Deferred candidate and runtime verification

### P5-T5-011 — Public reachability of the unbounded E2E RPC relay is unknown

- State: deferred
- Severity: Medium if the E2E fixture origin is publicly reachable; otherwise not reportable under the test-fixture exclusion
- Confidence: medium
- Primary audit task: Task 5
- Affected asset/surface: `web/app/e2e/rpc/route.ts` and preview/test deployment exposure
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`
- Actor/prerequisites: unauthenticated caller can reach a web deployment built/run with `NEXT_PUBLIC_E2E_FIXTURE=1` and an operator-configured RPC upstream.
- Source-to-sink or failure path: the route accepts POST only, but with fixture mode enabled it reads the complete unbounded request body and forwards it to `TASK6_ANVIL_RPC_URL` or `NEXT_PUBLIC_TASK6_ANVIL_RPC_URL` without body-size, method, or timeout limits (`web/app/e2e/rpc/route.ts:3-18`).
- Exact evidence: `web/app/e2e/rpc/route.ts:5-18`. Prescribed production release validation rejects the fixture flag (`web/scripts/validate-release.mjs:58-63`), and the root release workflow runs validation before build (`scripts/verify-release.mjs:149-170`); Anvil is the only target that injects the fixture flag (`:160`).
- Impact: if a fixture build is exposed to untrusted network clients, request bodies and RPC methods are unbounded and can consume relay/upstream resources. Production reachability is not established; the normal production gate blocks this configuration.
- Counterevidence and assumptions: the route is under the Task 6 E2E-only fixture, no repository deployment of that fixture is present in this scope, and the production gate rejects it. Task 1 policy excludes an unreachable test fixture absent a release path. Whether any external preview exposes it is an infrastructure fact not available in this audit.
- Reproduction/proof method: source proves unbounded forwarding when the flag is true. Resume by inventorying actual preview/test deployments and their environment/ingress reachability, without making test credentials public.
- Proposed remediation: if any fixture origin is network-accessible, bind it to loopback/private test access and add strict body-size, RPC-method allowlist, and upstream timeout/response limits before exposure.
- Required regression test: production build rejects fixture mode; fixture route rejects oversized bodies/disallowed methods and aborts slow upstreams; network inventory confirms no public preview.
- Disposition/owner: deferred to Task 7/release infrastructure owner until preview exposure is verified; resume with deployment inventory. If none is exposed, reject as test-only; if exposed, validate and prioritize a resource-limit fix.
- Related findings and cross-task references: production build gate evidence is part of Task 7; no production bypass is claimed.

Two separate verification gates are also deferred, not findings:

1. Production build/bundle scan with the real reviewed deployment, Privy, API, RPC, origin, and hosting values. `npm run verify:release` failed closed because those production variables are absent (`NEXT_PUBLIC_PRIVY_APP_ID`, deployment/chain/API/RPC/origin); the generated deployment manifest has no enabled chain-46630 release target. Existing `web/.next` has no `BUILD_ID`, so its `verify:bundle` result is not a production artifact. Resume after the external production-input backlog item is completed, then run `node scripts/verify-release.mjs --target=production` without copying secrets into this report.
2. Full Playwright/Anvil keyboard, quote-drift, reorg, reload, and responsive runtime proof. `forge`, `anvil`, and Chrome are not installed on this host; Docker and PowerShell 7 are present. The browser fixture also writes screenshots under `.impeccable/review`, outside the single permitted report path, so the E2E/Anvil harness was not started. Resume on the approved fully provisioned runner with test artifacts isolated from the product worktree.

## Rejected/unconfirmed surfaces and coverage notes

- Generated client and ABI drift checks passed; no Task 5 generated output was changed. The generated API and contract scripts were run with `--check` only.
- Config fail-closed behavior is source-backed: production configuration must match an enabled reviewed deployment; the Task 6 fixture injects its own fake wallet configuration only when its explicit flag is set. The production validator rejects that flag.
- API auth and metadata server authorization were not re-audited as Task 5 ownership; browser token and identity values are sent in headers, not URL query parameters. Server verification is Task 4.
- No DOM HTML insertion sink, external redirect, unbounded browser cache, generated-client drift, or secret-bearing browser storage path was found in owned web paths. This is source review, not a substitute for the deferred production artifact scan.
- CSS has a visible `:focus-visible` outline and reduced-motion override (`web/app/globals.css:56-59`, `:1024-1032`). The transaction-side tab controls are the validated keyboard-semantic exception (P5-T5-006). Automated axe coverage currently excludes token detail/trade (`web/e2e/accessibility.spec.ts:4-12`).

## Commands and test limitations

Host versions: Node `v24.16.0`; npm `12.0.1`.

| Command | Result |
|---|---|
| `npm run format:check` (`web/`) | PASS |
| `npm run lint` (`web/`) | PASS |
| `npm exec tsc -- --noEmit --incremental false` (`web/`) | PASS |
| `npm run web-api-diff` (`web/`) | PASS |
| `npm run web-contracts-diff` (`web/`) | PASS; existing `contracts/out/` available |
| `npm run verify:bundle` (`web/`) | PASS on pre-existing `.next` files: initial 43,708 bytes, all JS 7,355,145 bytes, largest manifest 607 bytes. No `.next/BUILD_ID`; not accepted as production-build proof. |
| `npm test` (`web/`) | BLOCKED before test collection: Vite config startup `spawn EPERM` in `optimizeSafeRealPathSync`. `--configLoader runner` alternative also failed config loading with `ReferenceError: require is not defined`. |
| `npm run test:platform` (`web/`) | BLOCKED before assertions: Node test runner `spawn EPERM`. |
| `npm run verify:release` (`web/`) | Expected fail-closed: required production environment values absent and no matching enabled deployment. No production build was run. |
| Playwright E2E / Task 6 Anvil gate | NOT RUN: required Foundry/Anvil/Chrome unavailable; test harness also writes screenshots outside the authorized report path. |

No gate failure above was treated as a product finding. No code generation or `--write` synchronization was run. The bundle budget result is limited to the pre-existing `.next` tree. No cross-stack live transaction, production secret canary, hosting, browser-provider, or real API/DB behavior is claimed as verified.

## Backlog state

`backlog.md` contains exactly **2 Active items**; this audit added none:

1. Robinhood testnet deployment manifest.
2. Production release, governance, and audit inputs.

## Completion summary

Task 5 baseline source audit completed with **6 validated findings**, **11 candidates total** (4 rejected; 1 deferred; remaining 6 validated), plus **2 deferred runtime-verification gates**. No product files, plans, backlog, README, or generated artifacts were changed. This report is the sole Task 5 output.
