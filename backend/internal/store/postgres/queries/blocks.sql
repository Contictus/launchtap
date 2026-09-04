-- name: UpsertIndexedBlock :execrows
INSERT INTO indexed_blocks (
    chain_id,
    block_number,
    block_hash,
    parent_hash,
    block_time,
    finality_status
) VALUES ($1, $2, $3, $4, $5, $6)
ON CONFLICT (chain_id, block_number) DO UPDATE
SET finality_status = EXCLUDED.finality_status
WHERE indexed_blocks.block_hash = EXCLUDED.block_hash
  AND indexed_blocks.parent_hash = EXCLUDED.parent_hash
  AND indexed_blocks.block_time = EXCLUDED.block_time;

-- name: GetIndexedBlockByNumber :one
SELECT chain_id, block_number, block_hash, parent_hash, block_time, finality_status
FROM indexed_blocks
WHERE chain_id = $1 AND block_number = $2;

-- name: GetIndexedBlockByHash :one
SELECT chain_id, block_number, block_hash, parent_hash, block_time, finality_status
FROM indexed_blocks
WHERE chain_id = $1 AND block_hash = $2;
