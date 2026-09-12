//go:build integration

package postgrestest

import (
	"context"
	"errors"
	"math/big"
	"testing"
	"time"

	"github.com/Contictus/launchtap/backend/internal/stats"
	storepostgres "github.com/Contictus/launchtap/backend/internal/store/postgres"
	"github.com/ethereum/go-ethereum/common"
	"github.com/jackc/pgx/v5/pgconn"
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

func TestRecomputeTokenStatsPriceChangeIntegerBoundary(t *testing.T) {
	database := NewMigrated(t)
	ctx, cancel := context.WithTimeout(t.Context(), 30*time.Second)
	defer cancel()
	pool := openPool(t, ctx, database.URL)

	const chainID int64 = 48008
	now := time.Now().UTC().Truncate(time.Second)
	blockHash := hashBytes(0x71)
	token, curve, pair, weth := addressBytes(0x72), addressBytes(0x73), addressBytes(0x74), addressBytes(0x75)
	mustInsertBlock(t, ctx, database.DB, chainID, 1, blockHash, hashBytes(0x70), now.Add(-26*time.Hour), "observed")
	insertProjectionLaunch(t, ctx, database.DB, chainID, 1, blockHash, now.Add(-26*time.Hour), hashBytes(0x76), projectionLaunchFixture{
		token: token, curve: curve, pair: pair, weth: weth,
	})
	callRebuild(t, ctx, database.DB, chainID, token)
	insert := func(bucket time.Time, price string) {
		t.Helper()
		if _, err := database.DB.ExecContext(ctx, `
			INSERT INTO candles (
				chain_id, token_address, interval, bucket_start_time,
				open_price_wad, high_price_wad, low_price_wad, close_price_wad
			) VALUES ($1, $2, '1m', $3, $4, $4, $4, $4)
		`, chainID, token, bucket, price); err != nil {
			t.Fatalf("insert boundary candle at %s: %v", bucket, err)
		}
	}
	baselineAt, latestAt := now.Add(-25*time.Hour), now.Add(-time.Hour)
	insert(baselineAt, "1")
	insert(latestAt, "214749")

	adapter := storepostgres.NewAdapter(pool)
	if err := adapter.RecomputeTokenStats(ctx, chainID, common.Address(token)); err != nil {
		t.Fatalf("recompute just-inside INTEGER price change: %v", err)
	}
	var inside int32
	if err := database.DB.QueryRowContext(ctx, `
		SELECT price_change_24h_bps FROM token_stats WHERE chain_id = $1 AND token_address = $2
	`, chainID, token).Scan(&inside); err != nil {
		t.Fatalf("read just-inside price change: %v", err)
	}
	insideMirror := stats.ComputeTokenStats(stats.TokenInput{Candles: []stats.Candle{
		{Start: baselineAt, Close: big.NewInt(1)},
		{Start: latestAt, Close: big.NewInt(214749)},
	}}, now)
	if inside != 2_147_480_000 || int64(inside) != insideMirror.PriceChange24hBPS {
		t.Fatalf("just-inside SQL/mirror values = %d/%d; want 2147480000", inside, insideMirror.PriceChange24hBPS)
	}

	if _, err := database.DB.ExecContext(ctx, `
		UPDATE candles
		SET open_price_wad = 214750, high_price_wad = 214750, low_price_wad = 214750, close_price_wad = 214750
		WHERE chain_id = $1 AND token_address = $2 AND interval = '1m' AND bucket_start_time = $3
	`, chainID, token, latestAt); err != nil {
		t.Fatalf("update just-outside candle: %v", err)
	}
	err := adapter.RecomputeTokenStats(ctx, chainID, common.Address(token))
	var pgError *pgconn.PgError
	if !errors.As(err, &pgError) || pgError.Code != "22003" {
		t.Fatalf("just-outside price change error = %v; want PostgreSQL numeric_value_out_of_range (22003)", err)
	}
	outsideMirror := stats.ComputeTokenStats(stats.TokenInput{Candles: []stats.Candle{
		{Start: baselineAt, Close: big.NewInt(1)},
		{Start: latestAt, Close: big.NewInt(214750)},
	}}, now)
	if outsideMirror.PriceChange24hBPS != 2_147_490_000 {
		t.Fatalf("just-outside calculator value = %d; want 2147490000", outsideMirror.PriceChange24hBPS)
	}
	var persisted int32
	if err := database.DB.QueryRowContext(ctx, `
		SELECT price_change_24h_bps FROM token_stats WHERE chain_id = $1 AND token_address = $2
	`, chainID, token).Scan(&persisted); err != nil {
		t.Fatalf("read token stats after rejected update: %v", err)
	}
	if persisted != inside {
		t.Fatalf("price change after rejected update = %d; want prior value %d", persisted, inside)
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
