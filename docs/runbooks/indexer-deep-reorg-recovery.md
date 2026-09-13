# Indexer Deep-Reorg Recovery

This procedure recovers a canonical-ledger divergence whose common ancestor is beyond the
indexer's normal 128-header search window. It uses the indexer's existing reorg rollback and
projection-rebuild path. Recovery remains automatic only within the configured search window;
the default is 128 candidate headers. An expanded window requires both
`INDEXER_REORG_RECOVERY_MODE=true` and an explicit `INDEXER_REORG_SEARCH_DEPTH` greater than 128.
The maximum accepted window is 100,000 candidate headers.

The search counts RPC headers, starting at the mismatching remote tip and including the common
ancestor candidate. The candidate floor is the higher of the persisted safe block and the
deployment start block (or the start block when no safe block is stored). The indexer will not
search for or delete canonical data below that floor. A mismatch at or below the safe head remains
terminal; finalized data is never automatically deleted. Do not lower safe/finalized watermarks or
edit canonical tables manually to bypass these checks.

## Preconditions

Use an assigned database and chain operator. Do not start recovery against production until the
same artifact, RPC source, backup/restore procedure, and recovery steps have been rehearsed on an
isolated restore of the affected database. The repository does not provide a dry-run command, and
the unit tests do not replace a database-backed rehearsal.

Before running the indexer:

1. Stop the managed indexer process for this exact chain and deployment. Confirm it has exited;
   do not launch a second writer. The process still verifies RPC chain ID and deployed bytecode
   before opening the database pool, then acquires the same chain/deployment PostgreSQL advisory
   ownership lock before it can write.
2. Take a database backup/checkpoint using the approved PostgreSQL procedure. Record the backup
   identifier and verify that it can be restored to an isolated database. Record the current
   `sync_state` observed, safe, and finalized numbers and hashes, plus the current deployment
   manifest digest and indexer artifact digest.
3. Verify the RPC provider is an owner-approved source for this chain, supports historical header
   reads across the suspected divergence, and is not returning inconsistent heads. Independently
   confirm the chain ID, deployment manifest, and incident range. The indexer repeats chain-ID and
   deployed-bytecode verification on startup; this does not establish that the provider's history
   is trustworthy.
4. Determine the expected ancestor range from incident evidence. Choose a search window large
   enough to include every candidate from the mismatching remote tip through the oldest expected
   ancestor, inclusive. Keep it at or below 100,000. If evidence points to an ancestor below the
   persisted safe head, stop and escalate for an owner-approved canonical-source and restore
   decision. An ancestor exactly at safe is eligible; a larger window cannot authorize crossing
   below that boundary.

There is no database write during preflight. If the chosen bound does not contain a common
ancestor, lookup fails before the reorg record or canonical tables are changed. If recovery is
recorded and the rollback/rebuild transaction fails, that transaction rolls back atomically while
the incident record remains `open` for diagnosis.

## Run

Record the old observed height as `OLD_OBSERVED_NUMBER`. Set the two recovery variables only in
the temporary environment of the single approved indexer instance. For a local/staging process
from `backend/`:

```powershell
$env:INDEXER_REORG_SEARCH_DEPTH = "512"
$env:INDEXER_REORG_RECOVERY_MODE = "true"
go run ./cmd/indexer
```

Replace `512` with the preflight value. Production must use the already approved deployment
artifact and its process supervisor; do not substitute `go run` for the deployed binary. Do not
persist these variables in normal service configuration. Startup logs include the effective
`reorg_search_depth` and `reorg_recovery_mode` values. The ownership lock and watchdog remain
active, and a lock loss remains fatal.

The indexer continues running after recovery and replays from the common ancestor. Watch the
indexer health endpoint and logs. The health JSON must report the expected chain/deployment,
`OwnershipHeld=true`, `RPCHealthy=true`, an empty `LastError`, and a `LastReorgID`/`LastReorgDepth`
matching the incident. The endpoint may remain not-ready until a post-recovery chunk commits.
For a local process with the default health bind address, inspect it with:

```powershell
Invoke-RestMethod "http://127.0.0.1:8081/healthz" |
    Format-List ChainID, DeploymentID, Observed, Safe, Finalized, OwnershipHeld,
                RPCHealthy, LastReorgID, LastReorgDepth, LastError
```

In PostgreSQL, replace the placeholders below with the reviewed manifest values and verify the
committed watermarks and reorg outcome:

```sql
SELECT observed_number, encode(observed_hash, 'hex') AS observed_hash,
       safe_number, encode(safe_hash, 'hex') AS safe_hash,
       finalized_number, encode(finalized_hash, 'hex') AS finalized_hash
FROM sync_state
WHERE chain_id = <CHAIN_ID> AND deployment_id = '<DEPLOYMENT_ID>';

SELECT reorg_id, detected_tip_number, common_ancestor_number, depth,
       outcome, completed_at
FROM indexer_reorgs
WHERE chain_id = <CHAIN_ID> AND deployment_id = '<DEPLOYMENT_ID>'
ORDER BY reorg_id DESC
LIMIT 5;
```

Confirm the recovered row has the expected tip, ancestor, and depth, with `outcome='recovered'`
and a non-null `completed_at`; there must be no newer `open` incident. Confirm observed is at or
past `OLD_OBSERVED_NUMBER`, safe and finalized are not ahead of observed, and the observed hash
matches the selected RPC at that height. Compare representative canonical events and affected
token/protocol aggregates with the isolated-rehearsal results and application reads.

Once the old observed height has been replayed and verification passes, stop this process, remove
both recovery variables, and restart the normal service with its default 128-header window.
Verify normal health and writer ownership again. Retain the backup identifier, manifest/artifact
digests, scrubbed logs, health snapshots, and SQL results with the incident record.

In the local PowerShell session, remove the temporary values with:

```powershell
Remove-Item Env:INDEXER_REORG_SEARCH_DEPTH, Env:INDEXER_REORG_RECOVERY_MODE
```

## Failure and escalation

- No common ancestor in the chosen window: the indexer exits without canonical writes. Recheck
  provider history and incident evidence. If justified, repeat preflight with the approved RPC
  source and a bound that includes the ancestor; never guess an arbitrarily large value.
- Safe-head violation, including a mismatch at/below safe: stop. Do not expand the search below
  safe. Obtain an explicit canonical-source and database recovery decision from the chain and
  database owners.
- An `open` incident row, failed rebuild, lost writer lock, unhealthy RPC, or failed post-recovery
  verification: stop the process, preserve the database and logs, and escalate. Do not rerun
  blindly or issue manual delete/update SQL. Restore a backup only through the approved DBA
  procedure and only after the isolated rehearsal has established the recovery point and replay
  consequences.
