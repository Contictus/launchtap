package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/Contictus/launchtap/backend/internal/indexer"
	"github.com/Contictus/launchtap/backend/internal/ledger"
	"github.com/ethereum/go-ethereum/common"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

// IndexerStore is the application bridge between the neutral indexer ports and
// the PostgreSQL adapter. It is kept here so generated types never escape.
type IndexerStore struct {
	Pool     *pgxpool.Pool
	Beginner TransactionBeginner
}

func (s IndexerStore) Transaction(ctx context.Context, fn func(context.Context, indexer.UnitOfWork) error) error {
	beginner := s.Beginner
	if beginner == nil {
		beginner = s.Pool
	}
	return WithinTx(ctx, beginner, func(ctx context.Context, a *Adapter) error { return fn(ctx, a) })
}
func (a *Adapter) ReadState(ctx context.Context, chainID int64, deployment string) (indexer.State, error) {
	state, err := a.GetSyncState(ctx, chainID, deployment)
	if err != nil {
		return indexer.State{}, fmt.Errorf("read indexer state: %w", err)
	}
	return indexer.State{ChainID: chainID, DeploymentID: deployment, Observed: syncBlock(chainID, state.ObservedNumber, state.ObservedHash, state.ObservedAt), Safe: syncBlock(chainID, state.SafeNumber, state.SafeHash, state.SafeAt), Finalized: syncBlock(chainID, state.FinalizedNumber, state.FinalizedHash, state.FinalizedAt)}, nil
}
func syncBlock(chainID int64, n pgtype.Int8, h *Hash, at pgtype.Timestamptz) *ledger.IndexedBlock {
	if !n.Valid || h == nil || !at.Valid {
		return nil
	}
	return &ledger.IndexedBlock{ChainID: chainID, BlockNumber: n.Int64, BlockHash: common.Hash(*h), BlockTime: at.Time}
}
func (a *Adapter) WriteState(ctx context.Context, state indexer.State) error {
	if state.Observed == nil {
		return nil
	}
	to := func(b *ledger.IndexedBlock) (pgtype.Int8, *Hash, pgtype.Timestamptz) {
		if b == nil {
			return pgtype.Int8{}, nil, pgtype.Timestamptz{}
		}
		h := Hash(b.BlockHash)
		return pgtype.Int8{Int64: b.BlockNumber, Valid: true}, &h, pgtype.Timestamptz{Time: b.BlockTime, Valid: true}
	}
	on, oh, oa := to(state.Observed)
	sn, sh, sa := to(state.Safe)
	fn, fh, fa := to(state.Finalized)
	_, err := a.UpsertSyncState(ctx, SyncState{ChainID: state.ChainID, DeploymentID: state.DeploymentID, ObservedNumber: on, ObservedHash: oh, ObservedAt: oa, SafeNumber: sn, SafeHash: sh, SafeAt: sa, FinalizedNumber: fn, FinalizedHash: fh, FinalizedAt: fa})
	return err
}
func (a *Adapter) ReadBlock(ctx context.Context, chainID, n int64) (ledger.IndexedBlock, bool, error) {
	b, err := a.GetIndexedBlockByNumber(ctx, chainID, n)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ledger.IndexedBlock{}, false, nil
		}
		return ledger.IndexedBlock{}, false, err
	}
	return b, true, nil
}
func (a *Adapter) PromoteBlocks(ctx context.Context, chainID int64, safe, final *ledger.IndexedBlock) error {
	for _, b := range []*ledger.IndexedBlock{safe, final} {
		if b == nil {
			continue
		}
		existing, ok, err := a.ReadBlock(ctx, chainID, b.BlockNumber)
		if err != nil || !ok {
			return err
		}
		existing.FinalityStatus = b.FinalityStatus
		if _, err := a.UpsertIndexedBlock(ctx, existing); err != nil {
			return err
		}
	}
	return nil
}
func (a *Adapter) TokenIdentities(ctx context.Context, chainID int64) ([]indexer.TokenIdentity, error) {
	rows, err := a.queries.ListTokenIdentities(ctx, chainID)
	if err != nil {
		return nil, err
	}
	result := make([]indexer.TokenIdentity, 0, len(rows))
	for _, row := range rows {
		result = append(result, indexer.TokenIdentity{Token: common.Address(row.TokenAddress), Curve: common.Address(row.CurveAddress), Pair: common.Address(row.LpPair), EngineVersion: uint16(row.EngineVersion), Launch: ledger.EventCoordinates{ChainID: chainID, BlockNumber: row.LaunchBlockNumber, BlockHash: common.Hash(row.LaunchBlockHash), BlockTime: row.LaunchBlockTime.Time}})
	}
	return result, nil
}
