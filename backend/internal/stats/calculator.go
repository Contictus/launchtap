// Package stats computes rebuildable aggregate values from projection snapshots.
package stats

import (
	"math/big"
	"time"

	"github.com/ethereum/go-ethereum/common"
)

type Holder struct { Address common.Address; Balance *big.Int }
type Candle struct { Start time.Time; Open,High,Low,Close,Volume *big.Int; Trades int64 }
type TokenInput struct {
	Token common.Address
	LaunchPrice *big.Int
	LaunchAt time.Time
	ReserveETH,ReserveToken *big.Int
	TotalSupply *big.Int
	Candles []Candle
	Holders []Holder
}
type TokenStats struct {
	Token common.Address
	SpotPrice,MarketCap,FDV,Liquidity,ATH,Volume24H *big.Int
	ATHAt time.Time
	PriceChange24hBPS int64
	HolderCount int64
}

var zero = new(big.Int)

// ComputeTokenStats is deterministic and uses only projection data. ATH is
// monotonic for normal worker updates; rollback callers pass the rebuilt input.
func ComputeTokenStats(input TokenInput, now time.Time) TokenStats {
	result:=TokenStats{Token:input.Token,SpotPrice:new(big.Int),MarketCap:new(big.Int),FDV:new(big.Int),Liquidity:new(big.Int),ATH:new(big.Int).Set(input.LaunchPrice),ATHAt:input.LaunchAt,Volume24H:new(big.Int)}
	if input.ReserveETH!=nil&&input.ReserveToken!=nil&&input.ReserveToken.Sign()>0{result.SpotPrice.Mul(input.ReserveETH,new(big.Int).Exp(big.NewInt(10),big.NewInt(18),nil));result.SpotPrice.Div(result.SpotPrice,input.ReserveToken)}
	if input.TotalSupply!=nil{result.FDV.Mul(result.SpotPrice,input.TotalSupply);result.MarketCap.Set(result.FDV)}
	if input.ReserveETH!=nil{result.Liquidity.Set(input.ReserveETH)}
	cutoff:=now.Add(-24*time.Hour)
	var prior,latest *big.Int
	for _,c:=range input.Candles{
		if c.High!=nil&&c.High.Cmp(result.ATH)>0{result.ATH.Set(c.High);result.ATHAt=c.Start}
		if c.Start.Before(cutoff){continue}
		if c.Volume!=nil{result.Volume24H.Add(result.Volume24H,c.Volume)}
		if prior==nil||c.Start.Before(cutoff){prior=new(big.Int).Set(c.Close)}
		if latest==nil||c.Start.After(cutoff){latest=new(big.Int).Set(c.Close)}
	}
	if prior!=nil&&prior.Sign()>0&&latest!=nil{delta:=new(big.Int).Sub(latest,prior);delta.Mul(delta,big.NewInt(10000));result.PriceChange24hBPS=delta.Div(delta,prior).Int64()}
	for _,holder:=range input.Holders{if holder.Balance==nil||holder.Balance.Sign()<=0{continue};result.HolderCount++}
	_ = zero
	return result
}
