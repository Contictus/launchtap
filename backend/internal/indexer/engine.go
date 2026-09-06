package indexer

import (
	"context"
	"errors"
	"fmt"
	"math"
	"time"

	"github.com/Contictus/launchtap/backend/internal/chain"
	"github.com/Contictus/launchtap/backend/internal/ledger"
	"github.com/ethereum/go-ethereum/core/types"
)

var ErrCanonicalMismatch = errors.New("canonical chain mismatch")
var ErrSafeViolation = errors.New("canonical mismatch at or below safe head")

type Engine struct {
	settings  Settings
	store     Store
	source    Source
	discovery Discovery
	decoder   *chain.Decoder
	router    Router
}

func New(settings Settings, store Store, source Source, discovery Discovery, decoder *chain.Decoder, router Router) (*Engine, error) {
	if settings.ChainID <= 0 || settings.DeploymentID == "" || settings.StartBlock < 0 || settings.ChunkSize <= 0 || settings.PollInterval <= 0 || store == nil || source == nil || discovery == nil || decoder == nil || router == nil {
		return nil, errors.New("invalid indexer dependencies or settings")
	}
	return &Engine{settings: settings, store: store, source: source, discovery: discovery, decoder: decoder, router: router}, nil
}

// Step commits at most one block-aligned chunk. RPC snapshots are checked against
// each other before opening the write transaction; no watermark describes work
// that has not committed locally.
func (e *Engine) Step(ctx context.Context) (bool, error) {
	var state State
	var identities []TokenIdentity
	if err := e.store.Transaction(ctx, func(ctx context.Context, u UnitOfWork) error {
		var err error
		state, err = u.ReadState(ctx, e.settings.ChainID, e.settings.DeploymentID)
		if err != nil {
			return err
		}
		identities, err = u.TokenIdentities(ctx, e.settings.ChainID)
		return err
	}); err != nil {
		return false, err
	}
	heads, err := e.source.Heads(ctx)
	if err != nil {
		return false, fmt.Errorf("read RPC heads: %w", err)
	}
	latest, err := e.block(heads.Latest)
	if err != nil {
		return false, err
	}
	safe, err := e.block(heads.Safe)
	if err != nil {
		return false, err
	}
	finalized, err := e.block(heads.Finalized)
	if err != nil {
		return false, err
	}
	if safe.BlockNumber > latest.BlockNumber || finalized.BlockNumber > safe.BlockNumber {
		return false, errors.New("inconsistent RPC head ordering")
	}
	for _, saved := range []*ledger.IndexedBlock{state.Safe, state.Observed} {
		if saved == nil {
			continue
		}
		remote, err := e.source.HeaderByNumber(ctx, uint64(saved.BlockNumber))
		if err != nil {
			return false, err
		}
		if remote.Hash() != saved.BlockHash {
			if state.Safe != nil && saved.BlockNumber <= state.Safe.BlockNumber {
				return false, ErrSafeViolation
			}
			tip, err := e.block(remote)
			if err != nil {
				return false, err
			}
			if err := e.recoverReorg(ctx, state, tip); err != nil {
				return false, err
			}
			return true, nil
		}
	}
	from := e.settings.StartBlock
	if state.Observed != nil {
		from = state.Observed.BlockNumber + 1
	}
	to := latest.BlockNumber
	if to-from >= e.settings.ChunkSize {
		to = from + e.settings.ChunkSize - 1
	}
	blocks := make(map[int64]ledger.IndexedBlock)
	previous := state.Observed
	for number := from; number <= to; number++ {
		header, err := e.source.HeaderByNumber(ctx, uint64(number))
		if err != nil {
			return false, err
		}
		block, err := e.block(header)
		if err != nil {
			return false, err
		}
		if block.BlockNumber != number {
			return false, errors.New("RPC header number differs from requested number")
		}
		if previous != nil && block.ParentHash != previous.BlockHash {
			if state.Safe != nil && previous.BlockNumber <= state.Safe.BlockNumber {
				return false, ErrSafeViolation
			}
			if err := e.recoverReorg(ctx, state, block); err != nil {
				return false, err
			}
			return true, nil
		}
		blocks[number] = block
		previous = &block
	}
	decoded := make([]chain.DecodedLog, 0)
	if len(blocks) > 0 {
		emitters := chain.Emitters{Factory: e.settings.Factory, Curves: chain.NewAddressSet(), Tokens: chain.NewAddressSet(), Pairs: chain.NewAddressSet()}
		for _, identity := range identities {
			if identity.EngineVersion != 1 {
				return false, fmt.Errorf("unsupported persisted engine version %d", identity.EngineVersion)
			}
			emitters.Curves[identity.Curve] = struct{}{}
			emitters.Tokens[identity.Token] = struct{}{}
			emitters.Pairs[identity.Pair] = struct{}{}
		}
		result, err := e.discovery.Discover(ctx, uint64(from), uint64(to), emitters)
		if err != nil {
			return false, err
		}
		for _, log := range result.Logs {
			if log.BlockNumber > math.MaxInt64 || log.TxIndex > math.MaxInt32 || log.Index > math.MaxInt32 || log.Removed {
				return false, errors.New("invalid log coordinates")
			}
			block, ok := blocks[int64(log.BlockNumber)]
			if !ok || block.BlockHash != log.BlockHash {
				return false, ErrCanonicalMismatch
			}
			event, err := e.decoder.Decode(log, result.Emitters)
			if err != nil {
				return false, err
			}
			decoded = append(decoded, event)
		}
		check, err := e.source.HeaderByNumber(ctx, uint64(to))
		if err != nil {
			return false, err
		}
		if check.Hash() != blocks[to].BlockHash {
			return false, ErrCanonicalMismatch
		}
		state.Observed = previous
	}
	if state.Observed == nil {
		return false, nil
	}
	previousSafe, previousFinalized := int64(-1), int64(-1)
	if state.Safe != nil {
		previousSafe = state.Safe.BlockNumber
	}
	if state.Finalized != nil {
		previousFinalized = state.Finalized.BlockNumber
	}
	// When RPC tags are ahead, promote only the locally processed intersection.
	for _, promotion := range []struct {
		remote ledger.IndexedBlock
		target **ledger.IndexedBlock
		status string
	}{{safe, &state.Safe, "safe"}, {finalized, &state.Finalized, "finalized"}} {
		number := min(promotion.remote.BlockNumber, state.Observed.BlockNumber)
		if number < e.settings.StartBlock || (*promotion.target != nil && number <= (*promotion.target).BlockNumber) {
			continue
		}
		var local ledger.IndexedBlock
		var ok bool
		local, ok = blocks[number]
		if !ok {
			if err := e.store.Transaction(ctx, func(ctx context.Context, u UnitOfWork) error {
				var err error
				local, ok, err = u.ReadBlock(ctx, e.settings.ChainID, number)
				return err
			}); err != nil {
				return false, err
			}
		}
		if !ok {
			return false, fmt.Errorf("missing promotion block %d", number)
		}
		remote, err := e.source.HeaderByNumber(ctx, uint64(number))
		if err != nil {
			return false, err
		}
		if remote.Hash() != local.BlockHash || (number == promotion.remote.BlockNumber && local.BlockHash != promotion.remote.BlockHash) {
			return false, ErrCanonicalMismatch
		}
		local.FinalityStatus = promotion.status
		*promotion.target = &local
	}
	err = e.store.Transaction(ctx, func(ctx context.Context, u UnitOfWork) error {
		for number := from; number <= to; number++ {
			if _, err := u.UpsertIndexedBlock(ctx, blocks[number]); err != nil {
				return err
			}
		}
		if err := e.router.Apply(ctx, u, decoded, blocks, identities); err != nil {
			return err
		}
		if err := u.PromoteBlocks(ctx, e.settings.ChainID, state.Safe, state.Finalized, previousSafe, previousFinalized); err != nil {
			return err
		}
		return u.WriteState(ctx, state)
	})
	return len(blocks) > 0, err
}

func (e *Engine) Run(ctx context.Context) error {
	for {
		advanced, err := e.Step(ctx)
		if err != nil {
			return err
		}
		if advanced {
			continue
		}
		timer := time.NewTimer(e.settings.PollInterval)
		select {
		case <-ctx.Done():
			timer.Stop()
			return ctx.Err()
		case <-timer.C:
		}
	}
}

func (e *Engine) block(header *types.Header) (ledger.IndexedBlock, error) {
	if header == nil || header.Number == nil || !header.Number.IsInt64() || header.Number.Sign() < 0 || header.Time > math.MaxInt64 {
		return ledger.IndexedBlock{}, errors.New("invalid RPC header")
	}
	return ledger.IndexedBlock{ChainID: e.settings.ChainID, BlockNumber: header.Number.Int64(), BlockHash: header.Hash(), ParentHash: header.ParentHash, BlockTime: time.Unix(int64(header.Time), 0).UTC(), FinalityStatus: "observed"}, nil
}
