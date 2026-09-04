-- +goose Up
CREATE TABLE tokens (
    chain_id BIGINT NOT NULL,
    token_address BYTEA NOT NULL,
    curve_address BYTEA NOT NULL,
    lp_pair BYTEA NOT NULL,
    weth BYTEA NOT NULL,
    creator BYTEA NOT NULL,
    protocol_treasury BYTEA NOT NULL,
    engine_version INTEGER NOT NULL,
    name TEXT NOT NULL,
    symbol TEXT NOT NULL,
    total_supply NUMERIC(78,0) NOT NULL,
    initial_virtual_eth NUMERIC(78,0) NOT NULL,
    initial_virtual_token NUMERIC(78,0) NOT NULL,
    curve_tokens NUMERIC(78,0) NOT NULL,
    lp_tokens NUMERIC(78,0) NOT NULL,
    graduation_eth NUMERIC(78,0) NOT NULL,
    trade_fee_bps INTEGER NOT NULL,
    protocol_share_bps INTEGER NOT NULL,
    launch_block_number BIGINT NOT NULL,
    launch_block_hash BYTEA NOT NULL,
    launch_block_time TIMESTAMPTZ NOT NULL,
    launch_tx_hash BYTEA NOT NULL,
    launch_log_index INTEGER NOT NULL,
    phase TEXT NOT NULL DEFAULT 'curve',
    graduation_block_number BIGINT,
    graduation_block_hash BYTEA,
    graduation_block_time TIMESTAMPTZ,
    graduation_tx_hash BYTEA,
    graduation_log_index INTEGER,
    token_is_token0 BOOLEAN GENERATED ALWAYS AS (token_address < weth) STORED NOT NULL,
    CONSTRAINT tokens_pkey PRIMARY KEY (chain_id, token_address),
    CONSTRAINT tokens_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT tokens_token_address_length CHECK (octet_length(token_address) = 20),
    CONSTRAINT tokens_curve_address_length CHECK (octet_length(curve_address) = 20),
    CONSTRAINT tokens_lp_pair_length CHECK (octet_length(lp_pair) = 20),
    CONSTRAINT tokens_weth_length CHECK (octet_length(weth) = 20),
    CONSTRAINT tokens_creator_length CHECK (octet_length(creator) = 20),
    CONSTRAINT tokens_protocol_treasury_length CHECK (octet_length(protocol_treasury) = 20),
    CONSTRAINT tokens_engine_version_uint16 CHECK (engine_version BETWEEN 0 AND 65535),
    CONSTRAINT tokens_total_supply_nonnegative CHECK (total_supply >= 0),
    CONSTRAINT tokens_initial_virtual_eth_nonnegative CHECK (initial_virtual_eth >= 0),
    CONSTRAINT tokens_initial_virtual_token_nonnegative CHECK (initial_virtual_token >= 0),
    CONSTRAINT tokens_curve_tokens_nonnegative CHECK (curve_tokens >= 0),
    CONSTRAINT tokens_lp_tokens_nonnegative CHECK (lp_tokens >= 0),
    CONSTRAINT tokens_graduation_eth_nonnegative CHECK (graduation_eth >= 0),
    CONSTRAINT tokens_trade_fee_bps_uint16 CHECK (trade_fee_bps BETWEEN 0 AND 65535),
    CONSTRAINT tokens_protocol_share_bps_uint16 CHECK (protocol_share_bps BETWEEN 0 AND 65535),
    CONSTRAINT tokens_launch_block_number_nonnegative CHECK (launch_block_number >= 0),
    CONSTRAINT tokens_launch_block_hash_length CHECK (octet_length(launch_block_hash) = 32),
    CONSTRAINT tokens_launch_tx_hash_length CHECK (octet_length(launch_tx_hash) = 32),
    CONSTRAINT tokens_launch_log_index_nonnegative CHECK (launch_log_index >= 0),
    CONSTRAINT tokens_phase_valid CHECK (phase IN ('curve', 'graduated')),
    CONSTRAINT tokens_graduation_block_number_nonnegative CHECK (graduation_block_number >= 0),
    CONSTRAINT tokens_graduation_block_hash_length CHECK (octet_length(graduation_block_hash) = 32),
    CONSTRAINT tokens_graduation_tx_hash_length CHECK (octet_length(graduation_tx_hash) = 32),
    CONSTRAINT tokens_graduation_log_index_nonnegative CHECK (graduation_log_index >= 0),
    CONSTRAINT tokens_graduation_coordinates_with_phase CHECK (
        (phase = 'curve'
            AND graduation_block_number IS NULL
            AND graduation_block_hash IS NULL
            AND graduation_block_time IS NULL
            AND graduation_tx_hash IS NULL
            AND graduation_log_index IS NULL)
        OR
        (phase = 'graduated'
            AND graduation_block_number IS NOT NULL
            AND graduation_block_hash IS NOT NULL
            AND graduation_block_time IS NOT NULL
            AND graduation_tx_hash IS NOT NULL
            AND graduation_log_index IS NOT NULL)
    ),
    CONSTRAINT tokens_token_launch_fk FOREIGN KEY (chain_id, token_address)
        REFERENCES token_launches (chain_id, token_address)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT tokens_graduation_block_fk FOREIGN KEY (
        chain_id, graduation_block_number, graduation_block_hash, graduation_block_time
    ) REFERENCES indexed_blocks (chain_id, block_number, block_hash, block_time)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT tokens_graduation_event_fk FOREIGN KEY (chain_id, graduation_tx_hash, graduation_log_index)
        REFERENCES graduations (chain_id, tx_hash, log_index)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX tokens_pair_lookup_idx ON tokens (chain_id, lp_pair);
CREATE INDEX tokens_graduation_block_fk_idx
    ON tokens (chain_id, graduation_block_number, graduation_block_hash, graduation_block_time)
    WHERE phase = 'graduated';
CREATE INDEX tokens_graduation_event_fk_idx
    ON tokens (chain_id, graduation_tx_hash, graduation_log_index)
    WHERE phase = 'graduated';

CREATE TABLE token_reserves (
    chain_id BIGINT NOT NULL,
    token_address BYTEA NOT NULL,
    reserve_source TEXT NOT NULL,
    eth_reserve NUMERIC(78,0) NOT NULL,
    token_reserve NUMERIC(78,0) NOT NULL,
    source_block_number BIGINT NOT NULL,
    source_block_hash BYTEA NOT NULL,
    source_block_time TIMESTAMPTZ NOT NULL,
    source_tx_hash BYTEA NOT NULL,
    source_log_index INTEGER NOT NULL,
    CONSTRAINT token_reserves_pkey PRIMARY KEY (chain_id, token_address),
    CONSTRAINT token_reserves_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT token_reserves_token_address_length CHECK (octet_length(token_address) = 20),
    CONSTRAINT token_reserves_source_valid CHECK (reserve_source IN ('curve', 'pair')),
    CONSTRAINT token_reserves_eth_reserve_nonnegative CHECK (eth_reserve >= 0),
    CONSTRAINT token_reserves_token_reserve_nonnegative CHECK (token_reserve >= 0),
    CONSTRAINT token_reserves_source_block_number_nonnegative CHECK (source_block_number >= 0),
    CONSTRAINT token_reserves_source_block_hash_length CHECK (octet_length(source_block_hash) = 32),
    CONSTRAINT token_reserves_source_tx_hash_length CHECK (octet_length(source_tx_hash) = 32),
    CONSTRAINT token_reserves_source_log_index_nonnegative CHECK (source_log_index >= 0),
    CONSTRAINT token_reserves_token_fk FOREIGN KEY (chain_id, token_address)
        REFERENCES tokens (chain_id, token_address)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT token_reserves_source_block_fk FOREIGN KEY (
        chain_id, source_block_number, source_block_hash, source_block_time
    ) REFERENCES indexed_blocks (chain_id, block_number, block_hash, block_time)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX token_reserves_source_block_fk_idx
    ON token_reserves (chain_id, source_block_number, source_block_hash, source_block_time);

CREATE INDEX trades_token_rebuild_idx
    ON trades (chain_id, token_address, block_number, transaction_index, log_index);
CREATE INDEX graduations_token_rebuild_idx
    ON graduations (chain_id, token_address, block_number, transaction_index, log_index);
CREATE INDEX transfers_token_rebuild_idx
    ON transfers (chain_id, token_address, block_number, transaction_index, log_index);

CREATE TABLE holder_balances (
    chain_id BIGINT NOT NULL,
    token_address BYTEA NOT NULL,
    holder_address BYTEA NOT NULL,
    balance NUMERIC(78,0) NOT NULL,
    first_acquired_block_number BIGINT,
    CONSTRAINT holder_balances_pkey PRIMARY KEY (chain_id, token_address, holder_address),
    CONSTRAINT holder_balances_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT holder_balances_token_address_length CHECK (octet_length(token_address) = 20),
    CONSTRAINT holder_balances_holder_address_length CHECK (octet_length(holder_address) = 20),
    CONSTRAINT holder_balances_balance_nonnegative CHECK (balance >= 0),
    CONSTRAINT holder_balances_first_acquired_nonnegative CHECK (first_acquired_block_number >= 0),
    CONSTRAINT holder_balances_first_acquired_with_balance CHECK (
        (balance = 0 AND first_acquired_block_number IS NULL)
        OR (balance > 0 AND first_acquired_block_number IS NOT NULL)
    ),
    CONSTRAINT holder_balances_token_fk FOREIGN KEY (chain_id, token_address)
        REFERENCES tokens (chain_id, token_address)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE SEQUENCE aggregation_dirty_generation_seq;

CREATE TABLE aggregation_dirty (
    chain_id BIGINT NOT NULL,
    token_address BYTEA NOT NULL,
    generation BIGINT NOT NULL,
    claimed_generation BIGINT,
    claimed_at TIMESTAMPTZ,
    claimed_by TEXT,
    CONSTRAINT aggregation_dirty_pkey PRIMARY KEY (chain_id, token_address),
    CONSTRAINT aggregation_dirty_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT aggregation_dirty_token_address_length CHECK (octet_length(token_address) = 20),
    CONSTRAINT aggregation_dirty_generation_nonnegative CHECK (generation >= 0),
    CONSTRAINT aggregation_dirty_claimed_generation_nonnegative CHECK (claimed_generation >= 0),
    CONSTRAINT aggregation_dirty_claim_together CHECK (
        (claimed_generation IS NULL AND claimed_at IS NULL AND claimed_by IS NULL)
        OR (claimed_generation IS NOT NULL AND claimed_at IS NOT NULL AND claimed_by IS NOT NULL)
    ),
    CONSTRAINT aggregation_dirty_claim_not_ahead CHECK (
        claimed_generation IS NULL OR claimed_generation <= generation
    ),
    CONSTRAINT aggregation_dirty_token_fk FOREIGN KEY (chain_id, token_address)
        REFERENCES tokens (chain_id, token_address)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE token_metadata (
    chain_id BIGINT NOT NULL,
    token_address BYTEA NOT NULL,
    description TEXT,
    image_url TEXT,
    x_url TEXT,
    telegram_url TEXT,
    updated_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT token_metadata_pkey PRIMARY KEY (chain_id, token_address),
    CONSTRAINT token_metadata_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT token_metadata_token_address_length CHECK (octet_length(token_address) = 20),
    CONSTRAINT token_metadata_token_launch_fk FOREIGN KEY (chain_id, token_address)
        REFERENCES token_launches (chain_id, token_address)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE candles (
    chain_id BIGINT NOT NULL,
    token_address BYTEA NOT NULL,
    interval TEXT NOT NULL,
    bucket_start_time TIMESTAMPTZ NOT NULL,
    open_price_wad NUMERIC(78,0) NOT NULL,
    high_price_wad NUMERIC(78,0) NOT NULL,
    low_price_wad NUMERIC(78,0) NOT NULL,
    close_price_wad NUMERIC(78,0) NOT NULL,
    gross_eth_volume NUMERIC(78,0) NOT NULL DEFAULT 0,
    token_volume NUMERIC(78,0) NOT NULL DEFAULT 0,
    trade_count INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT candles_pkey PRIMARY KEY (chain_id, token_address, interval, bucket_start_time),
    CONSTRAINT candles_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT candles_token_address_length CHECK (octet_length(token_address) = 20),
    CONSTRAINT candles_interval_valid CHECK (interval IN ('1m', '5m', '1h', '1d')),
    CONSTRAINT candles_open_price_nonnegative CHECK (open_price_wad >= 0),
    CONSTRAINT candles_high_price_nonnegative CHECK (high_price_wad >= 0),
    CONSTRAINT candles_low_price_nonnegative CHECK (low_price_wad >= 0),
    CONSTRAINT candles_close_price_nonnegative CHECK (close_price_wad >= 0),
    CONSTRAINT candles_gross_eth_volume_nonnegative CHECK (gross_eth_volume >= 0),
    CONSTRAINT candles_token_volume_nonnegative CHECK (token_volume >= 0),
    CONSTRAINT candles_trade_count_nonnegative CHECK (trade_count >= 0),
    CONSTRAINT candles_token_fk FOREIGN KEY (chain_id, token_address)
        REFERENCES tokens (chain_id, token_address)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE token_stats (
    chain_id BIGINT NOT NULL,
    token_address BYTEA NOT NULL,
    spot_price_eth_wad NUMERIC(78,0) NOT NULL,
    market_cap_eth_wad NUMERIC(78,0) NOT NULL,
    fdv_eth_wad NUMERIC(78,0) NOT NULL,
    liquidity_eth_wad NUMERIC(78,0) NOT NULL,
    ath_price_eth_wad NUMERIC(78,0) NOT NULL,
    ath_at TIMESTAMPTZ NOT NULL,
    volume_24h_eth_wad NUMERIC(78,0) NOT NULL DEFAULT 0,
    price_change_24h_bps INTEGER NOT NULL DEFAULT 0,
    holder_count INTEGER NOT NULL DEFAULT 0,
    spot_price_usd NUMERIC(38,18),
    market_cap_usd NUMERIC(38,18),
    fdv_usd NUMERIC(38,18),
    liquidity_usd NUMERIC(38,18),
    ath_usd NUMERIC(38,18),
    volume_24h_usd NUMERIC(38,18),
    updated_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT token_stats_pkey PRIMARY KEY (chain_id, token_address),
    CONSTRAINT token_stats_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT token_stats_token_address_length CHECK (octet_length(token_address) = 20),
    CONSTRAINT token_stats_spot_price_nonnegative CHECK (spot_price_eth_wad >= 0),
    CONSTRAINT token_stats_market_cap_nonnegative CHECK (market_cap_eth_wad >= 0),
    CONSTRAINT token_stats_fdv_nonnegative CHECK (fdv_eth_wad >= 0),
    CONSTRAINT token_stats_liquidity_nonnegative CHECK (liquidity_eth_wad >= 0),
    CONSTRAINT token_stats_ath_price_nonnegative CHECK (ath_price_eth_wad >= 0),
    CONSTRAINT token_stats_volume_24h_nonnegative CHECK (volume_24h_eth_wad >= 0),
    CONSTRAINT token_stats_holder_count_nonnegative CHECK (holder_count >= 0),
    CONSTRAINT token_stats_token_fk FOREIGN KEY (chain_id, token_address)
        REFERENCES tokens (chain_id, token_address)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE protocol_daily (
    chain_id BIGINT NOT NULL,
    day DATE NOT NULL,
    volume_eth_wad NUMERIC(78,0) NOT NULL DEFAULT 0,
    volume_usd NUMERIC(38,18),
    launches_count INTEGER NOT NULL DEFAULT 0,
    trades_count INTEGER NOT NULL DEFAULT 0,
    graduations_count INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT protocol_daily_pkey PRIMARY KEY (chain_id, day),
    CONSTRAINT protocol_daily_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT protocol_daily_volume_eth_nonnegative CHECK (volume_eth_wad >= 0),
    CONSTRAINT protocol_daily_launches_count_nonnegative CHECK (launches_count >= 0),
    CONSTRAINT protocol_daily_trades_count_nonnegative CHECK (trades_count >= 0),
    CONSTRAINT protocol_daily_graduations_count_nonnegative CHECK (graduations_count >= 0)
);

CREATE TABLE protocol_stats (
    chain_id BIGINT NOT NULL,
    volume_24h_eth_wad NUMERIC(78,0) NOT NULL DEFAULT 0,
    volume_24h_usd NUMERIC(38,18),
    volume_all_time_eth_wad NUMERIC(78,0) NOT NULL DEFAULT 0,
    volume_all_time_usd NUMERIC(38,18),
    launches_24h INTEGER NOT NULL DEFAULT 0,
    launches_all_time INTEGER NOT NULL DEFAULT 0,
    trades_24h INTEGER NOT NULL DEFAULT 0,
    trades_all_time BIGINT NOT NULL DEFAULT 0,
    graduations_24h INTEGER NOT NULL DEFAULT 0,
    graduations_all_time INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT protocol_stats_pkey PRIMARY KEY (chain_id),
    CONSTRAINT protocol_stats_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT protocol_stats_volume_24h_nonnegative CHECK (volume_24h_eth_wad >= 0),
    CONSTRAINT protocol_stats_volume_all_time_nonnegative CHECK (volume_all_time_eth_wad >= 0),
    CONSTRAINT protocol_stats_launches_24h_nonnegative CHECK (launches_24h >= 0),
    CONSTRAINT protocol_stats_launches_all_time_nonnegative CHECK (launches_all_time >= 0),
    CONSTRAINT protocol_stats_trades_24h_nonnegative CHECK (trades_24h >= 0),
    CONSTRAINT protocol_stats_trades_all_time_nonnegative CHECK (trades_all_time >= 0),
    CONSTRAINT protocol_stats_graduations_24h_nonnegative CHECK (graduations_24h >= 0),
    CONSTRAINT protocol_stats_graduations_all_time_nonnegative CHECK (graduations_all_time >= 0)
);

CREATE VIEW market_trades AS
SELECT
    trade.chain_id,
    trade.token_address,
    trade.block_number,
    trade.block_time,
    trade.transaction_index,
    trade.tx_hash,
    trade.log_index,
    'curve'::TEXT AS source,
    trade.is_buy AS side_buy,
    trade.trader,
    trunc(trade.eth_gross * 1000000000000000000::NUMERIC / NULLIF(trade.token_amount, 0))::NUMERIC(78,0)
        AS execution_price_wad,
    trunc(trade.new_eth_reserve * 1000000000000000000::NUMERIC / NULLIF(trade.new_token_reserve, 0))::NUMERIC(78,0)
        AS spot_price_wad,
    trade.eth_gross AS gross_eth_volume,
    trade.token_amount AS token_volume,
    block.finality_status AS finality
FROM trades AS trade
JOIN indexed_blocks AS block
  ON block.chain_id = trade.chain_id
 AND block.block_number = trade.block_number

UNION ALL

SELECT
    swap.chain_id,
    token.token_address,
    swap.block_number,
    swap.block_time,
    swap.transaction_index,
    swap.tx_hash,
    swap.log_index,
    'dex'::TEXT AS source,
    CASE WHEN token.token_is_token0 THEN swap.amount0_out > 0 ELSE swap.amount1_out > 0 END AS side_buy,
    NULL::BYTEA AS trader,
    trunc(legs.eth_volume * 1000000000000000000::NUMERIC / NULLIF(legs.token_volume, 0))::NUMERIC(78,0)
        AS execution_price_wad,
    trunc(legs.sync_eth_reserve * 1000000000000000000::NUMERIC / NULLIF(legs.sync_token_reserve, 0))::NUMERIC(78,0)
        AS spot_price_wad,
    legs.eth_volume AS gross_eth_volume,
    legs.token_volume,
    block.finality_status AS finality
FROM pool_swaps AS swap
JOIN tokens AS token
  ON token.chain_id = swap.chain_id
 AND token.lp_pair = swap.pair_address
JOIN indexed_blocks AS block
  ON block.chain_id = swap.chain_id
 AND block.block_number = swap.block_number
JOIN LATERAL (
    SELECT
        CASE
            WHEN token.token_is_token0 THEN swap.amount1_in + swap.amount1_out
            ELSE swap.amount0_in + swap.amount0_out
        END AS eth_volume,
        CASE
            WHEN token.token_is_token0 THEN swap.amount0_in + swap.amount0_out
            ELSE swap.amount1_in + swap.amount1_out
        END AS token_volume,
        CASE WHEN token.token_is_token0 THEN sync.reserve1 ELSE sync.reserve0 END AS sync_eth_reserve,
        CASE WHEN token.token_is_token0 THEN sync.reserve0 ELSE sync.reserve1 END AS sync_token_reserve
    FROM pool_syncs AS sync
    WHERE sync.chain_id = swap.chain_id
      AND sync.pair_address = swap.pair_address
      AND sync.tx_hash = swap.tx_hash
      AND sync.log_index < swap.log_index
    ORDER BY sync.log_index DESC
    LIMIT 1
) AS legs ON TRUE;

-- +goose StatementBegin
CREATE FUNCTION rebuild_token_projections(rebuild_chain_id BIGINT, rebuild_token_address BYTEA)
RETURNS void AS $$
BEGIN
    INSERT INTO public.tokens (
        chain_id, token_address, curve_address, lp_pair, weth, creator, protocol_treasury,
        engine_version, name, symbol, total_supply, initial_virtual_eth, initial_virtual_token,
        curve_tokens, lp_tokens, graduation_eth, trade_fee_bps, protocol_share_bps,
        launch_block_number, launch_block_hash, launch_block_time, launch_tx_hash, launch_log_index,
        phase, graduation_block_number, graduation_block_hash, graduation_block_time,
        graduation_tx_hash, graduation_log_index
    )
    SELECT
        launch.chain_id, launch.token_address, launch.curve_address, launch.lp_pair, launch.weth,
        launch.creator, launch.protocol_treasury, launch.engine_version, launch.name, launch.symbol,
        launch.total_supply, launch.virtual_eth, launch.virtual_token, launch.curve_tokens,
        launch.lp_tokens, launch.graduation_eth, launch.trade_fee_bps, launch.protocol_share_bps,
        launch.block_number, launch.block_hash, launch.block_time, launch.tx_hash, launch.log_index,
        CASE WHEN graduation.tx_hash IS NULL THEN 'curve' ELSE 'graduated' END,
        graduation.block_number, graduation.block_hash, graduation.block_time,
        graduation.tx_hash, graduation.log_index
    FROM public.token_launches AS launch
    LEFT JOIN LATERAL (
        SELECT candidate.block_number, candidate.block_hash, candidate.block_time,
               candidate.tx_hash, candidate.log_index
        FROM public.graduations AS candidate
        WHERE candidate.chain_id = launch.chain_id
          AND candidate.token_address = launch.token_address
        ORDER BY candidate.block_number DESC, candidate.transaction_index DESC, candidate.log_index DESC
        LIMIT 1
    ) AS graduation ON TRUE
    WHERE launch.chain_id = rebuild_chain_id
      AND launch.token_address = rebuild_token_address
    ON CONFLICT (chain_id, token_address) DO UPDATE SET
        curve_address = EXCLUDED.curve_address,
        lp_pair = EXCLUDED.lp_pair,
        weth = EXCLUDED.weth,
        creator = EXCLUDED.creator,
        protocol_treasury = EXCLUDED.protocol_treasury,
        engine_version = EXCLUDED.engine_version,
        name = EXCLUDED.name,
        symbol = EXCLUDED.symbol,
        total_supply = EXCLUDED.total_supply,
        initial_virtual_eth = EXCLUDED.initial_virtual_eth,
        initial_virtual_token = EXCLUDED.initial_virtual_token,
        curve_tokens = EXCLUDED.curve_tokens,
        lp_tokens = EXCLUDED.lp_tokens,
        graduation_eth = EXCLUDED.graduation_eth,
        trade_fee_bps = EXCLUDED.trade_fee_bps,
        protocol_share_bps = EXCLUDED.protocol_share_bps,
        launch_block_number = EXCLUDED.launch_block_number,
        launch_block_hash = EXCLUDED.launch_block_hash,
        launch_block_time = EXCLUDED.launch_block_time,
        launch_tx_hash = EXCLUDED.launch_tx_hash,
        launch_log_index = EXCLUDED.launch_log_index,
        phase = EXCLUDED.phase,
        graduation_block_number = EXCLUDED.graduation_block_number,
        graduation_block_hash = EXCLUDED.graduation_block_hash,
        graduation_block_time = EXCLUDED.graduation_block_time,
        graduation_tx_hash = EXCLUDED.graduation_tx_hash,
        graduation_log_index = EXCLUDED.graduation_log_index;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'cannot rebuild unknown token (chain_id=%, token=%)',
            rebuild_chain_id, rebuild_token_address;
    END IF;

    DELETE FROM public.token_reserves
    WHERE chain_id = rebuild_chain_id AND token_address = rebuild_token_address;

    INSERT INTO public.token_reserves (
        chain_id, token_address, reserve_source, eth_reserve, token_reserve,
        source_block_number, source_block_hash, source_block_time, source_tx_hash, source_log_index
    )
    SELECT chain_id, token_address, reserve_source, eth_reserve, token_reserve,
           block_number, block_hash, block_time, tx_hash, log_index
    FROM (
        SELECT trade.chain_id, trade.token_address, 'curve'::TEXT AS reserve_source,
               trade.new_eth_reserve AS eth_reserve, trade.new_token_reserve AS token_reserve,
               trade.block_number, trade.block_hash, trade.block_time, trade.transaction_index,
               trade.tx_hash, trade.log_index
        FROM public.trades AS trade
        WHERE trade.chain_id = rebuild_chain_id
          AND trade.token_address = rebuild_token_address

        UNION ALL

        SELECT sync.chain_id, token.token_address, 'pair'::TEXT,
               CASE WHEN token.token_is_token0 THEN sync.reserve1 ELSE sync.reserve0 END,
               CASE WHEN token.token_is_token0 THEN sync.reserve0 ELSE sync.reserve1 END,
               sync.block_number, sync.block_hash, sync.block_time, sync.transaction_index,
               sync.tx_hash, sync.log_index
        FROM public.pool_syncs AS sync
        JOIN public.tokens AS token
          ON token.chain_id = sync.chain_id
         AND token.lp_pair = sync.pair_address
         AND token.phase = 'graduated'
        WHERE token.chain_id = rebuild_chain_id
          AND token.token_address = rebuild_token_address
    ) AS reserve_event
    ORDER BY block_number DESC, transaction_index DESC, log_index DESC
    LIMIT 1;

    DELETE FROM public.holder_balances
    WHERE chain_id = rebuild_chain_id AND token_address = rebuild_token_address;

    INSERT INTO public.holder_balances (
        chain_id, token_address, holder_address, balance, first_acquired_block_number
    )
    WITH raw_deltas AS (
        SELECT transfer.chain_id, transfer.token_address, transfer.from_address AS holder_address,
               transfer.block_number, transfer.transaction_index, transfer.log_index,
               -transfer.value AS delta
        FROM public.transfers AS transfer
        WHERE transfer.chain_id = rebuild_chain_id
          AND transfer.token_address = rebuild_token_address
          AND transfer.from_address <> decode(repeat('00', 20), 'hex')
        UNION ALL
        SELECT transfer.chain_id, transfer.token_address, transfer.to_address,
               transfer.block_number, transfer.transaction_index, transfer.log_index,
               transfer.value
        FROM public.transfers AS transfer
        WHERE transfer.chain_id = rebuild_chain_id
          AND transfer.token_address = rebuild_token_address
    ), event_deltas AS (
        SELECT chain_id, token_address, holder_address, block_number, transaction_index, log_index,
               sum(delta) AS delta
        FROM raw_deltas
        GROUP BY chain_id, token_address, holder_address, block_number, transaction_index, log_index
    ), running AS (
        SELECT event_deltas.*,
               sum(delta) OVER (
                   PARTITION BY chain_id, token_address, holder_address
                   ORDER BY block_number, transaction_index, log_index
                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
               ) AS balance_after
        FROM event_deltas
    )
    SELECT chain_id, token_address, holder_address, max(balance_after) FILTER (WHERE is_last),
           CASE
               WHEN max(balance_after) FILTER (WHERE is_last) = 0 THEN NULL
               ELSE max(block_number) FILTER (WHERE balance_after - delta = 0 AND balance_after > 0)
           END
    FROM (
        SELECT running.*,
               row_number() OVER (
                   PARTITION BY chain_id, token_address, holder_address
                   ORDER BY block_number DESC, transaction_index DESC, log_index DESC
               ) = 1 AS is_last
        FROM running
    ) AS histories
    GROUP BY chain_id, token_address, holder_address;

    DELETE FROM public.candles
    WHERE chain_id = rebuild_chain_id AND token_address = rebuild_token_address;

    INSERT INTO public.candles (
        chain_id, token_address, interval, bucket_start_time,
        open_price_wad, high_price_wad, low_price_wad, close_price_wad,
        gross_eth_volume, token_volume, trade_count
    )
    WITH bucketed AS (
        SELECT market.*,
               interval_definition.interval,
               CASE interval_definition.interval
                   WHEN '1m' THEN date_trunc('minute', market.block_time)
                   WHEN '5m' THEN date_trunc('hour', market.block_time)
                       + floor(extract(minute FROM market.block_time) / 5) * interval '5 minutes'
                   WHEN '1h' THEN date_trunc('hour', market.block_time)
                   WHEN '1d' THEN date_trunc('day', market.block_time)
               END AS bucket_start_time
        FROM public.market_trades AS market
        CROSS JOIN (VALUES ('1m'), ('5m'), ('1h'), ('1d')) AS interval_definition(interval)
        WHERE market.chain_id = rebuild_chain_id
          AND market.token_address = rebuild_token_address
          AND market.execution_price_wad IS NOT NULL
    )
    SELECT chain_id, token_address, interval, bucket_start_time,
           (array_agg(execution_price_wad ORDER BY block_number, transaction_index, log_index))[1],
           max(execution_price_wad), min(execution_price_wad),
           (array_agg(execution_price_wad ORDER BY block_number DESC, transaction_index DESC, log_index DESC))[1],
           sum(gross_eth_volume), sum(token_volume), count(*)::INTEGER
    FROM bucketed
    GROUP BY chain_id, token_address, interval, bucket_start_time;

    INSERT INTO public.aggregation_dirty (chain_id, token_address, generation)
    VALUES (rebuild_chain_id, rebuild_token_address, nextval('public.aggregation_dirty_generation_seq'))
    ON CONFLICT (chain_id, token_address) DO UPDATE
        SET generation = nextval('public.aggregation_dirty_generation_seq');
END;
$$ LANGUAGE plpgsql SET search_path = pg_catalog;
-- +goose StatementEnd

-- +goose Down
DROP FUNCTION rebuild_token_projections(BIGINT, BYTEA);
DROP VIEW market_trades;
DROP INDEX transfers_token_rebuild_idx;
DROP INDEX graduations_token_rebuild_idx;
DROP INDEX trades_token_rebuild_idx;
DROP TABLE protocol_stats;
DROP TABLE protocol_daily;
DROP TABLE token_stats;
DROP TABLE candles;
DROP TABLE token_metadata;
DROP TABLE aggregation_dirty;
DROP SEQUENCE aggregation_dirty_generation_seq;
DROP TABLE holder_balances;
DROP TABLE token_reserves;
DROP TABLE tokens;
