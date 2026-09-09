package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/Contictus/launchtap/backend/internal/pagination"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ReadSnapshot is the immutable identity attached to every collection response.
type ReadSnapshot struct {
	Identity pagination.Snapshot
	State    SyncState
}

// WithReadSnapshot executes readFn in one read-only REPEATABLE READ transaction.
// The transaction is always rolled back: this helper is a read boundary and
// therefore cannot commit after a cancelled handler or a successful read.
func WithReadSnapshot(ctx context.Context, pool *pgxpool.Pool, chainID int64, deploymentID string, readFn func(context.Context, *Adapter, ReadSnapshot) error) error {
	if pool == nil || readFn == nil {
		return errors.New("read snapshot requires pool and callback")
	}
	tx, err := pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return fmt.Errorf("begin read snapshot: %w", err)
	}
	defer func() { _ = rollbackTx(tx) }()

	adapter := NewAdapter(tx)
	state, err := adapter.GetSyncState(ctx, chainID, deploymentID)
	if err != nil {
		return fmt.Errorf("read snapshot watermark: %w", err)
	}
	identity, err := observedIdentity(state)
	if err != nil {
		return err
	}
	if err := readFn(ctx, adapter, ReadSnapshot{Identity: identity, State: state}); err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	return nil
}

func observedIdentity(state SyncState) (pagination.Snapshot, error) {
	if !state.ObservedNumber.Valid || state.ObservedNumber.Int64 < 0 || state.ObservedHash == nil {
		return pagination.Snapshot{}, errors.New("snapshot has no observed canonical block")
	}
	return pagination.Snapshot{ChainID: state.ChainID, BlockNumber: state.ObservedNumber.Int64, BlockHash: [32]byte(*state.ObservedHash)}, nil
}
