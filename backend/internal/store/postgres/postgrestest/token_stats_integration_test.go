//go:build integration

package postgrestest

import (
	"context"
	"math/big"
	"testing"
	"time"

	"github.com/Contictus/launchtap/backend/internal/stats"
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
	expected := stats.ComputeTokenStats(stats.TokenInput{
		Token:        common.Address(token),
		Curve:        common.Address(curve),
		Pair:         common.Address(pair),
		LaunchPrice:  big.NewInt(10_000_000_000_000),
		LaunchAt:     now.Add(-26 * time.Hour),
		ReserveETH:   big.NewInt(200),
		ReserveToken: big.NewInt(100),
		TotalSupply:  big.NewInt(1_000_000),
		Holders: []stats.Holder{
			{Address: common.Address(curve), Balance: big.NewInt(799_999)},
			{Address: common.Address(pair), Balance: big.NewInt(100_000)},
			{Address: common.Address(addressBytes(0)), Balance: big.NewInt(50_000)},
			{Address: common.HexToAddress("0x000000000000000000000000000000000000dEaD"), Balance: big.NewInt(50_000)},
			{Address: common.Address(addressBytes(0x59)), Balance: big.NewInt(1)},
		},
		Candles: []stats.Candle{
			{Start: now.Add(-25 * time.Hour), High: big.NewInt(1_000_000_000_000_000), Close: big.NewInt(1_000_000_000_000_000), Volume: big.NewInt(1)},
			{Start: now.Add(-24*time.Hour - time.Minute), High: big.NewInt(2_000_000_000_000_000), Close: big.NewInt(800_000_000_000_000), Volume: big.NewInt(2)},
			{Start: now.Add(-time.Hour), High: big.NewInt(2_000_000_000_000_000), Close: big.NewInt(600_000_000_000_000), Volume: big.NewInt(3)},
		},
	}, now)
	assertTokenStatsMatchesCalculator(t, ctx, database, chainID, token, expected)

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

func assertTokenStatsMatchesCalculator(t testing.TB, ctx context.Context, database *Database, chainID int64, token []byte, expected stats.TokenStats) {
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
	if gotSpot != expected.SpotPrice.String() || gotMarketCap != expected.MarketCap.String() || gotFDV != expected.FDV.String() || gotATH != expected.ATH.String() || !gotATHAt.Equal(expected.ATHAt) || volume != expected.Volume24H.String() || int64(change) != expected.PriceChange24hBPS || int64(holders) != expected.HolderCount {
		t.Fatalf("token stats diverge from calculator: got spot=%s market_cap=%s fdv=%s ath=%s ath_at=%s volume=%s change=%d holders=%d; want %+v", gotSpot, gotMarketCap, gotFDV, gotATH, gotATHAt, volume, change, holders, expected)
	}
}
