//go:build integration

package postgrestest

import (
	"context"
	"errors"
	"testing"
	"time"

	storepostgres "github.com/Contictus/launchtap/backend/internal/store/postgres"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestSQLCPersistenceFoundation(t *testing.T) {
	database := NewMigrated(t)
	ctx, cancel := context.WithTimeout(t.Context(), 30*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, database.URL)
	if err != nil {
		t.Fatalf("open pgx pool: %v", err)
	}
	t.Cleanup(pool.Close)

	t.Run("pool and transaction DBTX", func(t *testing.T) {
		testSQLCDBTX(t, ctx, pool)
	})
	t.Run("idempotent event conflict comparison", func(t *testing.T) {
		testIdempotentLaunchPauseEvent(t, ctx, pool)
		testIdempotentTrade(t, ctx, database, pool)
	})
	t.Run("dirty completion compare and delete", func(t *testing.T) {
		testDirtyCompletionRace(t, ctx, database, pool)
	})
}

func testIdempotentTrade(
	t *testing.T,
	ctx context.Context,
	database *Database,
	pool *pgxpool.Pool,
) {
	t.Helper()
	const chainID int64 = 49004
	blockTime := time.Date(2026, 9, 4, 18, 3, 0, 0, time.UTC)
	blockHash := hashBytes(0x41)
	token := addressBytes(0x42)
	mustInsertBlock(t, ctx, database.DB, chainID, 400, blockHash, hashBytes(0x40), blockTime, "observed")
	insertProjectionLaunch(t, ctx, database.DB, chainID, 400, blockHash, blockTime, hashBytes(0x43), projectionLaunchFixture{
		token: token, curve: addressBytes(0x44), pair: addressBytes(0x45), weth: addressBytes(0x46),
	})

	trade := storepostgres.Trade{
		ChainID: chainID, BlockNumber: 400, BlockHash: fixedHash(0x41),
		BlockTime:        pgtype.Timestamptz{Time: blockTime, Valid: true},
		TransactionIndex: 1, TxHash: fixedHash(0x47), LogIndex: 2,
		TokenAddress: fixedAddress(token), Trader: fixedAddress(addressBytes(0x48)), IsBuy: true,
		EthGross: uint256Byte(100), TokenAmount: uint256Byte(200),
		ProtocolFee: uint256Byte(1), CreatorFee: uint256Byte(2),
		NewEthReserve: uint256Byte(110), NewTokenReserve: uint256Byte(199),
	}
	adapter := storepostgres.NewAdapter(pool)
	if err := adapter.InsertTrade(ctx, trade); err != nil {
		t.Fatalf("insert trade: %v", err)
	}
	if err := adapter.InsertTrade(ctx, trade); err != nil {
		t.Fatalf("replay identical trade: %v", err)
	}
	trade.CreatorFee = uint256Byte(3)
	err := adapter.InsertTrade(ctx, trade)
	var conflict *storepostgres.InvariantConflictError
	if !errors.As(err, &conflict) {
		t.Fatalf("divergent trade error = %T %v, want InvariantConflictError", err, err)
	}
}

func testSQLCDBTX(t *testing.T, ctx context.Context, pool *pgxpool.Pool) {
	t.Helper()
	const chainID int64 = 49001
	blockTime := pgtype.Timestamptz{Time: time.Date(2026, 9, 4, 18, 0, 0, 0, time.UTC), Valid: true}
	blockHash := fixedHash(0x11)
	parentHash := fixedHash(0x10)

	adapter := storepostgres.NewAdapter(pool)
	block := storepostgres.IndexedBlock{
		ChainID: chainID, BlockNumber: 100, BlockHash: blockHash, ParentHash: parentHash,
		BlockTime: blockTime, FinalityStatus: "observed",
	}
	if err := adapter.UpsertIndexedBlock(ctx, block); err != nil {
		t.Fatalf("insert block through pool DBTX: %v", err)
	}

	byNumber, err := adapter.GetIndexedBlockByNumber(ctx, chainID, 100)
	if err != nil {
		t.Fatalf("get block by number: %v", err)
	}
	byHash, err := adapter.GetIndexedBlockByHash(ctx, chainID, blockHash)
	if err != nil {
		t.Fatalf("get block by hash: %v", err)
	}
	if byNumber.BlockHash != blockHash || byHash.BlockNumber != 100 {
		t.Fatalf("link lookups returned inconsistent blocks: by_number=%+v by_hash=%+v", byNumber, byHash)
	}

	syncState := storepostgres.SyncState{
		ChainID: chainID, DeploymentID: "sqlc-foundation-test",
		ObservedNumber: pgtype.Int8{Int64: 100, Valid: true},
		ObservedHash:   &blockHash,
		ObservedAt:     blockTime,
	}
	storedState, err := adapter.UpsertSyncState(ctx, syncState)
	if err != nil {
		t.Fatalf("upsert sync state: %v", err)
	}
	readState, err := adapter.GetSyncState(ctx, chainID, syncState.DeploymentID)
	if err != nil {
		t.Fatalf("get sync state: %v", err)
	}
	if storedState.ObservedHash == nil || readState.ObservedHash == nil ||
		*storedState.ObservedHash != blockHash || *readState.ObservedHash != blockHash {
		t.Fatalf("sync state hash round trip failed: stored=%+v read=%+v", storedState, readState)
	}

	block.FinalityStatus = "safe"
	transaction, err := pool.Begin(ctx)
	if err != nil {
		t.Fatalf("begin transaction: %v", err)
	}
	defer func() { _ = transaction.Rollback(context.Background()) }()
	if err := storepostgres.NewAdapter(transaction).UpsertIndexedBlock(ctx, block); err != nil {
		t.Fatalf("update finality through pgx.Tx DBTX: %v", err)
	}
	if err := transaction.Commit(ctx); err != nil {
		t.Fatalf("commit caller-owned transaction: %v", err)
	}

	block.ParentHash = fixedHash(0xff)
	err = adapter.UpsertIndexedBlock(ctx, block)
	var conflict *storepostgres.InvariantConflictError
	if !errors.As(err, &conflict) {
		t.Fatalf("divergent block error = %T %v, want InvariantConflictError", err, err)
	}
}

func testIdempotentLaunchPauseEvent(t *testing.T, ctx context.Context, pool *pgxpool.Pool) {
	t.Helper()
	const chainID int64 = 49002
	blockTime := pgtype.Timestamptz{Time: time.Date(2026, 9, 4, 18, 1, 0, 123456789, time.UTC), Valid: true}
	adapter := storepostgres.NewAdapter(pool)
	if err := adapter.UpsertIndexedBlock(ctx, storepostgres.IndexedBlock{
		ChainID: chainID, BlockNumber: 200, BlockHash: fixedHash(0x21), ParentHash: fixedHash(0x20),
		BlockTime: blockTime, FinalityStatus: "observed",
	}); err != nil {
		t.Fatalf("insert event block: %v", err)
	}

	event := storepostgres.LaunchPauseEvent{
		ChainID: chainID, BlockNumber: 200, BlockHash: fixedHash(0x21), BlockTime: blockTime,
		TransactionIndex: 0, TxHash: fixedHash(0x22), LogIndex: 1, Paused: true,
	}
	if err := adapter.InsertLaunchPauseEvent(ctx, event); err != nil {
		t.Fatalf("insert launch pause event: %v", err)
	}
	if err := adapter.InsertLaunchPauseEvent(ctx, event); err != nil {
		t.Fatalf("replay identical launch pause event: %v", err)
	}

	event.Paused = false
	err := adapter.InsertLaunchPauseEvent(ctx, event)
	var conflict *storepostgres.InvariantConflictError
	if !errors.As(err, &conflict) {
		t.Fatalf("divergent replay error = %T %v, want InvariantConflictError", err, err)
	}
}

func testDirtyCompletionRace(
	t *testing.T,
	ctx context.Context,
	database *Database,
	pool *pgxpool.Pool,
) {
	t.Helper()
	const chainID int64 = 49003
	blockTime := time.Date(2026, 9, 4, 18, 2, 0, 0, time.UTC)
	blockHash := hashBytes(0x31)
	token := addressBytes(0x32)
	mustInsertBlock(t, ctx, database.DB, chainID, 300, blockHash, hashBytes(0x30), blockTime, "observed")
	insertProjectionLaunch(t, ctx, database.DB, chainID, 300, blockHash, blockTime, hashBytes(0x33), projectionLaunchFixture{
		token: token, curve: addressBytes(0x34), pair: addressBytes(0x35), weth: addressBytes(0x36),
	})

	adapter := storepostgres.NewAdapter(pool)
	if err := adapter.RebuildTokenProjections(ctx, chainID, fixedAddress(token)); err != nil {
		t.Fatalf("initial projection rebuild: %v", err)
	}
	claimA := claimOne(t, ctx, adapter, "worker-a")

	if err := adapter.RebuildTokenProjections(ctx, chainID, fixedAddress(token)); err != nil {
		t.Fatalf("second projection rebuild: %v", err)
	}
	claimB := claimOne(t, ctx, adapter, "worker-b")
	if claimB.ClaimedGeneration <= claimA.ClaimedGeneration {
		t.Fatalf("generation did not advance: A=%d B=%d", claimA.ClaimedGeneration, claimB.ClaimedGeneration)
	}

	completed, err := adapter.CompleteAggregationDirty(ctx, claimA, "worker-a")
	if err != nil {
		t.Fatalf("stale completion: %v", err)
	}
	if completed {
		t.Fatal("stale completion deleted worker B's live claim")
	}

	var generation, claimedGeneration int64
	var claimedBy string
	if err := database.DB.QueryRowContext(ctx, `
		SELECT generation, claimed_generation, claimed_by
		FROM aggregation_dirty
		WHERE chain_id = $1 AND token_address = $2
	`, chainID, token).Scan(&generation, &claimedGeneration, &claimedBy); err != nil {
		t.Fatalf("read worker B claim: %v", err)
	}
	if generation != claimB.ClaimedGeneration || claimedGeneration != generation || claimedBy != "worker-b" {
		t.Fatalf("live claim changed: generation=%d claimed_generation=%d claimed_by=%q", generation, claimedGeneration, claimedBy)
	}

	completed, err = adapter.CompleteAggregationDirty(ctx, claimB, "worker-b")
	if err != nil || !completed {
		t.Fatalf("live completion completed=%t err=%v, want completed=true", completed, err)
	}
}

func claimOne(
	t testing.TB,
	ctx context.Context,
	adapter *storepostgres.Adapter,
	worker string,
) storepostgres.DirtyClaim {
	t.Helper()
	claims, err := adapter.ClaimAggregationDirty(ctx, worker, 1)
	if err != nil {
		t.Fatalf("claim dirty row for %s: %v", worker, err)
	}
	if len(claims) != 1 {
		t.Fatalf("claims for %s = %+v, want one claim", worker, claims)
	}
	return claims[0]
}

func fixedHash(value byte) storepostgres.Hash {
	var result storepostgres.Hash
	for index := range result {
		result[index] = value
	}
	return result
}

func fixedAddress(value []byte) storepostgres.Address {
	var result storepostgres.Address
	copy(result[:], value)
	return result
}

func uint256Byte(value byte) storepostgres.Uint256 {
	var result storepostgres.Uint256
	result[len(result)-1] = value
	return result
}
