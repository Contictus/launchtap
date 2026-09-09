package stats

import (
	"math/big"
	"testing"
	"time"

	"github.com/ethereum/go-ethereum/common"
)

func TestComputeTokenStatsUsesCirculatingSupplyAndHolderExclusions(t *testing.T) {
	at := time.Date(2026, 9, 8, 12, 0, 0, 0, time.UTC)
	curve, pair, owner := common.Address{1}, common.Address{2}, common.Address{3}
	got := ComputeTokenStats(TokenInput{
		Token:        common.Address{4},
		Curve:        curve,
		Pair:         pair,
		LaunchPrice:  big.NewInt(10),
		LaunchAt:     at,
		ReserveETH:   new(big.Int).Mul(big.NewInt(2), wad),
		ReserveToken: new(big.Int).Mul(big.NewInt(1), wad),
		TotalSupply:  new(big.Int).Mul(big.NewInt(100), wad),
		Holders: []Holder{
			{Address: curve, Balance: new(big.Int).Mul(big.NewInt(80), wad)},
			{Address: pair, Balance: new(big.Int).Mul(big.NewInt(20), wad)},
			{Address: owner, Balance: new(big.Int).Mul(big.NewInt(1), wad)},
			{Address: zeroAddress, Balance: new(big.Int).Mul(big.NewInt(1), wad)},
			{Address: deadAddress, Balance: new(big.Int).Mul(big.NewInt(1), wad)},
		},
	}, at.Add(time.Hour))
	if got.ATH.Cmp(big.NewInt(10)) != 0 || got.HolderCount != 1 || got.SpotPrice.Cmp(new(big.Int).Mul(big.NewInt(2), wad)) != 0 {
		t.Fatalf("stats=%+v", got)
	}
	if got.FDV.Cmp(new(big.Int).Mul(big.NewInt(200), wad)) != 0 || got.MarketCap.Cmp(new(big.Int).Mul(big.NewInt(36), wad)) != 0 {
		t.Fatalf("supply stats=%+v", got)
	}
}

func TestComputeTokenStatsUsesBoundaryCandleForSignedChangeAndStableATH(t *testing.T) {
	now := time.Date(2026, 9, 8, 12, 0, 0, 0, time.UTC)
	got := ComputeTokenStats(TokenInput{
		LaunchPrice: big.NewInt(10),
		LaunchAt:    now.Add(-48 * time.Hour),
		Candles: []Candle{
			{Start: now.Add(-25 * time.Hour), High: big.NewInt(100), Close: big.NewInt(100), Volume: big.NewInt(1)},
			{Start: now.Add(-24 * time.Hour), High: big.NewInt(200), Close: big.NewInt(80), Volume: big.NewInt(2)},
			{Start: now.Add(-time.Hour), High: big.NewInt(200), Close: big.NewInt(60), Volume: big.NewInt(3)},
		},
	}, now)
	if got.ATH.Cmp(big.NewInt(200)) != 0 || !got.ATHAt.Equal(now.Add(-24*time.Hour)) || got.Volume24H.Cmp(big.NewInt(5)) != 0 || got.PriceChange24hBPS != -2500 {
		t.Fatalf("stats=%+v", got)
	}
}
