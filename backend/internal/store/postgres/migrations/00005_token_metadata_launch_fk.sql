-- +goose Up
ALTER TABLE token_metadata DROP CONSTRAINT token_metadata_token_launch_fk;

-- +goose Down
-- Refuse downgrade while orphan metadata exists; never discard creator content.
ALTER TABLE token_metadata ADD CONSTRAINT token_metadata_token_launch_fk
    FOREIGN KEY (chain_id, token_address)
    REFERENCES token_launches (chain_id, token_address)
    DEFERRABLE INITIALLY DEFERRED;
