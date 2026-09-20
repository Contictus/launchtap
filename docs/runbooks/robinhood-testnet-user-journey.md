# Robinhood Chain Testnet user journey

This runbook explains how a human tester uses the reviewed Launchpad deployment on
Robinhood Chain Testnet (`chainId 46630`). It covers wallet creation, faucet funding,
the first launch, the first trade, and the evidence needed for live acceptance.

It is deliberately separate from the deployment runbook: deployment uses an operator
account, while this journey uses fresh test-only user accounts.

## Safety rules

- Use test-only wallets. Never use a production wallet or a wallet holding real assets.
- Never paste a private key, seed phrase, keystore password, or credentialed RPC URL into
  chat, GitHub, an issue, a screenshot, or a repository file.
- The deployer account must not be used as the creator or trader. The current reviewed
  manifest records `0x12cB30400339831107589695E5C71455e223Bf02` as the deployer; do not
  use that address for this acceptance run.
- Creator and trader must be different addresses. The trader needs ETH for gas and buys.
- Every wallet write must be reviewed in the wallet: chain, destination, value, fee,
  deadline, and minimum output/slippage bound.

## Network details

| Setting | Value |
| --- | --- |
| Network name | Robinhood Chain Testnet |
| Chain ID | `46630` |
| Currency symbol | ETH |
| RPC URL | `https://rpc.testnet.chain.robinhood.com` |
| Explorer | https://explorer.testnet.chain.robinhood.com |
| Faucet | https://faucet.testnet.chain.robinhood.com |

The network name is only a wallet label. The chain ID is the identity check that matters.
If a wallet shows another chain ID, stop before signing.

## 1. Create the two test wallets

Create two separate accounts in the wallet you will use for testing:

1. `creator-testnet` — launches the token.
2. `trader-testnet` — buys and sells the token.

The wallet may call these accounts simply “Account 1” and “Account 2”; the labels are
local and do not affect the chain. Record only the public addresses:

```text
creator_address=0x...
trader_address=0x...
```

Do not export or share either account's private key. If the wallet only offers one account,
use its **Create account** action to add the second account. Do not import a key from a
message or a repository.

## 2. Add and verify the network

Add a custom network using the values above. Then switch to it and verify:

- chain ID is `46630`;
- the native asset is ETH;
- the RPC host is `rpc.testnet.chain.robinhood.com`;
- the explorer link opens the Robinhood testnet explorer.

Do not substitute Robinhood mainnet (`4663`) or Ethereum testnet settings.

## 3. Fund both wallets from the faucet

Open the faucet and paste one public address at a time:

1. Paste `creator_address` into **Send to** and request tokens.
2. Repeat with `trader_address`.
3. Import the faucet's test stock tokens only if the test specifically needs them; the
   Launchpad acceptance flow uses native test ETH for gas and curve trades.

The faucet enforces a cooldown (currently up to 24 hours per address). A cooldown message
means the request was rate-limited; it does not mean the wallet is misconfigured. Wait for
the cooldown rather than repeatedly submitting requests.

Refresh the wallet after the request and verify a non-zero ETH balance. The balance can also
be checked read-only with Foundry:

```powershell
cd contracts
cast balance <creator_address> --rpc-url https://rpc.testnet.chain.robinhood.com
cast balance <trader_address> --rpc-url https://rpc.testnet.chain.robinhood.com
```

Keep the faucet transaction or explorer link as evidence. Never include wallet secrets.

## 4. Confirm the reviewed deployment

The active testnet deployment is `robinhood-testnet-v1` on chain `46630`. The reviewed
LaunchFactory is:

```text
0xedddb61a53226ffdc6ecf7c042b803e769168d55
```

Before a live run, confirm the application is configured with the matching chain and
deployment ID. A healthy web page alone is not proof that the API/indexer is connected.
The operator should also have API `/healthz`, API `/readyz`, and indexer `/healthz` available.

## 5. Launch a token as the creator

1. Switch the wallet to `creator-testnet`.
2. Open the Launchpad web client configured for Robinhood Chain Testnet.
3. Enter a test name, symbol, and the required launch parameters.
4. Review the displayed launch fee, transaction value, destination factory, and optional
   developer-buy settings.
5. Submit the transaction and approve it in the wallet.
6. Wait for a successful receipt. Copy the transaction hash and the emitted token address.

The launch transaction creates the token and curve atomically. Do not treat a wallet's
“submitted” state as success; wait for the receipt and verify the transaction on the
explorer.

## 6. Execute the first buy and sell as the trader

1. Switch to `trader-testnet`; never sign the trade from the creator or deployer account.
2. Open the newly created token detail page.
3. Request a quote and check the token address, ETH input, expected output, fee, deadline,
   and minimum output/slippage bound.
4. Submit a small buy and approve it in the wallet.
5. Wait for the receipt and record its transaction hash.
6. Sell a portion of the acquired tokens, again reviewing the quote and minimum output.
7. Wait for the receipt and record the sell transaction hash.

Quotes are informational until the contract call is simulated or executed. The contract
state and receipt are authoritative. A successful wallet receipt and an indexed API record
are separate observations; allow the indexer to reach the block before checking the API.

## 7. Exercise graduation

Use the configured curve quote to submit buys until the graduation boundary is reached.
The final buy may refund unused ETH when it crosses the exact boundary. Verify all of the
following on-chain:

- the curve enters the graduated phase;
- a `Graduated` event is emitted;
- the canonical Uniswap v2 pair is created;
- the initial LP position is sent to the configured burn address;
- subsequent trading follows the post-graduation path.

Record the final buy hash, graduation event transaction hash (usually the same transaction),
token address, pair address, and explorer links.

## 8. Verify backend and finality

After every transaction, record:

```text
transaction_hash=0x...
block_number=...
token_address=0x...
pair_address=0x...            # after graduation
```

Wait until the indexer reports the block at the expected observed/safe/finalized watermark.
Capture the JSON returned by:

```powershell
Invoke-RestMethod http://localhost:8080/healthz
Invoke-RestMethod http://localhost:8080/readyz
Invoke-RestMethod http://localhost:8081/healthz
```

If a transaction is confirmed on-chain but absent from the API, do not insert rows manually.
Check indexer health, deployment identity, and the configured RPC first.

## Live acceptance evidence template

Fill this template without secrets and attach explorer links where possible:

```text
chain_id=46630
deployment_id=robinhood-testnet-v1
creator_address=0x...
trader_address=0x...
creator_is_deployer=false
trader_is_deployer=false
creator_funding_tx=0x... or faucet link
trader_funding_tx=0x... or faucet link
launch_tx=0x...
token_address=0x...
buy_tx=0x...
sell_tx=0x...
graduation_tx=0x...
pair_address=0x...
api_health_capture=<path or timestamp>
indexer_health_capture=<path or timestamp>
observed_safe_finalized=<values>
reorg_observation=<none or details>
```

The live-acceptance backlog item can be closed only after this evidence is checked against
the explorer, the manifest digest, and the API/indexer health output. This document does not
replace the deployment review or the production-readiness checklist.

## Common failures

- **No balance:** confirm chain ID `46630`, wait for the faucet cooldown, and refresh the
  wallet. Do not request funds for the deployer account as a substitute for a fresh trader.
- **Wrong network:** remove the incorrect custom network entry and add the values in this
  document again; the display name alone is not enough.
- **Transaction rejected:** check gas balance, deadline, slippage bound, pause state, and
  that the correct creator/trader account is selected.
- **Receipt succeeds but UI is empty:** wait for indexing and inspect `/healthz` and `/readyz`;
  the UI does not create database records itself.
- **Faucet says already claimed:** this is the faucet's address cooldown. Use another test-only
  wallet only if the test requires immediate parallel funding; never reuse a production key.
