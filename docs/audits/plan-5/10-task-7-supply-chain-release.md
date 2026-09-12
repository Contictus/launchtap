# Plan 5 Task 7 — Supply Chain, CI, Release, and Operational Readiness Audit

## Result

Reviewed the immutable product baseline `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`.
The current checkout is a descendant of that commit; the intervening changes inspected for
this audit are documentation only. No product, generated, workflow, dependency, deployment,
or backlog path was changed.

Task 7's 18 primary ownership-ledger rows account for 106 baseline paths (including two
submodule gitlinks); all were enumerated and reviewed. Fourteen generated contract/web
surfaces were also cross-checked for provenance. Result: **zero new validated security or
correctness findings**; two Task 7 hypotheses were rejected with repository evidence. Two
inherited boundaries (`P5-T3-003`, `P5-T4-006`) and one newly identified license-compliance
question (`P5-T7-001`) remain deferred, not validated. Supply-chain inventory is locally
complete for the pinned manifests and cached package evidence summarized below; current
registry/upstream status, CI advisory-log reconciliation, and selected tool-license/maintenance
fields remain explicitly incomplete. These statuses do not imply production readiness.

## Scope and path coverage

The audit followed the Task 7 acceptance criteria and the Plan 5 reportability policy. A
source/config concern was not promoted without a reachable release or operational impact,
and external production controls were not inferred from repository documentation.

| Task 7 primary ledger row | Baseline path count | Disposition |
| --- | ---: | --- |
| `contracts/script/local/` | 4 | Reviewed local deployment and bootstrap trust boundaries. |
| `contracts/deployments/` | 6 | Reviewed selectable/disabled manifests, schema inputs, and deployment checks. |
| `contracts/coverage/` | 4 | Reviewed generated coverage evidence and its gate provenance. |
| `contracts/slither/` | 1 | Reviewed pinned scanner-version evidence and check behavior. |
| `contracts/lib/forge-std/`, `contracts/lib/openzeppelin-contracts/` | 2 gitlinks | Pinned gitlink IDs matched `foundry.lock`; contents are third-party submodules, not first-party files. |
| `contracts/scripts/` | 15 | Reviewed pins, generated-output checks, deployment/release scripts, and fail-closed gates. |
| Contract-root manifests/configs | 4 | Reviewed `foundry.toml`, `foundry.lock`, `dependencies.lock`, and `slither.config.json`. |
| `backend/cmd/migrate/` | 2 | Reviewed explicit migration entrypoint and operator command boundary. |
| Backend generated-check commands | 4 | Reviewed deployment, OpenAPI, curve-vector, and ABI copy check/sync entrypoints. |
| `backend/deployments/` | 11 | Reviewed registry, schemas, manifests, and testdata. |
| Backend generated/copy surfaces | 26 | Reviewed OpenAPI, ABI/testdata, curve testdata, and sqlc generated files. |
| `backend/scripts/` | 1 | Reviewed release/E2E helper and cleanup behavior. |
| Backend-root manifests/configs | 6 | Reviewed `go.mod`, `go.sum`, `Taskfile.yml`, `.golangci.yml`, `sqlc.yaml`, `.env.example`. |
| Web-root manifests/configs | 8 | Reviewed package/lock, Next/TypeScript, browser/test config, budget policy, `.env.example`. |
| `.github/workflows/` | 4 | Reviewed trigger/path filters, job permissions, action/tool pins, secrets, and publication steps. |
| Root `scripts/` | 2 | Reviewed cross-stack release orchestration and subprocess timeout/cleanup. |
| `docs/runbooks/` | 5 | Reviewed deployment, production readiness, release/rollback, and operational procedure claims. |
| Release-facing root `README.md` | 1 | Cross-checked release/setup instructions against available gates. |

Cross-boundary provenance review covered 12 contract ABI/fixture/vector/storage-layout/size
paths and two web generated clients. `contracts/slither.db.json` was separately checked as
Task 2 scanner-triage evidence. Runtime consumers in `backend/cmd/api`, `backend/cmd/indexer`,
`backend/internal/config`, and `web/scripts` were read only where needed for manifest, release,
and generated-artifact flow; their primary ownership remains with Tasks 3–5.

## Dependency and toolchain inventory

- `contracts/foundry.toml` pins solc `0.8.36`, optimizer settings, and Cancun EVM.
  `contracts/dependencies.lock` and `contracts/foundry.lock` pin Foundry `1.8.1`, OpenZeppelin
  Contracts `5.7.0`, and forge-std `1.16.1`; the baseline gitlinks match
  `620536fa5277db4e3fd46772d5cbc1ea0696fb43` (forge-std) and
  `cab19933c33c2ad1d4c7a84864a3601dddfd16f3` (OpenZeppelin). Both submodules are source-pinned;
  local `LICENSE-MIT` / `LICENSE-APACHE` files were present for forge-std and `LICENSE` (MIT)
  for OpenZeppelin. Their pinned commits date to 2026-04-29 and 2026-07-29 respectively; those
  dates are not evidence of latest upstream status. They are build/test dependencies, not shipped
  contract runtime dependencies. Foundry/solc tool distribution license and current maintenance
  status are not in the repository and were not independently verified offline.
- `backend/go.mod` at the baseline is the exact name/version inventory for 76 Go modules (6
  direct, 70 indirect); `go.sum` has 345 lines of module checksums. All 76 source directories were
  cached and `go mod verify` passed. The per-module inventory below records the cached root-license
  signal, cached selected-version `.info` publication date (when present), and bounded package
  graph classification. Root-license evidence classifies 33 as Apache-2.0, 24 as MIT, 12 as
  BSD-3-Clause, 2 as BSD-2-Clause, 1 as the GPL/LGPL family (`go-ethereum` has `COPYING` and
  `COPYING.LESSER`), 1 as ISC, 2 with file-scoped mixed licensing (`klauspost/compress` and
  `go.yaml.in/yaml/v3`), and 1 unresolved (Ziren `zkvm_runtime`, no root license file found); these
  categories total 76. Cached `.info` publication metadata exists for 71/76 modules: 36 selected
  versions are under one year old, 11 are 1–2 years old, and 24 are at least two years old as of
  2026-09-12. Missing `.info` records are the Ziren pseudo-version plus Decred secp256k1 v4.0.1,
  ebitengine/purego v0.10.1, ethereum/c-kzg-4844 v2.1.8, and supranational/blst v0.3.16.
  Publication age is only a local maintenance signal, not a comparison to latest releases or a
  support-status assertion. On the local Windows package graph, 32 external modules are
  reachable by non-test backend packages; on the bounded Linux cross-target check, 31 are
  non-test reachable and 64 are present with integration/test packages (`-test -tags=integration`).
  Twelve pinned modules do not appear in that Linux graph; three of those are reachable by
  Windows runtime packages, and platform/build-tag variation means none are declared unused.
  `testcontainers` and its PostgreSQL module are integration test dependencies, not production
  runtime modules. Latest-version/advisory status is deferred because the configured Go proxy
  refused connections and `govulncheck` is absent.
- `backend/Taskfile.yml` pins Task `3.53.1`, sqlc `1.31.1`, and golangci-lint `2.13.2` through
  `go run module@version`; these are developer/CI verification tools, not application runtime
  dependencies. Their exact versions and Go module provenance are specified, but consolidated
  license/current-maintenance evidence for those tool modules was not available locally. CI reads
  Go version from `backend/go.mod` and disables setup-go caching.
- `web/package.json` defines 14 direct production and 13 direct development dependencies. The
  npm v3 lock (`web/package-lock.json`) is the per-package inventory for the full 1,304-record
  graph: each record has exact name/version, npm registry `resolved` URL, integrity hash, and
  `dev` reachability bit. All 1,304 have version/resolved/integrity; 880 are production-install
  reachable and 424 are dev-only (install-graph reachability, not proof of emitted bundle bytes).
  The lock records 23 license values; 1,295 entries have a license field and 9 do not. Counts by
  value: MIT 1,008; Apache-2.0 119; ISC 69; BSD-3-Clause 19; MPL-2.0 18; `SEE LICENSE IN
  LICENSE.md` 14; LGPL-3.0-or-later 10; unspecified 9; 0BSD 9; BSD-2-Clause 9; OFL-1.1 3;
  Apache-2.0 AND LGPL-3.0-or-later 3; `(Apache-2.0 AND MIT)` 2; Unlicense 2; BlueOak-1.0.0 2;
  and one each of `Apache-2.0 AND LGPL-3.0-or-later AND MIT`, `(MIT OR Apache-2.0)`,
  `(MIT OR CC0-1.0)`, `Python-2.0`, `(MIT AND BSD-3-Clause)`, `CC0-1.0`, `CC-BY-4.0`, and
  `LGPL-3.0-only`. The 25 lock deprecation records cover 14 package names: 24 are production-
  install reachable and one (`eslint@9.39.5`) is dev-only. Remaining records have no lockfile
  deprecation notice; that does not establish current maintenance. Registry release/support
  comparison is deferred because npm is offline and not all cached package metadata exists.
- The direct web dependency inventory below records the requested direct version, lock license,
  install reachability, and local maintenance signal. Source use was traced where relevant; the
  graph does not establish production bundle inclusion. Exact transitive package rows, pinned
  versions, provenance, license fields, deprecation notices, and dev bits remain individually
  inspectable in `web/package-lock.json`.

| Direct package | Locked version | Lock license | Reachability | Local maintenance signal |
| --- | --- | --- | --- | --- |
| `@fontsource/ibm-plex-mono` | 5.3.0 | OFL-1.1 | Production | No deprecation field |
| `@fontsource/ibm-plex-sans` | 5.3.0 | OFL-1.1 | Production | No deprecation field |
| `@fontsource/space-grotesk` | 5.3.0 | OFL-1.1 | Production | No deprecation field |
| `@phosphor-icons/react` | 2.1.7 | MIT | Production | No deprecation field |
| `@privy-io/react-auth` | 2.17.3 | Apache-2.0 | Production | No deprecation field |
| `@privy-io/wagmi` | 1.0.6 | Unspecified in lock; installed package has Apache-2.0 `LICENSE` | Production | No deprecation field |
| `@tanstack/react-query` | 5.66.8 | MIT | Production | No deprecation field |
| `lightweight-charts` | 5.0.0 | Apache-2.0 | Production | Deprecated field: “pre-release candidate version” |
| `motion` | 12.23.24 | MIT | Production | No deprecation field |
| `next` | 16.3.4 | MIT | Production | No deprecation field |
| `react` | 19.2.8 | MIT | Production | No deprecation field |
| `react-dom` | 19.2.8 | MIT | Production | No deprecation field |
| `viem` | 2.31.0 | MIT | Production | No deprecation field |
| `wagmi` | 2.16.9 | MIT | Production | No deprecation field |
| `@axe-core/playwright` | 4.13.0 | MPL-2.0 | Dev/test | No deprecation field |
| `@playwright/test` | 1.59.1 | Apache-2.0 | Dev/test | No deprecation field |
| `@types/node` | 24.10.1 | MIT | Dev/typecheck | No deprecation field |
| `@types/react` | 19.2.13 | MIT | Dev/typecheck | No deprecation field |
| `@types/react-dom` | 19.2.3 | MIT | Dev/typecheck | No deprecation field |
| `autoprefixer` | 10.4.21 | MIT | Dev/build | No deprecation field |
| `eslint` | 9.39.5 | MIT | Dev/lint | Deprecated field: version no longer supported |
| `eslint-config-next` | 16.3.4 | MIT | Dev/lint | No deprecation field |
| `openapi-typescript` | 7.13.0 | MIT | Dev/generated client | No deprecation field |
| `prettier` | 3.9.6 | MIT | Dev/format | No deprecation field |
| `tailwindcss` | 3.4.17 | MIT | Dev/build | No deprecation field |
| `typescript` | 5.9.3 | Apache-2.0 | Dev/typecheck | No deprecation field |
| `vitest` | 4.1.1 | MIT | Dev/test | No deprecation field |

### npm lifecycle scripts

The immutable baseline lock has 8 records with `hasInstallScript`: 6 are in the production-install
graph (2 marked optional), and 2 are dev/test-only (1 optional). This flag means npm has install-
time lifecycle metadata for that package; it does not establish that every platform installs or
runs it. The local installed `package.json` version matched the lock for 6 records. Their package
files were inspected locally, but were not re-fetched or verified against the lock's SRI; two
`fsevents` records are absent from local `node_modules`. The baseline lock marks both optional and
Darwin-only (`os: ["darwin"]`), so platform eligibility is known; only their package scripts and
SRI-verified tarball behavior remain unavailable.

| Baseline lock record | Reachability | Locally observed script / exact local evidence | Assessment and disposition |
| --- | --- | --- | --- |
| `node_modules/@metamask/sdk/node_modules/utf-8-validate` `5.0.10` (`web/package-lock.json:3126`) | Production install graph | `install: node-gyp-build`; local `package.json` SHA-256 `4638f6a95ec1fca2a158f8a5989bc90a898f4e267588f3c13d7ca052b9b94b94` | Calls the shared native-addon launcher (`web/node_modules/node-gyp-build/bin.js:8-27,41,66`). It selects a prebuilt addon when available and can invoke `node-gyp rebuild` on a miss. Expected native-build behavior; exact baseline bytes and CI branch remain unverified. |
| `node_modules/@reown/appkit` `1.8.23` (`web/package-lock.json:3928`) | Production install graph | `postinstall: node scripts/appkit-version-check.js`; manifest SHA-256 `f3c8b0b70e399895de48224fe401c3ca75d33cd17f43bf463f5866e9e2b99b55`; script SHA-256 `c0cee122dbe4fd506a71c0530206068f35df89c748ccdf23854b9e11ceba4d0a` | Inspected local `web/node_modules/@reown/appkit/scripts/appkit-version-check.js` reads the consumer manifest and installed Reown versions, reports mismatches, and exits successfully even on mismatch/error; no network or write was observed. No script vulnerability validated; local bytes are not SRI-bound to the baseline. |
| `node_modules/bufferutil` `4.1.0` (`web/package-lock.json:11151`) | Production install graph | `install: node-gyp-build`; local `package.json` SHA-256 `73f8333d4bf76ac969c65581b8017f56ec579a0346d6beef1d0bcc88d5174474` | Same inspected native-addon launcher behavior as the utf-8-validate records; no suspicious behavior observed in the local launcher. Exact baseline bytes and CI build branch remain unverified. |
| `node_modules/fsevents` `2.3.2` (`web/package-lock.json:13196`) | Production install graph; optional; Darwin-only (`os: ["darwin"]`) | Package not installed locally; baseline lock SRI is present, but package script contents are unavailable. | Deferred: obtain and SRI-verify the lock-pinned package bytes, then inspect the script and verify its lifecycle behavior. Darwin-only eligibility is established by the baseline lock. No script behavior or vulnerability is inferred. |
| `node_modules/keccak` `3.0.4` (`web/package-lock.json:14513`) | Production install graph | `install: node-gyp-build || exit 0`; local `package.json` SHA-256 `703d455a23fdb977e5c2336aba994bf70ac0d00dd0481e92d03beb43c7e8371d` | Attempts the native-addon path and deliberately returns success if it fails. The install-script source is the local manifest command; consumer fallback/runtime correctness and CI execution were not established, so that behavior is deferred rather than called a defect. |
| `node_modules/unrs-resolver` `1.12.2` (`web/package-lock.json:18129`) | Dev/test-only | `postinstall: node postinstall.js`; manifest SHA-256 `3ef3f74675fe31a88dc490e4136178a5fd8f96142df0c565d66be9a894543adf`; script SHA-256 `446a0aeed55eeb28eadd9ac31f0b71654265aba8ca5a99dbc22dab0b26a02469` | Local script delegates to `napi-postinstall@0.3.4`. Inspected `web/node_modules/napi-postinstall/lib/index.js:64,137-148,232`: helper first resolves a platform-specific optional binding, but can invoke nested `npm install` or direct HTTPS download/write if it is missing. No evidence shows that fallback ran. Deferred until a clean CI install proves the locked binding is present and the network fallback is not taken; no vulnerability is validated. |
| `node_modules/utf-8-validate` `6.0.6` (`web/package-lock.json:18357`) | Production install graph; optional | `install: node-gyp-build`; local `package.json` SHA-256 `75c6c1c5441fcc22114f12ddd202de797f606c1dc056f6c5181ed0abd4cda329` | Same inspected native-addon launcher behavior; optionality makes execution platform-dependent. Exact baseline bytes and CI branch remain unverified. |
| `node_modules/vite/node_modules/fsevents` `2.3.3` (`web/package-lock.json:18669`) | Dev/test-only; optional; Darwin-only (`os: ["darwin"]`) | Package not installed locally; baseline lock SRI is present, but package script contents are unavailable. | Deferred: obtain and SRI-verify the lock-pinned package bytes, then inspect the script and verify its lifecycle behavior. Darwin-only eligibility is established by the baseline lock. No script behavior or vulnerability is inferred. |

`web/package.json` defines no root `preinstall`, `install`, `postinstall`, or `prepare` lifecycle
script. The web workflow runs plain `npm ci` (`.github/workflows/web.yml:71-76`), with no
`--ignore-scripts` or script allowlist; `web/.npmrc` is absent. npm's documented
default is to run install-time lifecycle scripts. The npm v12 lifecycle order and `ignore-scripts`
default are documented by [npm's scripts reference](https://docs.npmjs.com/cli/v12/using-npm/scripts/)
and [npm ci reference](https://docs.npmjs.com/cli/v12/commands/npm-ci/). The workflow scopes
`GITHUB_TOKEN` permissions to `contents: read` and checks out with `persist-credentials: false`
(`.github/workflows/web.yml:26-27,50-53`); no production secret is configured on this web job.
These controls limit repository authority but do not sandbox dependency code, prevent outbound
network access, or suppress lifecycle scripts. The project declares npm `12.0.1`, but the workflow
does not assert the npm version, so the CI CLI version itself is not proven by repository config.
This inventory is lifecycle coverage, not a vulnerability finding: no malicious behavior was
validated, while the conditional `napi-postinstall` fetch path and unavailable `fsevents` scripts
remain explicit proof gaps.

- The 25 deprecated npm records (24 production-install, one dev-only) are individually marked
  in the lock. The groups are MetaMask SDK packages v0.32.0 (3 records, “no longer maintained”),
  uuid v8.3.2 (2) and v9.0.1 (1) (unsupported), `@motionone/vue@10.16.4`,
  `@paulmillr/qr@0.2.1` (security updates moved to `qr`),
  `@safe-global/safe-gateway-typescript-sdk@3.23.1`, `@simplewebauthn/types@9.0.1`,
  WalletConnect providers/clients (12 records across versions 2.19.2, 2.21.0, and 2.21.1,
  recommending newer releases), `@walletconnect/modal@2.7.0` (migration notice),
  `lightweight-charts@5.0.0` (pre-release candidate), and dev-only `eslint@9.39.5` (unsupported).
  “No deprecation field” for the other 1,279 lock records is not an affirmative maintenance or
  support signal.
- The 9 lock entries with no license field are `@metamask/eth-json-rpc-provider@1.0.1`,
  `@metamask/sdk@0.32.0`, `@metamask/sdk-install-modal-web@0.32.0`, nested
  `@metamask/sdk-communication-layer@0.32.0`, `@privy-io/api-base@1.5.2`,
  `@privy-io/wagmi@1.0.6`, `eyes@0.1.8`, `text-encoding-utf-8@1.0.2`, and
  `xmlhttprequest-ssl@2.1.2`. Eight corresponding locally installed package directories contain
  a license file; `@metamask/eth-json-rpc-provider@1.0.1` has neither package license metadata nor
  a license file. This is an unresolved attribution/compliance inventory item, not proof that
  source is unlicensed. Installed files were not freshly retrieved and SRI-verified.
- Fourteen npm records say `SEE LICENSE IN LICENSE.md`: 9 Reown AppKit packages at `1.8.23`
  and 5 WalletConnect universal-provider packages at `2.23.7`; all are production-install
  reachable. Current installed package license files were read, but package bytes were not
  re-fetched/reverified by fresh `npm ci`. `npm explain @reown/appkit` identifies the path through
  direct `@privy-io/react-auth@2.17.3`; `web/app/providers.tsx` uses Privy. The AppKit terms include
  attribution, a proprietary Reown gateway condition unless approved otherwise, and commercial
  thresholds stated as 2,500,000 monthly RPCs or 500 MAU. The installed `@metamask/sdk@0.32.0`
  license states non-commercial use with a threshold below 10,000 MAU; `npm explain` traces it
  through `wagmi`/`@wagmi/connectors`, while `web/src/wallet/config.ts` selects an injected
  connector only for Anvil. These are locally observed terms and graph paths, not a conclusion
  that a term applies to the deployed bundle or that a breach occurred. See deferred candidate
  `P5-T7-001` below.
- The 76 baseline Go modules have exact module path/version provenance in `backend/go.mod` and
  checksum records in `backend/go.sum`. The local package graph is bounded: `runtime (Linux)` means
  present in non-test Linux backend packages; `test/integration only` means absent from that graph
  but present with `go list -deps -test -tags=integration`; `Linux-unreached; Windows runtime`
  means absent from the Linux graph but present in non-test Windows packages; `unreached` means
  absent from both bounded graphs. These labels do not claim that a pinned module is unused on all
  platforms or under all build tags. License identifiers below are local root-file signals, not a
  compatibility opinion. The two mixed-license rows record the scope visible in the cached files:
  `klauspost/compress` has BSD-3-Clause terms plus component-scoped Apache-2.0/MIT sections, and
  `go.yaml.in/yaml/v3` splits MIT and Apache-2.0 terms by file group.

| Go module | Version | Pin type | Cached root-license signal | Cached publication signal | Bounded graph classification |
| --- | --- | --- | --- | --- | --- |
| `github.com/ethereum/go-ethereum` | `v1.17.5` | direct | GPL-3.0 + LGPL-3.0 (`COPYING`, `COPYING.LESSER`) | 2026-07-27 (<1y) | runtime (Linux) |
| `github.com/jackc/pgx/v5` | `v5.10.0` | direct | MIT (`LICENSE`) | 2026-06-02 (<1y) | runtime (Linux) |
| `github.com/pressly/goose/v3` | `v3.28.0` | direct | MIT (`LICENSE`) | 2026-09-02 (<1y) | runtime (Linux) |
| `github.com/santhosh-tekuri/jsonschema/v6` | `v6.0.3` | direct | Apache-2.0 (`LICENSE`) | 2026-06-28 (<1y) | runtime (Linux) |
| `github.com/testcontainers/testcontainers-go` | `v0.44.0` | direct | MIT (`LICENSE`) | 2026-08-07 (<1y) | test/integration only |
| `github.com/testcontainers/testcontainers-go/modules/postgres` | `v0.44.0` | direct | MIT (`LICENSE`) | 2026-08-07 (<1y) | test/integration only |
| `dario.cat/mergo` | `v1.0.2` | indirect | BSD-3-Clause (`LICENSE`) | 2025-05-07 (1–2y) | test/integration only |
| `github.com/Azure/go-ansiterm` | `v0.0.0-20250102033503-faa5f7b0171c` | indirect | MIT (`LICENSE`) | 2025-01-02 (1–2y) | unreached |
| `github.com/Microsoft/go-winio` | `v0.6.2` | indirect | MIT (`LICENSE`) | 2024-04-09 (≥2y) | Linux-unreached; Windows runtime |
| `github.com/ProjectZKM/Ziren/crates/go-runtime/zkvm_runtime` | `v0.0.0-20251001021608-1fe7b43fc4d6` | indirect | unresolved (no root license file) | unavailable (`.info` not cached) | unreached |
| `github.com/StackExchange/wmi` | `v1.2.1` | indirect | MIT (`LICENSE`) | 2021-07-23 (≥2y) | Linux-unreached; Windows runtime |
| `github.com/bits-and-blooms/bitset` | `v1.20.0` | indirect | BSD-3-Clause (`LICENSE`) | 2024-12-16 (1–2y) | runtime (Linux) |
| `github.com/cenkalti/backoff/v4` | `v4.3.0` | indirect | MIT (`LICENSE`) | 2024-01-02 (≥2y) | test/integration only |
| `github.com/cespare/xxhash/v2` | `v2.3.0` | indirect | MIT (`LICENSE.txt`) | 2024-04-04 (≥2y) | runtime (Linux) |
| `github.com/consensys/gnark-crypto` | `v0.18.1` | indirect | Apache-2.0 (`LICENSE`) | 2025-10-28 (<1y) | runtime (Linux) |
| `github.com/containerd/errdefs` | `v1.0.0` | indirect | Apache-2.0 (`LICENSE`) | 2024-10-08 (1–2y) | test/integration only |
| `github.com/containerd/errdefs/pkg` | `v0.3.0` | indirect | Apache-2.0 (`LICENSE`) | 2024-10-08 (1–2y) | test/integration only |
| `github.com/containerd/log` | `v0.1.0` | indirect | Apache-2.0 (`LICENSE`) | 2023-09-08 (≥2y) | test/integration only |
| `github.com/containerd/platforms` | `v0.2.1` | indirect | Apache-2.0 (`LICENSE`) | 2024-06-10 (≥2y) | test/integration only |
| `github.com/cpuguy83/dockercfg` | `v0.3.2` | indirect | MIT (`LICENSE`) | 2024-09-25 (1–2y) | test/integration only |
| `github.com/crate-crypto/go-eth-kzg` | `v1.5.0` | indirect | Apache-2.0 (`LICENSE`) | 2026-01-22 (<1y) | runtime (Linux) |
| `github.com/danielgtaylor/huma/v2` | `v2.39.1` | indirect | MIT (`LICENSE.md`) | 2026-07-29 (<1y) | runtime (Linux) |
| `github.com/deckarep/golang-set/v2` | `v2.6.0` | indirect | MIT (`LICENSE`) | 2023-12-26 (≥2y) | runtime (Linux) |
| `github.com/decred/dcrd/dcrec/secp256k1/v4` | `v4.0.1` | indirect | ISC (`LICENSE`) | unavailable (`.info` not cached) | unreached |
| `github.com/distribution/reference` | `v0.6.0` | indirect | Apache-2.0 (`LICENSE`) | 2024-03-20 (≥2y) | test/integration only |
| `github.com/docker/go-connections` | `v0.8.1` | indirect | Apache-2.0 (`LICENSE`) | 2026-07-27 (<1y) | test/integration only |
| `github.com/docker/go-units` | `v0.5.0` | indirect | Apache-2.0 (`LICENSE`) | 2022-05-17 (≥2y) | test/integration only |
| `github.com/ebitengine/purego` | `v0.10.1` | indirect | Apache-2.0 (`LICENSE`) | unavailable (`.info` not cached) | unreached |
| `github.com/ethereum/c-kzg-4844/v2` | `v2.1.8` | indirect | Apache-2.0 (`LICENSE`) | unavailable (`.info` not cached) | unreached |
| `github.com/felixge/httpsnoop` | `v1.1.0` | indirect | MIT (`LICENSE.txt`) | 2026-06-11 (<1y) | test/integration only |
| `github.com/fjl/jsonw` | `v0.1.0` | indirect | MIT (`LICENSE`) | 2026-05-20 (<1y) | runtime (Linux) |
| `github.com/go-logr/logr` | `v1.4.4` | indirect | Apache-2.0 (`LICENSE`) | 2026-07-20 (<1y) | runtime (Linux) |
| `github.com/go-logr/stdr` | `v1.2.2` | indirect | Apache-2.0 (`LICENSE`) | 2021-12-14 (≥2y) | runtime (Linux) |
| `github.com/go-ole/go-ole` | `v1.3.0` | indirect | MIT (`LICENSE`) | 2023-08-04 (≥2y) | Linux-unreached; Windows runtime |
| `github.com/google/uuid` | `v1.6.0` | indirect | BSD-3-Clause (`LICENSE`) | 2024-01-23 (≥2y) | test/integration only |
| `github.com/gorilla/websocket` | `v1.4.2` | indirect | BSD-2-Clause (`LICENSE`) | 2020-03-19 (≥2y) | runtime (Linux) |
| `github.com/holiman/uint256` | `v1.3.2` | indirect | BSD-3-Clause (`COPYING`) | 2024-12-06 (1–2y) | runtime (Linux) |
| `github.com/jackc/pgpassfile` | `v1.0.0` | indirect | MIT (`LICENSE`) | 2019-03-30 (≥2y) | runtime (Linux) |
| `github.com/jackc/pgservicefile` | `v0.0.0-20240606120523-5a60cdf6a761` | indirect | MIT (`LICENSE`) | 2024-06-06 (≥2y) | runtime (Linux) |
| `github.com/jackc/puddle/v2` | `v2.2.2` | indirect | MIT (`LICENSE`) | 2024-09-10 (≥2y) | runtime (Linux) |
| `github.com/klauspost/compress` | `v1.19.2` | indirect | mixed: BSD-3-Clause base with component-scoped Apache-2.0/MIT sections (`LICENSE`) | 2026-08-05 (<1y) | test/integration only |
| `github.com/lufia/plan9stats` | `v0.0.0-20260330125221-c963978e514e` | indirect | BSD-3-Clause (`LICENSE`) | 2026-03-30 (<1y) | unreached |
| `github.com/magiconair/properties` | `v1.8.10` | indirect | BSD-2-Clause (`LICENSE.md`) | 2025-04-09 (1–2y) | test/integration only |
| `github.com/mfridman/interpolate` | `v0.0.2` | indirect | MIT (`LICENSE.txt`) | 2023-12-22 (≥2y) | runtime (Linux) |
| `github.com/moby/docker-image-spec` | `v1.3.1` | indirect | Apache-2.0 (`LICENSE`) | 2024-02-09 (≥2y) | test/integration only |
| `github.com/moby/go-archive` | `v0.2.0` | indirect | Apache-2.0 (`LICENSE`) | 2025-12-19 (<1y) | test/integration only |
| `github.com/moby/moby/api` | `v1.55.0` | indirect | Apache-2.0 (`LICENSE`) | 2026-06-18 (<1y) | test/integration only |
| `github.com/moby/moby/client` | `v0.5.1` | indirect | Apache-2.0 (`LICENSE`) | 2026-07-27 (<1y) | test/integration only |
| `github.com/moby/patternmatcher` | `v0.6.1` | indirect | Apache-2.0 (`LICENSE`, `NOTICE`) | 2026-03-24 (<1y) | test/integration only |
| `github.com/moby/sys/sequential` | `v0.7.0` | indirect | Apache-2.0 (`LICENSE`) | 2026-06-05 (<1y) | test/integration only |
| `github.com/moby/sys/user` | `v0.4.0` | indirect | Apache-2.0 (`LICENSE`) | 2025-02-27 (1–2y) | test/integration only |
| `github.com/moby/sys/userns` | `v0.1.0` | indirect | Apache-2.0 (`LICENSE`) | 2024-08-07 (≥2y) | test/integration only |
| `github.com/moby/term` | `v0.5.2` | indirect | Apache-2.0 (`LICENSE`) | 2025-01-02 (1–2y) | test/integration only |
| `github.com/opencontainers/go-digest` | `v1.0.0` | indirect | Apache-2.0 (`LICENSE`, `LICENSE.docs`) | 2020-05-13 (≥2y) | test/integration only |
| `github.com/opencontainers/image-spec` | `v1.1.1` | indirect | Apache-2.0 (`LICENSE`) | 2025-02-24 (1–2y) | test/integration only |
| `github.com/power-devops/perfstat` | `v0.0.0-20240221224432-82ca36839d55` | indirect | MIT (`LICENSE`) | 2024-02-21 (≥2y) | unreached |
| `github.com/sethvargo/go-retry` | `v0.4.0` | indirect | Apache-2.0 (`LICENSE`) | 2026-07-17 (<1y) | runtime (Linux) |
| `github.com/shirou/gopsutil` | `v3.21.4-0.20210419000835-c7a38de76ee5+incompatible` | indirect | BSD-3-Clause (`LICENSE`) | 2021-04-18 (≥2y) | runtime (Linux) |
| `github.com/shirou/gopsutil/v4` | `v4.26.6` | indirect | BSD-3-Clause (`LICENSE`) | 2026-06-20 (<1y) | test/integration only |
| `github.com/sirupsen/logrus` | `v1.9.4` | indirect | MIT (`LICENSE`) | 2025-10-23 (<1y) | test/integration only |
| `github.com/stretchr/testify` | `v1.12.1` | indirect | MIT (`LICENSE`) | 2026-08-17 (<1y) | test/integration only |
| `github.com/supranational/blst` | `v0.3.16` | indirect | Apache-2.0 (`LICENSE`) | unavailable (`.info` not cached) | unreached |
| `github.com/tklauser/go-sysconf` | `v0.4.0` | indirect | BSD-3-Clause (`LICENSE`) | 2026-05-12 (<1y) | runtime (Linux) |
| `github.com/tklauser/numcpus` | `v0.12.0` | indirect | Apache-2.0 (`LICENSE`) | 2026-05-11 (<1y) | runtime (Linux) |
| `github.com/yusufpapurcu/wmi` | `v1.2.4` | indirect | MIT (`LICENSE`) | 2024-01-28 (≥2y) | unreached |
| `go.opentelemetry.io/auto/sdk` | `v1.2.1` | indirect | Apache-2.0 (`LICENSE`) | 2025-09-15 (<1y) | runtime (Linux) |
| `go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp` | `v0.71.0` | indirect | Apache-2.0 (`LICENSE`) | 2026-08-26 (<1y) | test/integration only |
| `go.opentelemetry.io/otel` | `v1.46.0` | indirect | Apache-2.0 (`LICENSE`) | 2026-08-25 (<1y) | runtime (Linux) |
| `go.opentelemetry.io/otel/metric` | `v1.46.0` | indirect | Apache-2.0 (`LICENSE`) | 2026-08-25 (<1y) | runtime (Linux) |
| `go.opentelemetry.io/otel/trace` | `v1.46.0` | indirect | Apache-2.0 (`LICENSE`) | 2026-08-25 (<1y) | runtime (Linux) |
| `go.uber.org/multierr` | `v1.11.0` | indirect | MIT (`LICENSE.txt`) | 2023-03-29 (≥2y) | runtime (Linux) |
| `go.yaml.in/yaml/v3` | `v3.0.5` | indirect | MIT/Apache-2.0 by file group (`LICENSE`, `NOTICE`) | 2026-07-26 (<1y) | test/integration only |
| `golang.org/x/crypto` | `v0.55.0` | indirect | BSD-3-Clause (`LICENSE`) | 2026-08-11 (<1y) | test/integration only |
| `golang.org/x/sync` | `v0.22.0` | indirect | BSD-3-Clause (`LICENSE`) | 2026-07-01 (<1y) | runtime (Linux) |
| `golang.org/x/sys` | `v0.47.0` | indirect | BSD-3-Clause (`LICENSE`) | 2026-06-30 (<1y) | runtime (Linux) |
| `golang.org/x/text` | `v0.41.0` | indirect | BSD-3-Clause (`LICENSE`) | 2026-08-11 (<1y) | runtime (Linux) |
- The two contract submodules and toolchain have these local provenance/reachability signals:

| Dependency/tool | Version or immutable source | Local license / maintenance evidence | Reachability |
| --- | --- | --- | --- |
| forge-std | 1.16.1; gitlink `620536fa5277db4e3fd46772d5cbc1ea0696fb43`; `.gitmodules` GitHub URL | MIT and Apache-2.0 files; pinned commit dated 2026-04-29, latest status unknown | Contract build/test, CI |
| OpenZeppelin Contracts | 5.7.0; gitlink `cab19933c33c2ad1d4c7a84864a3601dddfd16f3`; `.gitmodules` GitHub URL | MIT file; pinned commit dated 2026-07-29, latest status unknown | Contract compile/release validation |
| Foundry | 1.8.1; `contracts/dependencies.lock` and full-SHA-pinned action | Tool distribution license and current maintenance not locally verified | Contract build/test/deployment validation |
| solc | 0.8.36; `contracts/foundry.toml` | Compiler license/current maintenance not locally verified | Contract compilation |
| Python / Slither | Python 3.12, `slither-analyzer` 0.11.6 via pipx | Slither AGPL-3.0 locally; CI transitive versions/licensing unresolved | Contract source analysis only |
| Task | 3.53.1 via `go run ...@version` | Go module source pinned by version; tool license/current maintenance not consolidated locally | Backend build/test/lint orchestration |
| sqlc | 1.31.1 via `go run ...@version` | Go module source pinned by version; tool license/current maintenance not consolidated locally | SQL generated-code drift checks |
| golangci-lint | 2.13.2 via `go run ...@version` | Go module source pinned by version; tool license/current maintenance not consolidated locally | Backend lint gate |

- Contracts CI sets Python `3.12` and installs `slither-analyzer==0.11.6` via pipx; local
  `pip show` identifies Slither as AGPL-3.0. Its declared direct requirements are
  `crytic-compile`, `eth-abi`, `eth-typing`, `eth-utils`, `packaging`, `prettytable`,
  `pycryptodome`, and `web3`. CI does not lock those transitive versions. Versions/licenses and
  maintenance of that resolved CI graph are incomplete; the local tool environment cannot prove
  CI resolution. These packages are scanner-only, not shipped application runtime dependencies.
- All action references in the four workflows are full-SHA pinned: checkout
  `d23441a48e516b6c34aea4fa41551a30e30af803`, setup-go
  `924ae3a1cded613372ab5595356fb5720e22ba16`, setup-node
  `395ad3262231945c25e8478fd5baf05154b1d79f`, setup-python
  `0b93645e9fea7318ecaed2b359559ac225c90a2b`, and Foundry action
  `908c540300062bd5a7e473851cdb4282204cee09`. Versions/provenance are pinned by the workflow
  references; action source licenses and upstream maintenance/compromise history are not present
  in the checkout and remain unverified pending upstream metadata/provenance review. Actions are
  reachable in CI/release execution only.
- The workflows use `ubuntu-latest`, system Chrome, and `postgres:18.6-alpine`. The image has a
  version tag but no digest; runner image and Chrome build are host-managed/dynamic. Their
  licenses, exact patch versions, and maintenance state are not captured locally. These are CI
  test-environment dependencies, not proof of production runtime contents, and limit
  byte-for-byte environment reproducibility. CI does not explicitly assert npm `12.0.1`, although
  `web/package.json` declares it; Node is pinned to `24.16.0`.
- No package/artifact publishing or deployment tool was reachable in these workflows. No concrete
  altered release behavior was established: workflows verify but do not publish/deploy artifacts.

### Dependency/advisory checks

`go mod verify` passed (`all modules verified`). `go list -mod=readonly -m all` could not complete:
the host has offline module networking configured to a localhost proxy that refuses connections,
and module `.info` entries were absent. `govulncheck` is not installed, so no current Go advisory
result is claimed.

`npm audit --json` and `npm audit --omit=dev --json` both returned zero findings from the local
npm cache. `npm config get offline` is `true`, so that output is not a live registry audit and
does not establish current advisory status. `npm outdated --json` and
`npm view react@19.1.1 time --offline` failed with `ENOTCACHED`; no network refresh was attempted.
The dependency graph distinguishes 880 production-install records from 424 dev-only records, and
the cached `--omit=dev` audit also reported zero. However, no stored baseline `npm ci` output or
CI log containing the previously known advisory count was found in the owned paths. Therefore the
requested count-to-production-graph reconciliation is **incomplete**: current cache evidence is
zero findings for each audit mode but cannot establish what `npm ci` previously reported or
whether the registry advisory set has changed. Required proof is the exact baseline CI/install
log (including npm version and advisory total) plus an online audit against the pinned lock, with
the production-only result and package paths captured. The lock's integrity/resolution coverage
was checked separately. No raw cached audit total is treated as a current vulnerability finding.

## CI, path filters, privileges, and secrets

All four workflow files declare `permissions: contents: read`; checkouts set
`persist-credentials: false`. Contract/web/release workflows use bounded job timeouts. The
backend gate runs `task verify`; contracts run the contract gate; web runs generated checks,
format/lint/type/unit/browser/Anvil and bundle-secret/budget gates; the release workflow runs
the cross-stack gate. `backend.yml` watches backend plus deployment/ABI/vector/fixture copies;
`contracts.yml` watches all `contracts/**` and `.gitmodules`; `web.yml` watches web, OpenAPI/API,
contract source/ABI/deployment inputs; `release.yml` watches contracts, backend, web, and its
orchestration/workflow. These repository filters cover the owned source/config paths reviewed.

The Robinhood archive-RPC secret appears only in two contracts jobs guarded by
`github.event_name == 'workflow_dispatch'` (`contracts.yml:46-52,71-77`); those jobs are not
scheduled for pull-request events. The release PR expression selects `anvil`, uses synthetic
local PostgreSQL credentials, and passes public `vars.NEXT_PUBLIC_*` values; it does not deploy
or inject a production secret (`release.yml:40-52`). No workflow upload, artifact attestation,
container publishing, or deployment step was found. GitHub-hosted branch protection, required
checks/reviewers, environment approvals, secret/variable scopes, and retention policy are external
settings and were not accessible; repository prose claiming a required `backend` check does not
prove current GitHub settings.

**Rejected hypothesis — pull requests can receive the archive RPC secret.** The secret is scoped
to `workflow_dispatch`-only jobs, whereas PRs run the ordinary contracts/release gates. The
source/config evidence does not support PR exposure. Whether dispatch is restricted to trusted
operators is an external GitHub policy, not established here.

## Generated artifacts and scanner evidence

The repository declares single sources and byte-drift checks for contract deployment manifests,
OpenAPI, event ABIs, curve vectors, sqlc output, and web API/contract generated types. The
following bounded checks passed on this host:

| Command/check | Result |
| --- | --- |
| `go run ./cmd/check-deployments` | Passed. |
| `go run ./cmd/check-openapi` | Passed; checks generated bytes, not semantic API requirements. |
| `go run ./cmd/sync-curve-vectors --check` | Passed. |
| `go run ./cmd/sync-event-abis --check` | Passed. |
| `web: npm run web-api-diff` | Passed. |
| `web: npm run web-contracts-diff` | Passed using existing `contracts/out`; not a fresh Foundry build. |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File contracts/scripts/check-deployments.ps1` | Passed. |
| `backend: go test ./deployments` | Passed. |

Go drift checks used ignored workspace-local `GOCACHE=backend/.cache/go-build` after the
default cache was denied by Windows permissions; only cache files were produced. The pinned
`sqlc diff` command could not start because the required Go module metadata was unavailable
through the offline proxy. Fresh Forge tests, build, Slither, ABI/layout/size/fixture regeneration
were not run: `forge`/`anvil` are absent. Docker is installed but its daemon is unavailable, so
PostgreSQL-backed and full Anvil integration gates could not be executed.

`contracts/scripts/check-slither.ps1:22-35` verifies the exact scanner version and runs a fresh
source scan with `--fail-medium`. The checked-in `contracts/slither.db.json` is not referenced by
that gate; Task 2 independently reviewed and re-justified its five stored High/Medium entries.
Its baseline blob is `9904fdb0058a21a8281f93fe56d88d8fd3169814`. No freshness claim is made for
the stored database because Foundry regeneration was unavailable.

**Rejected hypothesis — stale Slither JSON can suppress the release scan.** The release gate
invokes the version-checked fresh source scan; it does not read the stored triage JSON. Task 2's
existing source dispositions remain the authority for those entries. This rejects a gate-bypass
claim, but does not substitute for running Slither against a fresh Foundry build.

Task 4 finding `P5-T4-003` is retained: OpenAPI generation/checking is byte-reproducible but
does not enforce handler/header/media/304-response semantics. This is already a validated API
contract finding; Task 7 adds no duplicate finding.

## Deployment manifests and runtime verification boundary

`backend/cmd/api/main.go:102-106` and `backend/cmd/indexer/main.go:153-158` use
`DEPLOYMENT_MANIFEST_PATH` when nonempty; `backend/deployments/registry.go:54-83` loads and
validates the supplied manifest against embedded schemas and registry constraints. It validates
schema, environment, address/hash formats, and exact chain/deployment lookup, but the loader
does not authenticate a manifest digest/signature or enforce a production-only immutable path.
The local Anvil helper deliberately creates and supplies an ephemeral overlay. No production
workflow in this baseline supplies that variable, but the production runtime environment,
filesystem permissions, and configuration manager are unavailable, so the source cannot prove
that the overlay is confined to local/test processes.

**Deferred inherited candidate `P5-T4-006` (Task 4 → Task 7).** Keep deferred, not validated or
rejected: the code path is confirmed, but exploitability depends on unavailable production
environment ownership, file permissions, manifest digest control, and startup policy. Resume
when the production deployment manifest and release configuration from backlog item “Production
release, governance, and audit inputs” are provided; then test an unapproved overlay and verify
the deployed configuration/file immutability and digest binding. Do not remove the intentional
local E2E overlay based only on repository inspection.

Runtime deployed-bytecode and pair-identity checks are available as helpers but are not called
from indexer startup; Task 3 already validates this as `P5-T3-005`. Task 7 does not duplicate it.
The disabled Robinhood testnet deployment manifest remains unselectable until reviewed. The
deployment scripts validate chain/dependency conditions, protect mainnet broadcast, collect
receipt/runtime hashes, and emit unreviewed candidates under ignored `.generated` for human
review; no broadcast was performed.

## Release, rollback, and operational readiness

`release.yml` maps PRs to the deterministic Anvil target; `workflow_dispatch` defaults to
`production` but only runs `scripts/verify-release.mjs`. The script rejects missing/unknown
targets, uses a ten-minute default subprocess timeout with child-tree termination, runs contract,
backend, web, browser, bundle, and mandatory Anvil transaction gates, and selects the production
web config validator when requested. These are validation gates, not a deployment pipeline:
there is no artifact promotion, hosting release, or automated production rollback in the repo.

The production runbook explicitly blocks approval while inputs remain `<pending>` and asks for
the exact commit/artifact digests, manifest/receipt/runtime hashes, governance proof, reproducible
gate evidence, and external signed audit (`docs/runbooks/production-readiness.md:23-46,107-119`).
It documents health, monitoring, pause/rollback, and forward-only database recovery steps
(`:84-105`). The web release runbook likewise distinguishes local Anvil evidence from live
production acceptance and leaves named owners pending (`docs/runbooks/web-release.md:84-111`).
These are useful procedures, not evidence that a production operator, host, backup, monitoring,
or rollback has been provisioned or rehearsed.

**Deferred inherited candidate `P5-T3-003` (Task 3 → operations).** The runbooks cover general
health and application rollback, but no source of truth/operator rehearsal is available for
recovery beyond the indexer's 128-block ancestor search. Task 3 deferred this boundary to Task 7;
it remains deferred pending an owner-approved deep-reorg recovery procedure, trusted RPC/source
data, and a staged rehearsal. Track it within the existing “Production release, governance, and
audit inputs” backlog item rather than creating a duplicate finding. No production backup/restore,
provider outage, governance handoff, rollback, or monitoring test was run.

## P5-T7-001 — Wallet SDK license scope and production compliance

- State: deferred; compliance candidate, not a validated finding.
- Severity: Medium if the conditional production-use scenario is confirmed; no breach is asserted.
- Confidence: low; production artifact, usage, deployment configuration, and legal approval are
  unavailable.
- Primary audit task: Task 7.
- Affected asset/surface: web package/build dependency graph and wallet-provider configuration;
  Task 7 web-root manifests/configs ownership row (`docs/audits/plan-5/01-surface-ownership.md:39`).
- Baseline: `6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`.
- Attacker/failure actor and prerequisites: no attacker is required. The risk requires that the
  affected SDK bytes are distributed or used in production, that their observed license conditions
  apply to that use and its RPC/MAU/gateway configuration, and that required attribution, commercial
  terms, or other approval are absent.
- Source-to-sink or failure path: the baseline npm lock resolves 9 Reown AppKit and 5 WalletConnect
  universal-provider records into the production install graph with exact versions, registry URLs,
  integrity hashes, and `SEE LICENSE IN LICENSE.md` signals (`web/package-lock.json:3928-3936`,
  `:10005-10012`; the inventory above enumerates these records). The recorded `npm explain
  @reown/appkit` path passes through direct `@privy-io/react-auth`; the application imports and uses
  `PrivyProvider` (`web/app/providers.tsx:3,23-36`). If those package bytes and applicable Reown terms
  reach production without required conditions, distribution or operation could be out of license
  scope. The lock also contains `@metamask/sdk@0.32.0` (`web/package-lock.json:3047-3052`), whose
  locally inspected license states non-commercial restrictions; `npm explain @metamask/sdk` places
  it under `wagmi`, while the inspected connector branch selects `injected()` only for the Anvil
  deployment (`web/src/wallet/config.ts:33-37`).
- Exact evidence: `web/package-lock.json:3928-3936`, `:10005-10012`, and `:3047-3052` pin the
  package records and integrity; `web/app/providers.tsx:3,23-36` shows the Privy provider path;
  `web/src/wallet/config.ts:33-37` bounds the inspected MetaMask connector selection to Anvil.
  Cached installed `@reown/appkit` and `@metamask/sdk` license files were previously read, but those
  package contents were not refreshed or verified against the lock integrity in this audit.
- Impact: conditional supply-chain/license-compliance exposure, including potential attribution,
  gateway, usage-threshold, or commercial-permission obligations. No financial loss, release breach,
  or violation has been established.
- Controls observed: baseline lock records pin package versions, registry URLs, and integrity hashes;
  the inspected MetaMask injected connector is selected only for the Anvil deployment.
- Counterevidence and assumptions: npm production-install reachability is not proof of emitted
  bundle bytes or exercised production features. No production bundle, deployment configuration,
  actual RPC/MAU measurement, gateway selection, or written legal approval was available. The
  inspected MetaMask connector is Anvil-only; no MetaMask production use is claimed.
- Proof gaps: installed package contents were not refreshed and integrity-verified; emitted
  production bytes, deployed provider configuration, actual RPC/MAU and gateway settings, and legal
  applicability/approval remain unknown.
- Reproduction/proof method: from a clean checkout of the baseline, perform a lock-verified
  `npm ci`, capture `npm explain @reown/appkit` and `npm explain @metamask/sdk`, inspect the actual
  production bundle/deployment dependency path and provider configuration, then compare observed
  use and RPC/MAU/gateway settings with the verified package license text and written owner/legal
  approval.
- Proposed remediation: no change is justified until the production path and applicable terms are
  established. If a term applies, obtain written permission or meet its conditions; otherwise remove
  or replace the affected package through the normal dependency review.
- Required regression test: while deferred, not applicable. If a package is removed or replaced,
  add a production-artifact check for the intended dependency state and retain wallet-flow coverage
  for supported production and Anvil configurations.
- Disposition/remediation owner: deferred to the product owner/legal approver and web release owner. Prerequisite:
  lock-verified package contents, production bundle/deployment evidence, actual usage and gateway
  configuration, and written legal determination. Resume with the reproduction/proof method above;
  no breach is asserted before that evidence exists.
- Related findings and cross-task references: none; this remains distinct from runtime manifest
  trust candidate `P5-T4-006` and the operational recovery candidate `P5-T3-003`.

## Candidate register and cross-task deduplication

| Candidate / hypothesis | Disposition |
| --- | --- |
| PR access to the Robinhood archive-RPC secret | Rejected; secret-bearing jobs require `workflow_dispatch`. |
| Stale checked-in Slither JSON suppresses the release scan | Rejected; release runs the fresh version-checked source scan, independent of that file. |
| `DEPLOYMENT_MANIFEST_PATH` could be a production trust root | Deferred as existing `P5-T4-006`; production configuration is unavailable. |
| Deep-reorg recovery beyond 128 blocks lacks an operationally proven procedure | Deferred as existing `P5-T3-003`; external operational inputs/rehearsal are unavailable. |
| Wallet SDK license scope/compliance (`P5-T7-001`) | Deferred; production bundle inclusion, usage thresholds, and legal approval are unavailable; no violation is asserted. |

Existing `P5-T3-001` (configured chain not bound to RPC `eth_chainId`), `P5-T3-005`
(missing runtime deployed-code/pair validation), `P5-T4-003` (OpenAPI semantic drift), and
`P5-T2-002` (external dependency/code evidence) remain owned by their prior reports. No finding
was silently closed or duplicated.

## Limitations and backlog

- This is baseline source/config evidence, not a live GitHub organization or production audit.
  No current hosted CI run, branch protection, secret/environment policy, cloud configuration,
  monitoring, backup, production traffic, live RPC, or external audit evidence was available.
- `forge`, `anvil`, and `govulncheck` were unavailable. Docker daemon was unreachable. Go proxy
  and npm were in offline/cache-only mode, preventing live advisory/latest-release refresh and
  sqlc module metadata fetch. Exact baseline `npm ci` advisory count/log is absent, so reconciliation
  to that count remains incomplete. To close, obtain the baseline workflow install log and run
  pinned-lock online `npm ci` plus production-only and full `npm audit`; for Go, restore the module
  proxy and run a current vulnerability database check. Cached npm audit output must not be
  presented as current.
- Python CI transitive versions/licenses, full-SHA-pinned action source license/current maintenance,
  Foundry/solc distribution license/current maintenance, and upstream provenance were not
  independently available offline. Close with the exact pipx-resolved transitive lock/inventory
  and upstream source/license review for each pinned action/tool. Runner/Chrome exact images and
  PostgreSQL image digest remain absent; close with immutable runner/browser evidence and pin the
  container by digest if byte-reproducible CI is required.
- Individual `package-lock.json` entries have version, resolved URL, integrity, lock-license field
  (where supplied), deprecation notice (where supplied), and `dev` bit; however, missing metadata,
  absence of a deprecation field, registry freshness, and effective emitted-bundle reachability
  must not be misrepresented as verified license, active maintenance, or production inclusion.
  Go pin/source/checksum inventory is complete locally, but latest-version and advisory status is
  incomplete; 5 Go timestamps and 1 module license remain unresolved as enumerated above.
- No product path, workflow, dependency, generated artifact, README, plan, or backlog file was
  changed. No commit or push was made.
- Backlog status remains **exactly 2 Active** items: “Robinhood testnet deployment manifest”
  and “Production release, governance, and audit inputs.” No new item was added.
