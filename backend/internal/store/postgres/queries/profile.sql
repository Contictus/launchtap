-- name: ListProfileActions :many
SELECT t.token_address, t.curve_address, t.name, t.symbol, t.phase,
       CASE WHEN t.creator = sqlc.arg(wallet) THEN GREATEST(
           COALESCE((SELECT sum(trade.creator_fee) FROM trades AS trade
                     WHERE trade.chain_id = t.chain_id AND trade.token_address = t.token_address), 0::numeric)
           - COALESCE((SELECT sum(claim.amount) FROM creator_fee_claims AS claim
                       WHERE claim.chain_id = t.chain_id AND claim.token_address = t.token_address), 0::numeric),
           0::numeric
       ) ELSE 0::numeric END::numeric(78, 0) AS creator_fee_amount,
       GREATEST(
           COALESCE((SELECT sum(credit.amount) FROM refund_credits AS credit
                     WHERE credit.chain_id = t.chain_id AND credit.token_address = t.token_address AND credit.account = sqlc.arg(wallet)), 0::numeric)
           - COALESCE((SELECT sum(claim.amount) FROM refund_claims AS claim
                       WHERE claim.chain_id = t.chain_id AND claim.token_address = t.token_address AND claim.account = sqlc.arg(wallet)), 0::numeric),
           0::numeric
       )::numeric(78, 0) AS refund_amount
FROM tokens AS t
WHERE t.chain_id = sqlc.arg(chain_id)
  AND (
      (t.creator = sqlc.arg(wallet)
       AND COALESCE((SELECT sum(trade.creator_fee) FROM trades AS trade
                     WHERE trade.chain_id = t.chain_id AND trade.token_address = t.token_address), 0::numeric)
           - COALESCE((SELECT sum(claim.amount) FROM creator_fee_claims AS claim
                       WHERE claim.chain_id = t.chain_id AND claim.token_address = t.token_address), 0::numeric) > 0)
      OR
      (COALESCE((SELECT sum(credit.amount) FROM refund_credits AS credit
                 WHERE credit.chain_id = t.chain_id AND credit.token_address = t.token_address AND credit.account = sqlc.arg(wallet)), 0::numeric)
       - COALESCE((SELECT sum(claim.amount) FROM refund_claims AS claim
                   WHERE claim.chain_id = t.chain_id AND claim.token_address = t.token_address AND claim.account = sqlc.arg(wallet)), 0::numeric) > 0)
  )
ORDER BY t.token_address ASC;
