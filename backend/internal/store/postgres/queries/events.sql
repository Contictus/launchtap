-- name: InsertTrade :execrows
INSERT INTO trades (
    chain_id, block_number, block_hash, block_time, transaction_index, tx_hash, log_index,
    token_address, trader, is_buy, eth_gross, eth_refund, token_amount, protocol_fee,
    creator_fee, new_eth_reserve, new_token_reserve
) VALUES (
    $1, $2, $3, $4, $5, $6, $7,
    $8, $9, $10, $11, $12, $13, $14,
    $15, $16, $17
)
ON CONFLICT (chain_id, tx_hash, log_index) DO NOTHING;

-- name: GetTradeByEventIdentity :one
SELECT
    chain_id, block_number, block_hash, block_time, transaction_index, tx_hash, log_index,
    token_address, trader, is_buy, eth_gross, eth_refund, token_amount, protocol_fee,
    creator_fee, new_eth_reserve, new_token_reserve
FROM trades
WHERE chain_id = $1 AND tx_hash = $2 AND log_index = $3;

-- name: InsertLaunchPauseEvent :execrows
INSERT INTO launch_pause_events (
    chain_id, block_number, block_hash, block_time, transaction_index, tx_hash, log_index, paused
) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
ON CONFLICT (chain_id, tx_hash, log_index) DO NOTHING;

-- name: GetLaunchPauseEventByIdentity :one
SELECT chain_id, block_number, block_hash, block_time, transaction_index, tx_hash, log_index, paused
FROM launch_pause_events
WHERE chain_id = $1 AND tx_hash = $2 AND log_index = $3;
