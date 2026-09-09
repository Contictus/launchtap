// Package candle defines the application-owned candle read contract.
package candle

import (
	"context"
	"math/big"
	"time"

	"github.com/Contictus/launchtap/backend/internal/pagination"
	"github.com/ethereum/go-ethereum/common"
)

type Query struct {
	ChainID  int64
	Token    common.Address
	Interval string
	From, To time.Time
	Limit    int
	Cursor   *pagination.Cursor
}

type Candle struct {
	Start       time.Time
	Open, High  *big.Int
	Low, Close  *big.Int
	ETHVolume   *big.Int
	TokenVolume *big.Int
	TradeCount  int64
}

type Page struct {
	Items      []Candle
	Snapshot   pagination.Snapshot
	NextCursor string
	Finality   string
}

type Reader interface {
	List(ctx context.Context, query Query) (Page, error)
}
