package postgres

import (
	"context"

	"github.com/Contictus/launchtap/backend/internal/stats"
	"github.com/ethereum/go-ethereum/common"
)

type AggregationSource struct {
	Owner   *Ownership
	ChainID int64
}

func (s AggregationSource) Poll(context.Context) ([]stats.Claim, error) { return nil, nil }
func (s AggregationSource) Claim(ctx context.Context, worker string, batch int32) ([]stats.Claim, error) {
	var claims []DirtyClaim
	err := s.Owner.WithinTx(ctx, func(ctx context.Context, adapter *Adapter) error {
		var err error
		claims, err = adapter.ClaimAggregationDirty(ctx, worker, batch)
		return err
	})
	if err != nil {
		return nil, err
	}
	result := make([]stats.Claim, 0, len(claims))
	for _, claim := range claims {
		result = append(result, stats.Claim{ChainID: claim.ChainID, Token: [20]byte(claim.TokenAddress), Generation: claim.ClaimedGeneration})
	}
	return result, nil
}
func (s AggregationSource) Compute(ctx context.Context, claim stats.Claim) error {
	return s.Owner.WithinTx(ctx, func(ctx context.Context, adapter *Adapter) error {
		if err := adapter.RecomputeTokenStats(ctx, claim.ChainID, common.Address(claim.Token)); err != nil {
			return err
		}
		return adapter.RecomputeProtocolAggregates(ctx, claim.ChainID)
	})
}
func (s AggregationSource) Complete(ctx context.Context, claim stats.Claim, worker string) (bool, error) {
	var completed bool
	err := s.Owner.WithinTx(ctx, func(ctx context.Context, adapter *Adapter) error {
		var err error
		completed, err = adapter.CompleteAggregationDirty(ctx, DirtyClaim{ChainID: claim.ChainID, TokenAddress: Address(claim.Token), ClaimedGeneration: claim.Generation}, worker)
		return err
	})
	return completed, err
}
