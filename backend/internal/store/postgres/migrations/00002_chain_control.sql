-- +goose Up
CREATE TABLE sync_state (
    chain_id BIGINT NOT NULL,
    deployment_id TEXT NOT NULL,
    observed_number BIGINT,
    observed_hash BYTEA,
    observed_at TIMESTAMPTZ,
    safe_number BIGINT,
    safe_hash BYTEA,
    safe_at TIMESTAMPTZ,
    finalized_number BIGINT,
    finalized_hash BYTEA,
    finalized_at TIMESTAMPTZ,
    CONSTRAINT sync_state_pkey PRIMARY KEY (chain_id, deployment_id),
    CONSTRAINT sync_state_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT sync_state_deployment_id_format CHECK (
        deployment_id ~ '^[a-z0-9][a-z0-9._-]{2,63}$'
    ),
    CONSTRAINT sync_state_observed_number_nonnegative CHECK (observed_number >= 0),
    CONSTRAINT sync_state_safe_number_nonnegative CHECK (safe_number >= 0),
    CONSTRAINT sync_state_finalized_number_nonnegative CHECK (finalized_number >= 0),
    CONSTRAINT sync_state_observed_hash_length CHECK (
        observed_hash IS NULL OR octet_length(observed_hash) = 32
    ),
    CONSTRAINT sync_state_safe_hash_length CHECK (
        safe_hash IS NULL OR octet_length(safe_hash) = 32
    ),
    CONSTRAINT sync_state_finalized_hash_length CHECK (
        finalized_hash IS NULL OR octet_length(finalized_hash) = 32
    ),
    CONSTRAINT sync_state_observed_complete CHECK (
        (observed_number IS NULL) = (observed_hash IS NULL)
        AND (observed_number IS NULL) = (observed_at IS NULL)
    ),
    CONSTRAINT sync_state_safe_complete CHECK (
        (safe_number IS NULL) = (safe_hash IS NULL)
        AND (safe_number IS NULL) = (safe_at IS NULL)
    ),
    CONSTRAINT sync_state_finalized_complete CHECK (
        (finalized_number IS NULL) = (finalized_hash IS NULL)
        AND (finalized_number IS NULL) = (finalized_at IS NULL)
    ),
    CONSTRAINT sync_state_safe_not_ahead CHECK (
        safe_number IS NULL
        OR (observed_number IS NOT NULL AND safe_number <= observed_number)
    ),
    CONSTRAINT sync_state_finalized_not_ahead CHECK (
        finalized_number IS NULL
        OR (safe_number IS NOT NULL AND finalized_number <= safe_number)
    )
);

CREATE TABLE indexed_blocks (
    chain_id BIGINT NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash BYTEA NOT NULL,
    parent_hash BYTEA NOT NULL,
    block_time TIMESTAMPTZ NOT NULL,
    finality_status TEXT NOT NULL,
    CONSTRAINT indexed_blocks_pkey PRIMARY KEY (chain_id, block_number),
    CONSTRAINT indexed_blocks_block_hash_key UNIQUE (chain_id, block_hash),
    CONSTRAINT indexed_blocks_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT indexed_blocks_block_number_nonnegative CHECK (block_number >= 0),
    CONSTRAINT indexed_blocks_block_hash_length CHECK (octet_length(block_hash) = 32),
    CONSTRAINT indexed_blocks_parent_hash_length CHECK (octet_length(parent_hash) = 32),
    CONSTRAINT indexed_blocks_finality_status_valid CHECK (
        finality_status IN ('observed', 'safe', 'finalized')
    )
);

-- +goose StatementBegin
CREATE FUNCTION indexed_blocks_immutable_identity() RETURNS trigger AS $$
BEGIN
    IF NEW.block_hash IS DISTINCT FROM OLD.block_hash
       OR NEW.parent_hash IS DISTINCT FROM OLD.parent_hash
       OR NEW.block_time IS DISTINCT FROM OLD.block_time THEN
        RAISE EXCEPTION
            'indexed_blocks block identity is immutable for (chain_id=%, block_number=%); delete and reinsert instead',
            OLD.chain_id, OLD.block_number;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = pg_catalog;
-- +goose StatementEnd

CREATE TRIGGER indexed_blocks_immutable_identity_trigger
    BEFORE UPDATE ON indexed_blocks
    FOR EACH ROW EXECUTE FUNCTION indexed_blocks_immutable_identity();

-- +goose Down
DROP TRIGGER indexed_blocks_immutable_identity_trigger ON indexed_blocks;
DROP FUNCTION indexed_blocks_immutable_identity();
DROP TABLE indexed_blocks;
DROP TABLE sync_state;
