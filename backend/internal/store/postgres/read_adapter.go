package postgres

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"github.com/Contictus/launchtap/backend/internal/pagination"
	"github.com/Contictus/launchtap/backend/internal/store/postgres/sqlc"
	"github.com/Contictus/launchtap/backend/internal/token"
	"github.com/ethereum/go-ethereum/common"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

// ReadTokenCardsNewest executes the set-based token-list query inside one
// snapshot and emits a cursor bound to that snapshot. It intentionally exposes
// only neutral token types; sqlc rows never cross this package boundary.
func ReadTokenCardsNewest(ctx context.Context, pool PoolReadBeginner, chainID int64, deploymentID string, query token.ListQuery) (token.Page, error) {
	if query.Sort != "newest" {
		return token.Page{}, fmt.Errorf("unsupported token sort %q", query.Sort)
	}
	if query.Limit < 1 || query.Limit > 100 {
		return token.Page{}, fmt.Errorf("token page size must be between 1 and 100")
	}
	if query.Phase != "curve" && query.Phase != "graduated" {
		return token.Page{}, fmt.Errorf("unsupported token phase %q", query.Phase)
	}
	var page token.Page
	err := withReadSnapshotBeginner(ctx, pool, chainID, deploymentID, func(ctx context.Context, adapter *Adapter, snapshot ReadSnapshot) error {
		search := strings.TrimSpace(query.Search)
		arg := sqlc.ListTokenCardsNewestParams{ChainID: chainID, Phase: query.Phase, Search: search, PageSize: int32(query.Limit)}
		if query.Cursor != nil {
			if err := query.Cursor.ValidateRequest("tokens", query.Sort, search, "next", snapshot.Identity); err != nil {
				return err
			}
			if len(query.Cursor.Key) != 2 {
				return fmt.Errorf("invalid token cursor key")
			}
			block, err := strconv.ParseInt(query.Cursor.Key[0], 10, 64)
			if err != nil || block < 0 {
				return fmt.Errorf("invalid token cursor block")
			}
			if !common.IsHexAddress(query.Cursor.Key[1]) {
				return fmt.Errorf("invalid token cursor address")
			}
			arg.AfterBlock = pgtype.Int8{Int64: block, Valid: true}
			arg.AfterAddress = common.HexToAddress(query.Cursor.Key[1]).Bytes()
		}
		rows, err := adapter.queries.ListTokenCardsNewest(ctx, arg)
		if err != nil {
			return err
		}
		page.Snapshot = snapshot.Identity
		page.Items = make([]token.Summary, 0, len(rows))
		for _, row := range rows {
			page.Items = append(page.Items, token.Summary{Address: common.Address(row.TokenAddress), Name: row.Name, Symbol: row.Symbol, Phase: row.Phase, LaunchTime: row.LaunchBlockTime.Time, LaunchBlock: row.LaunchBlockNumber, TotalSupply: row.TotalSupply.BigInt(), MarketCapETH: row.MarketCapEthWad.BigInt(), Volume24hETH: row.Volume24hEthWad.BigInt(), HolderCount: row.HolderCount})
		}
		if len(rows) == query.Limit {
			last := rows[len(rows)-1]
			cursor, err := pagination.Encode(pagination.Cursor{Version: pagination.CurrentVersion, Snapshot: snapshot.Identity, Endpoint: "tokens", Sort: query.Sort, Filters: search, Direction: "next", Key: []string{strconv.FormatInt(last.LaunchBlockNumber, 10), common.Address(last.TokenAddress).Hex()}})
			if err != nil {
				return err
			}
			page.NextCursor = cursor
		}
		return nil
	})
	return page, err
}

// PoolReadBeginner is the minimal pool capability required by read helpers.
type PoolReadBeginner interface {
	BeginTx(context.Context, pgx.TxOptions) (pgx.Tx, error)
}

func withReadSnapshotBeginner(ctx context.Context, pool PoolReadBeginner, chainID int64, deploymentID string, fn func(context.Context, *Adapter, ReadSnapshot) error) error {
	if pool == nil {
		return fmt.Errorf("read snapshot requires pool")
	}
	tx, err := pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return err
	}
	defer func() { _ = rollbackTx(tx) }()
	a := NewAdapter(tx)
	state, err := a.GetSyncState(ctx, chainID, deploymentID)
	if err != nil {
		return err
	}
	identity, err := observedIdentity(state)
	if err != nil {
		return err
	}
	if err := fn(ctx, a, ReadSnapshot{Identity: identity, State: state}); err != nil {
		return err
	}
	return ctx.Err()
}
