package postgres

import (
	"context"
	"errors"

	"github.com/Contictus/launchtap/backend/internal/observation"
	"github.com/Contictus/launchtap/backend/internal/store/postgres/sqlc"
	"github.com/ethereum/go-ethereum/common"
	"github.com/jackc/pgx/v5"
)

// ObservationReader reads the canonical event ledger and indexed block
// identity in one repeatable-read snapshot. It deliberately does not use
// token, trade, or other rebuildable projections.
type ObservationReader struct {
	Pool PoolReadBeginner
}

func (r ObservationReader) Get(ctx context.Context, chainID int64, deploymentID string, txHash common.Hash) (observation.Observation, error) {
	var out observation.Observation
	err := withReadSnapshotBeginner(ctx, r.Pool, chainID, deploymentID, func(ctx context.Context, a *Adapter, snapshot ReadSnapshot) error {
		rows, err := a.queries.GetCanonicalTransaction(ctx, sqlc.GetCanonicalTransactionParams{ChainID: chainID, TxHash: sqlc.Hash(txHash), DeploymentID: deploymentID})
		if err != nil {
			return err
		}
		if len(rows) == 0 {
			return observation.ErrNotFound
		}
		out = observation.Observation{
			ChainID: chainID, DeploymentID: deploymentID, Snapshot: snapshot.Identity,
			Finality: rows[0].FinalityStatus, Events: make([]observation.Event, 0, len(rows)),
		}
		for _, row := range rows {
			event := observation.Event{
				Kind: row.EventKind, TxHash: common.Hash(row.TxHash), BlockNumber: row.BlockNumber,
				BlockHash: common.Hash(row.BlockHash), BlockTime: row.BlockTime.Time.UTC().Format("2006-01-02T15:04:05.000000000Z"),
				TransactionIndex: row.TransactionIndex, LogIndex: row.LogIndex, Finality: row.FinalityStatus,
			}
			if row.TokenAddress != (sqlc.Address{}) {
				address := common.Address(row.TokenAddress)
				event.Token = &address
			}
			if len(row.PairAddress) == common.AddressLength {
				address := common.BytesToAddress(row.PairAddress)
				event.Pair = &address
			}
			out.Events = append(out.Events, event)
		}
		return nil
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return observation.Observation{}, observation.ErrNotFound
	}
	return out, err
}
