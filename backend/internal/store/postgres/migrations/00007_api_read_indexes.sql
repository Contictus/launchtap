-- +goose Up
CREATE INDEX tokens_phase_launch_cursor_idx
    ON tokens (chain_id, phase, launch_block_number DESC, token_address DESC);
CREATE INDEX tokens_name_prefix_idx
    ON tokens (chain_id, lower(name) text_pattern_ops, token_address);
CREATE INDEX tokens_symbol_prefix_idx
    ON tokens (chain_id, lower(symbol) text_pattern_ops, token_address);
CREATE INDEX token_stats_market_cap_cursor_idx
    ON token_stats (chain_id, market_cap_eth_wad DESC, token_address DESC);
CREATE INDEX token_stats_volume_cursor_idx
    ON token_stats (chain_id, volume_24h_eth_wad DESC, token_address DESC);

-- +goose Down
DROP INDEX token_stats_volume_cursor_idx;
DROP INDEX token_stats_market_cap_cursor_idx;
DROP INDEX tokens_symbol_prefix_idx;
DROP INDEX tokens_name_prefix_idx;
DROP INDEX tokens_phase_launch_cursor_idx;
