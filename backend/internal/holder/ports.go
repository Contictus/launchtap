package holder

import (
	"context"
	"math/big"

	"github.com/Contictus/launchtap/backend/internal/pagination"
	"github.com/ethereum/go-ethereum/common"
)

type Balance struct {
	Address            common.Address
	Balance            *big.Int
	FirstAcquiredBlock int64
}
type Query struct {
	ChainID int64
	Token   common.Address
	Limit   int
	Cursor  *pagination.Cursor
}
type Page struct {
	Items      []Balance
	Snapshot   pagination.Snapshot
	NextCursor string
	Finality   string
}
type Reader interface {
	ListHolders(context.Context, Query) (Page, error)
}
