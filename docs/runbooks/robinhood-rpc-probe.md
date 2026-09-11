# Robinhood RPC Probe

This note records the read-only public-RPC probe required by Backend Plan 2 Task 1. It is
operational evidence for the documented endpoints, not a provider SLA and not proof that a
deployment manifest exists on chain 46630.

## Probe metadata

- **Probe date:** 2026-09-11
- **UTC sample window:** `2026-09-11T15:32:35.4629107Z` to
  `2026-09-11T15:32:49.9809698Z`
- **Method:** JSON-RPC `POST` requests only; no transactions, signing, deployment, or
  state-changing method was used.
- **Endpoint identity:** `web3_clientVersion` reported
  `nitro/v3.11.4-rc.3-7d5ac27/linux-amd64/go1.25.14` on mainnet and
  `nitro/v3.11.4-rc.3-7d5ac27/linux-arm64/go1.25.14` on testnet.
- **Sampling limitation:** two finality samples were taken about 14.5 seconds apart. This
  establishes support and a first observed lag range; it is not a long-run latency
  distribution or an availability measurement.

## Chain and finality support

| Endpoint | Chain ID | Sample | latest | safe | finalized | latest-safe | latest-finalized |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| `https://rpc.mainnet.chain.robinhood.com` | 4663 | 15:32:35Z | 60,364,988 | 60,357,683 | 60,354,157 | 7,305 | 10,831 |
| same | 4663 | 15:32:50Z | 60,365,130 | 60,357,683 | 60,354,157 | 7,447 | 10,973 |
| `https://rpc.testnet.chain.robinhood.com` | 46630 | 15:32:37Z | 117,530,204 | 117,524,657 | 117,522,314 | 5,547 | 7,890 |
| same | 46630 | 15:32:53Z | 117,530,321 | 117,524,657 | 117,522,314 | 5,664 | 8,007 |

The `latest`, `safe`, and `finalized` tags all returned block objects on both endpoints.
Across the two samples, `latest` advanced and neither `safe` nor `finalized` regressed.
The observed block-timestamp legs at the first sample were approximately:

- Mainnet: latest → safe `743 s`; safe → finalized `363 s`; latest → finalized `1,106 s`.
- Testnet: latest → safe `746 s`; safe → finalized `351 s`; latest → finalized `1,097 s`.

These are observations from one short window, not configured health thresholds. The runtime
must continue to use the provider's `safe`/`finalized` tags and must not convert these values
into a fixed confirmation-count finality model.

The direct latest-head measurement over the 14.518-second wall-clock sample was approximately
9.79 blocks/second on mainnet (`+142` blocks) and 8.06 blocks/second on testnet (`+117`
blocks). The lag-leg rates implied by the first sample were approximately 9.84 and 9.71
blocks/second for mainnet observed→safe and safe→finalized, and 7.44 and 6.68 blocks/second
for testnet. The short window explains the spread; it is not sufficient to choose a percentile
health alert threshold.

## Repeated block-hash consistency

For each endpoint, the block returned for each tag was read once to obtain its number and then
read twice by that fixed number. Both reads returned the same hash for all three tags.

| Endpoint | fixed latest block/hash | fixed safe block/hash | fixed finalized block/hash |
| --- | --- | --- | --- |
| Mainnet | `60365749` / `0x55ebd7cfbb39fcb8ee327d647a832aac0d416fb1afc638f1792f4b04afeab659` | `60357683` / `0xd19940357f3e636df0f98f256db291e49fc0ffa50e05880ceacddae9aeb781f6` | `60354157` / `0x29983a5af3933d43a7fb91b6a2219c3c9399bd953a799af7a79500c1247d1598` |
| Testnet | `117530889` / `0x78b3242c92dde679be49f2fed06ec5584407c3fa5e7a803fa047129939429a0f` | `117524657` / `0x76e4733e613bc0be3df90a5a374295a2048f24c7355a986c6b2ba9c56e214a78` | `117522314` / `0x7cb69d40af26b8f54f877be30ee71e280e5367eaa3af37b129bdb54493ed8883` |

## `eth_getLogs` observations

The following requests were bounded and used an empty address filter
(`0x0000000000000000000000000000000000000000`) so that range-capacity checks did not ask the
provider to return a large live event set:

| Endpoint | Tested range widths | Result |
| --- | --- | --- |
| Mainnet | 1, 1,000, 10,000, 100,000, 1,000,000 blocks | All accepted, empty result, 37-byte response |
| Testnet | 1, 1,000, 10,000, 100,000, 1,000,000 blocks | All accepted, empty result, 37-byte response |

This establishes no range error through 1,000,000 blocks for this non-matching filter. It does
not establish an unlimited range or a provider maximum.

Two small unfiltered requests show the practical response-size constraint:

| Endpoint | 10-block range | 100-block range |
| --- | --- | --- |
| Mainnet | 938 logs / 833,263 bytes | 8,954 logs / 7,541,194 bytes |
| Testnet | 21 logs / 15,417 bytes | 141 logs / 101,964 bytes |

The address-array form was accepted at a single block with arrays of 2, 10, 100, 500, and
1,000 addresses. The probe did not search for the server's hard maximum; it only establishes
that the existing 500-address partition is within the tested range.

The matched and unfiltered requests above were measured with the exact `fromBlock`/`toBlock`
range stated in the table. The zero-match request used the exact zero address shown above.
Unfiltered response sizes and request latencies were: mainnet 833,263 bytes/369 ms for 10
blocks and 7,541,194 bytes/918 ms for 100 blocks; testnet 15,417 bytes/486 ms for 10 blocks
and 101,964 bytes/485 ms for 100 blocks. A timestamped finality-tag spot check at
`2026-09-11T15:39:48.2681079Z` returned the following response sizes and latencies:

| Endpoint | latest | safe | finalized |
| --- | --- | --- | --- |
| Mainnet | 4,376 bytes / 308 ms | 6,102 bytes / 1,135 ms | 2,444 bytes / 279 ms |
| Testnet | 1,752 bytes / 369 ms | 1,752 bytes / 346 ms | 1,751 bytes / 338 ms |

## Runtime implications

- The probe half of Plan 2 Task 1 is complete. Both official endpoints provide the required
  `safe` and `finalized` tags, so this probe found no finality-support launch blocker.
- The current conservative implementation defaults of a 100-block indexer chunk and a
  500-address log partition are compatible with the observed response sizes and address-array
  behavior. The 7.5 MB mainnet response from only 100 unfiltered blocks is evidence against
  using large unfiltered ranges in production.
- A longer operator sampling run is still appropriate before setting alert thresholds from a
  statistical percentile. This note intentionally does not turn a two-sample observation into
  a false precision threshold.
- The chain-46630 dependency/Launchpad deployment manifest remains a separate open prerequisite.
  Mainnet addresses must not be copied to testnet.
