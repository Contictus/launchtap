# Deployment manifests

The JSON schemas in this directory are shared by contract deployment, backend, and
frontend work. `deployment.schema.json` covers runnable deployments,
`chain-dependencies.schema.json` covers reviewed chain dependencies without a launchpad
deployment, and `chain-disabled.schema.json` covers explicit unavailable-chain markers.
Generated manifests are candidates until a human reviews the transaction, addresses,
bytecode hashes, dependencies, and governance owners.

Local Anvil manifests are written to `deployments/.generated/` and are never committed as
universal constants. A Robinhood testnet deployment is fail-closed while
`config/robinhood-testnet.disabled.json` exists. Replace that marker only with a reviewed
configuration produced after deploying or independently verifying testnet-specific WETH and
Uniswap v2 dependencies. Mainnet dependency addresses are version-controlled from the
official deployment records; factory and curve addresses are always generated from the
broadcast receipt.

No deployment command accepts a raw private key or mnemonic. Use an Anvil unlocked account
for local work or a Foundry keystore/hardware wallet account for signed deployments.
