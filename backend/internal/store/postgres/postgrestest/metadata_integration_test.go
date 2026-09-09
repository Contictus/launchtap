//go:build integration

package postgrestest

import (
	"context"
	"crypto/sha256"
	"errors"
	"testing"
	"time"

	"github.com/Contictus/launchtap/backend/internal/metadata"
	storepostgres "github.com/Contictus/launchtap/backend/internal/store/postgres"
	"github.com/ethereum/go-ethereum/common"
)

func TestMetadataAndImagesAuthorizeAndUseRevisionsAtomically(t *testing.T) {
	database := NewMigrated(t)
	ctx, cancel := context.WithTimeout(t.Context(), 30*time.Second)
	defer cancel()
	pool, err := storepostgres.OpenPool(ctx, database.URL, storepostgres.PoolOptions{})
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	const chainID int64 = 46630
	at := time.Date(2026, 9, 9, 12, 0, 0, 0, time.UTC)
	blockHash, tokenBytes := hashBytes(0x81), addressBytes(0x82)
	mustInsertBlock(t, ctx, database.DB, chainID, 10, blockHash, hashBytes(0x80), at, "safe")
	insertProjectionLaunch(t, ctx, database.DB, chainID, 10, blockHash, at, hashBytes(0x83), projectionLaunchFixture{token: tokenBytes, curve: addressBytes(0x84), pair: addressBytes(0x85), weth: addressBytes(0x86)})
	if _, err := database.DB.ExecContext(ctx, `SELECT rebuild_token_projections($1,$2)`, chainID, tokenBytes); err != nil {
		t.Fatal(err)
	}
	store := storepostgres.MetadataStore{Pool: pool, DeploymentID: "metadata-test"}
	tokenAddress := common.BytesToAddress(tokenBytes)
	creator := common.BytesToAddress(addressBytes(0x55))

	if _, err := store.ReplaceMetadata(ctx, chainID, tokenAddress, []common.Address{common.HexToAddress("0x01")}, metadata.Metadata{Revision: 0, UpdatedAt: at}); !errors.Is(err, metadata.ErrUnauthorized) {
		t.Fatalf("unauthorized error=%v", err)
	}
	revision, err := store.ReplaceMetadata(ctx, chainID, tokenAddress, []common.Address{creator}, metadata.Metadata{Description: "first", Revision: 0, UpdatedAt: at})
	if err != nil || revision != 0 {
		t.Fatalf("create metadata revision=%d error=%v", revision, err)
	}
	revision, err = store.ReplaceMetadata(ctx, chainID, tokenAddress, []common.Address{creator}, metadata.Metadata{Description: "second", Revision: 0, UpdatedAt: at.Add(time.Second)})
	if err != nil || revision != 1 {
		t.Fatalf("replace metadata revision=%d error=%v", revision, err)
	}
	if _, err := store.ReplaceMetadata(ctx, chainID, tokenAddress, []common.Address{creator}, metadata.Metadata{Revision: 0, UpdatedAt: at}); !errors.Is(err, metadata.ErrRevisionConflict) {
		t.Fatalf("stale metadata error=%v", err)
	}

	content := []byte("\x89PNG\r\n\x1a\nfixture")
	hash := sha256.Sum256(content)
	revision, err = store.ReplaceImage(ctx, chainID, tokenAddress, []common.Address{creator}, metadata.Image{ContentType: "image/png", Content: content, SHA256: hash, Revision: 0, UpdatedAt: at})
	if err != nil || revision != 0 {
		t.Fatalf("create image revision=%d error=%v", revision, err)
	}
	image, err := store.GetImage(ctx, chainID, tokenAddress)
	if err != nil || image.SHA256 != hash || image.ContentType != "image/png" {
		t.Fatalf("image=%+v error=%v", image, err)
	}

	// Off-chain creator content must not block or disappear during canonical rollback.
	for _, table := range []string{"aggregation_dirty", "token_reserves", "holder_balances", "candles", "token_stats", "tokens"} {
		if _, err := database.DB.ExecContext(ctx, `DELETE FROM `+table+` WHERE chain_id=$1 AND token_address=$2`, chainID, tokenBytes); err != nil {
			t.Fatalf("delete %s projection with image: %v", table, err)
		}
	}
	if _, err := database.DB.ExecContext(ctx, `DELETE FROM token_launches WHERE chain_id=$1 AND token_address=$2`, chainID, tokenBytes); err != nil {
		t.Fatalf("delete launch with image: %v", err)
	}
	if _, err := store.GetImage(ctx, chainID, tokenAddress); err != nil {
		t.Fatalf("image did not survive rollback: %v", err)
	}
	if _, err := store.ReplaceImage(ctx, chainID, tokenAddress, []common.Address{creator}, metadata.Image{ContentType: "image/png", Content: content, SHA256: hash, Revision: 0, UpdatedAt: at}); !errors.Is(err, metadata.ErrNotFound) {
		t.Fatalf("orphan image write error=%v", err)
	}
}
