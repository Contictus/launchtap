-- name: ListTokenIdentities :many
SELECT token_address, curve_address, lp_pair, engine_version,
       launch_block_number, launch_block_hash, launch_block_time
FROM tokens WHERE chain_id=$1 ORDER BY token_address;
