//go:build integration

package postgrestest

import (
	"context"
	"errors"
	"math/big"
	"testing"
	"time"

	"github.com/Contictus/launchtap/backend/internal/ledger"
	"github.com/Contictus/launchtap/backend/internal/observation"
	storepostgres "github.com/Contictus/launchtap/backend/internal/store/postgres"
	"github.com/ethereum/go-ethereum/common"
	"github.com/jackc/pgx/v5/pgtype"
)

// TestCanonicalObservationUnionAndScope exercises every event source in the
// HTTP transaction lookup query against PostgreSQL. It also verifies finality
// propagation, deployment scoping, and canonical disappearance after rollback.
func TestCanonicalObservationUnionAndScope(t *testing.T) {
	database := NewMigrated(t)
	ctx, cancel := context.WithTimeout(t.Context(), 30*time.Second)
	defer cancel()
	pool := openPool(t, ctx, database.URL)
	adapter := storepostgres.NewAdapter(pool)
	const chainID int64 = 49020
	const deploymentID = "observation-v1"
	when := time.Date(2026, 9, 10, 12, 0, 0, 0, time.UTC)
	blockHash := common.Hash{31: 0x20}
	mustInsertBlock(t, ctx, database.DB, chainID, 100, blockHash[:], hashBytes(0x19), when, "finalized")
	launchHash := common.Hash{31: 0x01}
	token, curve, creator, pair := addressBytes(1), addressBytes(2), addressBytes(3), addressBytes(4)
	coords := func(hash common.Hash, log int32, number int64, h common.Hash) ledger.EventCoordinates {
		return ledger.EventCoordinates{ChainID: chainID, BlockNumber: number, BlockHash: h, BlockTime: when, TransactionIndex: log, TxHash: hash, LogIndex: log}
	}
	launch := ledger.TokenLaunch{EventCoordinates: coords(launchHash, 1, 100, blockHash), Token: common.BytesToAddress(token), Curve: common.BytesToAddress(curve), Creator: common.BytesToAddress(creator), LPPair: common.BytesToAddress(pair), WETH: common.BytesToAddress(addressBytes(5)), ProtocolTreasury: common.BytesToAddress(addressBytes(6)), EngineVersion: 1, Name: "Observation", Symbol: "OBS", TotalSupply: big.NewInt(100), VirtualETH: big.NewInt(10), VirtualToken: big.NewInt(90), CurveTokens: big.NewInt(80), LPTokens: big.NewInt(20), GraduationETH: big.NewInt(20), LaunchFeePaid: big.NewInt(1)}
	if _, err := adapter.InsertTokenLaunch(ctx, launch); err != nil {
		t.Fatal(err)
	}
	tradeHash := common.Hash{31: 0x02}
	if _, err := adapter.InsertTrade(ctx, ledger.Trade{EventCoordinates: coords(tradeHash, 2, 100, blockHash), Token: common.BytesToAddress(token), Trader: common.BytesToAddress(addressBytes(7)), IsBuy: true, ETHGross: big.NewInt(2), ETHRefund: new(big.Int), TokenAmount: big.NewInt(3), ProtocolFee: big.NewInt(1), CreatorFee: big.NewInt(1), NewETHReserve: big.NewInt(12), NewTokenReserve: big.NewInt(87)}); err != nil {
		t.Fatal(err)
	}
	claimHash := common.Hash{31: 0x03}
	if _, err := adapter.InsertCreatorFeeClaim(ctx, ledger.CreatorFeeClaim{EventCoordinates: coords(claimHash, 3, 100, blockHash), Token: common.BytesToAddress(token), Creator: common.BytesToAddress(creator), Amount: big.NewInt(1)}); err != nil {
		t.Fatal(err)
	}
	refundHash := common.Hash{31: 0x04}
	if _, err := adapter.InsertRefundClaim(ctx, ledger.RefundClaim{EventCoordinates: coords(refundHash, 4, 100, blockHash), Token: common.BytesToAddress(token), Account: common.BytesToAddress(creator), Amount: big.NewInt(1)}); err != nil {
		t.Fatal(err)
	}
	swapHash := common.Hash{31: 0x05}
	if _, err := adapter.InsertPoolSwap(ctx, ledger.PoolSwap{EventCoordinates: coords(swapHash, 5, 100, blockHash), Pair: common.BytesToAddress(pair), Sender: common.BytesToAddress(creator), Amount0In: big.NewInt(1), Amount1In: new(big.Int), Amount0Out: new(big.Int), Amount1Out: big.NewInt(1), To: common.BytesToAddress(creator)}); err != nil {
		t.Fatal(err)
	}
	finalHash := storepostgres.Hash(blockHash)
	if _, err := adapter.UpsertSyncState(ctx, storepostgres.SyncState{ChainID: chainID, DeploymentID: deploymentID, ObservedNumber: pgtype.Int8{Int64: 100, Valid: true}, ObservedHash: &finalHash, ObservedAt: pgtype.Timestamptz{Time: when, Valid: true}, SafeNumber: pgtype.Int8{Int64: 100, Valid: true}, SafeHash: &finalHash, SafeAt: pgtype.Timestamptz{Time: when, Valid: true}, FinalizedNumber: pgtype.Int8{Int64: 100, Valid: true}, FinalizedHash: &finalHash, FinalizedAt: pgtype.Timestamptz{Time: when, Valid: true}}); err != nil {
		t.Fatal(err)
	}
	reader := storepostgres.ObservationReader{Pool: pool}
	for hash, kind := range map[common.Hash]string{launchHash: "token_launch", tradeHash: "trade", claimHash: "creator_fee_claim", refundHash: "refund_claim", swapHash: "router_swap"} {
		observation, err := reader.Get(ctx, chainID, deploymentID, hash)
		if err != nil {
			t.Fatalf("lookup %s: %v", kind, err)
		}
		if len(observation.Events) != 1 || observation.Events[0].Kind != kind || observation.Events[0].Finality != "finalized" {
			t.Fatalf("lookup %s = %+v", kind, observation.Events)
		}
	}
	if _, err := reader.Get(ctx, chainID, "other-deployment", tradeHash); !errors.Is(err, observation.ErrNotFound) {
		t.Fatalf("cross-deployment lookup error = %v, want not found", err)
	}
	if err := storepostgres.WithinTx(ctx, pool, func(ctx context.Context, tx *storepostgres.Adapter) error {
		return tx.DeleteCanonicalAbove(ctx, chainID, 99)
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := reader.Get(ctx, chainID, deploymentID, tradeHash); err == nil {
		t.Fatal("reorged trade remained observable")
	}
}
