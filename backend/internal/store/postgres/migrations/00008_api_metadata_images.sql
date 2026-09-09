-- +goose Up
ALTER TABLE token_metadata ADD COLUMN revision BIGINT NOT NULL DEFAULT 0;
ALTER TABLE token_metadata ADD CONSTRAINT token_metadata_revision_nonnegative CHECK (revision >= 0);

CREATE TABLE token_images (
    chain_id BIGINT NOT NULL,
    token_address BYTEA NOT NULL,
    content_type TEXT NOT NULL,
    content BYTEA NOT NULL,
    byte_size INTEGER NOT NULL,
    sha256 BYTEA NOT NULL,
    revision BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT token_images_pkey PRIMARY KEY (chain_id, token_address),
    CONSTRAINT token_images_chain_id_positive CHECK (chain_id > 0),
    CONSTRAINT token_images_token_address_length CHECK (octet_length(token_address) = 20),
    CONSTRAINT token_images_content_type_valid CHECK (content_type IN ('image/png', 'image/jpeg', 'image/webp')),
    CONSTRAINT token_images_byte_size_valid CHECK (byte_size > 0 AND byte_size <= 5242880),
    CONSTRAINT token_images_sha256_length CHECK (octet_length(sha256) = 32),
    CONSTRAINT token_images_revision_nonnegative CHECK (revision >= 0),
    CONSTRAINT token_images_token_fk FOREIGN KEY (chain_id, token_address)
        REFERENCES token_launches (chain_id, token_address) DEFERRABLE INITIALLY DEFERRED
);

-- +goose Down
DROP TABLE token_images;
ALTER TABLE token_metadata DROP CONSTRAINT token_metadata_revision_nonnegative;
ALTER TABLE token_metadata DROP COLUMN revision;
