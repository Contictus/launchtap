# Plan 5 Task 1 — Baseline and Provenance

## Audit target

The only implementation target is:

```text
commit: 6184bc5febd43de99ab6cc2b6f71f7f90c878bb6
subject: Merge pull request #5 from Contictus/dev
author: Contictus <mesutokul4@gmail.com>
author date: 2026-09-11T21:40:30+03:00
committer: GitHub <noreply@github.com>
commit date: 2026-09-11T21:40:30+03:00
parents: cfef0073f11993ddf5de06facc9e916a1a915f5e b73fabe8d64c46b82a24c573c4c35bc6183c0e5d
```

The checkout used for this Task 1 documentation is `dev` at `eb7f5f345e93f1ad02058b994d2eb02c721eedbb`.
`git diff 6184bc5..HEAD` contains only the Plan 5 plan and threat model; the implementation
tree is therefore the baseline tree. This pack is intentionally not treated as implementation
evidence.

Reproducible identity checks:

```powershell
$baseline = "6184bc5febd43de99ab6cc2b6f71f7f90c878bb6"
git cat-file -t $baseline
git show -s --format=fuller $baseline
git diff --name-status "$baseline..HEAD"
git ls-tree -r --name-only $baseline | Measure-Object
```

The baseline tree contains 444 tracked paths. Top-level implementation counts are 183 under
`backend/`, 88 under `contracts/`, and 99 under `web/` (the remainder are root, docs, CI, and
design/review material).

## Gitlinks and submodule provenance

The baseline has two gitlinks. Their exact object IDs are recorded from the baseline tree, not
inferred from the current checkout:

| Path | Baseline gitlink | URL in baseline `.gitmodules` | Use |
| --- | --- | --- | --- |
| `contracts/lib/forge-std` | `620536fa5277db4e3fd46772d5cbc1ea0696fb43` | `https://github.com/foundry-rs/forge-std.git` | Foundry test/runtime support |
| `contracts/lib/openzeppelin-contracts` | `cab19933c33c2ad1d4c7a84864a3601dddfd16f3` | `https://github.com/OpenZeppelin/openzeppelin-contracts.git` | Solidity library dependency |

Use plumbing when `git submodule status` is unavailable:

```powershell
git ls-tree "$baseline:contracts/lib"
git show "$baseline:.gitmodules"
git submodule update --init --recursive
git -C contracts/lib/forge-std rev-parse HEAD
git -C contracts/lib/openzeppelin-contracts rev-parse HEAD
```

On the Task 1 Windows host, `git submodule status` failed before producing status because Git's
bundled `sh.exe` could not create its signal pipe (`Win32 error 5`). This is a host/tooling
failure, not evidence that a gitlink is clean or dirty. The `git ls-tree` records above remain
valid baseline provenance. Direct `git -C ... rev-parse HEAD` checks did match both expected
objects on this host; a clean-machine run must still verify the checked-out submodule heads.

## Generated and copied inputs

The following relationships are source-backed at the baseline. A destination is not an
independent source of truth.

| Authoritative input | Destination or consumer | Drift/provenance check |
| --- | --- | --- |
| `contracts/vectors/v1/` | `backend/internal/curve/testdata/` | `cd backend; go run ./cmd/sync-curve-vectors --check` |
| `contracts/abi/v1/` and `contracts/fixtures/v1/` | `backend/internal/chain/abi/v1/` and `backend/internal/chain/testdata/` | `cd backend; go run ./cmd/sync-event-abis --check` |
| `contracts/deployments/` | `backend/deployments/testdata/` | `cd backend; go run ./cmd/check-deployments` |
| Go API route definitions | `backend/openapi/v1.json` | `cd backend; go run ./cmd/check-openapi` |
| `backend/openapi/v1.json` | `web/src/api/generated.ts` | `cd web; npm run web-api-diff` |
| contract ABIs, `contracts/out/`, and deployment configs | `web/src/contracts/generated.ts` | `cd web; npm run web-contracts-diff` |
| migrations and SQL queries | `backend/internal/store/postgres/sqlc/` | `cd backend; go run github.com/sqlc-dev/sqlc/cmd/sqlc@v1.31.1 diff` |
| Solidity source and Foundry outputs | contract sizes, storage layout, coverage, and release checks | `cd contracts; pwsh ./scripts/check.ps1 all` (requires Foundry and gitlinks) |

Task 1 records these relationships; it does not regenerate or modify any destination.

On the Task 1 host, all four local Go drift checks (`sync-curve-vectors --check`,
`sync-event-abis --check`, `check-deployments`, and `check-openapi`) exited 0. This verifies the
committed copies against their current baseline sources; it does not prove that a future checkout
or production artifact will remain synchronized.

## Pinned toolchain and host requirements

| Tool | Repository pin or requirement | Evidence |
| --- | --- | --- |
| Go | `go 1.26.0` module line; project guidance is Go 1.26.x | `backend/go.mod`, `README.md` |
| Foundry | `v1.8.1` | `contracts/foundry.toml`, CI workflows |
| Solidity | `0.8.36` | `contracts/foundry.toml` |
| sqlc | `v1.31.1` via `go run` | `backend/Taskfile.yml` |
| Task | `v3.53.1` via `go run` | `backend/Taskfile.yml`, release script |
| golangci-lint | `v2.13.2` via `go run` | `backend/Taskfile.yml` |
| Node.js / npm | `24.16.0` / `12.0.1` | `web/package.json`, CI, web README |
| PostgreSQL | `18.6` in CI service | backend/release workflows |
| Python / Slither | Python `3.12`, Slither `0.11.6` for contract release audit | contracts workflow |
| Browser | System Chrome or explicit `PLAYWRIGHT_EXECUTABLE_PATH` | release script and web workflow |

The host used for evidence had Git 2.55.0, Go 1.26.7, Node 24.16.0, npm 12.0.1, PowerShell
7.6.5, PostgreSQL client 18.6, Python 3.12.10, and Slither 0.11.6. `forge` and `anvil` were
not on `PATH`; Docker was not available for a successful server probe. These are observations
for this run, not changes to the pinned requirements.

## Gate commands and observed results

The commands below are the release-relevant commands from the baseline. Results are recorded
with the host limitation; a failed local prerequisite is never converted into a pass.

| Gate | Exact command | Result on Task 1 host |
| --- | --- | --- |
| Contracts normal gate | `pwsh -NoProfile -ExecutionPolicy Bypass -File contracts/scripts/check.ps1 all` | **Failed** in 3.977 s: dependency pin check reported `forge is not on PATH`. |
| Backend full gate | `cd backend; go run github.com/go-task/task/v3/cmd/task@v3.53.1 verify` | **Failed** in 1.618 s before Task ran: Go proxy access to `proxy.golang.org` was refused by the sandbox. A Go telemetry upload-token permission warning was also emitted. |
| Backend compile-only smoke | `cd backend; go test ./... -run '^$'` with workspace-local `GOCACHE` | **Passed** in 36.027 s; packages compiled and tests were intentionally not executed. The same Go telemetry permission warning was emitted. |
| Backend unit/race gate (without integration tag) | `cd backend; go test ./... -race` with workspace-local `GOCACHE` | **Passed** in 53.744 s; integration-tagged database tests were not included. The same Go telemetry permission warning was emitted. |
| Web formatting | `cd web; npm run format:check` | **Passed** in 4.936 s. |
| Web lint | `cd web; npm run lint` | **Passed** in 6.563 s. |
| Web typecheck | `cd web; npm run typecheck` | **Passed** in 7.392 s. |
| Web generated API | `cd web; npm run web-api-diff` | **Passed** in 2.497 s. |
| Web generated contracts | `cd web; npm run web-contracts-diff` | **Passed** in 1.385 s. |
| Web bundle budget and secret scan | `cd web; npm run verify:bundle` | **Passed** in 1.394 s; reported initial `43,708` bytes, all routes `7,355,145` bytes, largest manifest `607` bytes. |
| Web unit tests | `cd web; npm test` | **Failed** in 2.849 s with Vite `spawn EPERM` while loading `vitest.config.ts`. |
| Web production build | `cd web; npm run build` | **Failed** in 3.838 s after compilation with TypeScript `spawn EPERM`. It left only ignored `.next/` output; no tracked source changed. |

No contract, integration, Anvil, browser, fork, or production-target result is claimed. The
full cross-stack command is defined in `scripts/verify-release.mjs`; it requires all of the
above tools plus PostgreSQL, Chrome, and target-specific configuration.

## Baseline metrics and caveats

These are repeatable inventory/size measurements, not performance conclusions:

| Metric | Baseline observation | Method and caveat |
| --- | ---: | --- |
| Tracked paths | 444 | `git ls-tree -r --name-only 6184bc5`; includes docs/CI and generated files. |
| Go test files / declarations | 51 / 134 | `rg --files backend -g '*_test.go'` and `rg '^func Test'`; declaration count, not executed-test count. |
| Solidity test files / declarations | 55 / 627 | `rg --files contracts -g '*.t.sol'`; declaration count includes invariant helpers and is not a pass count. |
| Web test files / declarations | 30 / 137 | `rg --files web -g '*.test.ts' -g '*.test.mjs' -g '*.spec.ts'`; declaration count is approximate. |
| Backend OpenAPI | 1 file / 55,720 bytes | `backend/openapi/v1.json`. |
| Backend sqlc output | 17 files / 164,276 bytes | `backend/internal/store/postgres/sqlc/`. |
| Contract/backend ABI copies | 5 files / 38,473 bytes each | `contracts/abi/v1/` and `backend/internal/chain/abi/v1/`. |
| Curve vectors source/copy | 2 files / 14,093 bytes each | `contracts/vectors/v1/` and `backend/internal/curve/testdata/`. |
| Web generated API/contracts | 37,204 / 40,694 bytes | `web/src/api/generated.ts` and `web/src/contracts/generated.ts`. |

Durations are Windows, warm-cache, single-run observations on 2026-09-11. They are not a CI
budget, a production latency baseline, or evidence that one noisy run justifies optimization.
Task 6 must collect representative workloads, sample counts, medians, and tails before proposing
performance changes.
