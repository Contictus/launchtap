-- +goose Up
ALTER TABLE token_images DROP CONSTRAINT token_images_token_fk;

-- Images are creator-controlled off-chain state. Like token_metadata, they
-- survive removal and replay of the canonical launch that originally
-- authorized the write.

-- +goose Down
ALTER TABLE token_images ADD CONSTRAINT token_images_token_fk
    FOREIGN KEY (chain_id, token_address)
    REFERENCES token_launches (chain_id, token_address)
    DEFERRABLE INITIALLY DEFERRED;
