# Contracts

Foundry project for the launchpad contracts. V1 public interfaces, errors, events, storage
layouts, and the fixed-supply launch token are covered by local and CI drift gates.

## Pinned toolchain

- Foundry `v1.8.1` (`982849d3140c01fd3b72905759581a132df7aa98`)
- Solidity `0.8.36`
- OpenZeppelin Contracts `v5.7.0`
- forge-std `v1.16.1`

Install the exact Foundry release from the official release page, then initialize the pinned
submodules from the repository root:

```bash
git submodule update --init --recursive
```

Run the complete local gate from Windows PowerShell 5.1 or PowerShell 7:

```powershell
./contracts/scripts/check.ps1 all
```

Individual commands, run from `contracts/`, are:

```bash
forge fmt --check
forge build
./scripts/check-goldens.ps1
./scripts/check-vectors.ps1
./scripts/check-deployments.ps1
forge test
forge lint --severity high med low info -D warnings
forge build --sizes
```

The compiler configuration in `foundry.toml` is authoritative for local and CI builds.
`scripts/check-dependencies.ps1` rejects a different Foundry binary, dependency commit, or CI
toolchain pin. `scripts/check-goldens.ps1` rejects event ABI, storage layout, or compiler
pipeline drift. After an intentional reviewed ABI or layout change, regenerate the artifacts
from `contracts/` with:

```powershell
./scripts/check-goldens.ps1 -Write
```

`vectors/v1/curve.schema.json` defines the backend-facing V1 differential-vector format.
Every `uint256` is encoded as a base-10 string so JSON consumers cannot lose precision.
`vectors/v1/curve-v1.json` is generated from deployed `BondingCurveV1` clones and actual
buy, sell, quote, and graduation paths; expected amounts are never recalculated in the
generator. Regenerate it from `contracts/` only after reviewing an intentional math change:

```powershell
./scripts/check-vectors.ps1 -Write
```

The normal `./scripts/check-vectors.ps1` command regenerates into a temporary path and fails
on byte drift, missing coverage cases, malformed amounts, failed-state mutation, or buy/sell
conservation errors. It is part of `check.ps1 all` and therefore the GitHub Actions gate.

`abi/v1/ILaunchEvents.json` is the authoritative V1 event artifact consumed by the backend.
`abi/v1/LaunchToken.json` freezes the concrete inherited ERC-20 callable surface. The gate
uses an exact allowlist so accidental additions such as mint, burn, fallback, or receive fail.
`abi/v1/LaunchFactory.json` freezes the launch and governance surface with the same exact
allowlist approach; authority-transfer, rescue, fallback, and receive paths are rejected.
`storage-layout/v1/LaunchToken.json` captures the composed ERC-20 implementation layout.
`storage-layout/v1/BondingCurveV1.json` captures the concrete clone implementation layout.
`storage-layout/v1/LaunchFactory.json` captures the composed non-upgradeable factory layout.

## Deployment

`scripts/deploy.ps1` deploys the isolated local WETH/Uniswap v2 stack when targeting Anvil,
validates dependency bytecode and pair CREATE2 derivation, deploys the curve implementation
and factory, then builds a candidate manifest from the actual broadcast receipts. Candidate
manifests remain under the git-ignored `deployments/.generated/` directory until reviewed.
The command accepts only an unlocked Anvil account or a named Foundry keystore/hardware
wallet account; it has no raw private-key or mnemonic parameter.

Example local broadcast from `contracts/` using Anvil's deterministic development accounts:

```powershell
./scripts/deploy.ps1 `
  -Target anvil `
  -RpcUrl http://127.0.0.1:8545 `
  -DeploymentId anvil-v1 `
  -Sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 `
  -PauseAuthority 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 `
  -Timelock 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC `
  -ProtocolTreasury 0x90F79bf6EB2c4f870365E785982E1f101E93b906 `
  -Broadcast `
  -Unlocked
```

Robinhood testnet is disabled until `scripts/bootstrap-testnet-dependencies.ps1` deploys
testnet-specific dependencies and its generated evidence is independently reviewed into
`deployments/config/robinhood-testnet.json`. Mainnet broadcasts are intentionally blocked;
the same deployment command supports simulation only until the pinned Task 11 fork job and
the external-audit release gate pass. Production simulation also requires the final reviewed
pause multisig, timelock, and treasury addresses as arguments, so there is no authority
handover or placeholder manifest.

The Robinhood mainnet fork gate uses block `53,240,126` and a QuickNode archive endpoint. The
official public RPC is suitable for current-state checks but does not serve the historical
state required for a reproducible fork. Set the archive URL without writing it to disk, then
run the explicit gate:

```powershell
$archiveRpc = Read-Host "QuickNode Robinhood archive RPC URL" -AsSecureString
$env:ROBINHOOD_MAINNET_ARCHIVE_RPC_URL =
  [System.Net.NetworkCredential]::new("", $archiveRpc).Password
./scripts/check.ps1 fork
Remove-Item Env:ROBINHOOD_MAINNET_ARCHIVE_RPC_URL
Remove-Variable archiveRpc
```

GitHub Actions exposes the same explicit job through `workflow_dispatch` and reads the URL
from the `ROBINHOOD_MAINNET_ARCHIVE_RPC_URL` repository secret. Missing credentials, missing
archive history, chain mismatch, block-hash drift, dependency-code drift, or any fork-test
failure fails that job; none of those conditions silently skips the suite.

Market-delivery ETH sends (final-buy refunds and sell proceeds) use a 50,000 gas probe so a
recipient cannot consume the transaction's remaining gas and block market progress. A failed
probe becomes a pull refund. Explicit fee/refund claims use an uncapped call and revert on
failure, so smart accounts that need more than the probe limit remain able to receive funds.
