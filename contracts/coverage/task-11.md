# Task 11 Robinhood mainnet fork coverage

## Pinned gate

The reproducible fork target is Robinhood Chain block `53,240,126`, hash
`0xa1249b79d3ad41991913b02bb10057156a49fc22ab54ffebec27d05cff5f529a`. The successful
development run used Robinhood Public RPC while that block was current. Reproduction uses a
QuickNode archive endpoint supplied as `ROBINHOOD_MAINNET_ARCHIVE_RPC_URL`. The reviewed
configuration records both providers, the block, dependency addresses, and runtime code hashes.

Run from `contracts/`:

```powershell
./scripts/check.ps1 fork
```

`check-fork.ps1` fails before the Solidity suite if the endpoint is absent, is not the
recorded provider, reports a different chain, cannot read the pinned historical state, or
returns a different block/dependency hash. The GitHub Actions fork job invokes this exact
command and never converts a missing RPC into a skipped test.

## Integration properties

`RobinhoodMainnetFork.t.sol` runs the production contracts against the deployed Robinhood
mainnet WETH and Uniswap v2 Factory/Pair implementations. It proves:

- the reviewed WETH and Factory runtime hashes and WETH ERC-20 metadata;
- permissionless pair creation and canonical CREATE2 derivation using the reviewed init-code
  hash, followed by the reviewed production Pair runtime hash;
- launch-token construction, canonical pair resolution, zero initial reserves and supply,
  and `Transfer -> PairCreated -> TokenLaunched` ordering;
- final-fill quote/execution agreement, exact `4.2 ETH` and `200,000,000` token pool
  contribution, exact reserves under both token orderings, and all returned initial LP sent
  to `0xdead` apart from Uniswap's permanently minted minimum liquidity;
- `Trade -> token transfer to pair -> Sync -> Graduated` ordering;
- unrestricted post-graduation token transfer and direct Uniswap v2 swap under both token
  orderings, including the production Pair's adjacent `Sync -> Swap` event order; and
- graduation succeeding while Router02 is replaced by reverting bytecode on the local fork,
  proving that graduation has no Router dependency.

## Live development run

On 2026-09-03 the two-test suite passed against the official public RPC at block `53,240,126`.
Live reads also observed WETH runtime hash
`0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353`, Factory runtime
hash `0xbab145d02e7005f0d84c6c1639d39b799b0ea16df99ebbdaf5a14d9da820b4e0`, and Pair runtime
hash `0x5b83bdbcc56b2e630f2807bbadd2b0c21619108066b92a58de081261089e9ce5`.

That run proves the pinned state once but not its reproducibility. Within minutes the official
public endpoint rejected historical state at the same block. GitHub Actions run `33731325316`
then tried the pinned state twice through an Alchemy Robinhood mainnet endpoint; both attempts
failed with `missing trie node`, so the endpoint did not provide the required historical state.

Before changing providers, the public QuickNode Robinhood docs endpoint was checked against the
same evidence. It reported chain ID `4663`, returned the exact pinned block hash, and returned
non-empty historical WETH and Factory bytecode. QuickNode's provider documentation records
Robinhood mainnet as archive-enabled with no pruning. The pinned QuickNode fork job remains
required before Task 11 is accepted.
