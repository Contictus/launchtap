-- name: ListTokenCardsNewest :many
SELECT t.token_address, t.name, t.symbol, t.phase,
       t.launch_block_number, t.launch_block_time, t.total_supply,
       COALESCE(s.market_cap_eth_wad, 0::numeric) AS market_cap_eth_wad,
       COALESCE(s.volume_24h_eth_wad, 0::numeric) AS volume_24h_eth_wad,
       COALESCE(s.holder_count, 0)::BIGINT AS holder_count,
       m.description, m.image_url, m.x_url, m.telegram_url,
       t.launch_block_hash
FROM tokens AS t
LEFT JOIN token_metadata AS m USING (chain_id, token_address)
LEFT JOIN token_stats AS s USING (chain_id, token_address)
WHERE t.chain_id = sqlc.arg(chain_id)
  AND t.phase = sqlc.arg(phase)
  AND (sqlc.arg(search)::text = '' OR lower(t.name) LIKE lower(sqlc.arg(search)::text) || '%'
       OR lower(t.symbol) LIKE lower(sqlc.arg(search)::text) || '%'
       OR encode(t.token_address, 'hex') = lower(ltrim(sqlc.arg(search)::text, '0x')))
  AND (sqlc.narg(after_block)::bigint IS NULL
       OR (t.launch_block_number, t.token_address) < (sqlc.narg(after_block)::bigint, sqlc.narg(after_address)::bytea))
ORDER BY t.launch_block_number DESC, t.token_address DESC
LIMIT sqlc.arg(page_size)::integer;

-- name: ListTokenCardsOldest :many
SELECT t.token_address, t.name, t.symbol, t.phase, t.launch_block_number, t.launch_block_time, t.total_supply,
       COALESCE(s.market_cap_eth_wad, 0::numeric) AS market_cap_eth_wad, COALESCE(s.volume_24h_eth_wad, 0::numeric) AS volume_24h_eth_wad,
       COALESCE(s.holder_count, 0)::BIGINT AS holder_count, m.description, m.image_url, m.x_url, m.telegram_url, t.launch_block_hash
FROM tokens AS t LEFT JOIN token_metadata AS m USING (chain_id, token_address) LEFT JOIN token_stats AS s USING (chain_id, token_address)
WHERE t.chain_id = sqlc.arg(chain_id) AND t.phase = sqlc.arg(phase)
  AND (sqlc.arg(search)::text = '' OR lower(t.name) LIKE lower(sqlc.arg(search)::text) || '%' OR lower(t.symbol) LIKE lower(sqlc.arg(search)::text) || '%')
  AND (sqlc.narg(after_block)::bigint IS NULL OR (t.launch_block_number, t.token_address) > (sqlc.narg(after_block)::bigint, sqlc.narg(after_address)::bytea))
ORDER BY t.launch_block_number ASC, t.token_address ASC LIMIT sqlc.arg(page_size)::integer;

-- name: ListTokenCardsMarketCap :many
SELECT t.token_address, t.name, t.symbol, t.phase, t.launch_block_number, t.launch_block_time, t.total_supply,
       COALESCE(s.market_cap_eth_wad, 0::numeric) AS market_cap_eth_wad, COALESCE(s.volume_24h_eth_wad, 0::numeric) AS volume_24h_eth_wad,
       COALESCE(s.holder_count, 0)::BIGINT AS holder_count, m.description, m.image_url, m.x_url, m.telegram_url, t.launch_block_hash
FROM tokens AS t LEFT JOIN token_metadata AS m USING (chain_id, token_address) LEFT JOIN token_stats AS s USING (chain_id, token_address)
WHERE t.chain_id = sqlc.arg(chain_id) AND t.phase = sqlc.arg(phase)
  AND (sqlc.arg(search)::text = '' OR lower(t.name) LIKE lower(sqlc.arg(search)::text) || '%' OR lower(t.symbol) LIKE lower(sqlc.arg(search)::text) || '%')
  AND (sqlc.narg(after_metric)::numeric IS NULL OR (COALESCE(s.market_cap_eth_wad,0::numeric), t.token_address) < (sqlc.narg(after_metric)::numeric, sqlc.narg(after_address)::bytea))
ORDER BY COALESCE(s.market_cap_eth_wad,0::numeric) DESC, t.token_address DESC LIMIT sqlc.arg(page_size)::integer;

-- name: ListTokenCardsVolume :many
SELECT t.token_address, t.name, t.symbol, t.phase, t.launch_block_number, t.launch_block_time, t.total_supply,
       COALESCE(s.market_cap_eth_wad, 0::numeric) AS market_cap_eth_wad, COALESCE(s.volume_24h_eth_wad, 0::numeric) AS volume_24h_eth_wad,
       COALESCE(s.holder_count, 0)::BIGINT AS holder_count, m.description, m.image_url, m.x_url, m.telegram_url, t.launch_block_hash
FROM tokens AS t LEFT JOIN token_metadata AS m USING (chain_id, token_address) LEFT JOIN token_stats AS s USING (chain_id, token_address)
WHERE t.chain_id = sqlc.arg(chain_id) AND t.phase = sqlc.arg(phase)
  AND (sqlc.arg(search)::text = '' OR lower(t.name) LIKE lower(sqlc.arg(search)::text) || '%' OR lower(t.symbol) LIKE lower(sqlc.arg(search)::text) || '%')
  AND (sqlc.narg(after_metric)::numeric IS NULL OR (COALESCE(s.volume_24h_eth_wad,0::numeric), t.token_address) < (sqlc.narg(after_metric)::numeric, sqlc.narg(after_address)::bytea))
ORDER BY COALESCE(s.volume_24h_eth_wad,0::numeric) DESC, t.token_address DESC LIMIT sqlc.arg(page_size)::integer;

-- name: ListCandlesAggregated :many
SELECT min(c.bucket_start_time) AS bucket_start_time,
       (array_agg(c.open_price_wad ORDER BY c.bucket_start_time ASC))[1] AS open_price_wad,
       max(c.high_price_wad) AS high_price_wad,
       min(c.low_price_wad) AS low_price_wad,
       (array_agg(c.close_price_wad ORDER BY c.bucket_start_time DESC))[1] AS close_price_wad,
       sum(c.gross_eth_volume)::numeric AS gross_eth_volume,
       sum(c.token_volume)::numeric AS token_volume,
       sum(c.trade_count)::BIGINT AS trade_count
FROM candles AS c
WHERE c.chain_id = sqlc.arg(chain_id)
  AND c.token_address = sqlc.arg(token_address)
  AND c.interval = sqlc.arg(source_interval)
  AND c.bucket_start_time >= sqlc.arg(from_time)
  AND c.bucket_start_time < sqlc.arg(to_time)
GROUP BY CASE WHEN sqlc.arg(target_interval)::text = '6h'
             THEN date_trunc('day', c.bucket_start_time) + floor(extract(hour FROM c.bucket_start_time) / 6) * interval '6 hours'
             ELSE date_trunc('day', c.bucket_start_time) END
ORDER BY bucket_start_time ASC
LIMIT sqlc.arg(page_size)::integer;
