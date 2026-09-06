-- +goose Up
CREATE TABLE indexer_reorgs (
    reorg_id BIGSERIAL PRIMARY KEY,
    chain_id BIGINT NOT NULL CHECK (chain_id > 0),
    deployment_id TEXT NOT NULL,
    detected_tip_number BIGINT NOT NULL CHECK (detected_tip_number >= 0),
    detected_tip_hash BYTEA NOT NULL CHECK (octet_length(detected_tip_hash) = 32),
    common_ancestor_number BIGINT NOT NULL CHECK (common_ancestor_number >= 0),
    common_ancestor_hash BYTEA NOT NULL CHECK (octet_length(common_ancestor_hash) = 32),
    depth BIGINT NOT NULL CHECK (depth > 0),
    detected_at TIMESTAMPTZ NOT NULL,
    outcome TEXT NOT NULL CHECK (outcome IN ('open','recovered')),
    completed_at TIMESTAMPTZ
);
CREATE INDEX indexer_reorgs_open_idx ON indexer_reorgs(chain_id, deployment_id) WHERE outcome='open';

-- +goose Down
DROP TABLE indexer_reorgs;
