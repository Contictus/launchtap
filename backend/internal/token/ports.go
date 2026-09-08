// Package token defines the application-owned token read contract.
package token

import (
	"context"
	"math/big"
	"time"

	"github.com/Contictus/launchtap/backend/internal/pagination"
	"github.com/ethereum/go-ethereum/common"
)

type ListQuery struct {
	ChainID int64
	Phase   string
	Search  string
	Sort    string
	Cursor  *pagination.Cursor
	Limit   int
}

type Summary struct {
	Address      common.Address
	Name         string
	Symbol       string
	Phase        string
	LaunchTime   time.Time
	LaunchBlock  int64
	TotalSupply  *big.Int
	MarketCapETH *big.Int
	Volume24hETH *big.Int
	HolderCount  int64
}

type Page struct {
	Items      []Summary
	Snapshot   pagination.Snapshot
	NextCursor string
}

// Reader is implemented by the PostgreSQL adapter without exposing sqlc types.
type Reader interface {
	List(ctx context.Context, query ListQuery) (Page, error)
}
