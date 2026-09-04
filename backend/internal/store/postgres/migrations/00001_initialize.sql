-- +goose Up
-- Task 4 establishes the embedded migration pipeline without creating product tables.
-- Task 5 owns the first product schema. Goose still records this baseline version.
SELECT current_database();

-- +goose Down
SELECT current_database();
