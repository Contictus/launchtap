-- +goose Up
ALTER TABLE indexed_blocks
    ADD CONSTRAINT indexed_blocks_event_coordinates_key
    UNIQUE (chain_id, block_number, block_hash, block_time);

CREATE TABLE token_launches (
    chain_id BIGINT NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash BYTEA NOT NULL,
    block_time TIMESTAMPTZ NOT NULL,
    transaction_index INTEGER NOT NULL,
    tx_hash BYTEA NOT NULL,
    log_index INTEGER NOT NULL,
    token_address BYTEA NOT NULL,
    curve_address BYTEA NOT NULL,
    creator BYTEA NOT NULL,
    lp_pair BYTEA NOT NULL,
    weth BYTEA NOT NULL,
    protocol_treasury BYTEA NOT NULL,
    engine_version INTEGER NOT NULL,
    name TEXT NOT NULL,
    symbol TEXT NOT NULL,
    total_supply NUMERIC(78,0) NOT NULL,
    virtual_eth NUMERIC(78,0) NOT NULL,
    virtual_token NUMERIC(78,0) NOT NULL,
    curve_tokens NUMERIC(78,0) NOT NULL,
    lp_tokens NUMERIC(78,0) NOT NULL,
    graduation_eth NUMERIC(78,0) NOT NULL,
    launch_fee_paid NUMERIC(78,0) NOT NULL,
    trade_fee_bps INTEGER NOT NULL,
    protocol_share_bps INTEGER NOT NULL,
    CONSTRAINT token_launches_pkey PRIMARY KEY (chain_id, tx_hash, log_index),
    CONSTRAINT token_launches_chain_token_key UNIQUE (chain_id, token_address),
    CONSTRAINT token_launches_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT token_launches_block_number_nonnegative CHECK (block_number >= 0),
    CONSTRAINT token_launches_block_hash_length CHECK (octet_length(block_hash) = 32),
    CONSTRAINT token_launches_transaction_index_nonnegative CHECK (transaction_index >= 0),
    CONSTRAINT token_launches_tx_hash_length CHECK (octet_length(tx_hash) = 32),
    CONSTRAINT token_launches_log_index_nonnegative CHECK (log_index >= 0),
    CONSTRAINT token_launches_token_address_length CHECK (octet_length(token_address) = 20),
    CONSTRAINT token_launches_curve_address_length CHECK (octet_length(curve_address) = 20),
    CONSTRAINT token_launches_creator_length CHECK (octet_length(creator) = 20),
    CONSTRAINT token_launches_lp_pair_length CHECK (octet_length(lp_pair) = 20),
    CONSTRAINT token_launches_weth_length CHECK (octet_length(weth) = 20),
    CONSTRAINT token_launches_protocol_treasury_length CHECK (octet_length(protocol_treasury) = 20),
    CONSTRAINT token_launches_engine_version_uint16 CHECK (engine_version BETWEEN 0 AND 65535),
    CONSTRAINT token_launches_total_supply_nonnegative CHECK (total_supply >= 0),
    CONSTRAINT token_launches_virtual_eth_nonnegative CHECK (virtual_eth >= 0),
    CONSTRAINT token_launches_virtual_token_nonnegative CHECK (virtual_token >= 0),
    CONSTRAINT token_launches_curve_tokens_nonnegative CHECK (curve_tokens >= 0),
    CONSTRAINT token_launches_lp_tokens_nonnegative CHECK (lp_tokens >= 0),
    CONSTRAINT token_launches_graduation_eth_nonnegative CHECK (graduation_eth >= 0),
    CONSTRAINT token_launches_launch_fee_paid_nonnegative CHECK (launch_fee_paid >= 0),
    CONSTRAINT token_launches_trade_fee_bps_uint16 CHECK (trade_fee_bps BETWEEN 0 AND 65535),
    CONSTRAINT token_launches_protocol_share_bps_uint16 CHECK (protocol_share_bps BETWEEN 0 AND 65535),
    CONSTRAINT token_launches_block_fk FOREIGN KEY (chain_id, block_number, block_hash, block_time)
        REFERENCES indexed_blocks (chain_id, block_number, block_hash, block_time)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE trades (
    chain_id BIGINT NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash BYTEA NOT NULL,
    block_time TIMESTAMPTZ NOT NULL,
    transaction_index INTEGER NOT NULL,
    tx_hash BYTEA NOT NULL,
    log_index INTEGER NOT NULL,
    token_address BYTEA NOT NULL,
    trader BYTEA NOT NULL,
    is_buy BOOLEAN NOT NULL,
    eth_gross NUMERIC(78,0) NOT NULL,
    eth_refund NUMERIC(78,0) NOT NULL,
    token_amount NUMERIC(78,0) NOT NULL,
    protocol_fee NUMERIC(78,0) NOT NULL,
    creator_fee NUMERIC(78,0) NOT NULL,
    new_eth_reserve NUMERIC(78,0) NOT NULL,
    new_token_reserve NUMERIC(78,0) NOT NULL,
    CONSTRAINT trades_pkey PRIMARY KEY (chain_id, tx_hash, log_index),
    CONSTRAINT trades_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT trades_block_number_nonnegative CHECK (block_number >= 0),
    CONSTRAINT trades_block_hash_length CHECK (octet_length(block_hash) = 32),
    CONSTRAINT trades_transaction_index_nonnegative CHECK (transaction_index >= 0),
    CONSTRAINT trades_tx_hash_length CHECK (octet_length(tx_hash) = 32),
    CONSTRAINT trades_log_index_nonnegative CHECK (log_index >= 0),
    CONSTRAINT trades_token_address_length CHECK (octet_length(token_address) = 20),
    CONSTRAINT trades_trader_length CHECK (octet_length(trader) = 20),
    CONSTRAINT trades_eth_gross_nonnegative CHECK (eth_gross >= 0),
    CONSTRAINT trades_eth_refund_nonnegative CHECK (eth_refund >= 0),
    CONSTRAINT trades_token_amount_nonnegative CHECK (token_amount >= 0),
    CONSTRAINT trades_protocol_fee_nonnegative CHECK (protocol_fee >= 0),
    CONSTRAINT trades_creator_fee_nonnegative CHECK (creator_fee >= 0),
    CONSTRAINT trades_new_eth_reserve_nonnegative CHECK (new_eth_reserve >= 0),
    CONSTRAINT trades_new_token_reserve_nonnegative CHECK (new_token_reserve >= 0),
    CONSTRAINT trades_block_fk FOREIGN KEY (chain_id, block_number, block_hash, block_time)
        REFERENCES indexed_blocks (chain_id, block_number, block_hash, block_time)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT trades_token_launch_fk FOREIGN KEY (chain_id, token_address)
        REFERENCES token_launches (chain_id, token_address)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE graduations (
    chain_id BIGINT NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash BYTEA NOT NULL,
    block_time TIMESTAMPTZ NOT NULL,
    transaction_index INTEGER NOT NULL,
    tx_hash BYTEA NOT NULL,
    log_index INTEGER NOT NULL,
    token_address BYTEA NOT NULL,
    lp_pair BYTEA NOT NULL,
    eth_to_pool NUMERIC(78,0) NOT NULL,
    tokens_to_pool NUMERIC(78,0) NOT NULL,
    lp_liquidity_burned NUMERIC(78,0) NOT NULL,
    CONSTRAINT graduations_pkey PRIMARY KEY (chain_id, tx_hash, log_index),
    CONSTRAINT graduations_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT graduations_block_number_nonnegative CHECK (block_number >= 0),
    CONSTRAINT graduations_block_hash_length CHECK (octet_length(block_hash) = 32),
    CONSTRAINT graduations_transaction_index_nonnegative CHECK (transaction_index >= 0),
    CONSTRAINT graduations_tx_hash_length CHECK (octet_length(tx_hash) = 32),
    CONSTRAINT graduations_log_index_nonnegative CHECK (log_index >= 0),
    CONSTRAINT graduations_token_address_length CHECK (octet_length(token_address) = 20),
    CONSTRAINT graduations_lp_pair_length CHECK (octet_length(lp_pair) = 20),
    CONSTRAINT graduations_eth_to_pool_nonnegative CHECK (eth_to_pool >= 0),
    CONSTRAINT graduations_tokens_to_pool_nonnegative CHECK (tokens_to_pool >= 0),
    CONSTRAINT graduations_lp_liquidity_burned_nonnegative CHECK (lp_liquidity_burned >= 0),
    CONSTRAINT graduations_block_fk FOREIGN KEY (chain_id, block_number, block_hash, block_time)
        REFERENCES indexed_blocks (chain_id, block_number, block_hash, block_time)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT graduations_token_launch_fk FOREIGN KEY (chain_id, token_address)
        REFERENCES token_launches (chain_id, token_address)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE creator_fee_claims (
    chain_id BIGINT NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash BYTEA NOT NULL,
    block_time TIMESTAMPTZ NOT NULL,
    transaction_index INTEGER NOT NULL,
    tx_hash BYTEA NOT NULL,
    log_index INTEGER NOT NULL,
    token_address BYTEA NOT NULL,
    creator BYTEA NOT NULL,
    amount NUMERIC(78,0) NOT NULL,
    CONSTRAINT creator_fee_claims_pkey PRIMARY KEY (chain_id, tx_hash, log_index),
    CONSTRAINT creator_fee_claims_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT creator_fee_claims_block_number_nonnegative CHECK (block_number >= 0),
    CONSTRAINT creator_fee_claims_block_hash_length CHECK (octet_length(block_hash) = 32),
    CONSTRAINT creator_fee_claims_transaction_index_nonnegative CHECK (transaction_index >= 0),
    CONSTRAINT creator_fee_claims_tx_hash_length CHECK (octet_length(tx_hash) = 32),
    CONSTRAINT creator_fee_claims_log_index_nonnegative CHECK (log_index >= 0),
    CONSTRAINT creator_fee_claims_token_address_length CHECK (octet_length(token_address) = 20),
    CONSTRAINT creator_fee_claims_creator_length CHECK (octet_length(creator) = 20),
    CONSTRAINT creator_fee_claims_amount_nonnegative CHECK (amount >= 0),
    CONSTRAINT creator_fee_claims_block_fk FOREIGN KEY (chain_id, block_number, block_hash, block_time)
        REFERENCES indexed_blocks (chain_id, block_number, block_hash, block_time)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT creator_fee_claims_token_launch_fk FOREIGN KEY (chain_id, token_address)
        REFERENCES token_launches (chain_id, token_address)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE protocol_fee_claims (
    chain_id BIGINT NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash BYTEA NOT NULL,
    block_time TIMESTAMPTZ NOT NULL,
    transaction_index INTEGER NOT NULL,
    tx_hash BYTEA NOT NULL,
    log_index INTEGER NOT NULL,
    token_address BYTEA NOT NULL,
    treasury BYTEA NOT NULL,
    amount NUMERIC(78,0) NOT NULL,
    CONSTRAINT protocol_fee_claims_pkey PRIMARY KEY (chain_id, tx_hash, log_index),
    CONSTRAINT protocol_fee_claims_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT protocol_fee_claims_block_number_nonnegative CHECK (block_number >= 0),
    CONSTRAINT protocol_fee_claims_block_hash_length CHECK (octet_length(block_hash) = 32),
    CONSTRAINT protocol_fee_claims_transaction_index_nonnegative CHECK (transaction_index >= 0),
    CONSTRAINT protocol_fee_claims_tx_hash_length CHECK (octet_length(tx_hash) = 32),
    CONSTRAINT protocol_fee_claims_log_index_nonnegative CHECK (log_index >= 0),
    CONSTRAINT protocol_fee_claims_token_address_length CHECK (octet_length(token_address) = 20),
    CONSTRAINT protocol_fee_claims_treasury_length CHECK (octet_length(treasury) = 20),
    CONSTRAINT protocol_fee_claims_amount_nonnegative CHECK (amount >= 0),
    CONSTRAINT protocol_fee_claims_block_fk FOREIGN KEY (chain_id, block_number, block_hash, block_time)
        REFERENCES indexed_blocks (chain_id, block_number, block_hash, block_time)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT protocol_fee_claims_token_launch_fk FOREIGN KEY (chain_id, token_address)
        REFERENCES token_launches (chain_id, token_address)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE launch_fee_claims (
    chain_id BIGINT NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash BYTEA NOT NULL,
    block_time TIMESTAMPTZ NOT NULL,
    transaction_index INTEGER NOT NULL,
    tx_hash BYTEA NOT NULL,
    log_index INTEGER NOT NULL,
    treasury BYTEA NOT NULL,
    amount NUMERIC(78,0) NOT NULL,
    CONSTRAINT launch_fee_claims_pkey PRIMARY KEY (chain_id, tx_hash, log_index),
    CONSTRAINT launch_fee_claims_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT launch_fee_claims_block_number_nonnegative CHECK (block_number >= 0),
    CONSTRAINT launch_fee_claims_block_hash_length CHECK (octet_length(block_hash) = 32),
    CONSTRAINT launch_fee_claims_transaction_index_nonnegative CHECK (transaction_index >= 0),
    CONSTRAINT launch_fee_claims_tx_hash_length CHECK (octet_length(tx_hash) = 32),
    CONSTRAINT launch_fee_claims_log_index_nonnegative CHECK (log_index >= 0),
    CONSTRAINT launch_fee_claims_treasury_length CHECK (octet_length(treasury) = 20),
    CONSTRAINT launch_fee_claims_amount_nonnegative CHECK (amount >= 0),
    CONSTRAINT launch_fee_claims_block_fk FOREIGN KEY (chain_id, block_number, block_hash, block_time)
        REFERENCES indexed_blocks (chain_id, block_number, block_hash, block_time)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE refund_credits (
    chain_id BIGINT NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash BYTEA NOT NULL,
    block_time TIMESTAMPTZ NOT NULL,
    transaction_index INTEGER NOT NULL,
    tx_hash BYTEA NOT NULL,
    log_index INTEGER NOT NULL,
    token_address BYTEA NOT NULL,
    account BYTEA NOT NULL,
    amount NUMERIC(78,0) NOT NULL,
    CONSTRAINT refund_credits_pkey PRIMARY KEY (chain_id, tx_hash, log_index),
    CONSTRAINT refund_credits_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT refund_credits_block_number_nonnegative CHECK (block_number >= 0),
    CONSTRAINT refund_credits_block_hash_length CHECK (octet_length(block_hash) = 32),
    CONSTRAINT refund_credits_transaction_index_nonnegative CHECK (transaction_index >= 0),
    CONSTRAINT refund_credits_tx_hash_length CHECK (octet_length(tx_hash) = 32),
    CONSTRAINT refund_credits_log_index_nonnegative CHECK (log_index >= 0),
    CONSTRAINT refund_credits_token_address_length CHECK (octet_length(token_address) = 20),
    CONSTRAINT refund_credits_account_length CHECK (octet_length(account) = 20),
    CONSTRAINT refund_credits_amount_nonnegative CHECK (amount >= 0),
    CONSTRAINT refund_credits_block_fk FOREIGN KEY (chain_id, block_number, block_hash, block_time)
        REFERENCES indexed_blocks (chain_id, block_number, block_hash, block_time)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT refund_credits_token_launch_fk FOREIGN KEY (chain_id, token_address)
        REFERENCES token_launches (chain_id, token_address)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE refund_claims (
    chain_id BIGINT NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash BYTEA NOT NULL,
    block_time TIMESTAMPTZ NOT NULL,
    transaction_index INTEGER NOT NULL,
    tx_hash BYTEA NOT NULL,
    log_index INTEGER NOT NULL,
    token_address BYTEA NOT NULL,
    account BYTEA NOT NULL,
    amount NUMERIC(78,0) NOT NULL,
    CONSTRAINT refund_claims_pkey PRIMARY KEY (chain_id, tx_hash, log_index),
    CONSTRAINT refund_claims_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT refund_claims_block_number_nonnegative CHECK (block_number >= 0),
    CONSTRAINT refund_claims_block_hash_length CHECK (octet_length(block_hash) = 32),
    CONSTRAINT refund_claims_transaction_index_nonnegative CHECK (transaction_index >= 0),
    CONSTRAINT refund_claims_tx_hash_length CHECK (octet_length(tx_hash) = 32),
    CONSTRAINT refund_claims_log_index_nonnegative CHECK (log_index >= 0),
    CONSTRAINT refund_claims_token_address_length CHECK (octet_length(token_address) = 20),
    CONSTRAINT refund_claims_account_length CHECK (octet_length(account) = 20),
    CONSTRAINT refund_claims_amount_nonnegative CHECK (amount >= 0),
    CONSTRAINT refund_claims_block_fk FOREIGN KEY (chain_id, block_number, block_hash, block_time)
        REFERENCES indexed_blocks (chain_id, block_number, block_hash, block_time)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT refund_claims_token_launch_fk FOREIGN KEY (chain_id, token_address)
        REFERENCES token_launches (chain_id, token_address)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE transfers (
    chain_id BIGINT NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash BYTEA NOT NULL,
    block_time TIMESTAMPTZ NOT NULL,
    transaction_index INTEGER NOT NULL,
    tx_hash BYTEA NOT NULL,
    log_index INTEGER NOT NULL,
    token_address BYTEA NOT NULL,
    from_address BYTEA NOT NULL,
    to_address BYTEA NOT NULL,
    value NUMERIC(78,0) NOT NULL,
    CONSTRAINT transfers_pkey PRIMARY KEY (chain_id, tx_hash, log_index),
    CONSTRAINT transfers_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT transfers_block_number_nonnegative CHECK (block_number >= 0),
    CONSTRAINT transfers_block_hash_length CHECK (octet_length(block_hash) = 32),
    CONSTRAINT transfers_transaction_index_nonnegative CHECK (transaction_index >= 0),
    CONSTRAINT transfers_tx_hash_length CHECK (octet_length(tx_hash) = 32),
    CONSTRAINT transfers_log_index_nonnegative CHECK (log_index >= 0),
    CONSTRAINT transfers_token_address_length CHECK (octet_length(token_address) = 20),
    CONSTRAINT transfers_from_address_length CHECK (octet_length(from_address) = 20),
    CONSTRAINT transfers_to_address_length CHECK (octet_length(to_address) = 20),
    CONSTRAINT transfers_value_nonnegative CHECK (value >= 0),
    CONSTRAINT transfers_block_fk FOREIGN KEY (chain_id, block_number, block_hash, block_time)
        REFERENCES indexed_blocks (chain_id, block_number, block_hash, block_time)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT transfers_token_launch_fk FOREIGN KEY (chain_id, token_address)
        REFERENCES token_launches (chain_id, token_address)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE pool_mints (
    chain_id BIGINT NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash BYTEA NOT NULL,
    block_time TIMESTAMPTZ NOT NULL,
    transaction_index INTEGER NOT NULL,
    tx_hash BYTEA NOT NULL,
    log_index INTEGER NOT NULL,
    pair_address BYTEA NOT NULL,
    sender BYTEA NOT NULL,
    amount0 NUMERIC(78,0) NOT NULL,
    amount1 NUMERIC(78,0) NOT NULL,
    CONSTRAINT pool_mints_pkey PRIMARY KEY (chain_id, tx_hash, log_index),
    CONSTRAINT pool_mints_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT pool_mints_block_number_nonnegative CHECK (block_number >= 0),
    CONSTRAINT pool_mints_block_hash_length CHECK (octet_length(block_hash) = 32),
    CONSTRAINT pool_mints_transaction_index_nonnegative CHECK (transaction_index >= 0),
    CONSTRAINT pool_mints_tx_hash_length CHECK (octet_length(tx_hash) = 32),
    CONSTRAINT pool_mints_log_index_nonnegative CHECK (log_index >= 0),
    CONSTRAINT pool_mints_pair_address_length CHECK (octet_length(pair_address) = 20),
    CONSTRAINT pool_mints_sender_length CHECK (octet_length(sender) = 20),
    CONSTRAINT pool_mints_amount0_nonnegative CHECK (amount0 >= 0),
    CONSTRAINT pool_mints_amount1_nonnegative CHECK (amount1 >= 0),
    CONSTRAINT pool_mints_block_fk FOREIGN KEY (chain_id, block_number, block_hash, block_time)
        REFERENCES indexed_blocks (chain_id, block_number, block_hash, block_time)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE pool_burns (
    chain_id BIGINT NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash BYTEA NOT NULL,
    block_time TIMESTAMPTZ NOT NULL,
    transaction_index INTEGER NOT NULL,
    tx_hash BYTEA NOT NULL,
    log_index INTEGER NOT NULL,
    pair_address BYTEA NOT NULL,
    sender BYTEA NOT NULL,
    amount0 NUMERIC(78,0) NOT NULL,
    amount1 NUMERIC(78,0) NOT NULL,
    to_address BYTEA NOT NULL,
    CONSTRAINT pool_burns_pkey PRIMARY KEY (chain_id, tx_hash, log_index),
    CONSTRAINT pool_burns_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT pool_burns_block_number_nonnegative CHECK (block_number >= 0),
    CONSTRAINT pool_burns_block_hash_length CHECK (octet_length(block_hash) = 32),
    CONSTRAINT pool_burns_transaction_index_nonnegative CHECK (transaction_index >= 0),
    CONSTRAINT pool_burns_tx_hash_length CHECK (octet_length(tx_hash) = 32),
    CONSTRAINT pool_burns_log_index_nonnegative CHECK (log_index >= 0),
    CONSTRAINT pool_burns_pair_address_length CHECK (octet_length(pair_address) = 20),
    CONSTRAINT pool_burns_sender_length CHECK (octet_length(sender) = 20),
    CONSTRAINT pool_burns_amount0_nonnegative CHECK (amount0 >= 0),
    CONSTRAINT pool_burns_amount1_nonnegative CHECK (amount1 >= 0),
    CONSTRAINT pool_burns_to_address_length CHECK (octet_length(to_address) = 20),
    CONSTRAINT pool_burns_block_fk FOREIGN KEY (chain_id, block_number, block_hash, block_time)
        REFERENCES indexed_blocks (chain_id, block_number, block_hash, block_time)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE pool_swaps (
    chain_id BIGINT NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash BYTEA NOT NULL,
    block_time TIMESTAMPTZ NOT NULL,
    transaction_index INTEGER NOT NULL,
    tx_hash BYTEA NOT NULL,
    log_index INTEGER NOT NULL,
    pair_address BYTEA NOT NULL,
    sender BYTEA NOT NULL,
    amount0_in NUMERIC(78,0) NOT NULL,
    amount1_in NUMERIC(78,0) NOT NULL,
    amount0_out NUMERIC(78,0) NOT NULL,
    amount1_out NUMERIC(78,0) NOT NULL,
    to_address BYTEA NOT NULL,
    CONSTRAINT pool_swaps_pkey PRIMARY KEY (chain_id, tx_hash, log_index),
    CONSTRAINT pool_swaps_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT pool_swaps_block_number_nonnegative CHECK (block_number >= 0),
    CONSTRAINT pool_swaps_block_hash_length CHECK (octet_length(block_hash) = 32),
    CONSTRAINT pool_swaps_transaction_index_nonnegative CHECK (transaction_index >= 0),
    CONSTRAINT pool_swaps_tx_hash_length CHECK (octet_length(tx_hash) = 32),
    CONSTRAINT pool_swaps_log_index_nonnegative CHECK (log_index >= 0),
    CONSTRAINT pool_swaps_pair_address_length CHECK (octet_length(pair_address) = 20),
    CONSTRAINT pool_swaps_sender_length CHECK (octet_length(sender) = 20),
    CONSTRAINT pool_swaps_amount0_in_nonnegative CHECK (amount0_in >= 0),
    CONSTRAINT pool_swaps_amount1_in_nonnegative CHECK (amount1_in >= 0),
    CONSTRAINT pool_swaps_amount0_out_nonnegative CHECK (amount0_out >= 0),
    CONSTRAINT pool_swaps_amount1_out_nonnegative CHECK (amount1_out >= 0),
    CONSTRAINT pool_swaps_to_address_length CHECK (octet_length(to_address) = 20),
    CONSTRAINT pool_swaps_block_fk FOREIGN KEY (chain_id, block_number, block_hash, block_time)
        REFERENCES indexed_blocks (chain_id, block_number, block_hash, block_time)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX pool_swaps_reserve_lookup_idx
    ON pool_swaps (chain_id, pair_address, tx_hash, log_index);

CREATE TABLE pool_syncs (
    chain_id BIGINT NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash BYTEA NOT NULL,
    block_time TIMESTAMPTZ NOT NULL,
    transaction_index INTEGER NOT NULL,
    tx_hash BYTEA NOT NULL,
    log_index INTEGER NOT NULL,
    pair_address BYTEA NOT NULL,
    reserve0 NUMERIC(78,0) NOT NULL,
    reserve1 NUMERIC(78,0) NOT NULL,
    CONSTRAINT pool_syncs_pkey PRIMARY KEY (chain_id, tx_hash, log_index),
    CONSTRAINT pool_syncs_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT pool_syncs_block_number_nonnegative CHECK (block_number >= 0),
    CONSTRAINT pool_syncs_block_hash_length CHECK (octet_length(block_hash) = 32),
    CONSTRAINT pool_syncs_transaction_index_nonnegative CHECK (transaction_index >= 0),
    CONSTRAINT pool_syncs_tx_hash_length CHECK (octet_length(tx_hash) = 32),
    CONSTRAINT pool_syncs_log_index_nonnegative CHECK (log_index >= 0),
    CONSTRAINT pool_syncs_pair_address_length CHECK (octet_length(pair_address) = 20),
    CONSTRAINT pool_syncs_reserve0_nonnegative CHECK (reserve0 >= 0),
    CONSTRAINT pool_syncs_reserve1_nonnegative CHECK (reserve1 >= 0),
    CONSTRAINT pool_syncs_block_fk FOREIGN KEY (chain_id, block_number, block_hash, block_time)
        REFERENCES indexed_blocks (chain_id, block_number, block_hash, block_time)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX pool_syncs_reserve_lookup_idx
    ON pool_syncs (chain_id, pair_address, tx_hash, log_index);

CREATE TABLE launch_pause_events (
    chain_id BIGINT NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash BYTEA NOT NULL,
    block_time TIMESTAMPTZ NOT NULL,
    transaction_index INTEGER NOT NULL,
    tx_hash BYTEA NOT NULL,
    log_index INTEGER NOT NULL,
    paused BOOLEAN NOT NULL,
    CONSTRAINT launch_pause_events_pkey PRIMARY KEY (chain_id, tx_hash, log_index),
    CONSTRAINT launch_pause_events_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT launch_pause_events_block_number_nonnegative CHECK (block_number >= 0),
    CONSTRAINT launch_pause_events_block_hash_length CHECK (octet_length(block_hash) = 32),
    CONSTRAINT launch_pause_events_transaction_index_nonnegative CHECK (transaction_index >= 0),
    CONSTRAINT launch_pause_events_tx_hash_length CHECK (octet_length(tx_hash) = 32),
    CONSTRAINT launch_pause_events_log_index_nonnegative CHECK (log_index >= 0),
    CONSTRAINT launch_pause_events_block_fk FOREIGN KEY (chain_id, block_number, block_hash, block_time)
        REFERENCES indexed_blocks (chain_id, block_number, block_hash, block_time)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE trading_pause_events (
    chain_id BIGINT NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash BYTEA NOT NULL,
    block_time TIMESTAMPTZ NOT NULL,
    transaction_index INTEGER NOT NULL,
    tx_hash BYTEA NOT NULL,
    log_index INTEGER NOT NULL,
    paused BOOLEAN NOT NULL,
    CONSTRAINT trading_pause_events_pkey PRIMARY KEY (chain_id, tx_hash, log_index),
    CONSTRAINT trading_pause_events_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT trading_pause_events_block_number_nonnegative CHECK (block_number >= 0),
    CONSTRAINT trading_pause_events_block_hash_length CHECK (octet_length(block_hash) = 32),
    CONSTRAINT trading_pause_events_transaction_index_nonnegative CHECK (transaction_index >= 0),
    CONSTRAINT trading_pause_events_tx_hash_length CHECK (octet_length(tx_hash) = 32),
    CONSTRAINT trading_pause_events_log_index_nonnegative CHECK (log_index >= 0),
    CONSTRAINT trading_pause_events_block_fk FOREIGN KEY (chain_id, block_number, block_hash, block_time)
        REFERENCES indexed_blocks (chain_id, block_number, block_hash, block_time)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE engine_configurations (
    chain_id BIGINT NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash BYTEA NOT NULL,
    block_time TIMESTAMPTZ NOT NULL,
    transaction_index INTEGER NOT NULL,
    tx_hash BYTEA NOT NULL,
    log_index INTEGER NOT NULL,
    engine_version INTEGER NOT NULL,
    implementation BYTEA NOT NULL,
    enabled BOOLEAN NOT NULL,
    CONSTRAINT engine_configurations_pkey PRIMARY KEY (chain_id, tx_hash, log_index),
    CONSTRAINT engine_configurations_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT engine_configurations_block_number_nonnegative CHECK (block_number >= 0),
    CONSTRAINT engine_configurations_block_hash_length CHECK (octet_length(block_hash) = 32),
    CONSTRAINT engine_configurations_transaction_index_nonnegative CHECK (transaction_index >= 0),
    CONSTRAINT engine_configurations_tx_hash_length CHECK (octet_length(tx_hash) = 32),
    CONSTRAINT engine_configurations_log_index_nonnegative CHECK (log_index >= 0),
    CONSTRAINT engine_configurations_engine_version_uint16 CHECK (engine_version BETWEEN 0 AND 65535),
    CONSTRAINT engine_configurations_implementation_length CHECK (octet_length(implementation) = 20),
    CONSTRAINT engine_configurations_block_fk FOREIGN KEY (chain_id, block_number, block_hash, block_time)
        REFERENCES indexed_blocks (chain_id, block_number, block_hash, block_time)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE future_defaults_configurations (
    chain_id BIGINT NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash BYTEA NOT NULL,
    block_time TIMESTAMPTZ NOT NULL,
    transaction_index INTEGER NOT NULL,
    tx_hash BYTEA NOT NULL,
    log_index INTEGER NOT NULL,
    config_hash BYTEA NOT NULL,
    CONSTRAINT future_defaults_configurations_pkey PRIMARY KEY (chain_id, tx_hash, log_index),
    CONSTRAINT future_defaults_configurations_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT future_defaults_configurations_block_number_nonnegative CHECK (block_number >= 0),
    CONSTRAINT future_defaults_configurations_block_hash_length CHECK (octet_length(block_hash) = 32),
    CONSTRAINT future_defaults_configurations_transaction_index_nonnegative CHECK (transaction_index >= 0),
    CONSTRAINT future_defaults_configurations_tx_hash_length CHECK (octet_length(tx_hash) = 32),
    CONSTRAINT future_defaults_configurations_log_index_nonnegative CHECK (log_index >= 0),
    CONSTRAINT future_defaults_configurations_config_hash_length CHECK (octet_length(config_hash) = 32),
    CONSTRAINT future_defaults_configurations_block_fk FOREIGN KEY (chain_id, block_number, block_hash, block_time)
        REFERENCES indexed_blocks (chain_id, block_number, block_hash, block_time)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE future_treasury_configurations (
    chain_id BIGINT NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash BYTEA NOT NULL,
    block_time TIMESTAMPTZ NOT NULL,
    transaction_index INTEGER NOT NULL,
    tx_hash BYTEA NOT NULL,
    log_index INTEGER NOT NULL,
    previous_treasury BYTEA NOT NULL,
    new_treasury BYTEA NOT NULL,
    CONSTRAINT future_treasury_configurations_pkey PRIMARY KEY (chain_id, tx_hash, log_index),
    CONSTRAINT future_treasury_configurations_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT future_treasury_configurations_block_number_nonnegative CHECK (block_number >= 0),
    CONSTRAINT future_treasury_configurations_block_hash_length CHECK (octet_length(block_hash) = 32),
    CONSTRAINT future_treasury_configurations_transaction_index_nonnegative CHECK (transaction_index >= 0),
    CONSTRAINT future_treasury_configurations_tx_hash_length CHECK (octet_length(tx_hash) = 32),
    CONSTRAINT future_treasury_configurations_log_index_nonnegative CHECK (log_index >= 0),
    CONSTRAINT future_treasury_configurations_previous_treasury_length CHECK (octet_length(previous_treasury) = 20),
    CONSTRAINT future_treasury_configurations_new_treasury_length CHECK (octet_length(new_treasury) = 20),
    CONSTRAINT future_treasury_configurations_block_fk FOREIGN KEY (chain_id, block_number, block_hash, block_time)
        REFERENCES indexed_blocks (chain_id, block_number, block_hash, block_time)
        DEFERRABLE INITIALLY DEFERRED
);

-- +goose StatementBegin
CREATE FUNCTION trades_reject_after_graduation() RETURNS trigger AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.graduations
        WHERE graduations.chain_id = NEW.chain_id
          AND graduations.token_address = NEW.token_address
          AND graduations.block_number < NEW.block_number
    ) THEN
        RAISE EXCEPTION
            'trade (chain_id=%, token=%, block=%) occurs after graduation',
            NEW.chain_id, NEW.token_address, NEW.block_number;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = pg_catalog;
-- +goose StatementEnd

CREATE CONSTRAINT TRIGGER trades_reject_after_graduation_trigger
    AFTER INSERT OR UPDATE ON trades
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION trades_reject_after_graduation();

-- +goose StatementBegin
CREATE FUNCTION graduations_reject_before_later_trade() RETURNS trigger AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.trades
        WHERE trades.chain_id = NEW.chain_id
          AND trades.token_address = NEW.token_address
          AND trades.block_number > NEW.block_number
    ) THEN
        RAISE EXCEPTION
            'graduation (chain_id=%, token=%, block=%) precedes an existing later trade',
            NEW.chain_id, NEW.token_address, NEW.block_number;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = pg_catalog;
-- +goose StatementEnd

CREATE CONSTRAINT TRIGGER graduations_reject_before_later_trade_trigger
    AFTER INSERT OR UPDATE ON graduations
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION graduations_reject_before_later_trade();

-- +goose Down
DROP TRIGGER graduations_reject_before_later_trade_trigger ON graduations;
DROP FUNCTION graduations_reject_before_later_trade();
DROP TRIGGER trades_reject_after_graduation_trigger ON trades;
DROP FUNCTION trades_reject_after_graduation();

DROP TABLE future_treasury_configurations;
DROP TABLE future_defaults_configurations;
DROP TABLE engine_configurations;
DROP TABLE trading_pause_events;
DROP TABLE launch_pause_events;
DROP TABLE pool_syncs;
DROP TABLE pool_swaps;
DROP TABLE pool_burns;
DROP TABLE pool_mints;
DROP TABLE transfers;
DROP TABLE refund_claims;
DROP TABLE refund_credits;
DROP TABLE launch_fee_claims;
DROP TABLE protocol_fee_claims;
DROP TABLE creator_fee_claims;
DROP TABLE graduations;
DROP TABLE trades;
DROP TABLE token_launches;

ALTER TABLE indexed_blocks
    DROP CONSTRAINT indexed_blocks_event_coordinates_key;
