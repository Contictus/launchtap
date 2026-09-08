//go:build integration

package indexer_test

import (
	"context"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/Contictus/launchtap/backend/internal/chain"
	"github.com/Contictus/launchtap/backend/internal/indexer"
	storepostgres "github.com/Contictus/launchtap/backend/internal/store/postgres"
	"github.com/Contictus/launchtap/backend/internal/store/postgres/postgrestest"
	"github.com/ethereum/go-ethereum/common"
)

// TestAnvilIndexerEndToEnd indexes a production-contract TokenLaunched event
// emitted on a fresh Anvil chain. The PowerShell gate supplies its isolated
// RPC endpoint and the actual factory deployment coordinates.
func TestAnvilIndexerEndToEnd(t *testing.T) {
	if os.Getenv("ANVIL_INDEXER_RPC_URL") == "" {
		t.Skip("run through task anvil-indexer-e2e")
	}
	rpcURL := requireAnvilEnvironment(t, "ANVIL_INDEXER_RPC_URL")
	factoryText := requireAnvilEnvironment(t, "ANVIL_INDEXER_FACTORY")
	startText := requireAnvilEnvironment(t, "ANVIL_INDEXER_START_BLOCK")
	if !common.IsHexAddress(factoryText) {
		t.Fatalf("ANVIL_INDEXER_FACTORY is not an address: %q", factoryText)
	}
	start, err := strconv.ParseInt(startText, 10, 64)
	if err != nil || start < 0 {
		t.Fatalf("ANVIL_INDEXER_START_BLOCK is invalid: %q", startText)
	}

	ctx, cancel := context.WithTimeout(t.Context(), 30*time.Second)
	defer cancel()
	database := postgrestest.NewMigrated(t)
	pool, err := storepostgres.OpenPool(ctx, database.URL, storepostgres.PoolOptions{})
	if err != nil {
		t.Fatalf("open indexer pool: %v", err)
	}
	defer pool.Close()
	source, err := chain.Dial(ctx, rpcURL, chain.RPCConfig{Timeout: 2 * time.Second, RetryBackoff: 10 * time.Millisecond})
	if err != nil {
		t.Fatalf("dial Anvil: %v", err)
	}
	defer source.Close()
	decoder, err := chain.NewDecoder(1)
	if err != nil {
		t.Fatalf("create event decoder: %v", err)
	}
	factory := common.HexToAddress(factoryText)
	discovery, err := chain.NewDiscoverer(source, decoder, factory, 64)
	if err != nil {
		t.Fatalf("create discoverer: %v", err)
	}
	const chainID int64 = 31_337
	store := storepostgres.IndexerStore{Pool: pool, ChainID: chainID, DeploymentID: "anvil-indexer-e2e"}
	engine, err := indexer.New(indexer.Settings{
		ChainID: chainID, DeploymentID: "anvil-indexer-e2e", Factory: factory,
		StartBlock: start, ChunkSize: 128, PollInterval: time.Millisecond,
	}, store, source, discovery, decoder, indexer.LedgerRouter{ChainID: chainID})
	if err != nil {
		t.Fatalf("create engine: %v", err)
	}
	if advanced, err := engine.Step(ctx); err != nil || !advanced {
		t.Fatalf("index Anvil deployment: advanced=%t err=%v", advanced, err)
	}
	var launches, tokens, transfers int
	if err := database.DB.QueryRowContext(ctx, `SELECT count(*) FROM token_launches WHERE chain_id=$1`, chainID).Scan(&launches); err != nil {
		t.Fatalf("count launches: %v", err)
	}
	if err := database.DB.QueryRowContext(ctx, `SELECT count(*) FROM tokens WHERE chain_id=$1`, chainID).Scan(&tokens); err != nil {
		t.Fatalf("count token projections: %v", err)
	}
	if err := database.DB.QueryRowContext(ctx, `SELECT count(*) FROM transfers WHERE chain_id=$1`, chainID).Scan(&transfers); err != nil {
		t.Fatalf("count transfers: %v", err)
	}
	if launches != 1 || tokens != 1 || transfers == 0 {
		t.Fatalf("indexed rows launches=%d tokens=%d transfers=%d; want 1, 1, positive", launches, tokens, transfers)
	}
}

func requireAnvilEnvironment(t testing.TB, key string) string {
	t.Helper()
	value := os.Getenv(key)
	if value == "" {
		t.Fatalf("%s is required; run task anvil-indexer-e2e", key)
	}
	return value
}
