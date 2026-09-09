package postgres

import (
	"testing"

	"github.com/Contictus/launchtap/backend/internal/chain"
	"github.com/Contictus/launchtap/backend/internal/ledger"
)

// This compile-time contract forces every decoded ABI payload field through its
// neutral ledger counterpart. The conversion helpers then force every ledger
// field into its generated SQLC insert parameters.
func TestLedgerPayloadsCoverDecodedChainPayloads(t *testing.T) {
	t.Helper()
	launched := chain.TokenLaunched{}
	_ = ledger.TokenLaunch{Token: launched.Token, Curve: launched.Curve, Creator: launched.Creator, LPPair: launched.LPPair, WETH: launched.WETH, ProtocolTreasury: launched.ProtocolTreasury, EngineVersion: launched.EngineVersion, Name: launched.Name, Symbol: launched.Symbol, TotalSupply: launched.TotalSupply, VirtualETH: launched.VirtualETH, VirtualToken: launched.VirtualToken, CurveTokens: launched.CurveTokens, LPTokens: launched.LPTokens, GraduationETH: launched.GraduationETH, LaunchFeePaid: launched.LaunchFeePaid, TradeFeeBPS: launched.TradeFeeBPS, ProtocolShareBPS: launched.ProtocolShareBPS}
	trade := chain.Trade{}
	_ = ledger.Trade{Token: trade.Token, Trader: trade.Trader, IsBuy: trade.IsBuy, ETHGross: trade.ETHGross, ETHRefund: trade.ETHRefund, TokenAmount: trade.TokenAmount, ProtocolFee: trade.ProtocolFee, CreatorFee: trade.CreatorFee, NewETHReserve: trade.NewETHReserve, NewTokenReserve: trade.NewTokenReserve}
	graduation := chain.Graduated{}
	_ = ledger.Graduation{Token: graduation.Token, LPPair: graduation.LPPair, ETHToPool: graduation.ETHToPool, TokensToPool: graduation.TokensToPool, LPLiquidityBurned: graduation.LPLiquidityBurned}
	creatorClaim := chain.CreatorFeesClaimed{}
	_ = ledger.CreatorFeeClaim{Token: creatorClaim.Token, Creator: creatorClaim.Creator, Amount: creatorClaim.Amount}
	protocolClaim := chain.ProtocolFeesClaimed{}
	_ = ledger.ProtocolFeeClaim{Token: protocolClaim.Token, Treasury: protocolClaim.Treasury, Amount: protocolClaim.Amount}
	launchClaim := chain.LaunchFeesClaimed{}
	_ = ledger.LaunchFeeClaim{Treasury: launchClaim.Treasury, Amount: launchClaim.Amount}
	credit := chain.RefundCredited{}
	_ = ledger.RefundCredit{Token: credit.Token, Account: credit.Account, Amount: credit.Amount}
	claim := chain.RefundClaimed{}
	_ = ledger.RefundClaim{Token: claim.Token, Account: claim.Account, Amount: claim.Amount}
	transfer := chain.Transfer{}
	_ = ledger.Transfer{Token: transfer.Token, From: transfer.From, To: transfer.To, Value: transfer.Value}
	mint := chain.PoolMint{}
	_ = ledger.PoolMint{Pair: mint.Pair, Sender: mint.Sender, Amount0: mint.Amount0, Amount1: mint.Amount1}
	burn := chain.PoolBurn{}
	_ = ledger.PoolBurn{Pair: burn.Pair, Sender: burn.Sender, Amount0: burn.Amount0, Amount1: burn.Amount1, To: burn.To}
	swap := chain.PoolSwap{}
	_ = ledger.PoolSwap{Pair: swap.Pair, Sender: swap.Sender, Amount0In: swap.Amount0In, Amount1In: swap.Amount1In, Amount0Out: swap.Amount0Out, Amount1Out: swap.Amount1Out, To: swap.To}
	sync := chain.PoolSync{}
	_ = ledger.PoolSync{Pair: sync.Pair, Reserve0: sync.Reserve0, Reserve1: sync.Reserve1}
	launchPause := chain.LaunchPauseSet{}
	_ = ledger.LaunchPauseEvent{Paused: launchPause.Paused}
	tradingPause := chain.TradingPauseSet{}
	_ = ledger.TradingPauseEvent{Paused: tradingPause.Paused}
	engine := chain.EngineConfigured{}
	_ = ledger.EngineConfiguration{EngineVersion: engine.EngineVersion, Implementation: engine.Implementation, Enabled: engine.Enabled}
	defaults := chain.FutureDefaultsConfigured{}
	_ = ledger.FutureDefaultsConfiguration{ConfigHash: defaults.ConfigHash}
	futureTreasury := chain.FutureTreasuryConfigured{}
	_ = ledger.FutureTreasuryConfiguration{PreviousTreasury: futureTreasury.PreviousTreasury, NewTreasury: futureTreasury.NewTreasury}
}
