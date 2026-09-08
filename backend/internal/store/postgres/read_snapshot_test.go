package postgres

import (
	"testing"

	"github.com/Contictus/launchtap/backend/internal/pagination"
	"github.com/jackc/pgx/v5/pgtype"
)

func TestObservedIdentityRequiresCanonicalWatermark(t *testing.T) {
	_, err := observedIdentity(SyncState{ChainID: 1, ObservedNumber: pgtype.Int8{Valid: true, Int64: 2}})
	if err == nil {
		t.Fatal("expected missing hash error")
	}
	var hash Hash
	identity, err := observedIdentity(SyncState{ChainID: 1, ObservedNumber: pgtype.Int8{Valid: true, Int64: 2}, ObservedHash: &hash})
	if err != nil {
		t.Fatal(err)
	}
	if identity != (pagination.Snapshot{ChainID: 1, BlockNumber: 2}) {
		t.Fatalf("unexpected identity: %#v", identity)
	}
	if _, err := observedIdentity(SyncState{ChainID: 1, ObservedNumber: pgtype.Int8{Valid: true, Int64: -1}, ObservedHash: &hash}); err == nil {
		t.Fatal("negative watermark accepted")
	}
}
