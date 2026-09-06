package indexer

import (
	"context"
	"errors"
	"math/big"
	"testing"
	"time"

	"github.com/Contictus/launchtap/backend/internal/chain"
	"github.com/Contictus/launchtap/backend/internal/ledger"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
)

type memoryUnit struct {
	state  State
	blocks map[int64]ledger.IndexedBlock
	fail   bool
}
type memoryStore struct{ unit memoryUnit }

func (s *memoryStore) Transaction(ctx context.Context, fn func(context.Context, UnitOfWork) error) error {
	copyUnit := s.unit
	copyUnit.blocks = make(map[int64]ledger.IndexedBlock)
	for n, b := range s.unit.blocks {
		copyUnit.blocks[n] = b
	}
	if err := fn(ctx, &copyUnit); err != nil {
		return err
	}
	s.unit = copyUnit
	return nil
}
func (u *memoryUnit) ReadState(_ context.Context, chainID int64, deployment string) (State, error) {
	s := u.state
	s.ChainID = chainID
	s.DeploymentID = deployment
	return s, nil
}
func (u *memoryUnit) WriteState(_ context.Context, s State) error {
	if u.fail {
		return errors.New("watermark failure")
	}
	u.state = s
	return nil
}
func (u *memoryUnit) ReadBlock(_ context.Context, _ int64, n int64) (ledger.IndexedBlock, bool, error) {
	b, ok := u.blocks[n]
	return b, ok, nil
}
func (u *memoryUnit) UpsertIndexedBlock(_ context.Context, b ledger.IndexedBlock) (ledger.UpsertResult, error) {
	u.blocks[b.BlockNumber] = b
	return ledger.UpsertResult{Changed: true}, nil
}
func (u *memoryUnit) PromoteBlocks(_ context.Context, _ int64, safe, final *ledger.IndexedBlock) error {
	for n, b := range u.blocks {
		if final != nil && n <= final.BlockNumber {
			b.FinalityStatus = "finalized"
		} else if safe != nil && n <= safe.BlockNumber {
			b.FinalityStatus = "safe"
		}
		u.blocks[n] = b
	}
	return nil
}
func (*memoryUnit) TokenIdentities(context.Context, int64) ([]TokenIdentity, error) { return nil, nil }

type fakeSource struct {
	headers map[uint64]*types.Header
	heads   chain.Heads
}

func (s *fakeSource) Heads(context.Context) (chain.Heads, error) { return s.heads, nil }
func (s *fakeSource) HeaderByNumber(_ context.Context, n uint64) (*types.Header, error) {
	h, ok := s.headers[n]
	if !ok {
		return nil, errors.New("header missing")
	}
	return h, nil
}

type emptyDiscovery struct{}

func (emptyDiscovery) Discover(_ context.Context, _, _ uint64, e chain.Emitters) (chain.DiscoveryResult, error) {
	return chain.DiscoveryResult{Emitters: e}, nil
}

type emptyRouter struct{}

func (emptyRouter) Apply(context.Context, UnitOfWork, []chain.DecodedLog, map[int64]ledger.IndexedBlock, []TokenIdentity) error {
	return nil
}
func newTestEngine(t *testing.T) (*Engine, *memoryStore, *fakeSource) {
	t.Helper()
	store := &memoryStore{unit: memoryUnit{blocks: make(map[int64]ledger.IndexedBlock)}}
	source := &fakeSource{headers: make(map[uint64]*types.Header)}
	var parent common.Hash
	for n := uint64(1); n <= 5; n++ {
		h := &types.Header{Number: new(big.Int).SetUint64(n), ParentHash: parent, Time: 100 + n}
		source.headers[n] = h
		parent = h.Hash()
	}
	source.heads = chain.Heads{Latest: source.headers[5], Safe: source.headers[4], Finalized: source.headers[3]}
	decoder, err := chain.NewDecoder(1)
	if err != nil {
		t.Fatal(err)
	}
	e, err := New(Settings{ChainID: 1, DeploymentID: "local-test", StartBlock: 1, ChunkSize: 2, PollInterval: time.Millisecond}, store, source, emptyDiscovery{}, decoder, emptyRouter{})
	if err != nil {
		t.Fatal(err)
	}
	return e, store, source
}
func TestWatermarksAreBoundedByCommittedChunk(t *testing.T) {
	e, store, _ := newTestEngine(t)
	if advanced, err := e.Step(t.Context()); err != nil || !advanced {
		t.Fatalf("step: %t %v", advanced, err)
	}
	if store.unit.state.Observed.BlockNumber != 2 || store.unit.state.Safe.BlockNumber != 2 || store.unit.state.Finalized.BlockNumber != 2 {
		t.Fatalf("unprocessed head promoted: %+v", store.unit.state)
	}
	if len(store.unit.blocks) != 2 || store.unit.blocks[2].FinalityStatus != "finalized" {
		t.Fatalf("blocks: %+v", store.unit.blocks)
	}
	store.unit.fail = true
	if _, err := e.Step(t.Context()); err == nil {
		t.Fatal("expected watermark failure")
	}
	if len(store.unit.blocks) != 2 || store.unit.state.Observed.BlockNumber != 2 {
		t.Fatal("failed chunk partially committed")
	}
}
func TestSafeHashMismatchStopsBeforeWrites(t *testing.T) {
	e, store, source := newTestEngine(t)
	if _, err := e.Step(t.Context()); err != nil {
		t.Fatal(err)
	}
	replacement := *source.headers[2]
	replacement.Extra = []byte("fork")
	source.headers[2] = &replacement
	if _, err := e.Step(t.Context()); !errors.Is(err, ErrSafeViolation) {
		t.Fatalf("safe mismatch: %v", err)
	}
	if len(store.unit.blocks) != 2 {
		t.Fatal("wrote through safe mismatch")
	}
}
