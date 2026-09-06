package stats

import("math/big";"testing";"time";"github.com/ethereum/go-ethereum/common")
func TestComputeTokenStatsSeedsATHAndCountsPositiveHolders(t *testing.T){at:=time.Unix(100,0);got:=ComputeTokenStats(TokenInput{Token:common.Address{1},LaunchPrice:big.NewInt(10),LaunchAt:at,ReserveETH:big.NewInt(2),ReserveToken:big.NewInt(1),TotalSupply:big.NewInt(100),Holders:[]Holder{{Balance:big.NewInt(1)},{Balance:big.NewInt(0)}}},at.Add(time.Hour));if got.ATH.Cmp(big.NewInt(10))!=0||got.HolderCount!=1||got.SpotPrice.Sign()!=1{t.Fatalf("stats=%+v",got)}}
