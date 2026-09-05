//go:build integration

package postgrestest

import (
	"context"
	"errors"
	"math/big"
	"testing"
	"time"

	"github.com/Contictus/launchtap/backend/internal/ledger"
	storepostgres "github.com/Contictus/launchtap/backend/internal/store/postgres"
	"github.com/ethereum/go-ethereum/common"
)

func TestAllEventWrappersAreIdempotentAndRejectDivergence(t *testing.T) {
	database := NewMigrated(t)
	ctx, cancel := context.WithTimeout(t.Context(), 30*time.Second)
	defer cancel()
	pool := openPool(t, ctx, database.URL)
	adapter := storepostgres.NewAdapter(pool)

	const chainID int64 = 49010
	blockTime := time.Date(2026, 9, 6, 12, 0, 0, 0, time.UTC)
	blockHash := common.Hash{0xa1}
	if _, err := adapter.UpsertIndexedBlock(ctx, ledger.IndexedBlock{ChainID: chainID, BlockNumber: 100, BlockHash: blockHash, ParentHash: common.Hash{0xa0}, BlockTime: blockTime, FinalityStatus: "observed"}); err != nil {
		t.Fatalf("insert event block: %v", err)
	}

	address := func(last byte) common.Address { return common.Address{19: last} }
	amount := func(value int64) *big.Int { return big.NewInt(value) }
	coordinates := func(logIndex int32) ledger.EventCoordinates {
		return ledger.EventCoordinates{ChainID: chainID, BlockNumber: 100, BlockHash: blockHash, BlockTime: blockTime, TransactionIndex: logIndex, TxHash: common.Hash{31: byte(logIndex)}, LogIndex: 0}
	}
	token, curve, creator, pair, weth, treasury := address(1), address(2), address(3), address(4), address(5), address(6)

	launch := ledger.TokenLaunch{EventCoordinates: coordinates(1), Token: token, Curve: curve, Creator: creator, LPPair: pair, WETH: weth, ProtocolTreasury: treasury, EngineVersion: 1, Name: "Pons", Symbol: "PONS", TotalSupply: amount(100), VirtualETH: amount(10), VirtualToken: amount(90), CurveTokens: amount(80), LPTokens: amount(20), GraduationETH: amount(11), LaunchFeePaid: amount(1), TradeFeeBPS: 100, ProtocolShareBPS: 5000}
	trade := ledger.Trade{EventCoordinates: coordinates(2), Token: token, Trader: address(7), IsBuy: true, ETHGross: amount(10), ETHRefund: amount(0), TokenAmount: amount(5), ProtocolFee: amount(1), CreatorFee: amount(1), NewETHReserve: amount(20), NewTokenReserve: amount(85)}
	graduation := ledger.Graduation{EventCoordinates: coordinates(3), Token: token, LPPair: pair, ETHToPool: amount(20), TokensToPool: amount(20), LPLiquidityBurned: amount(1)}
	creatorClaim := ledger.CreatorFeeClaim{EventCoordinates: coordinates(4), Token: token, Creator: creator, Amount: amount(1)}
	protocolClaim := ledger.ProtocolFeeClaim{EventCoordinates: coordinates(5), Token: token, Treasury: treasury, Amount: amount(1)}
	launchClaim := ledger.LaunchFeeClaim{EventCoordinates: coordinates(6), Treasury: treasury, Amount: amount(1)}
	credit := ledger.RefundCredit{EventCoordinates: coordinates(7), Token: token, Account: address(8), Amount: amount(1)}
	claim := ledger.RefundClaim{EventCoordinates: coordinates(8), Token: token, Account: address(8), Amount: amount(1)}
	transfer := ledger.Transfer{EventCoordinates: coordinates(9), Token: token, From: common.Address{}, To: address(9), Value: amount(1)}
	mint := ledger.PoolMint{EventCoordinates: coordinates(10), Pair: pair, Sender: address(10), Amount0: amount(1), Amount1: amount(2)}
	burn := ledger.PoolBurn{EventCoordinates: coordinates(11), Pair: pair, Sender: address(10), Amount0: amount(1), Amount1: amount(2), To: address(11)}
	swap := ledger.PoolSwap{EventCoordinates: coordinates(12), Pair: pair, Sender: address(10), Amount0In: amount(1), Amount1In: amount(2), Amount0Out: amount(3), Amount1Out: amount(4), To: address(11)}
	sync := ledger.PoolSync{EventCoordinates: coordinates(13), Pair: pair, Reserve0: amount(50), Reserve1: amount(60)}
	launchPause := ledger.LaunchPauseEvent{EventCoordinates: coordinates(14), Paused: true}
	tradingPause := ledger.TradingPauseEvent{EventCoordinates: coordinates(15), Paused: true}
	engine := ledger.EngineConfiguration{EventCoordinates: coordinates(16), EngineVersion: 1, Implementation: address(12), Enabled: true}
	defaults := ledger.FutureDefaultsConfiguration{EventCoordinates: coordinates(17), ConfigHash: common.Hash{31: 17}}
	futureTreasury := ledger.FutureTreasuryConfiguration{EventCoordinates: coordinates(18), PreviousTreasury: treasury, NewTreasury: address(13)}

	tests := []struct {
		name      string
		insert    func() (ledger.InsertResult, error)
		divergent func() (ledger.InsertResult, error)
	}{
		{"token launch", func() (ledger.InsertResult, error) { return adapter.InsertTokenLaunch(ctx, launch) }, func() (ledger.InsertResult, error) {
			changed := launch
			changed.Symbol = "DIFF"
			return adapter.InsertTokenLaunch(ctx, changed)
		}},
		{"trade", func() (ledger.InsertResult, error) { return adapter.InsertTrade(ctx, trade) }, func() (ledger.InsertResult, error) {
			changed := trade
			changed.IsBuy = false
			return adapter.InsertTrade(ctx, changed)
		}},
		{"graduation", func() (ledger.InsertResult, error) { return adapter.InsertGraduation(ctx, graduation) }, func() (ledger.InsertResult, error) {
			changed := graduation
			changed.LPPair = address(14)
			return adapter.InsertGraduation(ctx, changed)
		}},
		{"creator claim", func() (ledger.InsertResult, error) { return adapter.InsertCreatorFeeClaim(ctx, creatorClaim) }, func() (ledger.InsertResult, error) {
			changed := creatorClaim
			changed.Creator = address(14)
			return adapter.InsertCreatorFeeClaim(ctx, changed)
		}},
		{"protocol claim", func() (ledger.InsertResult, error) { return adapter.InsertProtocolFeeClaim(ctx, protocolClaim) }, func() (ledger.InsertResult, error) {
			changed := protocolClaim
			changed.Treasury = address(14)
			return adapter.InsertProtocolFeeClaim(ctx, changed)
		}},
		{"launch claim", func() (ledger.InsertResult, error) { return adapter.InsertLaunchFeeClaim(ctx, launchClaim) }, func() (ledger.InsertResult, error) {
			changed := launchClaim
			changed.Treasury = address(14)
			return adapter.InsertLaunchFeeClaim(ctx, changed)
		}},
		{"refund credit", func() (ledger.InsertResult, error) { return adapter.InsertRefundCredit(ctx, credit) }, func() (ledger.InsertResult, error) {
			changed := credit
			changed.Account = address(14)
			return adapter.InsertRefundCredit(ctx, changed)
		}},
		{"refund claim", func() (ledger.InsertResult, error) { return adapter.InsertRefundClaim(ctx, claim) }, func() (ledger.InsertResult, error) {
			changed := claim
			changed.Account = address(14)
			return adapter.InsertRefundClaim(ctx, changed)
		}},
		{"transfer", func() (ledger.InsertResult, error) { return adapter.InsertTransfer(ctx, transfer) }, func() (ledger.InsertResult, error) {
			changed := transfer
			changed.To = address(14)
			return adapter.InsertTransfer(ctx, changed)
		}},
		{"pool mint", func() (ledger.InsertResult, error) { return adapter.InsertPoolMint(ctx, mint) }, func() (ledger.InsertResult, error) {
			changed := mint
			changed.Sender = address(14)
			return adapter.InsertPoolMint(ctx, changed)
		}},
		{"pool burn", func() (ledger.InsertResult, error) { return adapter.InsertPoolBurn(ctx, burn) }, func() (ledger.InsertResult, error) {
			changed := burn
			changed.To = address(14)
			return adapter.InsertPoolBurn(ctx, changed)
		}},
		{"pool swap", func() (ledger.InsertResult, error) { return adapter.InsertPoolSwap(ctx, swap) }, func() (ledger.InsertResult, error) {
			changed := swap
			changed.To = address(14)
			return adapter.InsertPoolSwap(ctx, changed)
		}},
		{"pool sync", func() (ledger.InsertResult, error) { return adapter.InsertPoolSync(ctx, sync) }, func() (ledger.InsertResult, error) {
			changed := sync
			changed.Reserve0 = amount(51)
			return adapter.InsertPoolSync(ctx, changed)
		}},
		{"launch pause", func() (ledger.InsertResult, error) { return adapter.InsertLaunchPauseEvent(ctx, launchPause) }, func() (ledger.InsertResult, error) {
			changed := launchPause
			changed.Paused = false
			return adapter.InsertLaunchPauseEvent(ctx, changed)
		}},
		{"trading pause", func() (ledger.InsertResult, error) { return adapter.InsertTradingPauseEvent(ctx, tradingPause) }, func() (ledger.InsertResult, error) {
			changed := tradingPause
			changed.Paused = false
			return adapter.InsertTradingPauseEvent(ctx, changed)
		}},
		{"engine configuration", func() (ledger.InsertResult, error) { return adapter.InsertEngineConfiguration(ctx, engine) }, func() (ledger.InsertResult, error) {
			changed := engine
			changed.Enabled = false
			return adapter.InsertEngineConfiguration(ctx, changed)
		}},
		{"future defaults", func() (ledger.InsertResult, error) { return adapter.InsertFutureDefaultsConfiguration(ctx, defaults) }, func() (ledger.InsertResult, error) {
			changed := defaults
			changed.ConfigHash = common.Hash{31: 18}
			return adapter.InsertFutureDefaultsConfiguration(ctx, changed)
		}},
		{"future treasury", func() (ledger.InsertResult, error) {
			return adapter.InsertFutureTreasuryConfiguration(ctx, futureTreasury)
		}, func() (ledger.InsertResult, error) {
			changed := futureTreasury
			changed.NewTreasury = address(14)
			return adapter.InsertFutureTreasuryConfiguration(ctx, changed)
		}},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			first, err := test.insert()
			if err != nil || !first.Inserted {
				t.Fatalf("first insert = %+v, %v; want inserted", first, err)
			}
			replay, err := test.insert()
			if err != nil || replay.Inserted {
				t.Fatalf("identical replay = %+v, %v; want no insert", replay, err)
			}
			_, err = test.divergent()
			var conflict *storepostgres.InvariantConflictError
			if !errors.As(err, &conflict) {
				t.Fatalf("divergent replay error = %T %v, want InvariantConflictError", err, err)
			}
		})
	}
}
