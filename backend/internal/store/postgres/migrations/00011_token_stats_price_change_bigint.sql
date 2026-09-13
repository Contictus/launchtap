-- +goose Up
ALTER TABLE token_stats
    ALTER COLUMN price_change_24h_bps TYPE BIGINT
    USING price_change_24h_bps::BIGINT;

ALTER TABLE token_stats
    ADD CONSTRAINT token_stats_price_change_24h_bps_js_safe_range
    CHECK (price_change_24h_bps BETWEEN -9007199254740991 AND 9007199254740991);

-- +goose Down
ALTER TABLE token_stats
    DROP CONSTRAINT token_stats_price_change_24h_bps_js_safe_range;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM token_stats
        WHERE price_change_24h_bps < -2147483648
           OR price_change_24h_bps > 2147483647
    ) THEN
        RAISE EXCEPTION 'cannot narrow token_stats.price_change_24h_bps to INTEGER: values outside signed 32-bit range exist';
    END IF;
END $$;

ALTER TABLE token_stats
    ALTER COLUMN price_change_24h_bps TYPE INTEGER
    USING price_change_24h_bps::INTEGER;
