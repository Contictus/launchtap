# Task 10 deployment coverage

## Reproduction

Run the complete contract gate from `contracts/`:

```powershell
./scripts/check.ps1 all
```

The deployment checks validate the JSON schema, reviewed network configuration, compiler
pins, secret hygiene, generated-artifact exclusions, and deployment-script source guards.
`Deployment.t.sol` exercises the executable validation and deployment paths.

## Proved by Task 10

- The isolated Anvil stack deploys local WETH, a CREATE2 Uniswap v2 factory and pair, the
  launchpad contracts, and completes launch through graduation with initial LP sent to the
  burn address.
- External-network deployment fails closed without an explicit dependency review, and the
  testnet configuration cannot reuse the pinned mainnet WETH or factory.
- Dependency validation checks code presence, optional reviewed runtime hashes, and pair
  init-code compatibility. Both the `pairCodeHash()` fast path and the getter-less factory
  fallback are tested; the fallback proves matching and mismatching CREATE2 addresses.
- Mainnet candidates must use the pinned chain dependencies and final non-deployer pause and
  timelock authorities. The deployer cannot call protected factory controls after deployment.
- Manifests are schema-constrained and exclude secret material. Mainnet broadcast remains
  disabled until Task 11 live validation is complete.

## Deferred to Task 11

Task 10 does not claim that the chain ID, WETH, Uniswap v2 factory, router, runtime bytecode,
or pair init-code hash have been verified against a live Robinhood Chain RPC. Task 11 must
pin a reviewed RPC block, reproduce those checks against live code, test WETH behaviour and
factory event/pair derivation, and record the resulting evidence before mainnet broadcast is
enabled.

Final production authority addresses and the production dry-run are also deployment inputs,
not local-simulation evidence. They remain required before a production manifest can be
accepted.
