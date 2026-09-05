-- name: RebuildTokenProjections :exec
SELECT rebuild_token_projections($1, $2);

-- name: ClaimAggregationDirty :many
WITH candidate AS (
    SELECT chain_id, token_address
    FROM aggregation_dirty
    WHERE claimed_generation IS NULL OR claimed_generation < generation
    ORDER BY generation, chain_id, token_address
    LIMIT sqlc.arg(batch_size)::integer
    FOR UPDATE SKIP LOCKED
)
UPDATE aggregation_dirty AS dirty
SET claimed_generation = dirty.generation,
    claimed_at = now(),
    claimed_by = sqlc.arg(worker_id)
FROM candidate
WHERE dirty.chain_id = candidate.chain_id
  AND dirty.token_address = candidate.token_address
RETURNING dirty.chain_id, dirty.token_address, dirty.claimed_generation;

-- name: CompleteAggregationDirty :execrows
DELETE FROM aggregation_dirty
WHERE chain_id = sqlc.arg(chain_id)
  AND token_address = sqlc.arg(token_address)
  AND generation = sqlc.arg(claimed_generation)
  AND claimed_generation = sqlc.arg(claimed_generation)
  AND claimed_by = sqlc.arg(worker_id);
