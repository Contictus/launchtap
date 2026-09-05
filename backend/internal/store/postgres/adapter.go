package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/Contictus/launchtap/backend/internal/store/postgres/sqlc"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
)

// InvariantConflictError reports that an immutable database identity was
// replayed with a different payload.
type InvariantConflictError struct {
	Entity string
	Key    string
	Cause  error
}

func (err *InvariantConflictError) Error() string {
	return fmt.Sprintf("%s invariant conflict at %s", err.Entity, err.Key)
}

func (err *InvariantConflictError) Unwrap() error {
	return err.Cause
}

// Adapter adds persistence invariants around generated sqlc queries. It does
// not own transaction lifecycle; db may be a pool or an existing pgx.Tx.
type Adapter struct {
	queries *sqlc.Queries
}

func NewAdapter(db DBTX) *Adapter {
	return &Adapter{queries: sqlc.New(db)}
}

func (adapter *Adapter) InsertTrade(ctx context.Context, trade Trade) error {
	arg := sqlc.InsertTradeParams(trade)
	rows, err := adapter.queries.InsertTrade(ctx, arg)
	if err != nil {
		return fmt.Errorf("insert trade: %w", err)
	}
	if rows == 1 {
		return nil
	}
	stored, err := adapter.queries.GetTradeByEventIdentity(ctx, sqlc.GetTradeByEventIdentityParams{
		ChainID: arg.ChainID, TxHash: arg.TxHash, LogIndex: arg.LogIndex,
	})
	if err != nil {
		return fmt.Errorf("read conflicting trade: %w", err)
	}
	if equalTrade(stored, trade) {
		return nil
	}
	return invariantConflict("trade", eventKey(arg.ChainID, arg.TxHash, arg.LogIndex), nil)
}

func (adapter *Adapter) InsertLaunchPauseEvent(
	ctx context.Context,
	event LaunchPauseEvent,
) error {
	arg := sqlc.InsertLaunchPauseEventParams(event)
	rows, err := adapter.queries.InsertLaunchPauseEvent(ctx, arg)
	if err != nil {
		return fmt.Errorf("insert launch pause event: %w", err)
	}
	if rows == 1 {
		return nil
	}
	stored, err := adapter.queries.GetLaunchPauseEventByIdentity(
		ctx,
		sqlc.GetLaunchPauseEventByIdentityParams{
			ChainID: arg.ChainID, TxHash: arg.TxHash, LogIndex: arg.LogIndex,
		},
	)
	if err != nil {
		return fmt.Errorf("read conflicting launch pause event: %w", err)
	}
	if equalLaunchPauseEvent(stored, event) {
		return nil
	}
	return invariantConflict("launch_pause_event", eventKey(arg.ChainID, arg.TxHash, arg.LogIndex), nil)
}

func (adapter *Adapter) UpsertIndexedBlock(ctx context.Context, block IndexedBlock) error {
	arg := sqlc.UpsertIndexedBlockParams(block)
	rows, err := adapter.queries.UpsertIndexedBlock(ctx, arg)
	if err != nil {
		var postgresError *pgconn.PgError
		if errors.As(err, &postgresError) && postgresError.Code == "23505" {
			return invariantConflict(
				"indexed_block",
				fmt.Sprintf("chain_id=%d block_number=%d", arg.ChainID, arg.BlockNumber),
				err,
			)
		}
		return fmt.Errorf("upsert indexed block: %w", err)
	}
	if rows == 1 {
		return nil
	}
	stored, err := adapter.queries.GetIndexedBlockByNumber(ctx, sqlc.GetIndexedBlockByNumberParams{
		ChainID: arg.ChainID, BlockNumber: arg.BlockNumber,
	})
	if err != nil {
		return fmt.Errorf("read conflicting indexed block: %w", err)
	}
	if equalIndexedBlockIdentity(stored, block) {
		return fmt.Errorf("upsert indexed block affected no rows despite identical identity")
	}
	return invariantConflict(
		"indexed_block",
		fmt.Sprintf("chain_id=%d block_number=%d", arg.ChainID, arg.BlockNumber),
		nil,
	)
}

func (adapter *Adapter) GetIndexedBlockByNumber(
	ctx context.Context,
	chainID int64,
	blockNumber int64,
) (IndexedBlock, error) {
	block, err := adapter.queries.GetIndexedBlockByNumber(ctx, sqlc.GetIndexedBlockByNumberParams{
		ChainID: chainID, BlockNumber: blockNumber,
	})
	if err != nil {
		return IndexedBlock{}, fmt.Errorf("get indexed block by number: %w", err)
	}
	return IndexedBlock(block), nil
}

func (adapter *Adapter) GetIndexedBlockByHash(
	ctx context.Context,
	chainID int64,
	blockHash Hash,
) (IndexedBlock, error) {
	block, err := adapter.queries.GetIndexedBlockByHash(ctx, sqlc.GetIndexedBlockByHashParams{
		ChainID: chainID, BlockHash: blockHash,
	})
	if err != nil {
		return IndexedBlock{}, fmt.Errorf("get indexed block by hash: %w", err)
	}
	return IndexedBlock(block), nil
}

func (adapter *Adapter) UpsertSyncState(ctx context.Context, state SyncState) (SyncState, error) {
	stored, err := adapter.queries.UpsertSyncState(ctx, sqlc.UpsertSyncStateParams(state))
	if err != nil {
		return SyncState{}, fmt.Errorf("upsert sync state: %w", err)
	}
	return SyncState(stored), nil
}

func (adapter *Adapter) GetSyncState(ctx context.Context, chainID int64, deploymentID string) (SyncState, error) {
	stored, err := adapter.queries.GetSyncState(ctx, sqlc.GetSyncStateParams{
		ChainID: chainID, DeploymentID: deploymentID,
	})
	if err != nil {
		return SyncState{}, fmt.Errorf("get sync state: %w", err)
	}
	return SyncState(stored), nil
}

func (adapter *Adapter) RebuildTokenProjections(ctx context.Context, chainID int64, token Address) error {
	if err := adapter.queries.RebuildTokenProjections(ctx, sqlc.RebuildTokenProjectionsParams{
		RebuildChainID: chainID, RebuildTokenAddress: token[:],
	}); err != nil {
		return fmt.Errorf("rebuild token projections: %w", err)
	}
	return nil
}

func (adapter *Adapter) ClaimAggregationDirty(
	ctx context.Context,
	workerID string,
	batchSize int32,
) ([]DirtyClaim, error) {
	rows, err := adapter.queries.ClaimAggregationDirty(ctx, sqlc.ClaimAggregationDirtyParams{
		WorkerID: pgtype.Text{String: workerID, Valid: true}, BatchSize: batchSize,
	})
	if err != nil {
		return nil, fmt.Errorf("claim dirty aggregation: %w", err)
	}
	claims := make([]DirtyClaim, 0, len(rows))
	for _, row := range rows {
		if !row.ClaimedGeneration.Valid {
			return nil, fmt.Errorf("claim dirty aggregation: returned NULL claimed generation")
		}
		claims = append(claims, DirtyClaim{
			ChainID: row.ChainID, TokenAddress: row.TokenAddress,
			ClaimedGeneration: row.ClaimedGeneration.Int64,
		})
	}
	return claims, nil
}

func (adapter *Adapter) CompleteAggregationDirty(
	ctx context.Context,
	claim DirtyClaim,
	workerID string,
) (bool, error) {
	rows, err := adapter.queries.CompleteAggregationDirty(ctx, sqlc.CompleteAggregationDirtyParams{
		ChainID: claim.ChainID, TokenAddress: claim.TokenAddress,
		ClaimedGeneration: claim.ClaimedGeneration,
		WorkerID:          pgtype.Text{String: workerID, Valid: true},
	})
	if err != nil {
		return false, fmt.Errorf("complete dirty aggregation: %w", err)
	}
	return rows == 1, nil
}

func invariantConflict(entity, key string, cause error) error {
	return &InvariantConflictError{Entity: entity, Key: key, Cause: cause}
}

func eventKey(chainID int64, txHash sqlc.Hash, logIndex int32) string {
	return fmt.Sprintf("chain_id=%d tx_hash=%x log_index=%d", chainID, txHash, logIndex)
}

func equalTrade(stored sqlc.Trade, attempted Trade) bool {
	return stored.ChainID == attempted.ChainID &&
		stored.BlockNumber == attempted.BlockNumber &&
		stored.BlockHash == attempted.BlockHash &&
		equalTimestamptz(stored.BlockTime, attempted.BlockTime) &&
		stored.TransactionIndex == attempted.TransactionIndex &&
		stored.TxHash == attempted.TxHash &&
		stored.LogIndex == attempted.LogIndex &&
		stored.TokenAddress == attempted.TokenAddress &&
		stored.Trader == attempted.Trader &&
		stored.IsBuy == attempted.IsBuy &&
		stored.EthGross == attempted.EthGross &&
		stored.EthRefund == attempted.EthRefund &&
		stored.TokenAmount == attempted.TokenAmount &&
		stored.ProtocolFee == attempted.ProtocolFee &&
		stored.CreatorFee == attempted.CreatorFee &&
		stored.NewEthReserve == attempted.NewEthReserve &&
		stored.NewTokenReserve == attempted.NewTokenReserve
}

func equalLaunchPauseEvent(
	stored sqlc.LaunchPauseEvent,
	attempted LaunchPauseEvent,
) bool {
	return stored.ChainID == attempted.ChainID &&
		stored.BlockNumber == attempted.BlockNumber &&
		stored.BlockHash == attempted.BlockHash &&
		equalTimestamptz(stored.BlockTime, attempted.BlockTime) &&
		stored.TransactionIndex == attempted.TransactionIndex &&
		stored.TxHash == attempted.TxHash &&
		stored.LogIndex == attempted.LogIndex &&
		stored.Paused == attempted.Paused
}

func equalIndexedBlockIdentity(stored sqlc.IndexedBlock, attempted IndexedBlock) bool {
	return stored.ChainID == attempted.ChainID &&
		stored.BlockNumber == attempted.BlockNumber &&
		stored.BlockHash == attempted.BlockHash &&
		stored.ParentHash == attempted.ParentHash &&
		equalTimestamptz(stored.BlockTime, attempted.BlockTime)
}
