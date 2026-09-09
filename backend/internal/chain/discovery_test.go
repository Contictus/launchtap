package chain

import (
	"context"
	"errors"
	"math/big"
	"slices"
	"testing"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
)

type capacityError struct{}

func (capacityError) Error() string { return "logs matched by query exceeds limit of 50000" }

type fixtureLogSource struct {
	logs                []types.Log
	shrink              bool
	singleBlockCapacity bool
	calls               int
	rogue               *types.Log
}

func (s *fixtureLogSource) FilterLogs(_ context.Context, query ethereum.FilterQuery) ([]types.Log, error) {
	s.calls++
	from, to := query.FromBlock.Uint64(), query.ToBlock.Uint64()
	if s.shrink && (to > from || s.singleBlockCapacity) {
		return nil, capacityError{}
	}
	addresses := NewAddressSet(query.Addresses...)
	var topics map[common.Hash]struct{}
	if len(query.Topics) > 0 {
		topics = make(map[common.Hash]struct{}, len(query.Topics[0]))
		for _, topic := range query.Topics[0] {
			topics[topic] = struct{}{}
		}
	}
	result := make([]types.Log, 0)
	if s.rogue != nil {
		result = append(result, *s.rogue)
	}
	for _, log := range s.logs {
		if log.BlockNumber < from || log.BlockNumber > to {
			continue
		}
		if _, ok := addresses[log.Address]; !ok {
			continue
		}
		if topics != nil {
			if _, ok := topics[log.Topics[0]]; !ok {
				continue
			}
		}
		result = append(result, log, log)
	}
	slices.Reverse(result)
	return result, nil
}

func TestDiscovererRejectsProviderLogOutsideRequestedEmitters(t *testing.T) {
	t.Parallel()
	_, _, emitters := loadFixtureLogs(t)
	decoder, _ := NewDecoder(1)
	rogue := types.Log{Address: common.HexToAddress("0xdead"), Topics: decoder.Topics(EmitterFactory), BlockNumber: 10}
	discoverer, _ := NewDiscoverer(&fixtureLogSource{rogue: &rogue}, decoder, emitters.Factory, 1)
	_, err := discoverer.Discover(context.Background(), 10, 10, emptyEmitters(emitters.Factory))
	if !errors.Is(err, ErrUnknownEmitter) {
		t.Fatalf("Discover() error = %v, want ErrUnknownEmitter", err)
	}
}

func TestDiscovererCombinesRefetchPartitioningShrinkingAndOrdering(t *testing.T) {
	t.Parallel()
	_, fixtures, allEmitters := loadFixtureLogs(t)
	decoder, _ := NewDecoder(1)
	var launchLog, sameTransactionTrade types.Log
	var launch TokenLaunched
	for _, log := range fixtures {
		decoded, err := decoder.Decode(log, allEmitters)
		if err != nil {
			t.Fatal(err)
		}
		if value, ok := decoded.Value.(TokenLaunched); ok {
			launchLog, launch = log, value
		}
	}
	for _, log := range fixtures {
		decoded, _ := decoder.Decode(log, allEmitters)
		if _, ok := decoded.Value.(Trade); ok && log.Address == launch.Curve {
			sameTransactionTrade = log
			break
		}
	}
	if launchLog.Address == (common.Address{}) || sameTransactionTrade.Address == (common.Address{}) {
		t.Fatal("required launch transaction fixtures missing")
	}
	launchLog.BlockNumber, launchLog.TxIndex, launchLog.Index = 10, 2, 5
	launchLog.BlockHash, launchLog.TxHash = common.BigToHash(big.NewInt(10)), common.BigToHash(big.NewInt(20))
	sameTransactionTrade.BlockNumber, sameTransactionTrade.TxIndex, sameTransactionTrade.Index = 10, 2, 6
	sameTransactionTrade.BlockHash, sameTransactionTrade.TxHash = launchLog.BlockHash, launchLog.TxHash

	known := emptyEmitters(allEmitters.Factory)
	for address := range allEmitters.Curves {
		if address != launch.Curve {
			known.Curves[address] = struct{}{}
		}
	}
	for address := range allEmitters.Pairs {
		if address != launch.LPPair {
			known.Pairs[address] = struct{}{}
		}
	}
	source := &fixtureLogSource{logs: []types.Log{sameTransactionTrade, launchLog}, shrink: true}
	discoverer, err := NewDiscoverer(source, decoder, allEmitters.Factory, 1)
	if err != nil {
		t.Fatal(err)
	}
	result, err := discoverer.Discover(context.Background(), 10, 12, known)
	if err != nil {
		t.Fatalf("Discover() error = %v", err)
	}
	if len(result.Logs) != 2 {
		t.Fatalf("logs = %d, want 2", len(result.Logs))
	}
	if result.Logs[0].Index != 5 || result.Logs[1].Index != 6 {
		t.Fatalf("log order = %d,%d, want 5,6", result.Logs[0].Index, result.Logs[1].Index)
	}
	if _, ok := result.Emitters.Curves[launch.Curve]; !ok {
		t.Fatal("new curve was not discovered")
	}
	if source.calls < 6 {
		t.Fatalf("RPC calls = %d, expected adaptive splitting and staged requests", source.calls)
	}
}

func TestDiscovererReturnsCapacityErrorForSingleBlock(t *testing.T) {
	t.Parallel()
	_, _, emitters := loadFixtureLogs(t)
	decoder, _ := NewDecoder(1)
	discoverer, _ := NewDiscoverer(&fixtureLogSource{shrink: true, singleBlockCapacity: true}, decoder, emitters.Factory, 1)
	_, err := discoverer.Discover(context.Background(), 10, 10, emptyEmitters(emitters.Factory))
	if !errors.Is(err, ErrRPCCapacity) {
		t.Fatalf("Discover() error = %v, want ErrRPCCapacity", err)
	}
}
