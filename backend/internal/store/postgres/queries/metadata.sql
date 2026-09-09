-- name: GetTokenCreatorForUpdate :one
SELECT creator
FROM token_launches
WHERE chain_id = sqlc.arg(chain_id) AND token_address = sqlc.arg(token_address)
FOR SHARE;

-- name: GetTokenImage :one
SELECT content_type, content, sha256, revision, updated_at
FROM token_images
WHERE chain_id = sqlc.arg(chain_id) AND token_address = sqlc.arg(token_address);

-- name: ReplaceTokenMetadata :one
INSERT INTO token_metadata (chain_id, token_address, description, image_url, x_url, telegram_url, revision, updated_at)
SELECT sqlc.arg(chain_id), sqlc.arg(token_address), sqlc.arg(description), sqlc.arg(image_url),
       sqlc.arg(x_url), sqlc.arg(telegram_url), 0, sqlc.arg(updated_at)
FROM token_launches
WHERE chain_id = sqlc.arg(chain_id) AND token_address = sqlc.arg(token_address)
  AND creator = sqlc.arg(creator) AND sqlc.arg(expected_revision)::bigint = 0
ON CONFLICT (chain_id, token_address) DO UPDATE
SET description = EXCLUDED.description, image_url = EXCLUDED.image_url,
    x_url = EXCLUDED.x_url, telegram_url = EXCLUDED.telegram_url,
    revision = token_metadata.revision + 1, updated_at = EXCLUDED.updated_at
WHERE token_metadata.revision = sqlc.arg(expected_revision)
RETURNING revision;

-- name: ReplaceTokenImage :one
INSERT INTO token_images (chain_id, token_address, content_type, content, byte_size, sha256, revision, updated_at)
SELECT sqlc.arg(chain_id), sqlc.arg(token_address), sqlc.arg(content_type), sqlc.arg(content),
       sqlc.arg(byte_size), sqlc.arg(sha256), 0, sqlc.arg(updated_at)
FROM token_launches
WHERE chain_id = sqlc.arg(chain_id) AND token_address = sqlc.arg(token_address)
  AND creator = sqlc.arg(creator) AND sqlc.arg(expected_revision)::bigint = 0
ON CONFLICT (chain_id, token_address) DO UPDATE
SET content_type = EXCLUDED.content_type, content = EXCLUDED.content,
    byte_size = EXCLUDED.byte_size, sha256 = EXCLUDED.sha256,
    revision = token_images.revision + 1, updated_at = EXCLUDED.updated_at
WHERE token_images.revision = sqlc.arg(expected_revision)
RETURNING revision;
