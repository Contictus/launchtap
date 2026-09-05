//go:build integration

package postgrestest

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/Contictus/launchtap/backend/internal/ledger"
	storepostgres "github.com/Contictus/launchtap/backend/internal/store/postgres"
	"github.com/ethereum/go-ethereum/common"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestWithinTxAtomicity(t *testing.T) {
	database := NewMigrated(t)
	ctx, cancel := context.WithTimeout(t.Context(), 45*time.Second)
	defer cancel()
	pool := openPool(t, ctx, database.URL)

	success := newAtomicFixture(50000)
	prepareAtomicFixture(t, ctx, database.DB, success, false)
	before := readAtomicSnapshot(t, ctx, database.DB, success)
	if err := storepostgres.WithinTx(ctx, pool, func(ctx context.Context, adapter *storepostgres.Adapter) error {
		return runAtomicWorkflow(ctx, adapter, success, "")
	}); err != nil {
		t.Fatalf("commit atomic workflow: %v", err)
	}
	after := readAtomicSnapshot(t, ctx, database.DB, success)
	if !after.greaterThan(before) {
		t.Fatalf("committed categories = %+v, want every category greater than baseline %+v", after, before)
	}

	for index, failurePoint := range []string{"block", "event", "rebuild", "watermark", "commit"} {
		t.Run(failurePoint, func(t *testing.T) {
			fixture := newAtomicFixture(50001 + int64(index))
			prepareAtomicFixture(t, ctx, database.DB, fixture, failurePoint == "rebuild")
			before := readAtomicSnapshot(t, ctx, database.DB, fixture)

			err := storepostgres.WithinTx(ctx, pool, func(ctx context.Context, adapter *storepostgres.Adapter) error {
				return runAtomicWorkflow(ctx, adapter, fixture, failurePoint)
			})
			if err == nil {
				t.Fatalf("%s failure returned nil", failurePoint)
			}
			assertAtomicFailure(t, failurePoint, err)
			after := readAtomicSnapshot(t, ctx, database.DB, fixture)
			if after != before {
				t.Fatalf("%s failure changed atomic categories: before=%+v after=%+v", failurePoint, before, after)
			}
		})
	}
}

func assertAtomicFailure(t testing.TB, failurePoint string, err error) {
	t.Helper()
	wantCode := "23514"
	wantConstraints := []string{
		map[string]string{
			"block":     "indexed_blocks_finality_status_valid",
			"event":     "trades_transaction_index_nonnegative",
			"rebuild":   "holder_balances_balance_nonnegative",
			"watermark": "sync_state_deployment_id_format",
		}[failurePoint],
	}
	if failurePoint == "commit" {
		wantCode = "23503"
		wantConstraints = []string{"trades_block_fk", "token_reserves_source_block_fk"}
	}

	var postgresError *pgconn.PgError
	if !errors.As(err, &postgresError) {
		t.Fatalf("%s error type = %T, want wrapped *pgconn.PgError: %v", failurePoint, err, err)
	}
	if postgresError.Code != wantCode {
		t.Fatalf("%s SQLSTATE = %s, want %s: %v", failurePoint, postgresError.Code, wantCode, err)
	}
	for _, constraint := range wantConstraints {
		if postgresError.ConstraintName == constraint {
			return
		}
	}
	t.Fatalf("%s constraint = %q, want one of %v", failurePoint, postgresError.ConstraintName, wantConstraints)
}

func TestWithinTxLifecycleFailures(t *testing.T) {
	database := NewMigrated(t)
	ctx, cancel := context.WithTimeout(t.Context(), 30*time.Second)
	defer cancel()
	pool := openPool(t, ctx, database.URL)

	t.Run("returned error", func(t *testing.T) {
		fixture := newAtomicFixture(50100)
		prepareAtomicFixture(t, ctx, database.DB, fixture, false)
		sentinel := errors.New("callback failed")
		err := storepostgres.WithinTx(ctx, pool, func(ctx context.Context, adapter *storepostgres.Adapter) error {
			if _, err := adapter.UpsertIndexedBlock(ctx, fixture.block()); err != nil {
				return err
			}
			return sentinel
		})
		if !errors.Is(err, sentinel) {
			t.Fatalf("WithinTx error = %v, want callback sentinel", err)
		}
		assertTargetBlockAbsent(t, ctx, database.DB, fixture)
	})

	t.Run("canceled context", func(t *testing.T) {
		fixture := newAtomicFixture(50101)
		prepareAtomicFixture(t, ctx, database.DB, fixture, false)
		canceledCtx, cancelTransaction := context.WithCancel(ctx)
		err := storepostgres.WithinTx(canceledCtx, pool, func(ctx context.Context, adapter *storepostgres.Adapter) error {
			if _, err := adapter.UpsertIndexedBlock(ctx, fixture.block()); err != nil {
				return err
			}
			cancelTransaction()
			return nil
		})
		if !errors.Is(err, context.Canceled) {
			t.Fatalf("WithinTx error = %v, want context.Canceled", err)
		}
		assertTargetBlockAbsent(t, ctx, database.DB, fixture)
	})

	t.Run("panic", func(t *testing.T) {
		fixture := newAtomicFixture(50102)
		prepareAtomicFixture(t, ctx, database.DB, fixture, false)
		panicValue := &struct{ message string }{message: "original panic"}
		recovered := capturePanic(func() {
			_ = storepostgres.WithinTx(ctx, pool, func(ctx context.Context, adapter *storepostgres.Adapter) error {
				if _, err := adapter.UpsertIndexedBlock(ctx, fixture.block()); err != nil {
					return err
				}
				panic(panicValue)
			})
		})
		if recovered != panicValue {
			t.Fatalf("recovered panic = %#v, want original value %#v", recovered, panicValue)
		}
		assertTargetBlockAbsent(t, ctx, database.DB, fixture)
	})
}

type atomicFixture struct {
	chainID       int64
	launchTime    time.Time
	targetTime    time.Time
	launchHash    storepostgres.Hash
	targetHash    storepostgres.Hash
	token         storepostgres.Address
	deploymentID  string
	transactionID storepostgres.Hash
}

func newAtomicFixture(chainID int64) atomicFixture {
	seed := byte(chainID % 200)
	return atomicFixture{
		chainID:    chainID,
		launchTime: time.Date(2026, time.September, 5, 10, 0, int(chainID%50), 0, time.UTC),
		targetTime: time.Date(2026, time.September, 5, 10, 1, int(chainID%50), 0, time.UTC),
		launchHash: fixedHash(seed + 1), targetHash: fixedHash(seed + 2),
		token:        fixedAddress(addressBytes(seed + 3)),
		deploymentID: fmt.Sprintf("tx-test-%d", chainID), transactionID: fixedHash(seed + 4),
	}
}

func (fixture atomicFixture) block() ledger.IndexedBlock {
	return ledger.IndexedBlock{
		ChainID: fixture.chainID, BlockNumber: 2, BlockHash: common.Hash(fixture.targetHash),
		ParentHash:     common.Hash(fixture.launchHash),
		BlockTime:      fixture.targetTime,
		FinalityStatus: "observed",
	}
}

func (fixture atomicFixture) trade() ledger.Trade {
	return ledger.Trade{
		EventCoordinates: ledger.EventCoordinates{ChainID: fixture.chainID, BlockNumber: 2, BlockHash: common.Hash(fixture.targetHash), BlockTime: fixture.targetTime, TransactionIndex: 0, TxHash: common.Hash(fixture.transactionID), LogIndex: 0},
		Token:            common.Address(fixture.token), Trader: common.Address(fixedAddress(addressBytes(0x71))), IsBuy: true,
		ETHGross: uint256Byte(20).BigInt(), ETHRefund: uint256Byte(0).BigInt(), TokenAmount: uint256Byte(10).BigInt(),
		ProtocolFee: uint256Byte(1).BigInt(), CreatorFee: uint256Byte(1).BigInt(),
		NewETHReserve: uint256Byte(30).BigInt(), NewTokenReserve: uint256Byte(90).BigInt(),
	}
}

func (fixture atomicFixture) syncState() storepostgres.SyncState {
	hash := fixture.targetHash
	return storepostgres.SyncState{
		ChainID: fixture.chainID, DeploymentID: fixture.deploymentID,
		ObservedNumber: pgtype.Int8{Int64: 2, Valid: true}, ObservedHash: &hash,
		ObservedAt: pgtype.Timestamptz{Time: fixture.targetTime, Valid: true},
	}
}

func prepareAtomicFixture(
	t testing.TB,
	ctx context.Context,
	database *sql.DB,
	fixture atomicFixture,
	invalidHolderHistory bool,
) {
	t.Helper()
	mustInsertBlock(t, ctx, database, fixture.chainID, 1, fixture.launchHash[:], hashBytes(0x01), fixture.launchTime, "observed")
	insertProjectionLaunch(t, ctx, database, fixture.chainID, 1, fixture.launchHash[:], fixture.launchTime, hashBytes(0x02), projectionLaunchFixture{
		token: fixture.token[:], curve: addressBytes(0x31), pair: addressBytes(0x32), weth: addressBytes(0x33),
	})
	if invalidHolderHistory {
		insertTransfer(t, ctx, database, fixture.chainID, 1, fixture.launchHash[:], fixture.launchTime,
			hashBytes(0x03), 1, fixture.token[:], addressBytes(0x41), addressBytes(0x42), 1)
	}
}

func runAtomicWorkflow(
	ctx context.Context,
	adapter *storepostgres.Adapter,
	fixture atomicFixture,
	failurePoint string,
) error {
	block := fixture.block()
	if failurePoint == "block" {
		block.FinalityStatus = "invalid"
	}
	if _, err := adapter.UpsertIndexedBlock(ctx, block); err != nil {
		return err
	}

	trade := fixture.trade()
	if failurePoint == "event" {
		trade.TransactionIndex = -1
	}
	if failurePoint == "commit" {
		trade.BlockHash = common.Hash(fixedHash(0xfe))
	}
	if _, err := adapter.InsertTrade(ctx, trade); err != nil {
		return err
	}

	if err := adapter.RebuildTokenProjections(ctx, fixture.chainID, common.Address(fixture.token)); err != nil {
		return err
	}

	state := fixture.syncState()
	if failurePoint == "watermark" {
		state.DeploymentID = "x"
	}
	_, err := adapter.UpsertSyncState(ctx, state)
	return err
}

type atomicSnapshot struct {
	blocks      int
	events      int
	projections int
	dirty       int
	watermarks  int
}

func (snapshot atomicSnapshot) greaterThan(before atomicSnapshot) bool {
	return snapshot.blocks > before.blocks && snapshot.events > before.events &&
		snapshot.projections > before.projections && snapshot.dirty > before.dirty &&
		snapshot.watermarks > before.watermarks
}

func readAtomicSnapshot(t testing.TB, ctx context.Context, database *sql.DB, fixture atomicFixture) atomicSnapshot {
	t.Helper()
	var snapshot atomicSnapshot
	err := database.QueryRowContext(ctx, `
		SELECT
			(SELECT count(*) FROM indexed_blocks WHERE chain_id = $1 AND block_number = 2),
			(SELECT count(*) FROM trades WHERE chain_id = $1 AND tx_hash = $2),
			(SELECT count(*) FROM tokens WHERE chain_id = $1 AND token_address = $3)
			 + (SELECT count(*) FROM token_reserves WHERE chain_id = $1 AND token_address = $3)
			 + (SELECT count(*) FROM holder_balances WHERE chain_id = $1 AND token_address = $3)
			 + (SELECT count(*) FROM candles WHERE chain_id = $1 AND token_address = $3),
			(SELECT count(*) FROM aggregation_dirty WHERE chain_id = $1 AND token_address = $3),
			(SELECT count(*) FROM sync_state WHERE chain_id = $1 AND deployment_id = $4)
	`, fixture.chainID, fixture.transactionID[:], fixture.token[:], fixture.deploymentID).Scan(
		&snapshot.blocks, &snapshot.events, &snapshot.projections, &snapshot.dirty, &snapshot.watermarks,
	)
	if err != nil {
		t.Fatalf("read atomic snapshot: %v", err)
	}
	return snapshot
}

func openPool(t testing.TB, ctx context.Context, databaseURL string) *pgxpool.Pool {
	t.Helper()
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		t.Fatalf("open pgx pool: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

func assertTargetBlockAbsent(t testing.TB, ctx context.Context, database *sql.DB, fixture atomicFixture) {
	t.Helper()
	var count int
	if err := database.QueryRowContext(ctx,
		"SELECT count(*) FROM indexed_blocks WHERE chain_id = $1 AND block_number = 2",
		fixture.chainID,
	).Scan(&count); err != nil {
		t.Fatalf("count target block: %v", err)
	}
	if count != 0 {
		t.Fatalf("target block count = %d, want 0", count)
	}
}

func capturePanic(fn func()) (recovered any) {
	defer func() { recovered = recover() }()
	fn()
	return nil
}
