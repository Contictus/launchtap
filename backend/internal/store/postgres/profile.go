package postgres

import (
	"context"
	"math/big"

	"github.com/Contictus/launchtap/backend/internal/profile"
	"github.com/Contictus/launchtap/backend/internal/store/postgres/sqlc"
	"github.com/ethereum/go-ethereum/common"
	"github.com/jackc/pgx/v5/pgtype"
)

type ProfileReader struct {
	Pool         PoolReadBeginner
	DeploymentID string
}

func (r ProfileReader) List(ctx context.Context, chainID int64, wallets []common.Address) (profile.Page, error) {
	var page profile.Page
	err := withReadSnapshotBeginner(ctx, r.Pool, chainID, r.DeploymentID, func(ctx context.Context, adapter *Adapter, snapshot ReadSnapshot) error {
		seen := make(map[common.Address]struct{})
		for _, wallet := range wallets {
			rows, err := adapter.queries.ListProfileActions(ctx, sqlc.ListProfileActionsParams{ChainID: chainID, Wallet: sqlc.Address(wallet)})
			if err != nil {
				return err
			}
			for _, row := range rows {
				token := common.Address(row.TokenAddress)
				if _, exists := seen[token]; exists {
					continue
				}
				seen[token] = struct{}{}
				page.Items = append(page.Items, profile.Action{
					Token: token, Curve: common.Address(row.CurveAddress), Name: row.Name, Symbol: row.Symbol, Phase: row.Phase,
					CreatorFees: profileNumeric(row.CreatorFeeAmount), Refund: profileNumeric(row.RefundAmount),
				})
			}
		}
		page.Snapshot = snapshot.Identity
		page.Finality = finality(snapshot.State, snapshot.Identity.BlockNumber)
		return nil
	})
	return page, err
}

func profileNumeric(value pgtype.Numeric) *big.Int {
	if value.Int == nil {
		return new(big.Int)
	}
	return new(big.Int).Set(value.Int)
}
