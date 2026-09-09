package trading

import (
	"context"
	"math/big"
	"time"

	"github.com/Contictus/launchtap/backend/internal/pagination"
	"github.com/ethereum/go-ethereum/common"
)

type Trade struct {
	Source                                            string
	Trader                                            *common.Address
	Buy                                               bool
	ExecutionPrice, SpotPrice, ETHVolume, TokenVolume *big.Int
	BlockNumber                                       int64
	TransactionIndex                                  int32
	TxHash                                            common.Hash
	LogIndex                                          int32
	Time                                              time.Time
	Finality                                          string
}
type Query struct {
	ChainID int64
	Token   common.Address
	Limit   int
	Cursor  *pagination.Cursor
}
type Page struct {
	Items      []Trade
	Snapshot   pagination.Snapshot
	NextCursor string
	Finality   string
}
type Reader interface {
	ListTrades(context.Context, Query) (Page, error)
}
