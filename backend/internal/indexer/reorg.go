package indexer

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/Contictus/launchtap/backend/internal/ledger"
	"github.com/ethereum/go-ethereum/common"
)

type RecoveryUnit interface {
	UnitOfWork
	FindCommonAncestor(context.Context, int64, []common.Hash) (ledger.IndexedBlock, error)
	AffectedTokensAbove(context.Context, int64, int64) ([]common.Address, error)
	DeleteCanonicalAbove(context.Context, int64, int64) error
	RebuildTokenProjections(context.Context, int64, common.Address) error
	RecomputeTokenStats(context.Context, int64, common.Address) error
	RecomputeProtocolAggregates(context.Context, int64) error
	RecordReorg(context.Context, ReorgRecord) (int64, error)
	CompleteReorg(context.Context, int64) error
}

func (e *Engine) recoverReorg(ctx context.Context, state State, tip ledger.IndexedBlock) error {
	if state.Observed == nil {
		return errors.New("cannot recover reorg without observed tip")
	}
	candidates := make([]common.Hash, 0, 128)
	for number := tip.BlockNumber; number >= e.settings.StartBlock && len(candidates) < 128; number-- {
		header, err := e.source.HeaderByNumber(ctx, uint64(number))
		if err != nil {
			return err
		}
		candidates = append(candidates, header.Hash())
	}
	var reorgID int64
	if err := e.store.Transaction(ctx, func(ctx context.Context, u UnitOfWork) error {
		recovery, ok := u.(RecoveryUnit)
		if !ok {
			return errors.New("store does not support reorg recovery")
		}
		ancestor, err := recovery.FindCommonAncestor(ctx, e.settings.ChainID, candidates)
		if err != nil {
			return err
		}
		depth := state.Observed.BlockNumber - ancestor.BlockNumber
		if depth <= 0 {
			return errors.New("reorg ancestor is not below observed tip")
		}
		reorgID, err = recovery.RecordReorg(ctx, ReorgRecord{ChainID: e.settings.ChainID, DeploymentID: e.settings.DeploymentID, DetectedTipNumber: tip.BlockNumber, DetectedTipHash: tip.BlockHash, CommonAncestorNumber: ancestor.BlockNumber, CommonAncestorHash: ancestor.BlockHash, Depth: depth, DetectedAt: time.Now().UTC()})
		return err
	}); err != nil {
		return fmt.Errorf("record reorg: %w", err)
	}
	if err := e.store.Transaction(ctx, func(ctx context.Context, u UnitOfWork) error {
		recovery, ok := u.(RecoveryUnit)
		if !ok {
			return errors.New("store does not support reorg recovery")
		}
		ancestor, err := recovery.FindCommonAncestor(ctx, e.settings.ChainID, candidates)
		if err != nil {
			return err
		}
		tokens, err := recovery.AffectedTokensAbove(ctx, e.settings.ChainID, ancestor.BlockNumber)
		if err != nil {
			return err
		}
		if err := recovery.DeleteCanonicalAbove(ctx, e.settings.ChainID, ancestor.BlockNumber); err != nil {
			return err
		}
		for _, token := range tokens {
			if err := recovery.RebuildTokenProjections(ctx, e.settings.ChainID, token); err != nil {
				return err
			}
			if err := recovery.RecomputeTokenStats(ctx, e.settings.ChainID, token); err != nil {
				return err
			}
		}
		if err := recovery.RecomputeProtocolAggregates(ctx, e.settings.ChainID); err != nil {
			return err
		}
		return recovery.CompleteReorg(ctx, reorgID)
	}); err != nil {
		return fmt.Errorf("recover reorg %d: %w", reorgID, err)
	}
	return nil
}
