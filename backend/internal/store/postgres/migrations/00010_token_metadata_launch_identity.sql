-- +goose Up
ALTER TABLE token_metadata
    DROP CONSTRAINT token_metadata_pkey,
    ADD COLUMN content_id BIGINT GENERATED ALWAYS AS IDENTITY,
    ADD COLUMN launch_tx_hash BYTEA,
    ADD COLUMN launch_log_index INTEGER,
    ADD CONSTRAINT token_metadata_launch_tx_hash_length CHECK (octet_length(launch_tx_hash) = 32),
    ADD CONSTRAINT token_metadata_launch_log_index_nonnegative CHECK (launch_log_index >= 0),
    ADD CONSTRAINT token_metadata_launch_identity_pair CHECK ((launch_tx_hash IS NULL) = (launch_log_index IS NULL)),
    ADD CONSTRAINT token_metadata_pkey PRIMARY KEY (content_id);

-- The v9 address-only rows cannot be reliably assigned to a launch: a row may
-- survive a reorg and an address can later be reused. Keep those rows unbound
-- and hidden from canonical reads; new writes carry explicit launch identity.
CREATE UNIQUE INDEX token_metadata_launch_identity_key
    ON token_metadata (chain_id, token_address, launch_tx_hash, launch_log_index)
    WHERE launch_tx_hash IS NOT NULL AND launch_log_index IS NOT NULL;

ALTER TABLE token_images
    DROP CONSTRAINT token_images_pkey,
    ADD COLUMN content_id BIGINT GENERATED ALWAYS AS IDENTITY,
    ADD COLUMN launch_tx_hash BYTEA,
    ADD COLUMN launch_log_index INTEGER,
    ADD CONSTRAINT token_images_launch_tx_hash_length CHECK (octet_length(launch_tx_hash) = 32),
    ADD CONSTRAINT token_images_launch_log_index_nonnegative CHECK (launch_log_index >= 0),
    ADD CONSTRAINT token_images_launch_identity_pair CHECK ((launch_tx_hash IS NULL) = (launch_log_index IS NULL)),
    ADD CONSTRAINT token_images_pkey PRIMARY KEY (content_id);

CREATE UNIQUE INDEX token_images_launch_identity_key
    ON token_images (chain_id, token_address, launch_tx_hash, launch_log_index)
    WHERE launch_tx_hash IS NOT NULL AND launch_log_index IS NOT NULL;

-- +goose Down
-- +goose StatementBegin
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM token_metadata
        GROUP BY chain_id, token_address
        HAVING count(*) > 1
    ) OR EXISTS (
        SELECT 1
        FROM token_images
        GROUP BY chain_id, token_address
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'cannot restore address-only metadata keys while multiple metadata or image rows exist for one token address';
    END IF;
END $$;
-- +goose StatementEnd

DROP INDEX token_metadata_launch_identity_key;
ALTER TABLE token_metadata
    DROP CONSTRAINT token_metadata_pkey,
    DROP CONSTRAINT token_metadata_launch_identity_pair,
    DROP CONSTRAINT token_metadata_launch_tx_hash_length,
    DROP CONSTRAINT token_metadata_launch_log_index_nonnegative,
    DROP COLUMN content_id,
    DROP COLUMN launch_tx_hash,
    DROP COLUMN launch_log_index,
    ADD CONSTRAINT token_metadata_pkey PRIMARY KEY (chain_id, token_address);

DROP INDEX token_images_launch_identity_key;
ALTER TABLE token_images
    DROP CONSTRAINT token_images_pkey,
    DROP CONSTRAINT token_images_launch_identity_pair,
    DROP CONSTRAINT token_images_launch_tx_hash_length,
    DROP CONSTRAINT token_images_launch_log_index_nonnegative,
    DROP COLUMN content_id,
    DROP COLUMN launch_tx_hash,
    DROP COLUMN launch_log_index,
    ADD CONSTRAINT token_images_pkey PRIMARY KEY (chain_id, token_address);
