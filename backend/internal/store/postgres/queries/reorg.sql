-- name: FindCommonAncestor :one
SELECT block_number, block_hash
FROM indexed_blocks
WHERE chain_id = $1 AND block_hash = ANY($2::bytea[])
ORDER BY block_number DESC
LIMIT 1;

-- name: AffectedTokensAbove :many
SELECT DISTINCT affected.token_address FROM (
    SELECT launch.token_address FROM token_launches AS launch WHERE launch.chain_id=$1 AND launch.block_number>$2
    UNION ALL SELECT trade.token_address FROM trades AS trade WHERE trade.chain_id=$1 AND trade.block_number>$2
    UNION ALL SELECT graduation.token_address FROM graduations AS graduation WHERE graduation.chain_id=$1 AND graduation.block_number>$2
    UNION ALL SELECT claim.token_address FROM creator_fee_claims AS claim WHERE claim.chain_id=$1 AND claim.block_number>$2
    UNION ALL SELECT claim.token_address FROM protocol_fee_claims AS claim WHERE claim.chain_id=$1 AND claim.block_number>$2
    UNION ALL SELECT credit.token_address FROM refund_credits AS credit WHERE credit.chain_id=$1 AND credit.block_number>$2
    UNION ALL SELECT claim.token_address FROM refund_claims AS claim WHERE claim.chain_id=$1 AND claim.block_number>$2
    UNION ALL SELECT transfer.token_address FROM transfers AS transfer WHERE transfer.chain_id=$1 AND transfer.block_number>$2
    UNION ALL
    SELECT token.token_address FROM tokens AS token JOIN (
        SELECT mint.pair_address FROM pool_mints AS mint WHERE mint.chain_id=$1 AND mint.block_number>$2
        UNION SELECT burn.pair_address FROM pool_burns AS burn WHERE burn.chain_id=$1 AND burn.block_number>$2
        UNION SELECT swap.pair_address FROM pool_swaps AS swap WHERE swap.chain_id=$1 AND swap.block_number>$2
        UNION SELECT sync.pair_address FROM pool_syncs AS sync WHERE sync.chain_id=$1 AND sync.block_number>$2
    ) AS pairs ON pairs.pair_address=token.lp_pair WHERE token.chain_id=$1
) AS affected ORDER BY token_address;

-- name: DeleteTokenLaunchesAbove :execrows
DELETE FROM token_launches WHERE chain_id=$1 AND block_number>$2;
-- name: DeleteTradesAbove :execrows
DELETE FROM trades WHERE chain_id=$1 AND block_number>$2;
-- name: DeleteGraduationsAbove :execrows
DELETE FROM graduations WHERE chain_id=$1 AND block_number>$2;
-- name: DeleteCreatorFeeClaimsAbove :execrows
DELETE FROM creator_fee_claims WHERE chain_id=$1 AND block_number>$2;
-- name: DeleteProtocolFeeClaimsAbove :execrows
DELETE FROM protocol_fee_claims WHERE chain_id=$1 AND block_number>$2;
-- name: DeleteLaunchFeeClaimsAbove :execrows
DELETE FROM launch_fee_claims WHERE chain_id=$1 AND block_number>$2;
-- name: DeleteRefundCreditsAbove :execrows
DELETE FROM refund_credits WHERE chain_id=$1 AND block_number>$2;
-- name: DeleteRefundClaimsAbove :execrows
DELETE FROM refund_claims WHERE chain_id=$1 AND block_number>$2;
-- name: DeleteTransfersAbove :execrows
DELETE FROM transfers WHERE chain_id=$1 AND block_number>$2;
-- name: DeletePoolMintsAbove :execrows
DELETE FROM pool_mints WHERE chain_id=$1 AND block_number>$2;
-- name: DeletePoolBurnsAbove :execrows
DELETE FROM pool_burns WHERE chain_id=$1 AND block_number>$2;
-- name: DeletePoolSwapsAbove :execrows
DELETE FROM pool_swaps WHERE chain_id=$1 AND block_number>$2;
-- name: DeletePoolSyncsAbove :execrows
DELETE FROM pool_syncs WHERE chain_id=$1 AND block_number>$2;
-- name: DeleteLaunchPauseEventsAbove :execrows
DELETE FROM launch_pause_events WHERE chain_id=$1 AND block_number>$2;
-- name: DeleteTradingPauseEventsAbove :execrows
DELETE FROM trading_pause_events WHERE chain_id=$1 AND block_number>$2;
-- name: DeleteEngineConfigurationsAbove :execrows
DELETE FROM engine_configurations WHERE chain_id=$1 AND block_number>$2;
-- name: DeleteFutureDefaultsConfigurationsAbove :execrows
DELETE FROM future_defaults_configurations WHERE chain_id=$1 AND block_number>$2;
-- name: DeleteFutureTreasuryConfigurationsAbove :execrows
DELETE FROM future_treasury_configurations WHERE chain_id=$1 AND block_number>$2;
-- name: DeleteIndexedBlocksAbove :execrows
DELETE FROM indexed_blocks WHERE chain_id=$1 AND block_number>$2;
