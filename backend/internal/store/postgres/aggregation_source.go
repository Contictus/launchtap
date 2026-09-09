package postgres

import (
	"context"

	"github.com/Contictus/launchtap/backend/internal/stats"
	"github.com/ethereum/go-ethereum/common"
)

type AggregationSource struct {
	Adapter *Adapter
	ChainID int64
}

func (s AggregationSource) Poll(context.Context) ([]stats.Claim, error) { return nil, nil }
func (s AggregationSource) Claim(ctx context.Context, worker string, batch int32) ([]stats.Claim, error) {
	var claims []DirtyClaim
	err := func() error {
		var err error
		claims, err = s.Adapter.ClaimAggregationDirty(ctx, worker, batch)
		return err
	}()
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
	if err := s.Adapter.RecomputeTokenStats(ctx, claim.ChainID, common.Address(claim.Token)); err != nil {
		return err
	}
	return s.Adapter.RecomputeProtocolAggregates(ctx, claim.ChainID)
}
func (s AggregationSource) Complete(ctx context.Context, claim stats.Claim, worker string) (bool, error) {
	var completed bool
	err := func() error {
		var err error
		completed, err = s.Adapter.CompleteAggregationDirty(ctx, DirtyClaim{ChainID: claim.ChainID, TokenAddress: Address(claim.Token), ClaimedGeneration: claim.Generation}, worker)
		return err
	}()
	return completed, err
}
