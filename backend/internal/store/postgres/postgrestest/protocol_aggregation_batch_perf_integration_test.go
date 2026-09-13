//go:build integration

package postgrestest

import (
	"context"
	"database/sql"
	"os"
	"reflect"
	"sort"
	"testing"
	"time"

	"github.com/Contictus/launchtap/backend/internal/stats"
	storepostgres "github.com/Contictus/launchtap/backend/internal/store/postgres"
	"github.com/ethereum/go-ethereum/common"
)

const (
	aggregationPerfEnv        = "LAUNCHPAD_AGGREGATION_PERF"
	aggregationPerfTokenCount = 32
	aggregationPerfTradeCount = 200_000
)

// TestProtocolAggregationBatchPerf is a reproducible opt-in PostgreSQL 18
// measurement. Run with LAUNCHPAD_AGGREGATION_PERF=1 and DATABASE_URL pointing
// at a disposable PostgreSQL 18 server:
// go test -tags=integration ./internal/store/postgres/postgrestest -run '^TestProtocolAggregationBatchPerf$' -count=1 -v
func TestProtocolAggregationBatchPerf(t *testing.T) {
	if os.Getenv(aggregationPerfEnv) != "1" {
		t.Skipf("set %s=1 to run the bounded 200k-row aggregation benchmark", aggregationPerfEnv)
	}

	database := NewMigrated(t)
	ctx, cancel := context.WithTimeout(t.Context(), 4*time.Minute)
	defer cancel()
	pool := openPool(t, ctx, database.URL)
	const chainID int64 = 48009
	now := time.Now().UTC().Truncate(time.Second)
	tradeTime := now.Add(-time.Hour)

	claims := make([]stats.Claim, aggregationPerfTokenCount)
	seedStarted := time.Now()
	for i := range claims {
		ordinal := byte(i + 1)
		blockHash := hashBytes(ordinal)
		blockTime := now.Add(time.Duration(i) * time.Second)
		mustInsertBlock(t, ctx, database.DB, chainID, int64(i+1), blockHash, hashBytes(ordinal+32), blockTime, "observed")
		token, curve := addressBytes(ordinal+64), addressBytes(ordinal+96)
		pair, weth := addressBytes(ordinal+128), addressBytes(0xf0)
		insertProjectionLaunch(t, ctx, database.DB, chainID, int64(i+1), blockHash, blockTime, hashBytes(ordinal+160), projectionLaunchFixture{
			token: token, curve: curve, pair: pair, weth: weth,
		})
		callRebuild(t, ctx, database.DB, chainID, token)
		claims[i] = stats.Claim{ChainID: chainID, Token: [20]byte(token), Generation: 1}
	}

	if _, err := database.DB.ExecContext(ctx, `
		INSERT INTO indexed_blocks (chain_id, block_number, block_hash, parent_hash, block_time, finality_status)
		SELECT $1, 1000 + value,
		       decode(lpad(to_hex(value::bigint), 64, '0'), 'hex'),
		       decode(lpad(to_hex((value - 1)::bigint), 64, '0'), 'hex'),
		       $2, 'observed'
	FROM generate_series(1, $3::integer) AS generated(value)
	`, chainID, tradeTime, aggregationPerfTradeCount); err != nil {
		t.Fatalf("seed canonical blocks for perf fixture: %v", err)
	}
	if _, err := database.DB.ExecContext(ctx, `
		WITH token_order AS (
			SELECT token_address, row_number() OVER (ORDER BY block_number) - 1 AS ordinal
			FROM token_launches WHERE chain_id = $1
	)
		INSERT INTO trades (
			chain_id, block_number, block_hash, block_time, transaction_index, tx_hash, log_index,
			token_address, trader, is_buy, eth_gross, eth_refund, token_amount,
			protocol_fee, creator_fee, new_eth_reserve, new_token_reserve
		)
		SELECT $1, 1000 + generated.value,
		       decode(lpad(to_hex(generated.value::bigint), 64, '0'), 'hex'),
		       $2, 0,
		       decode(lpad(to_hex((1000000 + generated.value)::bigint), 64, '0'), 'hex'),
		       0, token_order.token_address,
		       decode('0000000000000000000000000000000000000001', 'hex'), TRUE,
		       1000000000000000, 0, 1000000000000000000, 0, 0, 10, 1000
		FROM generate_series(1, $3::integer) AS generated(value)
		JOIN token_order ON token_order.ordinal = ((generated.value - 1) % $4::bigint)
	`, chainID, tradeTime, aggregationPerfTradeCount, aggregationPerfTokenCount); err != nil {
		t.Fatalf("seed market trades for perf fixture: %v", err)
	}
	var marketRows, dirtyRows int64
	if err := database.DB.QueryRowContext(ctx, `SELECT count(*) FROM market_trades WHERE chain_id = $1`, chainID).Scan(&marketRows); err != nil {
		t.Fatalf("count seeded market rows: %v", err)
	}
	if err := database.DB.QueryRowContext(ctx, `SELECT count(*) FROM aggregation_dirty WHERE chain_id = $1`, chainID).Scan(&dirtyRows); err != nil {
		t.Fatalf("count seeded dirty rows: %v", err)
	}
	if marketRows != aggregationPerfTradeCount || dirtyRows != aggregationPerfTokenCount {
		t.Fatalf("fixture cardinality: market rows=%d dirty rows=%d; want %d/%d", marketRows, dirtyRows, aggregationPerfTradeCount, aggregationPerfTokenCount)
	}
	t.Logf("fixture market_rows=%d dirty_tokens=%d seed_ms=%d", marketRows, dirtyRows, time.Since(seedStarted).Milliseconds())

	countingDB := &protocolAggregateCountingDB{pool: pool}
	adapter := storepostgres.NewAdapter(countingDB)
	source := storepostgres.AggregationSource{Adapter: adapter}
	claims, err := source.Claim(ctx, "perf-worker", aggregationPerfTokenCount)
	if err != nil || len(claims) != aggregationPerfTokenCount {
		t.Fatalf("claim seeded dirty tokens: claims=%d err=%v", len(claims), err)
	}
	beforeSamples := make([]time.Duration, 0, 4)
	afterSamples := make([]time.Duration, 0, 4)
	orders := []string{"AB", "BA", "AB", "BA"} // A=old per-claim path, B=batched path.
	for pair, order := range orders {
		var outputs [2]protocolAggregateSnapshot
		var elapsed [2]time.Duration
		for side := 0; side < 2; side++ {
			method := order[side]
			resetAggregationOutputs(t, ctx, database.DB, chainID)
			countingDB.reset()
			started := time.Now()
			if method == 'A' {
				for _, claim := range claims {
					if err := adapter.RecomputeTokenStats(ctx, claim.ChainID, common.Address(claim.Token)); err != nil {
						t.Fatalf("pair %d old token refresh: %v", pair+1, err)
					}
					if err := adapter.RecomputeProtocolAggregates(ctx, claim.ChainID); err != nil {
						t.Fatalf("pair %d old protocol refresh: %v", pair+1, err)
					}
				}
				assertAggregationCounts(t, countingDB, 128, 96, 32, 32)
			} else {
				results := source.ComputeBatch(ctx, claims)
				for i, err := range results {
					if err != nil {
						t.Fatalf("pair %d batched claim %d: %v", pair+1, i, err)
					}
				}
				assertAggregationCounts(t, countingDB, 35, 3, 32, 1)
			}
			elapsed[side] = time.Since(started)
			outputs[side] = snapshotProtocolAggregates(t, ctx, database.DB, chainID)
			if method == 'A' {
				beforeSamples = append(beforeSamples, elapsed[side])
			} else {
				afterSamples = append(afterSamples, elapsed[side])
			}
		}
		if !reflect.DeepEqual(outputs[0], outputs[1]) {
			t.Fatalf("pair %d order %s output mismatch:\nfirst: %#v\nsecond: %#v", pair+1, order, outputs[0], outputs[1])
		}
		t.Logf("pair=%d order=%s old_ms=%d batched_ms=%d old_counts=128/96 batched_counts=35/3 parity=true", pair+1, order, elapsedForMethod(order, elapsed, 'A').Milliseconds(), elapsedForMethod(order, elapsed, 'B').Milliseconds())
	}
	maxBatch := maxDuration(afterSamples)
	if maxBatch >= 30*time.Second {
		t.Fatalf("max batch duration %s reaches the fixed 30s dirty-claim lease", maxBatch)
	}
	t.Logf("old_ms=%v old_median_ms=%d protocol_statements=96 total_compute_statements=128 tx=32", durationMillis(beforeSamples), medianDuration(beforeSamples).Milliseconds())
	t.Logf("batched_ms=%v batched_median_ms=%d batched_max_ms=%d protocol_statements=3 total_compute_statements=35 tx=1 output_parity=true lease=30s", durationMillis(afterSamples), medianDuration(afterSamples).Milliseconds(), maxBatch.Milliseconds())

}

func resetAggregationOutputs(t *testing.T, ctx context.Context, database *sql.DB, chainID int64) {
	t.Helper()
	for _, table := range []string{"token_stats", "protocol_daily", "protocol_stats"} {
		if _, err := database.ExecContext(ctx, "DELETE FROM "+table+" WHERE chain_id = $1", chainID); err != nil {
			t.Fatalf("reset %s before timing: %v", table, err)
		}
	}
	var rows int64
	if err := database.QueryRowContext(ctx, `
		SELECT (SELECT count(*) FROM token_stats WHERE chain_id = $1)
		     + (SELECT count(*) FROM protocol_daily WHERE chain_id = $1)
		     + (SELECT count(*) FROM protocol_stats WHERE chain_id = $1)
	`, chainID).Scan(&rows); err != nil {
		t.Fatalf("verify aggregate reset: %v", err)
	}
	if rows != 0 {
		t.Fatalf("aggregate reset left %d rows", rows)
	}
}

func elapsedForMethod(order string, elapsed [2]time.Duration, method byte) time.Duration {
	for i := range order {
		if order[i] == method {
			return elapsed[i]
		}
	}
	panic("benchmark order omitted method")
}

func assertAggregationCounts(t *testing.T, database *protocolAggregateCountingDB, total, protocol, tokenStats, transactions int) {
	t.Helper()
	gotProtocol := database.clearDailyCalls + database.dailyCalls + database.protocolStatsCalls
	if database.statementCalls != total || gotProtocol != protocol || database.tokenStatsCalls != tokenStats || database.transactions != transactions {
		t.Fatalf("compute statement counts total/protocol/token-stats/transactions=%d/%d/%d/%d; want %d/%d/%d/%d",
			database.statementCalls, gotProtocol, database.tokenStatsCalls, database.transactions, total, protocol, tokenStats, transactions)
	}
}

func durationMillis(values []time.Duration) []int64 {
	result := make([]int64, len(values))
	for i, value := range values {
		result[i] = value.Milliseconds()
	}
	return result
}

func medianDuration(values []time.Duration) time.Duration {
	ordered := append([]time.Duration(nil), values...)
	sort.Slice(ordered, func(i, j int) bool { return ordered[i] < ordered[j] })
	middle := len(ordered) / 2
	if len(ordered)%2 == 1 {
		return ordered[middle]
	}
	return (ordered[middle-1] + ordered[middle]) / 2
}

func maxDuration(values []time.Duration) time.Duration {
	var max time.Duration
	for _, value := range values {
		if value > max {
			max = value
		}
	}
	return max
}
