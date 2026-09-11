# Plan 5 Task 1 — Exclusions, Unknowns, and Threat-Model Reconciliation

## Threat-model reconciliation

`docs/specs/2026-09-11-security-threat-model.md` declares the same immutable baseline,
`6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`, and labels its attack stories as hypotheses. Its
component, trust-boundary, sensitive-resource, and external-prerequisite sections match the
repository surfaces in the ownership ledger.

Task 1 mechanically verified 80 unique `path:line` references in the threat model against the
baseline implementation tree: every referenced file exists and every cited line is in range.
Representative verified evidence includes:

| Boundary | Baseline evidence |
| --- | --- |
| Contract authority/economics | `contracts/src/LaunchFactory.sol:51`, `:148`, `:160`, `:179`; `contracts/src/BondingCurveV1.sol:89`, `:110`, `:147`, `:370`; `contracts/src/libraries/CurveMath.sol:73` |
| Chain/indexer/reorg | `backend/internal/chain/rpc.go:62`; `backend/internal/indexer/engine.go:16`, `:54`, `:243`; `backend/internal/indexer/reorg.go:31`; `backend/internal/store/postgres/ownership.go:33` |
| API/identity/metadata | `backend/internal/apiserver/server.go:26`, `:103`, `:157`; `backend/internal/privyauth/verifier.go:59`, `:161`; `backend/internal/apiserver/metadata_routes.go:143`, `:212`, `:260` |
| Browser/write intent | `web/src/config/public.ts:45`, `:89`, `:96`, `:100`; `web/src/config/release.ts:14`, `:29`; `web/src/transactions.ts:36`, `:87`, `:132`, `:183`; `web/src/wallet/readiness.ts:46` |
| Release/supply chain | `.github/workflows/contracts.yml:29`; `.github/workflows/backend.yml:59`; `.github/workflows/web.yml:51`; `.github/workflows/release.yml:53`; `scripts/verify-release.mjs:109`, `:119`, `:132` |

`Line-range verification` is provenance, not semantic approval. Tasks 2–7 must inspect the cited
symbols and either validate or reject each hypothesis with the canonical finding record. A line
that exists is not a security conclusion.

Reproducible check:

```powershell
$baseline = "6184bc5febd43de99ab6cc2b6f71f7f90c878bb6"
$text = Get-Content -Raw docs/specs/2026-09-11-security-threat-model.md
$refs = [regex]::Matches($text, '(?<![A-Za-z0-9_])([A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+):(\d+)') |
  ForEach-Object { $_.Groups[0].Value } | Sort-Object -Unique
foreach ($ref in $refs) {
  $path, $line = $ref -split ':'
  git cat-file -e "\${baseline}:$path"
  if ($LASTEXITCODE -ne 0) { throw "missing baseline path: $ref" }
}
```

The command above checks baseline path existence. The Task 1 run additionally checked line
ranges in the working tree, whose product paths are unchanged from the baseline (only the Plan 5
plan and threat model are after the baseline). Later task reports own semantic verification.

## Explicit exclusions

- **Product changes:** Tasks 1–7 cannot modify Solidity, Go, SQL, migrations, TypeScript/CSS,
  generated output, dependencies, workflows, scripts, or runtime configuration. Task 8 is the
  only remediation task.
- **Forum/Memestock:** intentionally not implemented; it receives a new persistence,
  authorization, moderation, abuse, and privacy model before implementation.
- **Vendored code:** `contracts/lib/*` is not first-party code-quality scope. Task 7 reviews its
  pin, provenance, and release reachability; it is not silently considered secure.
- **Generated copies:** generated/copy destinations are not independent implementation sources.
  Their provenance and drift are Task 7's primary concern; semantic consumers remain owned by
  Tasks 2–4.
- **Design/review images:** `.impeccable/` is not a deployed or release surface. Task 5 may use
  it as UX evidence but it does not establish browser security.
- **External controls:** a repository test cannot prove hosting, WAF/CDN, secret-manager,
  monitoring, legal/geo, signer custody, or independent audit controls.
- **Secrets:** no real key, token, database credential, private RPC URL, or Privy value is used
  or copied into the audit pack. Synthetic canaries are the only permitted leak-path values.

## External prerequisites and unknowns

The following remain outside repository proof and stay visible in `backlog.md`:

1. A funded, independently reviewed Robinhood chain-46630 deployment manifest and first live
   acceptance evidence.
2. Production Privy, RPC/API/origin, database/hosting/domain/CDN/WAF, secret-manager,
   monitoring, rollback values, and named owners.
3. Production pause multisig, timelock, treasury, legal/geo policy, and external audit evidence.
4. Production CoinGecko commercial credentials and attribution implementation.

Additional unknowns to carry into later tasks are the actual production database role/backup
policy, RPC provider behavior/SLA and archive depth, deployment bytecode evidence on the runtime
startup path, CI environment protection and artifact retention, and real traffic/cardinality for
performance measurements. These are not findings until a reachable control failure is shown.

Task 1 also records one documentation-consistency candidate without editing the forbidden
governing file: `AGENTS.md:37` says that no API/indexer runtime exists and that migration is the
only executable backend entrypoint, while the baseline contains `backend/cmd/api/`,
`backend/cmd/indexer/`, and their release/integration gates. This is an `IMPORTANT` documentation
candidate for later reconciliation, not a product-security finding; the Task 1 scope prohibits
editing `AGENTS.md`.

## Baseline caveats

The observed command outcomes and sizes in [00-baseline-provenance.md](00-baseline-provenance.md)
are host-specific Windows measurements. Missing Foundry/Anvil, unavailable Docker/network access,
and `spawn EPERM` prevent a complete local release result. They are recorded as failures or
conditional skips, not as product defects and not as passes. No production-readiness claim is
made from this Task 1 pack.
