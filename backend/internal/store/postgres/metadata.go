package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/Contictus/launchtap/backend/internal/store/postgres/sqlc"
	"github.com/ethereum/go-ethereum/common"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

var (
	ErrWriteUnauthorized = errors.New("creator is not authorized")
	ErrRevisionConflict  = errors.New("metadata or image revision conflict")
)

func (adapter *Adapter) ReplaceTokenMetadata(ctx context.Context, chainID int64, token, creator common.Address, description, imageURL, xURL, telegramURL string, expectedRevision int64, now time.Time) (int64, error) {
	revision, err := adapter.queries.ReplaceTokenMetadata(ctx, sqlc.ReplaceTokenMetadataParams{
		ChainID: chainID, TokenAddress: sqlc.Address(token), Creator: sqlc.Address(creator),
		Description: pgtype.Text{String: description, Valid: description != ""}, ImageUrl: pgtype.Text{String: imageURL, Valid: imageURL != ""},
		XUrl: pgtype.Text{String: xURL, Valid: xURL != ""}, TelegramUrl: pgtype.Text{String: telegramURL, Valid: telegramURL != ""},
		ExpectedRevision: expectedRevision, UpdatedAt: pgtype.Timestamptz{Time: now, Valid: true},
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, fmt.Errorf("%w: metadata", ErrRevisionConflict)
	}
	if err != nil {
		return 0, fmt.Errorf("replace token metadata: %w", err)
	}
	return revision, nil
}

func (adapter *Adapter) ReplaceTokenImage(ctx context.Context, chainID int64, token, creator common.Address, contentType string, content, sha256 []byte, expectedRevision int64, now time.Time) (int64, error) {
	revision, err := adapter.queries.ReplaceTokenImage(ctx, sqlc.ReplaceTokenImageParams{
		ChainID: chainID, TokenAddress: sqlc.Address(token), Creator: sqlc.Address(creator), ContentType: contentType,
		Content: content, ByteSize: int32(len(content)), Sha256: sha256, ExpectedRevision: expectedRevision,
		UpdatedAt: pgtype.Timestamptz{Time: now, Valid: true},
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, fmt.Errorf("%w: image", ErrRevisionConflict)
	}
	if err != nil {
		return 0, fmt.Errorf("replace token image: %w", err)
	}
	return revision, nil
}
