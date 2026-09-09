package postgres

import (
	"context"
	"fmt"
	"math/big"
	"reflect"
	"strconv"
	"strings"
	"time"

	"github.com/Contictus/launchtap/backend/internal/candle"
	"github.com/Contictus/launchtap/backend/internal/pagination"
	"github.com/Contictus/launchtap/backend/internal/store/postgres/sqlc"
	"github.com/Contictus/launchtap/backend/internal/token"
	"github.com/ethereum/go-ethereum/common"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

// ReadTokenCards executes one set-based, snapshot-bound query for each
// supported ordering. Reflection is confined to this adapter to normalize the
// generated row structs, which intentionally never cross the application boundary.
func ReadTokenCards(ctx context.Context, pool PoolReadBeginner, chainID int64, deploymentID string, query token.ListQuery) (token.Page, error) {
	if query.Limit < 1 || query.Limit > 100 {
		return token.Page{}, fmt.Errorf("token page size must be between 1 and 100")
	}
	if query.Phase != "curve" && query.Phase != "graduated" {
		return token.Page{}, fmt.Errorf("unsupported token phase %q", query.Phase)
	}
	if query.Sort != "newest" && query.Sort != "oldest" && query.Sort != "market_cap" && query.Sort != "volume_24h" {
		return token.Page{}, fmt.Errorf("unsupported token sort %q", query.Sort)
	}
	var page token.Page
	err := withReadSnapshotBeginner(ctx, pool, chainID, deploymentID, func(ctx context.Context, adapter *Adapter, snapshot ReadSnapshot) error {
		search := strings.TrimSpace(query.Search)
		if query.Cursor != nil {
			if err := query.Cursor.ValidateRequest("tokens", query.Sort, search, "next", snapshot.Identity); err != nil {
				return err
			}
		}
		var cards []cardView
		var err error
		switch query.Sort {
		case "newest":
			arg := sqlc.ListTokenCardsNewestParams{ChainID: chainID, Phase: query.Phase, Search: search, PageSize: int32(query.Limit)}
			if query.Cursor != nil {
				arg.AfterBlock, arg.AfterAddress, err = tupleCursor(query.Cursor)
				if err != nil {
					return err
				}
			}
			rows, e := adapter.queries.ListTokenCardsNewest(ctx, arg)
			err = e
			for _, row := range rows {
				cards = append(cards, reflectCard(row))
			}
		case "oldest":
			arg := sqlc.ListTokenCardsOldestParams{ChainID: chainID, Phase: query.Phase, Search: search, PageSize: int32(query.Limit)}
			if query.Cursor != nil {
				arg.AfterBlock, arg.AfterAddress, err = tupleCursor(query.Cursor)
				if err != nil {
					return err
				}
			}
			rows, e := adapter.queries.ListTokenCardsOldest(ctx, arg)
			err = e
			for _, row := range rows {
				cards = append(cards, reflectCard(row))
			}
		case "market_cap", "volume_24h":
			argMetric, argAddress, e := metricCursor(query.Cursor)
			if e != nil {
				return e
			}
			if query.Sort == "market_cap" {
				rows, e := adapter.queries.ListTokenCardsMarketCap(ctx, sqlc.ListTokenCardsMarketCapParams{ChainID: chainID, Phase: query.Phase, Search: search, AfterMetric: argMetric, AfterAddress: argAddress, PageSize: int32(query.Limit)})
				err = e
				for _, row := range rows {
					cards = append(cards, reflectCard(row))
				}
			} else {
				rows, e := adapter.queries.ListTokenCardsVolume(ctx, sqlc.ListTokenCardsVolumeParams{ChainID: chainID, Phase: query.Phase, Search: search, AfterMetric: argMetric, AfterAddress: argAddress, PageSize: int32(query.Limit)})
				err = e
				for _, row := range rows {
					cards = append(cards, reflectCard(row))
				}
			}
		}
		if err != nil {
			return err
		}
		page.Snapshot = snapshot.Identity
		page.Items = make([]token.Summary, 0, len(cards))
		for _, row := range cards {
			page.Items = append(page.Items, token.Summary{Address: row.Address, Name: row.Name, Symbol: row.Symbol, Phase: row.Phase, LaunchTime: row.LaunchTime, LaunchBlock: row.Block, TotalSupply: row.Supply, MarketCapETH: row.Market, Volume24hETH: row.Volume, HolderCount: row.Holders})
		}
		if len(cards) == query.Limit {
			last := cards[len(cards)-1]
			key := []string{strconv.FormatInt(last.Block, 10), last.Address.Hex()}
			if query.Sort == "market_cap" {
				key = []string{last.Market.String(), last.Address.Hex()}
			}
			if query.Sort == "volume_24h" {
				key = []string{last.Volume.String(), last.Address.Hex()}
			}
			page.NextCursor, err = pagination.Encode(pagination.Cursor{Version: pagination.CurrentVersion, Snapshot: snapshot.Identity, Endpoint: "tokens", Sort: query.Sort, Filters: search, Direction: "next", Key: key})
			if err != nil {
				return err
			}
		}
		return nil
	})
	return page, err
}

// ReadTokenCardsNewest is retained as a compatibility spelling for callers of
// the first Task 2 slice.
func ReadTokenCardsNewest(ctx context.Context, pool PoolReadBeginner, chainID int64, deploymentID string, query token.ListQuery) (token.Page, error) {
	query.Sort = "newest"
	return ReadTokenCards(ctx, pool, chainID, deploymentID, query)
}

type cardView struct {
	Address                common.Address
	Name, Symbol, Phase    string
	Block                  int64
	LaunchTime             time.Time
	Supply, Market, Volume *big.Int
	Holders                int64
}

func reflectCard(row any) cardView {
	v := reflect.ValueOf(row)
	field := func(name string) reflect.Value { return v.FieldByName(name) }
	return cardView{Address: common.Address(field("TokenAddress").Interface().(sqlc.Address)), Name: field("Name").String(), Symbol: field("Symbol").String(), Phase: field("Phase").String(), Block: field("LaunchBlockNumber").Int(), LaunchTime: field("LaunchBlockTime").Interface().(pgtype.Timestamptz).Time, Supply: field("TotalSupply").Interface().(sqlc.Uint256).BigInt(), Market: field("MarketCapEthWad").Interface().(sqlc.Uint256).BigInt(), Volume: field("Volume24hEthWad").Interface().(sqlc.Uint256).BigInt(), Holders: field("HolderCount").Int()}
}

func tupleCursor(c *pagination.Cursor) (pgtype.Int8, []byte, error) {
	if c == nil {
		return pgtype.Int8{}, nil, nil
	}
	if len(c.Key) != 2 {
		return pgtype.Int8{}, nil, fmt.Errorf("invalid tuple cursor")
	}
	n, err := strconv.ParseInt(c.Key[0], 10, 64)
	if err != nil || n < 0 || !common.IsHexAddress(c.Key[1]) {
		return pgtype.Int8{}, nil, fmt.Errorf("invalid tuple cursor")
	}
	return pgtype.Int8{Int64: n, Valid: true}, common.HexToAddress(c.Key[1]).Bytes(), nil
}
func metricCursor(c *pagination.Cursor) (pgtype.Numeric, []byte, error) {
	if c == nil {
		return pgtype.Numeric{}, nil, nil
	}
	if len(c.Key) != 2 || !common.IsHexAddress(c.Key[1]) {
		return pgtype.Numeric{}, nil, fmt.Errorf("invalid metric cursor")
	}
	n, ok := new(big.Int).SetString(c.Key[0], 10)
	if !ok || n.Sign() < 0 {
		return pgtype.Numeric{}, nil, fmt.Errorf("invalid metric cursor")
	}
	return pgtype.Numeric{Int: n, Valid: true}, common.HexToAddress(c.Key[1]).Bytes(), nil
}

type PoolReadBeginner interface {
	BeginTx(context.Context, pgx.TxOptions) (pgx.Tx, error)
}

// ReadAggregatedCandles serves the stored 6h/all rollups without OFFSET and
// keeps the watermark and rows in the same repeatable-read snapshot.
func ReadAggregatedCandles(ctx context.Context, pool PoolReadBeginner, chainID int64, deploymentID string, query candle.Query) (candle.Page, error) {
	if query.Limit < 1 || query.Limit > 100 {
		return candle.Page{}, fmt.Errorf("candle page size must be between 1 and 100")
	}
	if query.Interval != "6h" && query.Interval != "all" {
		return candle.Page{}, fmt.Errorf("unsupported candle interval %q", query.Interval)
	}
	var page candle.Page
	err := withReadSnapshotBeginner(ctx, pool, chainID, deploymentID, func(ctx context.Context, adapter *Adapter, snapshot ReadSnapshot) error {
		arg := sqlc.ListCandlesAggregatedParams{ChainID: chainID, TokenAddress: sqlc.Address(query.Token), SourceInterval: "1h", TargetInterval: query.Interval, FromTime: pgtype.Timestamptz{Time: query.From, Valid: true}, ToTime: pgtype.Timestamptz{Time: query.To, Valid: true}, PageSize: int32(query.Limit)}
		if query.Interval == "all" {
			arg.SourceInterval = "1d"
		}
		rows, err := adapter.queries.ListCandlesAggregated(ctx, arg)
		if err != nil {
			return err
		}
		page.Snapshot = snapshot.Identity
		page.Items = make([]candle.Candle, 0, len(rows))
		for _, row := range rows {
			start, err := candleTime(row.BucketStartTime)
			if err != nil {
				return err
			}
			page.Items = append(page.Items, candle.Candle{Start: start, Open: candleNumeric(row.OpenPriceWad), High: candleNumeric(row.HighPriceWad), Low: candleNumeric(row.LowPriceWad), Close: candleNumeric(row.ClosePriceWad), ETHVolume: candleNumeric(row.GrossEthVolume), TokenVolume: candleNumeric(row.TokenVolume), TradeCount: row.TradeCount})
		}
		return nil
	})
	return page, err
}

func candleTime(v any) (time.Time, error) {
	switch value := v.(type) {
	case time.Time:
		return value, nil
	case pgtype.Timestamptz:
		return value.Time, nil
	default:
		return time.Time{}, fmt.Errorf("unexpected candle timestamp %T", v)
	}
}
func candleNumeric(v any) *big.Int {
	switch value := v.(type) {
	case sqlc.Uint256:
		return value.BigInt()
	case pgtype.Numeric:
		if value.Int == nil {
			return new(big.Int)
		}
		return new(big.Int).Set(value.Int)
	case int64:
		return big.NewInt(value)
	default:
		return new(big.Int)
	}
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
