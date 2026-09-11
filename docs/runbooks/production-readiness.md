# Production readiness and handoff

This is the operator handoff for production release. It separates repository evidence from
inputs that only the product owner, infrastructure owner, Privy organization, governance
signers, or an external auditor can provide. No placeholder value in this document is a
production approval.

## Repository evidence already available

Before requesting production approval, record the exact commit and successful run IDs for:

```powershell
node scripts/verify-release.mjs --target=production
cd contracts
pwsh ./scripts/check.ps1 release
cd ..\backend
go run github.com/go-task/task/v3/cmd/task@v3.53.1 verify
```

The release gate must run against a reviewed manifest. It must not use an Anvil manifest,
fixture credentials, a guessed origin, or a public value copied from another chain.

## Human-owned input sheet

Fill this sheet in the release ticket, not in source control. Every value must have an owner
and evidence link before the release gate is run.

| Input | Required evidence | Owner / status |
| --- | --- | --- |
| Reviewed production deployment manifest | committed manifest digest and receipt/explorer evidence | `<owner>` / `<pending>` |
| `NEXT_PUBLIC_PRIVY_APP_ID` | Privy dashboard app ID for the reviewed organization | `<owner>` / `<pending>` |
| Privy production web origin | dashboard allowlist screenshot/export and tested origin | `<owner>` / `<pending>` |
| `PRIVY_APP_ID` | backend app identifier matching the dashboard | `<owner>` / `<pending>` |
| `PRIVY_VERIFICATION_KEY` | key retrieved through the approved secret manager | `<owner>` / `<pending>` |
| `NEXT_PUBLIC_API_BASE_URL` | deployed HTTPS API origin and certificate ownership | `<owner>` / `<pending>` |
| `NEXT_PUBLIC_RPC_URL` | approved HTTPS RPC endpoint, rate and outage contact | `<owner>` / `<pending>` |
| `API_ALLOWED_ORIGINS` | exact production web origin(s), no wildcard | `<owner>` / `<pending>` |
| Database URL | secret-manager reference and backup/restore owner | `<owner>` / `<pending>` |
| Hosting/domain/CSP owner | DNS, TLS, edge rate-limit, and deployment rollback ownership | `<owner>` / `<pending>` |
| Monitoring owner | alert destination, on-call rota, and severity policy | `<owner>` / `<pending>` |
| ETH/USD adapter configuration | selected provider account, key, attribution, and freshness owner | `<owner>` / `<pending>` |
| Pause authority | multisig address, signer set, threshold, and tested pause handoff | `<owner>` / `<pending>` |
| Timelock | address, delay, proposer/executor roles, and acceptance test | `<owner>` / `<pending>` |
| Protocol treasury | address, custody owner, and transfer verification | `<owner>` / `<pending>` |
| External audit | signed report, scope, commit/artifact digest, and accepted findings | `<owner>` / `<pending>` |
| Legal/geo policy | approved jurisdiction policy and enforcement owner | `<owner>` / `<pending>` |

Never put private keys, seed phrases, bearer tokens, database passwords, credentialed RPC URLs,
or Privy verification keys in this repository or in browser-visible `NEXT_PUBLIC_*` variables.

## Privy dashboard checklist

The Privy organization owner must complete and record:

1. Create/select the production app and record its public app ID.
2. Add the exact HTTPS web origin; do not add localhost or wildcard origins.
3. Enable only the wallet login methods approved by the product/security review.
4. Verify embedded and external wallet linking against the backend's linked-wallet proof flow.
5. Store the backend verification key in the production secret manager and test key rotation.
6. Confirm logout, wrong-chain, disconnected, and unauthorized metadata actions in a live
   staging-like environment.

The browser receives only `NEXT_PUBLIC_PRIVY_APP_ID`; the verification key never reaches the
browser, logs, URL, analytics, or persistent client storage.

## Governance handoff

The signer owner must provide the final pause multisig, timelock, and treasury addresses and
the evidence that each owner has accepted the role. The deployment script validates that the
deployer does not retain pause or timelock authority, but it cannot choose or approve the
signer set. Record:

- multisig address, chain ID, threshold, signer addresses, and recovery process;
- timelock address, delay, proposer/executor roles, and emergency procedure;
- protocol treasury address and accounting owner;
- a successful read-only role check and a controlled test of pause/timelock handoff;
- the transaction hashes and explorer links for the final role configuration.

Do not accept mainnet funds until the external audit and governance owners have signed off.
Contract rollback is not a database rollback: the contracts are non-upgradeable. The planned
emergency action is an approved pause/governance procedure, followed by a forward contract or
application release if required.

## Release, health, rollback, and monitoring

Before promotion, the release owner records the manifest digest and runs the production gate
with the values supplied through the CI secret/variable manager. After promotion, the operator
checks:

```powershell
Invoke-WebRequest "$webOrigin" -UseBasicParsing
Invoke-WebRequest "$apiOrigin/healthz" -UseBasicParsing
Invoke-WebRequest "$indexerHealthOrigin/healthz" -UseBasicParsing
Invoke-WebRequest "$apiOrigin/v1/tokens?limit=1" -UseBasicParsing
```

The response must be successful, the chain/deployment metadata must match the manifest, and
the logs must contain no credentials, cookies, signatures, private RPC material, or raw access
tokens. Confirm indexer head/finality lag, database connectivity, RPC error rate, HTTP 5xx,
write rejection rate, and notification/reconciliation activity against the agreed alert policy.

The rollback owner first stops or pauses new transaction-capable traffic when compatibility is
uncertain, then rolls the web/API/indexer deployment back to the last passing commit. Do not
roll back a database migration independently; deploy a forward-compatible fix. Preserve the
incident timeline, manifest digest, gate output, health responses, and scrubbed request IDs.

## Audit evidence checklist

The audit packet must identify the exact commit and contain the Solidity source/artifact
digests, Foundry/solc versions, invariant and fuzz results, pinned Robinhood fork evidence,
deployment receipt and runtime-code hashes, manifest digest, governance role evidence,
reproducible release-gate output, threat-model findings, accepted-risk register, and the
external auditor's signed report. A green CI run is not an audit approval.

## Final approval rule

Production is not approved while any row in the input sheet is `<pending>`, the testnet or
production manifest is disabled/unreviewed, the Privy origin is unverified, the rollback and
monitoring owners are unnamed, or the external audit/governance evidence is absent.
