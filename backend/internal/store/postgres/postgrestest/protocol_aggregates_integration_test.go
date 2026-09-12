//go:build integration

package postgrestest

import (
	"context"
	"database/sql"
	"strings"
	"sync"
	"testing"
	"time"

	storepostgres "github.com/Contictus/launchtap/backend/internal/store/postgres"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestRecomputeProtocolAggregatesKeepsCommittedRowsVisibleUntilRefreshCompletes(t *testing.T) {
	database := NewMigrated(t)
	ctx, cancel := context.WithTimeout(t.Context(), 30*time.Second)
	defer cancel()
	pool := openPool(t, ctx, database.URL)
	const chainID int64 = 48006
	oldDay := seedProtocolAggregateFixture(t, ctx, database, chainID)

	barrier := &protocolAggregateBarrier{pool: pool, reached: make(chan struct{}), resume: make(chan struct{})}
	defer barrier.release()
	done := make(chan error, 1)
	go func() {
		done <- storepostgres.NewAdapter(barrier).RecomputeProtocolAggregates(ctx, chainID)
	}()

	select {
	case <-barrier.reached:
	case <-time.After(5 * time.Second):
		barrier.release()
		if err := <-done; err != nil {
			t.Fatalf("recompute protocol aggregates before timeout: %v", err)
		}
		t.Fatal("refresh did not pause after clearing protocol_daily")
	}

	assertProtocolAggregateState(t, ctx, database.DB, chainID, oldDay, 1, 9, 19, 1)
	barrier.release()
	if err := <-done; err != nil {
		t.Fatalf("recompute protocol aggregates: %v", err)
	}
	assertProtocolAggregateState(t, ctx, database.DB, chainID, oldDay, 1, 1, 1, 0)
}

func TestRecomputeProtocolAggregatesRollsBackOnSummaryFailure(t *testing.T) {
	database := NewMigrated(t)
	ctx, cancel := context.WithTimeout(t.Context(), 30*time.Second)
	defer cancel()
	pool := openPool(t, ctx, database.URL)
	const chainID int64 = 48007
	oldDay := seedProtocolAggregateFixture(t, ctx, database, chainID)

	if _, err := database.DB.ExecContext(ctx, `
		CREATE FUNCTION fail_protocol_stats_refresh() RETURNS trigger
		LANGUAGE plpgsql AS $fn$
		BEGIN
			RAISE EXCEPTION 'injected protocol summary failure';
		END
		$fn$
	`); err != nil {
		t.Fatalf("create failure trigger function: %v", err)
	}
	if _, err := database.DB.ExecContext(ctx, `
		CREATE TRIGGER fail_protocol_stats_refresh
		BEFORE INSERT OR UPDATE ON protocol_stats
		FOR EACH ROW EXECUTE FUNCTION fail_protocol_stats_refresh()
	`); err != nil {
		t.Fatalf("create failure trigger: %v", err)
	}

	err := storepostgres.NewAdapter(pool).RecomputeProtocolAggregates(ctx, chainID)
	if err == nil {
		t.Fatal("recompute succeeded with an injected protocol summary failure")
	}
	assertProtocolAggregateState(t, ctx, database.DB, chainID, oldDay, 1, 9, 19, 1)
}

func seedProtocolAggregateFixture(t *testing.T, ctx context.Context, database *Database, chainID int64) string {
	t.Helper()
	now := time.Now().UTC().Truncate(time.Second)
	blockTime := now.Add(-time.Hour)
	blockHash := hashBytes(0x61)
	token, curve, pair, weth := addressBytes(0x62), addressBytes(0x63), addressBytes(0x64), addressBytes(0x65)
	mustInsertBlock(t, ctx, database.DB, chainID, 1, blockHash, hashBytes(0x60), blockTime, "observed")
	insertProjectionLaunch(t, ctx, database.DB, chainID, 1, blockHash, blockTime, hashBytes(0x66), projectionLaunchFixture{
		token: token, curve: curve, pair: pair, weth: weth,
	})
	callRebuild(t, ctx, database.DB, chainID, token)

	oldDay := now.AddDate(0, 0, -3).Format("2006-01-02")
	if _, err := database.DB.ExecContext(ctx, `
		INSERT INTO protocol_daily (chain_id, day, volume_eth_wad, launches_count, trades_count, graduations_count)
		VALUES ($1, $2, 99, 9, 7, 3)
	`, chainID, oldDay); err != nil {
		t.Fatalf("insert old protocol daily row: %v", err)
	}
	if _, err := database.DB.ExecContext(ctx, `
		INSERT INTO protocol_stats (
			chain_id, volume_24h_eth_wad, volume_all_time_eth_wad, launches_24h, launches_all_time,
			trades_24h, trades_all_time, graduations_24h, graduations_all_time, updated_at
		) VALUES ($1, 99, 99, 9, 19, 7, 17, 3, 13, now())
	`, chainID); err != nil {
		t.Fatalf("insert old protocol summary row: %v", err)
	}
	return oldDay
}

func assertProtocolAggregateState(t testing.TB, ctx context.Context, database *sql.DB, chainID int64, oldDay string, dailyRows, dailyLaunches, allTimeLaunches, expectedOldRows int64) {
	t.Helper()
	var rows, launches int64
	if err := database.QueryRowContext(ctx, `
		SELECT count(*), COALESCE(sum(launches_count), 0)
		FROM protocol_daily WHERE chain_id = $1
	`, chainID).Scan(&rows, &launches); err != nil {
		t.Fatalf("read protocol daily aggregates: %v", err)
	}
	if rows != dailyRows || launches != dailyLaunches {
		t.Fatalf("protocol daily rows/launches = %d/%d; want %d/%d", rows, launches, dailyRows, dailyLaunches)
	}
	var gotAllTime int64
	if err := database.QueryRowContext(ctx, `
		SELECT launches_all_time FROM protocol_stats WHERE chain_id = $1
	`, chainID).Scan(&gotAllTime); err != nil {
		t.Fatalf("read protocol summary: %v", err)
	}
	if gotAllTime != allTimeLaunches {
		t.Fatalf("protocol all-time launches = %d; want %d", gotAllTime, allTimeLaunches)
	}
	var oldRows int64
	if err := database.QueryRowContext(ctx, `
		SELECT count(*) FROM protocol_daily WHERE chain_id = $1 AND day = $2::date
	`, chainID, oldDay).Scan(&oldRows); err != nil {
		t.Fatalf("check old daily row: %v", err)
	}
	if oldRows != expectedOldRows {
		t.Fatalf("old daily row count = %d; want %d", oldRows, expectedOldRows)
	}
}

type protocolAggregateBarrier struct {
	pool    *pgxpool.Pool
	reached chan struct{}
	resume  chan struct{}
	once    sync.Once
}

func (barrier *protocolAggregateBarrier) Exec(ctx context.Context, query string, args ...any) (pgconn.CommandTag, error) {
	tag, err := barrier.pool.Exec(ctx, query, args...)
	if err == nil {
		err = barrier.pauseAfterClear(ctx, query)
	}
	return tag, err
}

func (barrier *protocolAggregateBarrier) Query(ctx context.Context, query string, args ...any) (pgx.Rows, error) {
	return barrier.pool.Query(ctx, query, args...)
}

func (barrier *protocolAggregateBarrier) QueryRow(ctx context.Context, query string, args ...any) pgx.Row {
	return barrier.pool.QueryRow(ctx, query, args...)
}

func (barrier *protocolAggregateBarrier) BeginTx(ctx context.Context, options pgx.TxOptions) (pgx.Tx, error) {
	tx, err := barrier.pool.BeginTx(ctx, options)
	if err != nil {
		return nil, err
	}
	return &protocolAggregateBarrierTx{Tx: tx, barrier: barrier}, nil
}

func (barrier *protocolAggregateBarrier) pauseAfterClear(ctx context.Context, query string) error {
	if !strings.Contains(query, "DELETE FROM protocol_daily") {
		return nil
	}
	barrier.once.Do(func() { close(barrier.reached) })
	select {
	case <-barrier.resume:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (barrier *protocolAggregateBarrier) release() {
	select {
	case <-barrier.resume:
	default:
		close(barrier.resume)
	}
}

type protocolAggregateBarrierTx struct {
	pgx.Tx
	barrier *protocolAggregateBarrier
}

func (tx *protocolAggregateBarrierTx) Exec(ctx context.Context, query string, args ...any) (pgconn.CommandTag, error) {
	tag, err := tx.Tx.Exec(ctx, query, args...)
	if err == nil {
		err = tx.barrier.pauseAfterClear(ctx, query)
	}
	return tag, err
}

var _ storepostgresTransactionBeginner = (*protocolAggregateBarrier)(nil)
var _ storepostgresDBTX = (*protocolAggregateBarrier)(nil)
var _ storepostgresDBTX = (*protocolAggregateBarrierTx)(nil)

type storepostgresTransactionBeginner interface {
	BeginTx(context.Context, pgx.TxOptions) (pgx.Tx, error)
}

type storepostgresDBTX interface {
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
	Query(context.Context, string, ...any) (pgx.Rows, error)
	QueryRow(context.Context, string, ...any) pgx.Row
}
