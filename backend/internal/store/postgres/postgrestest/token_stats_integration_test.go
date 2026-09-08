//go:build integration

package postgrestest

import (
	"context"
	"testing"
	"time"

	storepostgres "github.com/Contictus/launchtap/backend/internal/store/postgres"
	"github.com/ethereum/go-ethereum/common"
)

func TestRecomputeTokenStatsUsesCanonicalSupplyAndCandleHistory(t *testing.T) {
	database := NewMigrated(t)
	ctx, cancel := context.WithTimeout(t.Context(), 30*time.Second)
	defer cancel()
	pool := openPool(t, ctx, database.URL)

	const chainID int64 = 48005
	now := time.Now().UTC().Truncate(time.Minute)
	blockHash := hashBytes(0x51)
	token, curve, pair, weth := addressBytes(0x52), addressBytes(0x53), addressBytes(0x54), addressBytes(0x55)
	dead := make([]byte, 20)
	dead[18], dead[19] = 0xde, 0xad
	mustInsertBlock(t, ctx, database.DB, chainID, 1, blockHash, hashBytes(0x50), now.Add(-26*time.Hour), "observed")
	insertProjectionLaunch(t, ctx, database.DB, chainID, 1, blockHash, now.Add(-26*time.Hour), hashBytes(0x56), projectionLaunchFixture{token: token, curve: curve, pair: pair, weth: weth})
	callRebuild(t, ctx, database.DB, chainID, token)

	if _, err := database.DB.ExecContext(ctx, `
		INSERT INTO token_reserves (
			chain_id, token_address, reserve_source, eth_reserve, token_reserve,
			source_block_number, source_block_hash, source_block_time, source_tx_hash, source_log_index
		) VALUES ($1, $2, 'curve', 200, 100, 1, $3, $4, $5, 1)
	`, chainID, token, blockHash, now.Add(-26*time.Hour), hashBytes(0x57)); err != nil {
		t.Fatalf("insert reserve: %v", err)
	}
	for _, holder := range []struct {
		address []byte
		balance int64
	}{
		{curve, 799999},
		{pair, 100000},
		{addressBytes(0), 50000},
		{dead, 50000},
		{addressBytes(0x59), 1},
	} {
		if _, err := database.DB.ExecContext(ctx, `
			INSERT INTO holder_balances (chain_id, token_address, holder_address, balance, first_acquired_block_number)
			VALUES ($1, $2, $3, $4, 1)
		`, chainID, token, holder.address, holder.balance); err != nil {
			t.Fatalf("insert holder: %v", err)
		}
	}
	for _, candle := range []struct {
		start               time.Time
		high, close, volume string
	}{
		{now.Add(-25 * time.Hour), "1000000000000000", "1000000000000000", "1"},
		{now.Add(-24*time.Hour - time.Minute), "2000000000000000", "800000000000000", "2"},
		{now.Add(-time.Hour), "2000000000000000", "600000000000000", "3"},
	} {
		if _, err := database.DB.ExecContext(ctx, `
			INSERT INTO candles (
				chain_id, token_address, interval, bucket_start_time,
				open_price_wad, high_price_wad, low_price_wad, close_price_wad, gross_eth_volume
			) VALUES ($1, $2, '1m', $3, $4, $4, $4, $5, $6)
		`, chainID, token, candle.start, candle.high, candle.close, candle.volume); err != nil {
			t.Fatalf("insert candle: %v", err)
		}
	}

	adapter := storepostgres.NewAdapter(pool)
	if err := adapter.RecomputeTokenStats(ctx, chainID, common.Address(token)); err != nil {
		t.Fatalf("recompute token stats: %v", err)
	}
	assertTokenStats(t, ctx, database, chainID, token, "2000000000000000000", "200002", "2000000", "2000000000000000", now.Add(-24*time.Hour-time.Minute))

	if _, err := database.DB.ExecContext(ctx, `DELETE FROM candles WHERE chain_id=$1 AND token_address=$2 AND high_price_wad=2000000000000000`, chainID, token); err != nil {
		t.Fatalf("delete former ATH candles: %v", err)
	}
	if err := adapter.DeleteTokenStats(ctx, chainID, common.Address(token)); err != nil {
		t.Fatalf("delete invalidated stats: %v", err)
	}
	if err := adapter.RecomputeTokenStats(ctx, chainID, common.Address(token)); err != nil {
		t.Fatalf("recompute surviving stats: %v", err)
	}
	var ath string
	if err := database.DB.QueryRowContext(ctx, `SELECT ath_price_eth_wad::TEXT FROM token_stats WHERE chain_id=$1 AND token_address=$2`, chainID, token).Scan(&ath); err != nil {
		t.Fatalf("read rebuilt ATH: %v", err)
	}
	if ath != "1000000000000000" {
		t.Fatalf("rebuilt ATH = %s, want surviving candle high", ath)
	}
}

func assertTokenStats(t testing.TB, ctx context.Context, database *Database, chainID int64, token []byte, spot, marketCap, fdv, ath string, athAt time.Time) {
	t.Helper()
	var gotSpot, gotMarketCap, gotFDV, gotATH string
	var holders, change int
	var volume string
	var gotATHAt time.Time
	if err := database.DB.QueryRowContext(ctx, `
		SELECT spot_price_eth_wad::TEXT, market_cap_eth_wad::TEXT, fdv_eth_wad::TEXT,
			ath_price_eth_wad::TEXT, ath_at, volume_24h_eth_wad::TEXT, price_change_24h_bps, holder_count
		FROM token_stats WHERE chain_id=$1 AND token_address=$2
	`, chainID, token).Scan(&gotSpot, &gotMarketCap, &gotFDV, &gotATH, &gotATHAt, &volume, &change, &holders); err != nil {
		t.Fatalf("read token stats: %v", err)
	}
	if gotSpot != spot || gotMarketCap != marketCap || gotFDV != fdv || gotATH != ath || !gotATHAt.Equal(athAt) || volume != "3" || change != -2500 || holders != 1 {
		t.Fatalf("token stats = spot=%s market_cap=%s fdv=%s ath=%s ath_at=%s volume=%s change=%d holders=%d", gotSpot, gotMarketCap, gotFDV, gotATH, gotATHAt, volume, change, holders)
	}
}
