package postgres

import (
	"errors"
	"testing"
	"time"

	"github.com/Contictus/launchtap/backend/internal/pagination"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

func TestObservedIdentityRequiresCanonicalWatermark(t *testing.T) {
	var hash Hash
	observedTime := pgtype.Timestamptz{Time: time.Unix(1, 0).UTC(), Valid: true}
	tests := []struct {
		name            string
		number          pgtype.Int8
		hash            *Hash
		at              pgtype.Timestamptz
		wantUnavailable bool
		wantValid       bool
	}{
		{name: "all observed fields absent", wantUnavailable: true},
		{name: "number only", number: pgtype.Int8{Valid: true, Int64: 2}},
		{name: "hash only", hash: &hash},
		{name: "timestamp only", at: observedTime},
		{name: "number and hash", number: pgtype.Int8{Valid: true, Int64: 2}, hash: &hash},
		{name: "number and timestamp", number: pgtype.Int8{Valid: true, Int64: 2}, at: observedTime},
		{name: "hash and timestamp", hash: &hash, at: observedTime},
		{
			name: "complete watermark", number: pgtype.Int8{Valid: true, Int64: 2},
			hash: &hash, at: observedTime, wantValid: true,
		},
		{
			name: "negative block number", number: pgtype.Int8{Valid: true, Int64: -1},
			hash: &hash, at: observedTime,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			identity, err := observedIdentity(SyncState{
				ChainID: 1, ObservedNumber: tt.number,
				ObservedHash: tt.hash, ObservedAt: tt.at,
			})
			if tt.wantValid {
				if err != nil {
					t.Fatal(err)
				}
				if identity != (pagination.Snapshot{ChainID: 1, BlockNumber: 2}) {
					t.Fatalf("unexpected identity: %#v", identity)
				}
				return
			}
			if err == nil {
				t.Fatal("incomplete or invalid watermark was accepted")
			}
			if got := errors.Is(err, pagination.ErrSnapshotUnavailable); got != tt.wantUnavailable {
				t.Fatalf("unavailable classification=%t, want %t (error=%v)", got, tt.wantUnavailable, err)
			}
		})
	}
}

func TestReadSnapshotWatermarkErrorClassifiesUninitializedState(t *testing.T) {
	err := readSnapshotWatermarkError(pgx.ErrNoRows)
	if !errors.Is(err, pagination.ErrSnapshotUnavailable) {
		t.Fatalf("missing sync state error=%v, want ErrSnapshotUnavailable", err)
	}
	invariantErr := errors.New("unexpected database failure")
	err = readSnapshotWatermarkError(invariantErr)
	if err == nil || errors.Is(err, pagination.ErrSnapshotUnavailable) || !errors.Is(err, invariantErr) {
		t.Fatalf("unexpected database error=%v, want wrapped invariant error", err)
	}
}
