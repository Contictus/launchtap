# Plan 5 Task 1 — Reproducible Audit Harness

This harness is read-only with respect to product source. Build tools may create ignored caches,
`contracts/out/`, `web/.next/`, or temporary test data. A clean run must remove or isolate those
outputs and must finish with a clean working tree. No command may edit a tracked generated file as
part of an audit; use `--check`, `--diff`, or a temporary checkout when available.

## Clean-machine setup

1. Clone the repository and check out the exact target. Do not substitute `main`, `dev`, or the
   current head for the target.

   ```powershell
   git clone <repository-url> launchpad
   Set-Location launchpad
   git checkout --detach 6184bc5febd43de99ab6cc2b6f71f7f90c878bb6
   git submodule update --init --recursive
   git status --short --branch
   ```

2. Verify the gitlinks before running gates:

   ```powershell
   git ls-tree 6184bc5febd43de99ab6cc2b6f71f7f90c878bb6 contracts/lib
   git -C contracts/lib/forge-std rev-parse HEAD
   git -C contracts/lib/openzeppelin-contracts rev-parse HEAD
   ```

   The expected object IDs are in [00-baseline-provenance.md](00-baseline-provenance.md).

3. Install the pinned host tools: Foundry 1.8.1, Go 1.26.x, Node 24.16.0, npm 12.0.1,
   PowerShell 7, PostgreSQL 18.6 or Docker's `postgres:18.6-alpine`, Python 3.12, Slither
   0.11.6, and system Chrome for Playwright. `pwsh` is required; Windows PowerShell 5.1 is not
   an accepted fallback for contract/release gates.

4. Use synthetic local credentials only. Never place a real private key, seed phrase, Privy key,
   database credential, private RPC URL, or production token in a report, test, log, prompt, or
   commit. Production and fork commands are conditional and require separately approved values.

## Baseline command sequence

Run commands from the indicated directory and capture exit code, duration, tool versions, and
relevant output. The sequence is deliberately explicit so a missing prerequisite is visible.

| Order | Command | Required host / expected evidence |
| ---: | --- | --- |
| 1 | `git diff --check 6184bc5^ 6184bc5` | Git; baseline change hygiene. |
| 2 | `pwsh -NoProfile -ExecutionPolicy Bypass -File contracts/scripts/check.ps1 all` | Foundry, gitlinks, `forge`; normal contract test/size/layout/vector gate. |
| 3 | `cd backend; go run github.com/go-task/task/v3/cmd/task@v3.53.1 verify` | Go, network or cached Task module, Docker PostgreSQL, Foundry/Anvil; backend build, unit/race, integration, lint, migrations, generated drift, and Anvil indexer evidence. |
| 4 | `cd web; npm ci` | Node/npm and lockfile; clean dependency install. |
| 5 | `cd web; npm run web-api-diff; npm run web-contracts-diff; npm run format:check; npm run lint; npm run typecheck; npm test` | Node/npm and installed dependencies; generated, static, type, and unit evidence. Run as separate commands when collecting durations. |
| 6 | `cd web; npm run build; npm run verify:bundle; npm run test:e2e` | Node/npm, system Chrome or `PLAYWRIGHT_EXECUTABLE_PATH`; production build, bundle budgets/secret scan, and browser evidence. |
| 7 | `cd web; npm run test:anvil` | Node/npm, Foundry Anvil, PowerShell 7, and Docker PostgreSQL; real local cross-stack transaction evidence. |
| 8 | `pwsh -NoProfile -ExecutionPolicy Bypass -File contracts/scripts/check.ps1 release` | Foundry, Slither, Python, and conditional fork RPC; contract release/fork evidence. |
| 9 | `node scripts/verify-release.mjs --target=anvil` | All tools above, PostgreSQL, Chrome, and local Anvil; complete deterministic cross-stack release evidence. |

The canonical backend dependency list is `backend/Taskfile.yml`; the canonical web/release
sequence is `scripts/verify-release.mjs`. CI additionally proves integration sentinels and uses
read-only workflow permissions. A CI green result is evidence for that exact commit and runner,
not a substitute for production controls.

## Skip and failure policy

| Condition | Disposition |
| --- | --- |
| Baseline commit cannot be resolved, or checkout is dirty before the run | Stop. Do not audit another revision and do not call the result a baseline audit. |
| A gitlink cannot be initialized or its head cannot be verified | Mark contract-dependent tasks blocked/conditional; preserve the expected gitlink ID and exact error. Do not replace it with a floating dependency. |
| `forge` or `anvil` is missing | Skip contract/Anvil gates with `tool missing`; run unrelated static checks only. Do not claim contract or cross-stack coverage. |
| Docker/PostgreSQL is unavailable | Skip integration, migration lifecycle, database, and Anvil gates; retain unit/static results and report the missing service. |
| Chrome or Playwright executable is unavailable | Skip browser/E2E gates. The release script is expected to fail closed rather than silently use a different browser. |
| Network access or an uncached pinned tool/module is unavailable | Record the exact dependency-fetch failure. Do not change lockfiles, versions, or source to make the run pass. |
| Fork RPC, production configuration, or external credentials are absent | Mark the check conditional/external. Use synthetic canaries for leak-path tests; never invent values. |
| A command times out, is killed, or reports `spawn EPERM`/permission failure | Record command, host, exit/error, and duration as an environment failure. Do not convert it to a product finding without an independent source-backed path. |
| A drift check reports stale output | Record the candidate against the owning task; do not regenerate during Tasks 1–7. Task 8 may change generated outputs only under a validated finding. |

## Evidence record

Every gate record must include:

```text
baseline: 6184bc5febd43de99ab6cc2b6f71f7f90c878bb6
host: OS / architecture / tool versions
command: exact command and working directory
environment: non-secret variable names and safe mode only
start/end or duration:
exit status:
result: pass | fail | skipped | conditional
artifacts: paths, hashes, counts, sizes, or test sentinels
error/limitation: exact text when not pass
working-tree-after: git status --short --branch
```

After each run, inspect `git status --short` and `git diff --name-only`. Any tracked change is a
stop condition for a read-only audit and must be reverted only through an approved, recoverable
workflow; never hide it in the report.
